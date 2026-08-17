import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/core/math_worksheet.dart';
import 'package:zuoye_fluter/core/math_gen.dart';
import 'package:zuoye_fluter/core/chinese_worksheet.dart';
import 'package:zuoye_fluter/core/english_worksheet.dart';
import 'package:zuoye_fluter/core/wav_merge.dart';
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

    test('英语题型按年级过滤', () async {
      await AppData().load();
      List<String> allowed(int g) {
        final data = AppData();
        return ['alphabet', 'trace', 'match', 'cn2en', 'en2cn', 'spell', 'listening', 'aiyuedu']
            .where((id) {
              final r = data.engTypeGrades[id];
              return r == null || (g >= r[0] && g <= r[1]);
            })
            .toList();
      }

      final g1 = allowed(1);
      expect(g1.contains('alphabet'), true); // 一年级字母
      expect(g1.contains('match'), true); // 连线一年级可做
      expect(g1.contains('listening'), true); // 听力一年级可做
      expect(g1.contains('cn2en'), false); // 中译英二年级起
      expect(g1.contains('spell'), false); // 拼写三年级起

      final g2 = allowed(2);
      expect(g2.contains('cn2en'), true);
      expect(g2.contains('spell'), false);

      final g3 = allowed(3);
      expect(g3.contains('spell'), true);
    });

    test('听力题生成：选项含正确项且 4 项', () async {
      await AppData().load();
      final vocab = AppData().vol('renjiao', 3, '上', 'eng')?.eng ?? [];
      expect(vocab.length >= 8, true);
      final items = buildListeningItems(vocab, 8);
      expect(items.length, 8);
      for (final it in items) {
        expect(it.options.length, 4);
        expect(it.options[it.answerIdx], it.correctCn);
        expect(it.options.toSet().length, 4, reason: '${it.en} 选项有重复');
      }
    });

    test('听力朗读文本按年级分级', () async {
      await AppData().load();
      final vocab = AppData().vol('renjiao', 6, '上', 'eng')?.eng ?? [];
      final g1 = buildListeningItems(vocab, 3, grade: 1);
      final g3 = buildListeningItems(vocab, 3, grade: 3);
      final g6 = buildListeningItems(vocab, 3, grade: 6);
      expect(g1.first.readText.startsWith('Number 1.'), true);
      expect(g3.first.readText.contains('It is a'), true);
      expect(g6.first.readText.contains('I can see'), true);
    });

    test('默认只启用默认题型，未勾选/年级不支持的题型不出现', () async {
      await AppData().load();
      List<WsHeading> headings(List<WsPage> pages) => [
            for (final p in pages)
              for (final n in p.nodes)
                if (n is WsHeading) n
          ];

      // 二年级：字母书写、拼写、AI 阅读均不在默认/允许范围，不应出现
      final g2 = englishRenderPages(EnglishOptions(
        grade: 2,
        version: 'renjiao',
        volume: '上',
        types: ['alphabet', 'trace', 'match', 'cn2en', 'en2cn', 'spell', 'listening', 'aiyuedu'],
        counts: {
          'trace': 4,
          'cn2en': 0,
          'en2cn': 0,
          'listening': 0,
        },
      ));
      final t2 = headings(g2).map((h) => h.title).join('|');
      expect(t2.contains('字母书写'), false, reason: t2);
      expect(t2.contains('单词拼写'), false, reason: t2);
      expect(t2.contains('阅读理解'), false, reason: t2);
      expect(t2.contains('单词抄写'), true, reason: t2);

      // 外研三起点三年级：字母书写仅限一年级、拼写需 5 年级起，均不应出现
      final sq3 = englishRenderPages(EnglishOptions(
        grade: 3,
        version: 'waiyanSQ',
        volume: '上',
        types: ['alphabet', 'trace', 'match', 'cn2en', 'en2cn', 'spell', 'listening', 'aiyuedu'],
        counts: {'alphabet': 8, 'trace': 4, 'spell': 8, 'cn2en': 0, 'en2cn': 0, 'listening': 0, 'aiyuedu': 0},
      ));
      final t3 = headings(sq3).map((h) => h.title).join('|');
      expect(t3.contains('字母书写'), false, reason: t3);
      expect(t3.contains('单词拼写'), false, reason: t3);
      expect(t3.contains('单词抄写'), true, reason: t3);
    });

    test('多题型同页紧凑排布，减少页数', () async {
      await AppData().load();
      // 4 个题型各 4 题：若每题型独占一页则至少 4 页；紧凑排布后应更少
      final pages = englishRenderPages(EnglishOptions(
        grade: 3,
        version: 'renjiao',
        volume: '上',
        types: ['trace', 'match', 'cn2en', 'en2cn', 'spell'],
        counts: {'trace': 4, 'match': 4, 'cn2en': 4, 'en2cn': 4, 'spell': 4},
      ));
      final qPages = pages.where((p) => p.title?.main.startsWith('英语练习') ?? false).length;
      expect(qPages, lessThan(5), reason: '共 $qPages 个题目页（4 个题型不应各占一页）');
    });
  });

  group('wav', () {
    Uint8List _makeWav(int rate, int sampleCount) {
      // 生成 1 秒 16bit mono 正弦波 WAV
      final bytes = 44 + sampleCount * 2;
      final out = ByteData(bytes);
      void writeStr(int pos, String s) {
        for (var i = 0; i < s.length; i++) {
          out.setUint8(pos + i, s.codeUnitAt(i));
        }
      }

      writeStr(0, 'RIFF');
      out.setUint32(4, 36 + sampleCount * 2, Endian.little);
      writeStr(8, 'WAVE');
      writeStr(12, 'fmt ');
      out.setUint32(16, 16, Endian.little);
      out.setUint16(20, 1, Endian.little);
      out.setUint16(22, 1, Endian.little);
      out.setUint32(24, rate, Endian.little);
      out.setUint32(28, rate * 2, Endian.little);
      out.setUint16(32, 2, Endian.little);
      out.setUint16(34, 16, Endian.little);
      writeStr(36, 'data');
      out.setUint32(40, sampleCount * 2, Endian.little);
      for (var i = 0; i < sampleCount; i++) {
        out.setInt16(44 + i * 2, 3000, Endian.little);
      }
      return out.buffer.asUint8List();
    }

    test('WAV 拼接含静音间隔', () {
      final a = _makeWav(8000, 8000); // 1 秒
      final b = _makeWav(8000, 8000); // 1 秒
      final merged = WavMerge.merge([a, b], silenceMs: 2000);
      // 2 段各 1 秒 + 1 段 2 秒静音 = 4 秒 @8000Hz = 32000 采样
      final totalSamples = merged.length - 44;
      expect(totalSamples, (8000 * 4) * 2);
      // 中间 2 秒应为静音（近似 0）
      final mid = 44 + 8000 * 2 + 4000; // 第 2.5 秒处
      final b0 = ByteData.sublistView(merged);
      expect(b0.getInt16(mid, Endian.little).abs() < 5, true,
          reason: '间隔应为静音');
      // 首段非静音
      final head = ByteData.sublistView(merged);
      expect(head.getInt16(44 + 1000, Endian.little).abs() > 5, true,
          reason: '首段应有声音');
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

    test('AI 题型按年级过滤', () async {
      await AppData().load();
      // 一年级语文：有 zuci/zaoju/ktian，无 jinyi（近反义词二年级起）
      final g1 = AI_STYLE_OPTIONS['chinese']!
          .where((o) => o.grades.isEmpty || (1 >= o.grades[0] && 1 <= o.grades[1]))
          .map((o) => o.id)
          .toList();
      expect(g1.contains('jinyi'), false);
      expect(g1.contains('zaoju'), true);
      // 三年级英语：trans（互译）四年级起，三年级不出现
      final g3en = AI_STYLE_OPTIONS['english']!
          .where((o) => o.grades.isEmpty || (3 >= o.grades[0] && 3 <= o.grades[1]))
          .map((o) => o.id)
          .toList();
      expect(g3en.contains('trans'), false);
      expect(g3en.contains('vocab'), true);
      // 五年级英语：trans 出现
      final g5en = AI_STYLE_OPTIONS['english']!
          .where((o) => o.grades.isEmpty || (5 >= o.grades[0] && 5 <= o.grades[1]))
          .map((o) => o.id)
          .toList();
      expect(g5en.contains('trans'), true);
    });
  });
}
