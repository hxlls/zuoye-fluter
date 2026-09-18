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

  AiPromptOpts opts(int grade, {String version = 'renjiao'}) => AiPromptOpts(
        version: version,
        volume: '上',
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
}
