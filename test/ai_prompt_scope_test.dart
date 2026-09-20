import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/ai/ai_generator.dart';
import 'package:zuoye_fluter/data/app_data.dart';

/// AI 提示词的「防超纲」约束测试。
///
/// AI 生成是软约束（最终靠模型自觉），这里锁住的是「我们确实把范围告诉了模型」——
/// 避免以后有人改提示词时把约束改没了，或又退回「供参考」这种软措辞。
///
/// 本地生成（数学口算/语文语料/英语词汇）走的是硬约束，由 type_catalog_test.dart
/// 与既有测试覆盖，不在此文件。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  AiPromptOpts opts(int grade,
          {String version = 'renjiao', String volume = '上'}) =>
      AiPromptOpts(
        version: version,
        volume: volume,
        grade: grade,
        diff: 'easy',
        showAnswer: true,
      );

  String mathPrompt(int grade) =>
      aiBuildPrompt('math', [AiStyleSpec('calc', 10)], opts(grade));

  group('数学提示词：数值与运算硬约束', () {
    test('一年级 20 以内，不得出现乘除法、小数、分数', () {
      final p = mathPrompt(1);
      expect(p, contains('整数运算限制在20 以内'));
      expect(p, contains('不得出现乘法和除法'));
      expect(p, contains('不得出现小数'));
      expect(p, contains('不得出现分数'));
    });

    test('二年级 100 以内，可含乘法但不得出现除法', () {
      final p = mathPrompt(2);
      expect(p, contains('整数运算限制在100 以内'));
      expect(p, contains('可含乘法，但不得出现除法'));
    });

    test('三年级万以内，可含乘法但不得出现除法', () {
      final p = mathPrompt(3);
      expect(p, contains('整数运算限制在万以内'));
      expect(p, contains('可含乘法，但不得出现除法'));
    });

    test('四五六年级不给数值禁令（数域交错，避免误伤）', () {
      for (final g in [4, 5, 6]) {
        expect(mathPrompt(g), isNot(contains('数值与运算硬性约束')),
            reason: '$g 年级不应出现数值禁令');
      }
    });

    test('所有年级都带题型清单约束', () {
      for (var g = 1; g <= 6; g++) {
        expect(mathPrompt(g), contains('只能出这些类型'), reason: '$g 年级缺少题型清单约束');
      }
    });
  });

  group('语文/英语提示词：措辞已从「供参考」硬化', () {
    test('语文要求「必须限定在本册写字表范围内」', () {
      final p = aiBuildPrompt('chinese', [AiStyleSpec('pinyin2char', 6)], opts(1));
      expect(p, contains('必须'));
      expect(p, contains('本册生字表'));
      expect(p, isNot(contains('供参考')));
    });

    test('英语要求「必须限定在该年级词汇表内」', () {
      final p = aiBuildPrompt('english', [AiStyleSpec('trace', 6)], opts(1));
      expect(p, contains('必须'));
      expect(p, contains('本年级词汇表'));
      expect(p, isNot(contains('供参考')));
    });

    test('生字范围不再被截断到 60 字', () {
      final p = aiBuildPrompt('chinese', [AiStyleSpec('pinyin2char', 6)], opts(1));
      // 一年级上册生字表远超 60 字；截断会让范围外的生字被误当成允许
      final seg = p.split('本册生字表：').last.split('\n').first;
      final n = seg.split('、').where((s) => s.trim().isNotEmpty).length;
      expect(n, greaterThan(60), reason: '生字表被截断了，实际给出 $n 个');
    });
  });

  /// 本册教材单元清单（MATH_UNITS → 提示词）。
  ///
  /// 它是**正向**的「本册有哪些单元」，而题型清单（`MathType`）是**逆向**的
  /// 「题型 → 单元」，天然残缺：人教版四下 10 个单元，题型只覆盖 3 个。
  /// 两者分工不同 —— 题型清单答「能出什么」，单元清单答「情境落在哪」，
  /// 所以提示词必须把从属关系写明，否则模型会拿单元当题型清单用（导致超纲）。
  group('数学提示词：本册教材单元（情境约束）', () {
    test('四年级上册带上本册单元，并限定只影响应用题情境', () {
      final p = mathPrompt(4);
      expect(p, contains('本册教材单元'));
      expect(p, contains('一 万以上数的认识'), reason: '单元名要真的来自数据');
      expect(p, contains('仅用于让应用题的情境与数据贴合本册进度'));
      expect(p, contains('绝不可因此引入上面清单之外的题型或运算'),
          reason: '单元里有「认识立体图形」这类本地生成器出不了的，必须禁止据它扩题型');
    });

    test('单元清单排在题型白名单之后 —— 顺序决定主从', () {
      final p = mathPrompt(4);
      final iTopics = p.indexOf('只能出这些类型');
      final iUnits = p.indexOf('本册教材单元');
      expect(iTopics, greaterThanOrEqualTo(0));
      expect(iUnits, greaterThan(iTopics),
          reason: '先说能出什么、再说情境落在哪；反过来模型容易把单元当题型清单');
    });

    test('12 个册次都带得上单元清单', () {
      for (var g = 1; g <= 6; g++) {
        for (final v in ['上', '下']) {
          final p = aiBuildPrompt(
              'math', [AiStyleSpec('calc', 10)], opts(g, volume: v));
          expect(p, contains('本册教材单元'), reason: '$g$v 没带上单元清单');
        }
      }
    });

    test('声明与人教版对齐的版本才有清单，冀教版不给（宁可没有也不能说错）', () {
      final data = AppData();
      for (final v in data.mathUnitsAligned) {
        expect(data.mathUnitsFor(v, 4, '上'), isNotEmpty,
            reason: '$v 声明了对齐人教版，却没有单元数据');
      }
      expect(data.mathUnitsFor('hebei', 4, '上'), isEmpty,
          reason: '冀教版数学用冀教版教材，套用人教版单元名会说错');
      final p = aiBuildPrompt(
          'math', [AiStyleSpec('calc', 10)], opts(4, version: 'hebei'));
      expect(p, isNot(contains('本册教材单元')));
      expect(p, contains('只能出这些类型'), reason: '没有单元清单时题型约束照旧');
    });
  });

  group('MATH_UNITS 数据层', () {
    test('解析时跳过 _meta，不留进版本表', () {
      final data = AppData();
      expect(data.mathUnits.keys, contains('renjiao'));
      expect(data.mathUnits.keys, isNot(contains('_meta')));
      expect(data.mathUnitsAligned, contains('tongbiao'));
      expect(data.mathUnitsAligned, isNot(contains('hebei')));
    });

    test('6 个年级 × 2 册 = 12 册齐全，共 96 条，无空条目、无重复', () {
      final data = AppData();
      var total = 0;
      for (var g = 1; g <= 6; g++) {
        for (final v in ['上', '下']) {
          final units = data.mathUnitsFor('renjiao', g, v);
          expect(units, isNotEmpty, reason: '$g$v 缺单元清单');
          expect(units.every((u) => u.trim().isNotEmpty), isTrue,
              reason: '$g$v 有空单元名');
          expect(units.toSet().length, units.length, reason: '$g$v 有重复单元名');
          total += units.length;
        }
      }
      expect(total, 96);
    });

    test('越界查询返回空表而不是抛错（调用方必须能安全回退）', () {
      final data = AppData();
      expect(data.mathUnitsFor('renjiao', 9, '上'), isEmpty);
      expect(data.mathUnitsFor('renjiao', 4, '中'), isEmpty);
      expect(data.mathUnitsFor('不存在的版本', 4, '上'), isEmpty);
    });
  });
}
