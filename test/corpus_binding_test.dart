/// 「导入的教材/语料是否真的约束出题」的回归测试。
///
/// 分三条路径分别锁定，**结论必须分开看**（一条通不代表另一条通）：
///   A. 普通出题 · 课文阅读（duanwen）—— 由 `chineseRenderPages(customCorpus:)` 承接
///   C. AI 出题 · 语料补题（`aiGenerateQuestionsForPassage`）—— 以语料正文为唯一依据
///   D. AI 出题 · AI 阅读理解（`aiBuildReadingPrompt`）—— 语料优先于内置课文库
///
/// 手法是**哨兵串**：往语料里放一句内置数据、随机模板都不可能拼出来的话，
/// 再看它有没有出现在出题产物里。出现了就说明约束生效，而且来源可归因。
///
/// 这套断言是「教材导入」这条线的核心契约：改了 `aiBuildReadingPrompt`
/// 或语料读取逻辑，这里必须跟着红一次。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/ai/ai_generator.dart';
import 'package:zuoye_fluter/core/chinese_worksheet.dart';
import 'package:zuoye_fluter/core/pdf_textbook_import.dart';
import 'package:zuoye_fluter/core/worksheet_model.dart';
import 'package:zuoye_fluter/data/app_data.dart';

/// 真实教材样本。只存在于开发机（源码机），CI 上没有 —— 依赖它的用例自动跳过。
const _sampleYuwen = '/home/ling/samples/_yuwen6x.pdf';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  const sentinelA = '哨兵甲：猫头鹰在夜里数星星，数到第七颗时天亮了。';
  const sentinelB = '哨兵乙：铁匠铺的炉火映红了半条街，风箱一响就是一整天。';

  List<ReadingBlockData> sentinelCorpus() => [
        ReadingBlockData(
          title: '哨兵课文一',
          text: sentinelA,
          source: 'licensed',
          questions: [ReadingQuestion('哨兵问题一？', '哨兵答案一')],
        ),
        ReadingBlockData(
          title: '哨兵课文二',
          text: sentinelB,
          source: 'licensed',
          questions: [ReadingQuestion('哨兵问题二？', '哨兵答案二')],
        ),
      ];

  ChineseOptions chineseOpts() => ChineseOptions(
        grade: 6,
        version: 'tongbiao',
        volume: '下',
        types: const ['duanwen'],
        counts: const {'duanwen': 2},
      );

  AiPromptOpts aiOpts({bool useTextbook = false, int readingCount = 2}) =>
      AiPromptOpts(
        version: 'tongbiao',
        volume: '下',
        grade: 6,
        diff: 'easy',
        showAnswer: true,
        readingCount: readingCount,
        useTextbook: useTextbook,
      );

  /// 渲染结果里的阅读块
  List<ReadingBlockData> readingBlocks(List<WsPage> pages) => [
        for (final p in pages)
          for (final n in p.nodes)
            if (n is WsBlock && n.data is ReadingBlockData)
              n.data as ReadingBlockData,
      ];

  bool hasPlaceholder(List<WsPage> pages) => pages
      .any((p) => p.nodes.any((n) => n is WsPlaceholder));

  bool hasSection(List<WsPage> pages, String kw) => pages.any((p) => p.nodes
      .any((n) => n is WsSection && n.text.contains(kw)));

  // =========================================================================
  // A. 普通出题（本地渲染）
  // =========================================================================
  group('普通出题 · 课文阅读吃导入语料', () {
    test('传入语料 → 阅读页正文就是语料的正文', () {
      final texts = [
        for (final b in readingBlocks(
            chineseRenderPages(chineseOpts(), customCorpus: sentinelCorpus())))
          b.text
      ];
      expect(texts, contains(sentinelA));
      expect(texts, contains(sentinelB));
    });

    test('不传语料 → 哨兵不出现，且给占位提示（负向对照）', () {
      final pages = chineseRenderPages(chineseOpts());
      expect([for (final b in readingBlocks(pages)) b.text],
          isNot(contains(sentinelA)));
      expect(hasPlaceholder(pages), isTrue,
          reason: '无语料时应显式占位，而不是静默出一张空阅读页');
    });

    test('语料 source=licensed → 卷面出「版权说明」横幅', () {
      final pages =
          chineseRenderPages(chineseOpts(), customCorpus: sentinelCorpus());
      expect(hasSection(pages, '版权说明'), isTrue,
          reason: '导入的课本材料必须带来源声明');
    });
  });

  // =========================================================================
  // A+. 真实 PDF 端到端（无样本时跳过）
  // =========================================================================
  group('真实教材端到端', () {
    test('从真实 PDF 切出的课文，逐课原样成为阅读页正文', () async {
      final bytes = await File(_sampleYuwen).readAsBytes();

      // 分段导入的目录必须由「探测整本」得到再传进来：本段里没有目录页，
      // 而《语文》的课题形态（`2会唱歌的石头`，不带「第N课」）兜底认不出来。
      final probe = await probeTextbookPdf(bytes);
      expect(probe.result.toc, isNotEmpty);

      final r = await parseTextbookPdf(
        bytes,
        firstPage: 6,
        lastPage: 22,
        knownToc: probe.result.toc,
      );
      expect(r.lessons, isNotEmpty);
      expect(r.plannedByToc, isTrue);

      final blocks = readingBlocks(chineseRenderPages(
        chineseOpts(),
        customCorpus: [
          for (final l in r.lessons)
            ReadingBlockData(
                title: l.title, text: l.text, source: 'licensed')
        ],
      ));
      expect(blocks.length, r.lessons.length,
          reason: '切出几课就该渲染几个阅读块，不多不少');
      for (final l in r.lessons) {
        expect(blocks.any((b) => b.title == l.title && b.text == l.text), isTrue,
            reason: '《${l.title}》未原样落到卷面上');
      }
      expect(blocks.every((b) => b.text.trim().isNotEmpty), isTrue);
    }, skip: File(_sampleYuwen).existsSync() ? false : '本机无真实教材样本');

    test('段内无目录页且未传 knownToc → 切不出课（已知边界）', () async {
      final bytes = await File(_sampleYuwen).readAsBytes();
      final r = await parseTextbookPdf(bytes, firstPage: 6, lastPage: 22);
      expect(r.lessons, isEmpty,
          reason: '《语文》课题不带「第N课」，无目录时兜底识别不了；'
              '面板必须先 probe 再把 toc 传进来');
    }, skip: File(_sampleYuwen).existsSync() ? false : '本机无真实教材样本');
  });

  // =========================================================================
  // C/D. AI 出题
  // =========================================================================
  group('AI 出题', () {
    test('语料补题：提示词内嵌【原文】，以语料正文为唯一依据', () {
      final src = File('lib/ai/ai_generator.dart').readAsStringSync();
      final a = src.indexOf(
          'Future<List<ReadingQuestion>> aiGenerateQuestionsForPassage');
      final b = src.indexOf('/// AI 阅读生成（英语）');
      expect(a, greaterThanOrEqualTo(0));
      expect(b, greaterThan(a));
      final body = src.substring(a, b);
      expect(body, contains('【原文】'));
      expect(body, contains(r'$text'));
      expect(body, contains(r'$title'));
      expect(body, contains('请勿改写'),
          reason: '必须明确禁止 AI 改写/替代原文');
    });

    test('AI 阅读理解：导入语料进提示词，且不再混入内置课文', () {
      final p = aiBuildReadingPrompt(aiOpts(), corpus: sentinelCorpus());
      expect(p, contains(sentinelA));
      expect(p, contains(sentinelB));
      expect(p, contains('哨兵课文一'),
          reason: '全书篇目要列出 —— 这是「不许超纲选文」的约束本体');
      expect(p, contains('严禁超出上面【全书篇目】的范围'));
      expect(p, isNot(contains('是从"')),
          reason: '两边同时给会让出题范围漂移，语料驱动时应完全压制内置库');
    });

    test('无语料时退回内置课文库（不回归）', () {
      final p = aiBuildReadingPrompt(aiOpts(useTextbook: true));
      expect(p, contains('课本中选取的'));
      expect(p, isNot(contains(sentinelA)));
    });

    test('未开课文模式 → 原创短文提示词（不回归）', () {
      final p = aiBuildReadingPrompt(aiOpts());
      expect(p, contains('原创阅读理解练习'));
      expect(p, isNot(contains(sentinelA)));
    });

    test('只有导入语料时，正文只取前 readingCount 篇（控制提示词长度）', () {
      final p = aiBuildReadingPrompt(aiOpts(readingCount: 1),
          corpus: sentinelCorpus());
      expect(p, contains(sentinelA));
      expect(p, isNot(contains(sentinelB)),
          reason: '正文按 readingCount 截取；但篇目仍全列于【全书篇目】');
      expect(p, contains('哨兵课文二'),
          reason: '未入选正文的篇目也要出现在范围清单里');
    });
  });
}
