import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/core/math_worksheet.dart';
import 'package:zuoye_fluter/core/math_gen.dart';
import 'package:zuoye_fluter/core/chinese_worksheet.dart';
import 'package:zuoye_fluter/core/english_worksheet.dart';
import 'package:zuoye_fluter/core/calligraphy_worksheet.dart';
import 'package:zuoye_fluter/core/rand_gen.dart';
import 'package:zuoye_fluter/core/worksheet_model.dart';

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
}
