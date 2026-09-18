import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/ai/ai_generator.dart';
import 'package:zuoye_fluter/core/scope_guard.dart';
import 'package:zuoye_fluter/data/app_data.dart';

/// 生成后超纲检查的测试。
///
/// 这套检查是 AI 出题唯一的兜底手段（本地生成走硬约束，不需要）。因此重点是
/// **不能误报**——宁可漏报也不要让老师看到假警报。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  group('integerCeil · 从题型 id 推导整数上限', () {
    test('一年级 20 / 二年级 100 / 三年级 10000', () {
      expect(ScopeGuard.integerCeil(version: 'renjiao', grade: 1, volume: '上'), 20);
      expect(ScopeGuard.integerCeil(version: 'renjiao', grade: 2, volume: '上'), 100);
      expect(ScopeGuard.integerCeil(version: 'renjiao', grade: 3, volume: '上'), 10000);
    });

    test('四五六年级不设上限（数域交错，避免误伤）', () {
      for (final g in [4, 5, 6]) {
        expect(ScopeGuard.integerCeil(version: 'renjiao', grade: g, volume: '上'),
            isNull, reason: '$g 年级不应设上限');
      }
    });

    test('反漂移：与提示词里写的上限一致', () {
      for (final g in [1, 2, 3]) {
        final ceil = ScopeGuard.integerCeil(
            version: 'renjiao', grade: g, volume: '上')!;
        final prompt = aiBuildPrompt('math', [AiStyleSpec('calc', 10)],
            AiPromptOpts(
                version: 'renjiao',
                volume: '上',
                grade: g,
                diff: 'easy',
                showAnswer: true));
        final expectText = ceil >= 10000 ? '万以内' : '$ceil 以内';
        // 提示词与校验器必须用同一个上限，否则会出现「提示词说 20、校验按 100」
        expect(prompt, contains(expectText),
            reason: '$g 年级提示词未提到上限 $expectText');
      }
    });
  });

  group('mathNumbersOver · 数值越界识别', () {
    test('超出上限的数字会被抓出来', () {
      expect(ScopeGuard.mathNumbersOver('小明有 156 颗糖。', 20), ['156']);
      expect(ScopeGuard.mathNumbersOver('25 + 7 = ?', 20), ['25']);
    });

    test('上限内不算越界', () {
      expect(ScopeGuard.mathNumbersOver('12 + 8 = 20', 20), isEmpty);
      expect(ScopeGuard.mathNumbersOver('18 - 9 = 9', 20), isEmpty);
    });

    test('引用类数字不算越界（第3单元 / 第5页）', () {
      expect(ScopeGuard.mathNumbersOver('第3单元 第5页', 20), isEmpty);
      expect(ScopeGuard.mathNumbersOver('三年级上册', 20), isEmpty);
    });

    test('年份不算越界', () {
      expect(ScopeGuard.mathNumbersOver('2022 年新课标', 20), isEmpty);
    });

    test('多个越界数字全部返回', () {
      final r = ScopeGuard.mathNumbersOver('45 + 67 = 112', 20);
      expect(r, containsAll(['45', '67', '112']));
    });
  });

  group('inspect · 数学', () {
    String run(List<ScopeItem> items, int grade) => ScopeGuard.inspect(
          items,
          subject: 'math',
          version: 'renjiao',
          grade: grade,
          volume: '上',
        );

    test('一年级出现三位数 -> 报超纲', () {
      final note = run([const ScopeItem('word', '小明有 156 颗糖，吃了 23 颗。')], 1);
      expect(note, isNotEmpty);
      expect(note, contains('156'));
      expect(note, contains('20'));
    });

    test('一年级正常题目 -> 不报', () {
      expect(run([const ScopeItem('add20', '9 + 8 = ?')], 1), isEmpty);
    });

    test('六年级 -> 不做数值检查（不设上限）', () {
      expect(run([const ScopeItem('word', '一条路长 3600 米。')], 6), isEmpty);
    });
  });

  group('inspect · 语文', () {
    late Set<String> table;
    setUp(() {
      table = ScopeGuard.writingTable(
          version: 'renjiao', grade: 1, volume: '上');
    });

    String run(List<ScopeItem> items) => ScopeGuard.inspect(
          items,
          subject: 'chinese',
          version: 'renjiao',
          grade: 1,
          volume: '上',
        );

    test('写字表里的字 -> 不报', () {
      final sample = table.take(6).join();
      expect(run([ScopeItem('pinyin2char', sample)]), isEmpty);
    });

    test('大量表外字 -> 报超纲', () {
      final outside =
          '餐舞钢琴歌蝴蝶鲸'.split('').where((c) => !table.contains(c)).join();
      expect(outside.length, greaterThan(3), reason: '测试素材需确实在表外');
      final note = run([ScopeItem('pinyin2char', outside)]);
      expect(note, isNotEmpty);
      expect(note, contains('写字表'));
    });

    test('古诗/成语类题型不做生字检查（各有自己的语料来源）', () {
      final outside =
          '餐舞钢琴歌蝴蝶鲸'.split('').where((c) => !table.contains(c)).join();
      expect(run([ScopeItem('gushiFill', outside)]), isEmpty);
      expect(run([ScopeItem('chengyuFill', outside)]), isEmpty);
      expect(run([ScopeItem('aiyuedu', outside)]), isEmpty);
    });

    test('混入少量表外提示语 -> 不报（阈值 20%）', () {
      final inScope = table.take(20).join();
      expect(run([ScopeItem('pinyin2char', '$inScope 照样子')]), isEmpty);
    });
  });

  group('inspect · 英语', () {
    test('不做词汇检查（ENG_505 是 headword 形式，逐词比对误报率高）', () {
      final note = ScopeGuard.inspect(
        [const ScopeItem('trace', 'It is a beautiful butterfly.')],
        subject: 'english',
        version: 'renjiao',
        grade: 1,
        volume: '上',
      );
      expect(note, isEmpty);
    });
  });

  test('空输入不报错', () {
    expect(
      ScopeGuard.inspect(const [],
          subject: 'math', version: 'renjiao', grade: 1, volume: '上'),
      isEmpty,
    );
  });
}
