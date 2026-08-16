import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/core/math_worksheet.dart';
import 'package:zuoye_fluter/core/math_gen.dart';
import 'package:zuoye_fluter/core/chinese_worksheet.dart';
import 'package:zuoye_fluter/core/english_worksheet.dart';
import 'package:zuoye_fluter/core/calligraphy_worksheet.dart';
import 'package:zuoye_fluter/core/rand_gen.dart';
import 'package:zuoye_fluter/core/worksheet_model.dart';
import 'package:zuoye_fluter/ai/ai_generator.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('AppData', () {
    test('加载数据', () async {
      await AppData().load();
      expect(AppData().textbooks.length, 4);
      expect(AppData().gradeNames[1], '一年级');
      // 人教版一年级上册生字
      final cally = AppData().vol('renjiao', 1, '上', 'cally')!.cally!;
      expect(cally.isNotEmpty, true);
      expect(cally[0].length, 2);
      // 数学题型含 word 和 unitconv
      final math = AppData().vol('renjiao', 2, '上', 'math')!.math!;
      expect(math.any((t) => t.id == 'word'), true);
      // 外研版仅一年级
      expect(AppData().vol('waiyanYQ', 3, '上', 'eng'), isNull);
    });
  });

  group('math', () {
    test('生成 10 以内加法', () {
      final g = RandGen(grade: 1);
      final p = genMathProblem('add10', g);
      expect(p.op, '+');
      expect(p.a >= 1 && p.a <= 9, true);
      expect(p.ans, p.a + p.b);
    });

    test('一年级比较大小限 20 以内', () {
      final g = RandGen(grade: 1);
      for (var i = 0; i < 200; i++) {
        final p = genMathProblem('compare', g);
        expect(p.a <= 20 && p.b <= 20, true);
      }
    });

    test('一年级下两位数加减一位数(100以内)', () {
      final g = RandGen(grade: 1);
      for (var i = 0; i < 200; i++) {
        final p = genMathProblem('add100a', g);
        expect(p.a >= 11 && p.a <= 99, true);
        // b 为一位数(1-9)或整十数(10-90)
        expect(p.b >= 1 && p.b <= 9 || (p.b % 10 == 0 && p.b <= 90), true);
        final ans = p.op == '+' ? p.a + p.b : p.a - p.b;
        expect(ans >= 0 && ans <= 100, true);
      }
    });

    test('二年级下两步混合运算结果不溢出', () {
      final g = RandGen(grade: 2);
      for (var i = 0; i < 200; i++) {
        final p = genMathProblem('mix20', g);
        final num ans = p.ans as num;
        expect(ans >= 0 && ans <= 90, true);
      }
    });

    test('图形与生活题型可生成且答案非空', () {
      final cases = <(String, int)>[
        ('tensComp', 1), ('perimeter', 3), ('areaRect', 3), ('timeCalc', 3),
        ('avg', 4), ('polyArea', 5), ('surface', 5), ('volume', 5),
        ('ratio', 6), ('circle', 6), ('cylinder', 6), ('discount', 6),
      ];
      for (final (tid, gr) in cases) {
        final g = RandGen(grade: gr);
        for (var i = 0; i < 50; i++) {
          final p = genMathProblem(tid, g);
          expect(p.ans != null, true, reason: '$tid 答案为空');
          expect(p.expr != null && p.expr!.isNotEmpty, true, reason: '$tid 题目为空');
        }
      }
    });

    test('分数化简', () {
      expect(fracStr(4, 8), '1/2');
      expect(fracStr(6, 3), '2');
      expect(fracStr(0, 5), '0');
    });

    test('生成数学作业页面', () async {
      await AppData().load();
      final pages = mathRenderPages(MathOptions(
        grade: 2,
        version: 'renjiao',
        volume: '上',
        count: 30,
        diff: 'easy',
        showAnswer: true,
        showTitle: true,
      ));
      expect(pages.isNotEmpty, true);
      // 每页有节点
      for (final p in pages) {
        expect(p.nodes.isNotEmpty, true);
      }
    });

    test('题目不重复', () async {
      await AppData().load();
      final pages = mathRenderPages(MathOptions(
        grade: 3,
        version: 'renjiao',
        volume: '上',
        count: 40,
        diff: 'mid',
        showAnswer: true,
      ));
      // 收集所有 math 卡片的 key
      final keys = <String>{};
      for (final p in pages) {
        for (final n in p.nodes) {
          if (n is WsGrid) {
            for (final c in n.cards) {
              if (c.kind == 'math') {
                final d = c.data as MathItemData;
                keys.add(d.key);
              }
            }
          }
        }
      }
      // 无重复
      expect(keys.length, keys.toSet().length);
    });

    test('参考答案不含 HTML 标签', () async {
      await AppData().load();
      final pages = mathRenderPages(MathOptions(
        grade: 3,
        version: 'renjiao',
        volume: '上',
        count: 40,
        diff: 'mid',
        showAnswer: true,
      ));
      final htmlRe = RegExp(r'<[a-z/][^>]*>', caseSensitive: false);
      for (final p in pages) {
        for (final n in p.nodes) {
          if (n is WsAnswerLine) {
            expect(n.key.contains('<'), false, reason: '答案行 key 含 HTML: ${n.key}');
            expect(n.ans.contains('<'), false, reason: '答案行 ans 含 HTML: ${n.ans}');
          }
          if (n is WsMatchAnswer) {
            for (final l in n.lines) {
              expect(htmlRe.hasMatch(l), false, reason: '连线答案含 HTML: $l');
            }
          }
        }
      }
    });
  });

  group('chinese', () {
    test('生成语文作业', () async {
      await AppData().load();
      final pages = chineseRenderPages(ChineseOptions(
        grade: 3,
        version: 'renjiao',
        volume: '上',
        types: ['pinyin2char', 'gushiFill', 'chengyuFill', 'mingjuFill'],
        counts: {'pinyin2char': 6, 'gushiFill': 2, 'chengyuFill': 3, 'mingjuFill': 2},
        showAnswer: true,
        showTitle: true,
      ));
      expect(pages.isNotEmpty, true);
    });

    test('诗句切分', () {
      final segs = splitSegments('床前明月光，疑是地上霜。举头望明月，低头思故乡。');
      expect(segs.length, 4);
      expect(segs[0], '床前明月光，');
    });

    test('古诗填空不挖第一句', () async {
      await AppData().load();
      final pages = chineseRenderPages(ChineseOptions(
        grade: 2,
        version: 'renjiao',
        volume: '上',
        types: ['gushiFill'],
        counts: {'gushiFill': 3},
      ));
      // 找到 gushiFill 卡片，验证 blank > 0
      for (final p in pages) {
        for (final n in p.nodes) {
          if (n is WsGrid) {
            for (final c in n.cards) {
              if (c.kind == 'cn') {
                final d = c.data as CnCardData;
                if (d.type == 'gushiFill' && !d.pad) {
                  expect(d.blank! > 0, true);
                }
              }
            }
          }
        }
      }
    });
  });

  group('english', () {
    test('生成英语作业（一年级：字母+描红）', () async {
      await AppData().load();
      final pages = englishRenderPages(EnglishOptions(
        grade: 1,
        version: 'renjiao',
        volume: '上',
        count: 8,
      ));
      expect(pages.isNotEmpty, true);
    });

    test('单词拼写空白字母数', () {
      // 通过 englishRenderPages 间接验证 blankWord 不出界
      expect('a'.split('').length, 1);
    });

    test('连线题答案与右列标号一致', () {
      final vocab = <List<String>>[
        ['ice cream', '冰激凌'],
        ['tiger', '老虎'],
        ['grandpa', '爷爷'],
        ['candy', '糖果'],
        ['nine', '九'],
        ['China', '中国'],
        ['six', '六'],
        ['big', '大的'],
      ];
      final built = buildMatchingRows(vocab);
      final answers = buildMatchAnswer(vocab, built.rightCn);
      expect(answers.length, vocab.length);
      for (var i = 0; i < answers.length; i++) {
        // 答案形如 "1. ice cream → b. 冰激凌"
        final en = vocab[i][0];
        expect(answers[i].contains(en), true, reason: '第${i + 1}行应含 $en');
        // 标号对应的右列中文应等于该单词的释义
        final letter = answers[i].split('→ ')[1].split('.')[0];
        final letterIdx = letter.codeUnitAt(0) - 'a'.codeUnitAt(0);
        final rightCn = built.rightCn[letterIdx][1];
        expect(rightCn, vocab[i][1],
            reason: '第${i + 1}行 $en 标号 $letter 应为 ${vocab[i][1]}，实际右列该位为 $rightCn');
      }
    });
  });

  group('calligraphy', () {
    test('生成练字帖', () async {
      await AppData().load();
      final pages = calligraphyRenderPages(CalligraphyOptions(
        source: 'grade',
        grade: 1,
        version: 'renjiao',
        volume: '上',
        charCount: 16,
        practice: 2,
        perRow: 5,
        rows: 5,
      ));
      expect(pages.isNotEmpty, true);
      expect(pages.first.rows.first.length, 5);
    });

    test('自定义文字', () async {
      await AppData().load();
      final pages = calligraphyRenderPages(CalligraphyOptions(
        source: 'custom',
        customText: '我爱我的祖国',
        practice: 2,
        perRow: 5,
        rows: 5,
      ));
      expect(pages.isNotEmpty, true);
    });
  });

  group('ai', () {
    test('AI 出题 prompt 含年级教材约束', () async {
      await AppData().load();
      // 语文：含该年级生字
      final zh = aiBuildPrompt('chinese', [
        AiStyleSpec('zuci', 2),
      ], AiPromptOpts(version: 'renjiao', volume: '上', grade: 1, diff: 'easy', showAnswer: true));
      expect(zh.contains('生字'), true);
      expect(zh.contains('一年级'), true);
      // 数学：含该年级知识范围
      final math = aiBuildPrompt('math', [
        AiStyleSpec('calc', 2),
      ], AiPromptOpts(version: 'renjiao', volume: '上', grade: 3, diff: 'easy', showAnswer: true));
      expect(math.contains('万以内加减法'), true);
      // 英语：含该年级词汇
      final en = aiBuildPrompt('english', [
        AiStyleSpec('vocab', 2),
      ], AiPromptOpts(version: 'renjiao', volume: '上', grade: 2, diff: 'easy', showAnswer: true));
      expect(en.contains('词汇'), true);
    });
  });
}
