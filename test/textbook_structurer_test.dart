/// 教材结构化（`textbook_structurer.dart`）的单元测试。
///
/// 用一本**合成小书**当夹具，它的版面参数抄自真实教材的实测值：
/// 页眉 top≈30、课题 top≈58、单元扉页 top≈70（标签与名字只差 1pt）、
/// 正文 top>100、页脚页码在带里。把这些真实特征写进夹具，
/// 才能测出「标题带」「单元标签跨行」「分段续接」这些真实踩过的坑。
///
/// 划界的主路径是**目录**（见 lib/core/textbook_structurer.dart 文件头），
/// 所以夹具里那两页目录是关键输入：页码（`/2`）与页序（第 6 页）之差
/// 恰好是 4，与真实教材同样规律。
///
/// ⚠️ **口径：形态真实，内容合成。**
/// 这里所有书页文字（科目名、单元名、课题、正文、目录、水印）都是自己写的，
/// 只沿用真实教材的**版面形态**（点线引导、课号不带「第N课」、子篇目同页、
/// 页码与页序的固定偏移等）。仓库里不要放任何出版社教材的课文名与原文 ——
/// 夹具会被到处复制，混进真课文就等于把版权内容带进代码库。
/// 需要真实样本时放 `~/samples/`（仓库外，见 .gitignore），
/// 端到端验收用 `test/corpus_binding_test.dart`。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zuoye_fluter/core/pdf_page_cleaner.dart';
import 'package:zuoye_fluter/core/textbook_structurer.dart';

/// 造一行：字宽按字数估，够聚类用。
PdfLine line(double top, String text, {double left = 40}) => PdfLine([
      PdfSegment([
        PdfWord(text, 'FZKTK', left, top, left + text.length * 14.0, top + 14)
      ])
    ]);

CleanedPage pg(int no, int? printed, List<PdfLine> lines) =>
    CleanedPage(pageNumber: no, lines: lines, printedPageNo: printed);

/// 页眉、页脚页码 —— 真实教材每页都有，正文阶段必须被挡掉。
List<PdfLine> furniture(int printed, String unit) => [
      line(30, unit), // 页眉
      line(695.9, '$printed'), // 页脚页码
    ];

/// 一本 12 页的小书：封面 / 版权 / 跨页目录 / 单元扉页 ×2 / 3 课。
/// 页偏移 = 4（PDF 第 6 页 = 书页 2），与真实教材同样规律。
List<CleanedPage> miniBook() => [
      pg(1, null, [
        line(200, '义务教育教科书'),
        line(300, '科学'),
        line(340, '一年级上册'),
      ]),
      pg(2, null, [line(200, '示例教育出版社')]),
      // 目录第一页：有「目录」标题
      pg(3, null, [
        line(80, '目录'),
        line(120, '第一单元 走进新校园/1'),
        line(140, '第1课 认识新同学/2'),
        line(160, '第2课 学会看课程表/5'),
        line(200, '第二单元 校园里的规则/7'),
        line(220, '第3课 课间的安全/8'),
      ]),
      // 目录第二页：**没有**「目录」二字 —— 真实教材就是如此
      pg(4, null, [
        line(120, '第三单元 每天的好习惯/11'),
        line(140, '第4课 按时睡觉/12'),
        line(180, '第四单元 说话有礼貌/15'),
        line(200, '第5课 借东西要说谢谢/16'),
      ]),
      pg(5, null, [line(70.3, '第一单元'), line(71.3, '走进新校园')]),
      pg(6, 2, [
        ...furniture(2, '第一单元 走进新校园'),
        line(58, '第1课 认识新同学'),
        line(120, '教室里坐了三十个新同学。'),
      ]),
      pg(7, 3, [
        ...furniture(3, '第一单元 走进新校园'),
        line(120, '同桌把名字写在纸上，'),
        line(140, '一笔一画地教我念。'),
      ]),
      pg(8, 4, [
        ...furniture(4, '第一单元 走进新校园'),
        line(120, '窗外的旗杆上，旗子被风吹得笔直。'),
      ]),
      pg(9, 5, [
        ...furniture(5, '第一单元 走进新校园'),
        line(58, '第2课 学会看课程表'),
        line(120, '课程表贴在教室门后面。'),
      ]),
      pg(10, 6, [
        ...furniture(6, '第一单元 走进新校园'),
        line(120, '语文、数学、体育，一行一行排得很齐。'),
      ]),
      pg(11, null, [line(70.3, '第二单元'), line(71.3, '校园里的规则')]),
      pg(12, 8, [
        ...furniture(8, '第二单元 校园里的规则'),
        line(58, '第3课 课间的安全'),
        line(120, '课间的安全'),
      ]),
    ];

/// 一本「语文」形态的小书：**点线目录**（`1山那边的邮局...........2`）、
/// **课号不带「第/课」**、目录跨页、单元扉页只印一行 `第一单元`、
/// 子篇目与父条目同页（页码不增）。
///
/// 版面形态抄自真实人教版语文教材（**篇名与正文均为合成**）。
/// 偏移 = 3（书页 b 在第 b+3 页），与真实教材一样是常量。
/// 末页是无页码的后记 —— 用来验证「末课不算被切断」。
List<CleanedPage> miniBook2() {
  final out = <CleanedPage>[
    pg(1, null, [
      line(200, '义务教育教科书'),
      line(300, '语文'),
      line(340, '六年级下册'),
    ]),
    // 目录第一页
    pg(2, null, [
      line(100, '第一单元...........1'),
      line(124, '1山那边的邮局...........2'),
      line(148, '2会唱歌的石头...........6'),
    ]),
    // 目录第二页：**没有**「目录」二字，且挂着三个与父条目同页的子篇目
    pg(3, null, [
      line(100, '3三首童谣...........10'),
      line(124, '露珠...........10'),
      line(148, '会走路的树...........10'),
      line(172, '数星星的孩子...........10'),
      line(196, '第二单元...........15'),
      line(220, '4爷爷的木工房...........16'),
    ]),
    pg(4, null, [line(70, '第一单元')]), // 单元扉页：只有一行，无页码
  ];
  void page(int pdfPage, int? printed, List<(double, String)> ls) {
    out.add(pg(pdfPage, printed, [for (final l in ls) line(l.$1, l.$2)]));
  }

  // 第1课：书页 2 → PDF 5（正文首行 62.2 与课题行同高，实测如此）
  page(5, 2, [
    (62.2, '1山那边的邮局'),
    (120, '山那边的邮局天不亮就亮起了第一盏灯。'),
  ]);
  page(6, 3, [(120, '邮差老周一天要走三十里山路。')]);
  page(7, 4, [(120, '信装在帆布包里，一封也不会少。')]);
  page(8, 5, [(120, '山风把铃声送出去很远。')]);
  // 第2课：书页 6 → PDF 9
  page(9, 6, [
    (62.2, '2会唱歌的石头'),
    (120, '溪水从石头上淌过，声音像有人在轻轻哼歌。'),
  ]);
  page(10, 7, [(120, '孩子们把耳朵贴在石头上，听了整整一个下午。')]);
  page(11, 8, [(120, '爷爷说，这块石头记得山谷里所有的调子。')]);
  page(12, 9, [(120, '月亮升起来的时候，石头还在低低地唱。')]);
  // 第3课：书页 10 → PDF 13
  page(13, 10, [
    (62.2, '3三首童谣'),
    (120, '露珠'),
  ]);
  page(14, 11, [(120, '露珠在草叶上滚了一夜。')]);
  page(15, 12, [(120, '会走路的树，一步一步挪过山坡。')]);
  page(16, 13, [(120, '数星星的孩子，把名字念给夜空听。')]);
  page(17, 14, [(120, '天亮了，露珠悄悄回了家。')]);
  page(18, null, [(70, '第二单元')]); // 单元扉页
  // 第4课：书页 16 → PDF 19
  page(19, 16, [
    (62.2, '4爷爷的木工房'),
    (120, '木工房的刨花一层压着一层，闻着像雨后的林子。'),
  ]);
  page(20, 17, [(120, '爷爷说，手艺是手把手传下来的，急不得。')]);
  page(21, null, [(120, '后记')]); // 无页码，不算正文被切断
  return out;
}

/// 一本「语文」形态小书的**版面文本目录**。
///
/// 形态抄自真实语文教材 `extractText(layoutText: true)` 的实测输出：
/// **条目 / 点线 / 页码三行一组**，双栏也按栏内顺序排（**条目名与页码为合成**）。
/// 里面刻意保留了四种真实形态：
/// - 子篇目与父条目同页或紧随其后（`露珠`/`会走路的树`/`数星星的孩子`）；
/// - 条目名印成两行（`◎ 习作园地：` + `我家的院子`）；
/// - 无编号的独立板块及其下的无名篇目（`诗词赏读` + `1 溪边（节选）`）；
/// - 印在书末的表格板块（`写字表`/`词语表`）。
const String kYuwenTocText = '''
目录
第一单元
......................................
1
 1 山那边的邮局
 ...............................
2
 2 会唱歌的石头
 .......................................
4
 3 三首童谣
 ..................................
6
 露珠
 ......................................
6
 会走路的树
 ..........................
6
 数星星的孩子
 ..........................
7
第二单元
.....................................
9
 4 爷爷的木工房
 ..........................................
8
 ◎ 习作园地：
 我家的院子
 ......................
10
 秋天的味道
 ..................
11
 诗词赏读
	.....................................
12
	1 溪边（节选）
	...........................
12
	2 村晚
	.........................
13
写字表
	.............................................
14
词语表
	.............................................
15
''';

/// 与 [kYuwenTocText] 配套的 18 页小书，偏移恒为 3（书页 b 在第 b+3 页）。
({List<CleanedPage> pages, Map<int, String> tocTexts}) yuwenBook() {
  final pages = <CleanedPage>[
    pg(1, null, [line(300, '语文'), line(340, '六年级下册')]),
    // 目录页：正文以 tocTexts 为准，这里只放个标题行占位
    pg(2, null, [line(80, '目录')]),
    pg(3, null, [line(70, '第一单元')]),
    pg(4, null, [line(70, '第二单元')]),
  ];
  void body(int no, int printed, List<(double, String)> ls) {
    pages.add(pg(no, printed, [
      line(30, '语文 六年级下册'), // 页眉
      line(695.9, '$printed'), // 页脚页码
      for (final l in ls) line(l.$1, l.$2),
    ]));
  }

  body(5, 2, [(62.2, '1山那边的邮局'), (120, '山那边的邮局天不亮就亮起了第一盏灯。')]);
  body(6, 3, [(120, '邮差老周一天要走三十里山路。')]);
  body(7, 4, [(62.2, '2会唱歌的石头'), (120, '溪水从石头上淌过，声音像有人在轻轻哼歌。')]);
  body(8, 5, [(120, '孩子们把耳朵贴在石头上，听了整整一个下午。')]);
  body(9, 6, [(62.2, '3三首童谣'), (120, '露珠在草叶上滚了一夜。')]);
  body(10, 7, [(120, '数星星的孩子，把名字念给夜空听。')]);
  body(11, 8, [(62.2, '4爷爷的木工房'), (120, '木工房的刨花落了满地。')]);
  body(12, 9, [(120, '爷爷说，手艺要慢慢学。')]);
  body(13, 10, [
    (62.2, '习作园地：我家的院子'),
    (120, '院墙角那棵石榴树，是我出生那年栽下的。'),
  ]);
  body(14, 11, [(62.2, '秋天的味道'), (120, '秋天的味道，藏在晒过的被子和新收的稻谷里。')]);
  body(15, 12, [(62.2, '1 溪边（节选）'), (120, '溪边的小路弯了又弯。')]);
  body(16, 13, [(62.2, '2 村晚'), (120, '晚风把炊烟吹成了一条线。')]);
  body(17, 14, [(62.2, '写字表'), (120, '写字表的字。')]);
  body(18, 15, [(62.2, '词语表'), (120, '词语表的词。')]);
  return (pages: pages, tocTexts: {2: kYuwenTocText});
}

void main() {
  group('目录', () {
    test('跨页目录：第二页没有「目录」二字也要认出来', () {
      final book = miniBook();
      expect(looksLikeTocPage(book[2].lines.map((l) => l.text)), true);
      // 只认「目录」标题就会漏掉后半本的书目
      expect(looksLikeTocPage(book[3].lines.map((l) => l.text)), true);
      expect(looksLikeTocPage(book[5].lines.map((l) => l.text)), false);
    });

    test('解析出单元与课，并按教材顺序', () {
      final book = miniBook();
      final toc = parseTableOfContents([book[2], book[3]]);
      expect(
          [for (final t in toc) '${t.title}/${t.bookPage}'],
          [
            '第一单元 走进新校园/1',
            '第1课 认识新同学/2',
            '第2课 学会看课程表/5',
            '第二单元 校园里的规则/7',
            '第3课 课间的安全/8',
            '第三单元 每天的好习惯/11',
            '第4课 按时睡觉/12',
            '第四单元 说话有礼貌/15',
            '第5课 借东西要说谢谢/16',
          ]);
      expect(toc.where((t) => t.isUnit).length, 4);
    });
  });

  group('书名', () {
    test('封面能认出科目与年级册次', () {
      expect(guessTextbookName(miniBook()), '科学 一年级上册');
    });

    test('扫到的不是封面时不许猜', () {
      // 分段导入时前几页是正文。实测一段正文里的「你课后去美术教室帮忙吧！」
      // 曾让整段被命名成「美术」—— 没有年级册次就说明不是封面。
      final body = [
        for (var i = 0; i < 3; i++) pg(i + 1, 30 + i, [line(120, '你课后去美术教室帮忙吧！')]),
      ];
      expect(guessTextbookName(body, fallback: '导入教材'), '导入教材');
    });
  });

  group('标题带', () {
    test('页码排在全页最前时，标题仍要被认出来', () {
      // 真实第 7 页的 lines.first 是页脚页码（top=695.9），不是标题 ——
      // 只认 lines.first 会漏掉所有「标题不在最前」的页（实测漏 8/16 课）。
      final p = pg(7, 2, [
        line(695.9, '2'),
        line(120, '教室里坐了三十个新同学。'),
        line(58, '第1课 认识新同学'),
      ]);
      final r = structureTextbook([p]);
      expect(r.lessons.length, 1);
      expect(r.lessons.first.title, '第1课 认识新同学');
      // 标题行不该重复出现在正文里
      expect(r.lessons.first.text, '教室里坐了三十个新同学。');
    });

    test('单元扉页：标签与名字只差 1pt，要拼成「第一单元 走进新校园」', () {
      final p = pg(1, null, [line(70.3, '第一单元'), line(71.3, '走进新校园')]);
      final band = headBand(p);
      expect([for (final l in band) l.text], ['第一单元', '走进新校园']);
    });

    test('页眉不在标题带里，不会被当成标题', () {
      final p = pg(1, 2, [line(30, '第一单元 走进新校园'), line(120, '正文')]);
      expect(headBand(p), isEmpty);
    });
  });

  group('整本结构化', () {
    test('切出单元/课/正文，并挡掉页眉页脚', () {
      final r = structureTextbook(miniBook());
      expect(r.name, '科学 一年级上册');
      expect(r.tocPages, [3, 4]);
      expect(r.unitCount, 4);
      expect(r.plannedByToc, true, reason: '有目录时主路径是按目录划界');
      expect([for (final l in r.lessons) l.title],
          ['第1课 认识新同学', '第2课 学会看课程表', '第3课 课间的安全']);
      expect([for (final l in r.lessons) l.unit], [
        '第一单元 走进新校园',
        '第一单元 走进新校园',
        '第二单元 校园里的规则',
      ]);
      expect(r.lessons[0].text,
          '教室里坐了三十个新同学。\n同桌把名字写在纸上，\n一笔一画地教我念。\n窗外的旗杆上，旗子被风吹得笔直。');
      expect(r.lessons[0].startPage, 6);
      expect(r.lessons[0].endPage, 8);
      expect(r.lessons[0].contentPages, [6, 7, 8]);
      // 目录页码与标题行位置交叉算出的偏移
      expect(r.pageOffset, 4);
      // 封面前的正文只包含有页码的正文页，封面/版权/目录都要挡掉
      expect(r.leadingText, '');
    });

    test('末课撞到末页且有页码时标为「未完」', () {
      final r = structureTextbook(miniBook());
      expect(r.lastLessonCutOff, true,
          reason: '第3课起于末页且末页有页码，正文可能还没结束');
    });

    test('末课后是无页码的后记页时，不算「未完」', () {
      final book = [...miniBook(), pg(13, null, [line(120, '后记')])];
      final r = structureTextbook(book);
      expect(r.lessons.last.startPage, 12);
      expect(r.lessons.last.endPage, 13);
      expect(r.lessons.last.cutOff, false,
          reason: '末页没有页码，是后记而不是被切断的正文');
    });
  });

  group('按目录划界（《语文》六年级下册形态）', () {
    test('点线目录 + 不带「第/课」的课号，照样切出 4 课 2 单元', () {
      final r = structureTextbook(miniBook2());
      expect(r.plannedByToc, true);
      expect(r.name, '语文 六年级下册');
      expect([for (final l in r.lessons) l.title],
          ['1 山那边的邮局', '2 会唱歌的石头', '3 三首童谣', '4 爷爷的木工房']);
      expect([for (final l in r.lessons) l.unit],
          ['第一单元', '第一单元', '第一单元', '第二单元']);
      expect([for (final l in r.lessons) l.startPage], [5, 9, 13, 19]);
      expect([for (final l in r.lessons) l.endPage], [8, 12, 18, 21]);
      expect(r.pageOffset, 3);
    });

    test('课首页上的课题行不进正文，正文首行与课题同高也一样', () {
      final r = structureTextbook(miniBook2());
      // 真实《语文》六下的课题 top=62.2、正文首行 58.2 —— 只差 3.8pt，
      // 靠位置分不开，只能靠「这一行就是课题」来挡
      expect(r.lessons[0].text,
          '山那边的邮局天不亮就亮起了第一盏灯。\n邮差老周一天要走三十里山路。\n'
          '信装在帆布包里，一封也不会少。\n山风把铃声送出去很远。');
    });

    test('目录里页码不增的连续条目是子篇目，并到父条目上', () {
      final r = structureTextbook(miniBook2());
      // 「露珠/会走路的树/数星星的孩子」与《三首童谣》同页（都是书页 10）。
      // 不合并的话它们会算出空正文（end < start），凭空多出三节课。
      expect(r.lessons.any((l) => l.title == '露珠'), false);
      expect(r.lessons[2].title, '3 三首童谣');
      expect(r.lessons[2].text, contains('露珠在草叶上滚了一夜。'));
      expect(r.lessons[2].text, contains('天亮了，露珠悄悄回了家。'));
    });

    test('末课之后是无页码的后记页 → 不算「未完」', () {
      final r = structureTextbook(miniBook2());
      expect(r.lessons.last.endPage, 21);
      expect(r.lessons.last.cutOff, false);
      expect(r.lastLessonCutOff, false);
    });

    test('目录页码与正文对不上时，退回标题带兜底而不是切出一堆空课', () {
      // 把目录页码整体挪到全书之外：偏移算得出来、但课首页全部越界 ——
      // 这正是「拿页面内容核对目录」要拦住的情况
      final book = [
        for (final p in miniBook2())
          CleanedPage(
            pageNumber: p.pageNumber,
            printedPageNo: p.printedPageNo,
            lines: [
              for (final l in p.lines)
                if (!l.text.contains('...')) l else line(l.top, '${l.text.split('...')[0]}...........900'),
            ],
          ),
      ];
      final r = structureTextbook(book);
      expect(r.plannedByToc, false, reason: '课首页全部越界，不能按目录切');
      // 《语文》形态的课题不带「第N课」，标题带兜底认不出来 —— 这是兜底路径
      // 已知的局限，写在这里是为了「以后换教材时能一眼看出退化到哪一步」
      expect(r.lessons, isEmpty);
      expect(r.toc.where((t) => t.isUnit).length, 2, reason: '目录本身还是解析出来了');
    });

    test('分段导入：跨段的那一课只算续文，不重复成课', () {
      final whole = structureTextbook(miniBook2());
      final a = structureTextbook([
        for (final p in miniBook2())
          if (p.pageNumber <= 10) p,
      ]);
      // 第2课跨 9–12 页，本段只到第 10 页
      expect([for (final l in a.lessons) l.title], ['1 山那边的邮局', '2 会唱歌的石头']);
      expect(a.lastLessonCutOff, true);
      expect(a.lessons.last.endPage, 10);

      final b = structureTextbook(
        [
          for (final p in miniBook2())
            if (p.pageNumber >= 11) p,
        ],
        knownToc: a.toc,
      );
      // 段首那两页仍是第2课的（跨段续文），不能在本段又出一课「2 会唱歌的石头」
      expect([for (final l in b.lessons) l.title], ['3 三首童谣', '4 爷爷的木工房']);
      expect(b.leadingPages, [11, 12]);
      expect(b.leadingText, '爷爷说，这块石头记得山谷里所有的调子。\n月亮升起来的时候，石头还在低低地唱。');

      final merged = mergeSegments([a, b]);
      expect([for (final l in merged) l.title],
          [for (final l in whole.lessons) l.title]);
      for (var i = 0; i < merged.length; i++) {
        expect(merged[i].text, whole.lessons[i].text,
            reason: '第 ${i + 1} 课正文应与整本一致');
      }
      expect(merged[1].cutOff, false, reason: '续上之后就不再是未完');
      expect(merged[1].endPage, whole.lessons[1].endPage);
      expect(merged[1].contentPages, whole.lessons[1].contentPages);
    });

    test('本段里一页目录都没有时，靠传入的目录照样切分', () {
      // 切在第 13 页：本段只有末页那一页属于第3课，其余全在下一段
      final a = structureTextbook([
        for (final p in miniBook2())
          if (p.pageNumber <= 13) p,
      ]);
      expect([for (final l in a.lessons) l.title],
          ['1 山那边的邮局', '2 会唱歌的石头', '3 三首童谣']);
      expect(a.lastLessonCutOff, true);

      final b = structureTextbook(
        [
          for (final p in miniBook2())
            if (p.pageNumber >= 14) p,
        ],
        knownToc: a.toc,
      );
      expect([for (final l in b.lessons) l.title], ['4 爷爷的木工房'],
          reason: '第3课起于上一段，它的续文不该在本段又成一课');
      expect(b.lessons.first.unit, '第二单元', reason: '单元归属要能从目录推');

      final whole = structureTextbook(miniBook2());
      final merged = mergeSegments([a, b]);
      expect([for (final l in merged) l.title],
          [for (final l in whole.lessons) l.title]);
      for (var i = 0; i < merged.length; i++) {
        expect(merged[i].text, whole.lessons[i].text,
            reason: '第 ${i + 1} 课正文应与整本一致');
      }
    });
  });

  group('分段导入', () {
    test('一段里没有目录页时，单元归属只能从传入的目录补', () {
      final whole = structureTextbook(miniBook());
      final seg = [
        for (final p in miniBook())
          if (p.pageNumber >= 9) p,
      ];

      // 课题行是印在页面上的，没有目录也切得出来 —— 但本段里没有第一单元的
      // 扉页（在第 5 页，不在本段），单元名无处可推，只能留空。
      // 这就是分段导入必须把首段目录传下来的原因。
      final bare = structureTextbook(seg);
      expect([for (final l in bare.lessons) l.title],
          ['第2课 学会看课程表', '第3课 课间的安全']);
      expect(bare.lessons[0].unit, '',
          reason: '第2课所属单元的扉页不在本段内');

      final withToc = structureTextbook(seg, knownToc: whole.toc);
      expect([for (final l in withToc.lessons) l.title],
          ['第2课 学会看课程表', '第3课 课间的安全']);
      expect(withToc.lessons[0].unit, '第一单元 走进新校园',
          reason: '本段里没有第一单元的扉页，单元要从目录推');
      expect(withToc.lessons[1].unit, '第二单元 校园里的规则');
    });

    test('两段合并后与整本逐字一致', () {
      final whole = structureTextbook(miniBook());
      final a = structureTextbook([
        for (final p in miniBook())
          if (p.pageNumber <= 7) p,
      ]);
      final b = structureTextbook(
        [
          for (final p in miniBook())
            if (p.pageNumber >= 8) p,
        ],
        knownToc: a.toc,
      );

      expect(a.lastLessonCutOff, true);
      expect(a.lessons.length, 1);
      expect(b.leadingText, '窗外的旗杆上，旗子被风吹得笔直。',
          reason: '段首、第一个课题之前的正文属于上一段的最后一课');

      final merged = mergeSegments([a, b]);
      expect([for (final l in merged) l.title],
          [for (final l in whole.lessons) l.title]);
      for (var i = 0; i < merged.length; i++) {
        expect(merged[i].text, whole.lessons[i].text,
            reason: '第 ${i + 1} 课正文应与整本一致');
      }
      expect(merged[0].endPage, whole.lessons[0].endPage);
      expect(merged[0].contentPages, whole.lessons[0].contentPages);
      expect(merged[0].cutOff, false, reason: '续上之后就不再是未完');
    });

    test('三段的拼接同样等价于整本', () {
      final whole = structureTextbook(miniBook());
      final cuts = [1, 5, 9]; // 每段的起始页
      final segs = <TextbookParseResult>[];
      for (var i = 0; i < cuts.length; i++) {
        final from = cuts[i];
        final to = i + 1 < cuts.length ? cuts[i + 1] - 1 : 999;
        segs.add(structureTextbook(
          [
            for (final p in miniBook())
              if (p.pageNumber >= from && p.pageNumber <= to) p,
          ],
          knownToc: segs.isEmpty ? null : segs.first.toc,
        ));
      }
      final merged = mergeSegments(segs);
      expect([for (final l in merged) l.title],
          [for (final l in whole.lessons) l.title]);
      for (var i = 0; i < merged.length; i++) {
        expect(merged[i].text, whole.lessons[i].text);
      }
    });
  });

  group('目录解析（版面文本）', () {
    test('条目 / 点线 / 页码三行一组 → 单元与课按顺序解析', () {
      final toc = parseTableOfContentsText([kYuwenTocText]);
      expect(
          [for (final t in toc) '${t.title}/${t.bookPage}'],
          [
            '第一单元/1',
            '1 山那边的邮局/2',
            '2 会唱歌的石头/4',
            '3 三首童谣/6',
            '露珠/6',
            '会走路的树/6',
            '数星星的孩子/7',
            '第二单元/9',
            '4 爷爷的木工房/8',
            '习作园地：我家的院子/10',
            '秋天的味道/11',
            '诗词赏读/12',
            '1 溪边（节选）/12',
            '2 村晚/13',
            '写字表/14',
            '词语表/15',
          ]);
      expect(toc.where((t) => t.isUnit).length, 2);
      // 页首的「目录」二字是页面标题，不是条目
      expect(toc.any((t) => t.name.contains('目录')), false);
      // 版面文本里 `◎ 习作园地：` 与 `我家的院子` 分两行印，要拼成一条
      expect(toc.any((t) => t.name == '习作园地：我家的院子'), true);
      expect(toc.firstWhere((t) => t.name == '习作园地：我家的院子').marked,
          true);
    });

    test('末尾的水印不进入目录', () {
      // 页脚水印排在最后一条页码之后，与正文之间还隔着一个空行
      const tail = '\n'
          '供学习参考使用\n'
          '**\n'
          '\n'
          '仅供学习参考使用，请勿用于任何商业用途\n';
      final toc = parseTableOfContentsText([kYuwenTocText + tail]);
      expect(toc.length, 16);
      expect(toc.any((t) => t.name.contains('仅供')), false);
    });

    test('整本：子篇目并入父条目，书末表格各自成条', () {
      final b = yuwenBook();
      final r = structureTextbook(b.pages, tocTexts: b.tocTexts);
      expect(r.plannedByToc, true);
      expect(r.pageOffset, 3);
      expect([for (final l in r.lessons) l.title], [
        '1 山那边的邮局',
        '2 会唱歌的石头',
        '3 三首童谣',
        '4 爷爷的木工房',
        '习作园地：我家的院子',
        '秋天的味道',
        '1 溪边（节选）',
        '2 村晚',
        '写字表',
        '词语表',
      ]);
      // 子篇目（露珠/会走路的树/数星星的孩子）不与父条目抢页码，
      // 它们所在的两页都归《三首童谣》
      expect(r.lessons[2].text, contains('露珠在草叶上滚了一夜。'));
      expect(r.lessons[2].text, contains('数星星的孩子，把名字念给夜空听。'));
      expect(r.lessons[1].endPage, 8, reason: '第2课到第3课前一页为止');
      expect(r.lessons[2].endPage, 10);
      expect(r.unitCount, 2);
    });

    test('诗词赏读与 1 溪边同页 → 留诗、丢只有标题的板块行', () {
      final b = yuwenBook();
      final r = structureTextbook(b.pages, tocTexts: b.tocTexts);
      expect(r.lessons.any((l) => l.title == '诗词赏读'), false);
      expect(r.lessons[6].title, '1 溪边（节选）');
      expect(r.lessons[6].startPage, 15);
    });

    test('版面文本目录对不上正文时仍退回标题带，不会切出空课', () {
      final b = yuwenBook();
      // 把目录里的页码整体推到全书之外：偏移照样算得出来，
      // 但每一课的首页都越界 —— 这正是「拿页面内容核对目录」要拦住的情况
      final bad = {
        2: kYuwenTocText.split('\n').map((l) {
          final n = int.tryParse(l.trim());
          return n == null ? l : '${n + 900}';
        }).join('\n'),
      };
      final r = structureTextbook(b.pages, tocTexts: bad);
      expect(r.plannedByToc, false);
      // 兜底认不出这本的课题（不带「第N课」），但目录本身还是解析出来了
      expect(r.toc.where((t) => t.isUnit).length, 2);
    });

    test('给版面文本时，标题行不再需要落在标题带里', () {
      final b = yuwenBook();
      expect(structureTextbook(b.pages, tocTexts: b.tocTexts).lessons.length, 10);
      // 夹具里课题印在 top=62.2，恰在标题带内；把课题挪到带外，
      // 目录路径照样切得出来（兜底路径就会全灭）
      final moved = [
        for (final p in b.pages)
          CleanedPage(
            pageNumber: p.pageNumber,
            printedPageNo: p.printedPageNo,
            lines: [
              for (final l in p.lines)
                if (l.text.startsWith('1山那边的邮局')) line(140, l.text) else l,
            ],
          ),
      ];
      expect(structureTextbook(moved, tocTexts: b.tocTexts).lessons.length, 10);
      expect(structureTextbook(moved).lessons.length, 0,
          reason: '不带目录文本时，课题不在标题带里就认不出来');
    });
  });

  // 「一节课都切不出来」有两种原因，给用户的建议正好相反（换教材 vs 先 OCR）。
  // 判据是汉字占比，本组把阈值两侧与「文本量不足不下结论」都钉住。
  group('语言画像（切不出课时的诊断依据）', () {
    /// 造 [n] 行正文，每行是 [unit] 重复 [perLine] 次。
    List<PdfLine> body(String unit, int n, {int perLine = 20}) => [
          for (var i = 0; i < n; i++) line(120.0 + i * 18, unit * perLine),
        ];

    test('中文教材：汉字占比高，不会被误判成外文', () {
      final p = profileLanguage([pg(1, 1, body('认识新同学。', 20))]);
      expect(p.totalChars, greaterThan(kLangVerdictMinChars));
      // 不会正好 100%：句号这类标点计入总字符但不计入汉字（实测中文教材 77%–83%）
      expect(p.hanRatio, greaterThan(0.8));
      expect(p.looksNonChinese, false);
    });

    test('外文教材：字符数够、汉字占比极低 → 判为非中文', () {
      final p = profileLanguage([
        pg(1, 1, body('Slow and steady wins the race. ', 20)),
      ]);
      expect(p.totalChars, greaterThan(kLangVerdictMinChars));
      expect(p.hanRatio, 0);
      expect(p.looksNonChinese, true);
    });

    test('文本量不足时不下结论（用户可能只选了封面与版权页）', () {
      final p = profileLanguage([
        pg(1, null, [line(200, '英语'), line(300, 'ENGLISH')]),
      ]);
      expect(p.enoughText, false);
      expect(p.looksNonChinese, false,
          reason: '页数太少，分不清「外文教材」与「这几页本来就没有课文」');
    });

    test('阈值边界：汉字正好占 30% 不算外文，差一点才算', () {
      // 阈值两侧各造一本 400 字的书
      final at30 = profileLanguage([
        pg(1, 1, [
          line(120, '${'中' * 120}${'a' * 280}'),
        ]),
      ]);
      expect(at30.totalChars, 400);
      expect(at30.hanRatio, closeTo(kChineseHanRatio, 1e-9));
      expect(at30.looksNonChinese, false);

      final at29 = profileLanguage([
        pg(1, 1, [
          line(120, '${'中' * 116}${'a' * 284}'),
        ]),
      ]);
      expect(at29.hanRatio, lessThan(kChineseHanRatio));
      expect(at29.looksNonChinese, true);
    });

    test('structureTextbook 把画像带进结果', () {
      final r = structureTextbook([
        pg(1, 1, body('Slow and steady wins the race. ', 20)),
      ]);
      expect(r.lessons, isEmpty);
      expect(r.language.looksNonChinese, true);
      expect(r.language.totalChars, greaterThan(kLangVerdictMinChars));
    });
  });
}
