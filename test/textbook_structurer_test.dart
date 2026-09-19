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
        line(300, '道德与法治'),
        line(340, '一年级上册'),
      ]),
      pg(2, null, [line(200, '人民教育出版社')]),
      // 目录第一页：有「目录」标题
      pg(3, null, [
        line(80, '目录'),
        line(120, '第一单元 我是小学生啦/1'),
        line(140, '第1课 开开心心上学去/2'),
        line(160, '第2课 我向国旗敬个礼/5'),
        line(200, '第二单元 过好校园生活/7'),
        line(220, '第3课 老师，您好！/8'),
      ]),
      // 目录第二页：**没有**「目录」二字 —— 真实教材就是如此
      pg(4, null, [
        line(120, '第三单元 养成良好习惯/11'),
        line(140, '第4课 作息有规律/12'),
        line(180, '第四单元 我们讲文明/15'),
        line(200, '第5课 对人有礼貌/16'),
      ]),
      pg(5, null, [line(70.3, '第一单元'), line(71.3, '我是小学生啦')]),
      pg(6, 2, [
        ...furniture(2, '第一单元 我是小学生啦'),
        line(58, '第1课 开开心心上学去'),
        line(120, '上学啦，真高兴'),
      ]),
      pg(7, 3, [
        ...furniture(3, '第一单元 我是小学生啦'),
        line(120, '学校是你学本领、'),
        line(140, '长见识的地方……'),
      ]),
      pg(8, 4, [
        ...furniture(4, '第一单元 我是小学生啦'),
        line(120, '今天你就是小学生啦，祝贺你！'),
      ]),
      pg(9, 5, [
        ...furniture(5, '第一单元 我是小学生啦'),
        line(58, '第2课 我向国旗敬个礼'),
        line(120, '升国旗了'),
      ]),
      pg(10, 6, [
        ...furniture(6, '第一单元 我是小学生啦'),
        line(120, '要面向国旗，立正敬礼。'),
      ]),
      pg(11, null, [line(70.3, '第二单元'), line(71.3, '过好校园生活')]),
      pg(12, 8, [
        ...furniture(8, '第二单元 过好校园生活'),
        line(58, '第3课 老师，您好！'),
        line(120, '老师，您好！'),
      ]),
    ];

/// 一本「语文」形态的小书，抄自《义务教育教科书·语文》六年级下册的实测特征：
/// **点线目录**（`1北京的春节...........2`）、**课号不带「第/课」**、
/// 目录跨页、单元扉页只印一行 `第一单元`、子篇目与父条目同页（页码不增）。
///
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
      line(124, '1北京的春节...........2'),
      line(148, '2腊八粥...........6'),
    ]),
    // 目录第二页：**没有**「目录」二字，且挂着三个与父条目同页的子篇目
    pg(3, null, [
      line(100, '3古诗三首...........10'),
      line(124, '寒食...........10'),
      line(148, '迢迢牵牛星...........10'),
      line(172, '十五夜望月...........10'),
      line(196, '第二单元...........15'),
      line(220, '4藏戏...........16'),
    ]),
    pg(4, null, [line(70, '第一单元')]), // 单元扉页：只有一行，无页码
  ];
  void page(int pdfPage, int? printed, List<(double, String)> ls) {
    out.add(pg(pdfPage, printed, [for (final l in ls) line(l.$1, l.$2)]));
  }

  // 第1课：书页 2 → PDF 5（正文首行 62.2 与课题行同高，实测如此）
  page(5, 2, [
    (62.2, '1北京的春节'),
    (120, '照北京的老规矩，春节差不多在腊月的初旬就开始了。'),
  ]);
  page(6, 3, [(120, '腊七腊八，冻死寒鸦。')]);
  page(7, 4, [(120, '孩子们准备过年，第一件事是买杂拌儿。')]);
  page(8, 5, [(120, '除夕真热闹。')]);
  // 第2课：书页 6 → PDF 9
  page(9, 6, [
    (62.2, '2腊八粥'),
    (120, '初学喊爸爸的小孩子，会出门叫洋车了。'),
  ]);
  page(10, 7, [(120, '锅中的粥，有声无力地叹着气。')]);
  page(11, 8, [(120, '八儿想，这粥的味道真好啊。')]);
  page(12, 9, [(120, '晚饭桌边，靠着他妈妈斜立着的八儿。')]);
  // 第3课：书页 10 → PDF 13
  page(13, 10, [
    (62.2, '3古诗三首'),
    (120, '寒食'),
  ]);
  page(14, 11, [(120, '春城无处不飞花。')]);
  page(15, 12, [(120, '迢迢牵牛星。')]);
  page(16, 13, [(120, '十五夜望月。')]);
  page(17, 14, [(120, '日暮汉宫传蜡烛。')]);
  page(18, null, [(70, '第二单元')]); // 单元扉页
  // 第4课：书页 16 → PDF 19
  page(19, 16, [
    (62.2, '4藏戏'),
    (120, '藏戏的种子随之撒遍了雪域高原。'),
  ]);
  page(20, 17, [(120, '藏戏就是这样，一代一代地师传身授下去。')]);
  page(21, null, [(120, '后记')]); // 无页码，不算正文被切断
  return out;
}

/// 一本「语文」形态小书的**版面文本目录**。
///
/// 文本抄自《义务教育教科书·语文》六年级下册第 4–5 页
/// `extractText(layoutText: true)` 的实测输出：**条目 / 点线 / 页码三行一组**，
/// 双栏也按栏内顺序排。里面刻意保留了四种真实形态：
/// - 子篇目与父条目同页或紧随其后（`寒食`/`迢迢牵牛星`/`十五夜望月`）；
/// - 条目名印成两行（`◎ 习作例文：` + `别了，语文课`）；
/// - 无编号的独立板块及其下的无名篇目（`古诗词诵读` + `1 采薇（节选）`）；
/// - 印在书末的表格板块（`写字表`/`词语表`）。
const String kYuwenTocText = '''
目录
第一单元
......................................
1
 1 北京的春节
 ...............................
2
 2 腊八粥
 .......................................
4
 3 古诗三首
 ..................................
6
 寒食
 ......................................
6
 迢迢牵牛星
 ..........................
6
 十五夜望月
 ..........................
7
第二单元
.....................................
9
 4 藏戏
 ..........................................
8
 ◎ 习作例文：
 别了，语文课
 ......................
10
 阳光的两种用法
 ..................
11
 古诗词诵读
	.....................................
12
	1 采薇（节选）
	...........................
12
	2 送元二使安西
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

  body(5, 2, [(62.2, '1北京的春节'), (120, '照北京的老规矩，春节差不多在腊月的初旬就开始了。')]);
  body(6, 3, [(120, '腊七腊八，冻死寒鸦。')]);
  body(7, 4, [(62.2, '2腊八粥'), (120, '初学喊爸爸的小孩子，会出门叫洋车了。')]);
  body(8, 5, [(120, '锅中的粥，有声无力地叹着气。')]);
  body(9, 6, [(62.2, '3古诗三首'), (120, '春城无处不飞花。')]);
  body(10, 7, [(120, '十五夜望月。')]);
  body(11, 8, [(62.2, '4藏戏'), (120, '藏戏的种子撒遍雪域高原。')]);
  body(12, 9, [(120, '藏戏就这样一代一代传下去。')]);
  body(13, 10, [
    (62.2, '习作例文：别了，语文课'),
    (120, '我从来没有这样难过。'),
  ]);
  body(14, 11, [(62.2, '阳光的两种用法'), (120, '冬天，母亲把老阳儿叠在被子里。')]);
  body(15, 12, [(62.2, '1 采薇（节选）'), (120, '昔我往矣，杨柳依依。')]);
  body(16, 13, [(62.2, '2 送元二使安西'), (120, '渭城朝雨浥轻尘。')]);
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
            '第一单元 我是小学生啦/1',
            '第1课 开开心心上学去/2',
            '第2课 我向国旗敬个礼/5',
            '第二单元 过好校园生活/7',
            '第3课 老师，您好！/8',
            '第三单元 养成良好习惯/11',
            '第4课 作息有规律/12',
            '第四单元 我们讲文明/15',
            '第5课 对人有礼貌/16',
          ]);
      expect(toc.where((t) => t.isUnit).length, 4);
    });
  });

  group('书名', () {
    test('封面能认出科目与年级册次', () {
      expect(guessTextbookName(miniBook()), '道德与法治 一年级上册');
    });

    test('扫到的不是封面时不许猜', () {
      // 分段导入时前几页是正文。实测一段正文里的「你课后参加美术小组吧！」
      // 曾让整段被命名成「美术」—— 没有年级册次就说明不是封面。
      final body = [
        for (var i = 0; i < 3; i++) pg(i + 1, 30 + i, [line(120, '你课后参加美术小组吧！')]),
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
        line(120, '上学啦，真高兴'),
        line(58, '第1课 开开心心上学去'),
      ]);
      final r = structureTextbook([p]);
      expect(r.lessons.length, 1);
      expect(r.lessons.first.title, '第1课 开开心心上学去');
      // 标题行不该重复出现在正文里
      expect(r.lessons.first.text, '上学啦，真高兴');
    });

    test('单元扉页：标签与名字只差 1pt，要拼成「第一单元 我是小学生啦」', () {
      final p = pg(1, null, [line(70.3, '第一单元'), line(71.3, '我是小学生啦')]);
      final band = headBand(p);
      expect([for (final l in band) l.text], ['第一单元', '我是小学生啦']);
    });

    test('页眉不在标题带里，不会被当成标题', () {
      final p = pg(1, 2, [line(30, '第一单元 我是小学生啦'), line(120, '正文')]);
      expect(headBand(p), isEmpty);
    });
  });

  group('整本结构化', () {
    test('切出单元/课/正文，并挡掉页眉页脚', () {
      final r = structureTextbook(miniBook());
      expect(r.name, '道德与法治 一年级上册');
      expect(r.tocPages, [3, 4]);
      expect(r.unitCount, 4);
      expect(r.plannedByToc, true, reason: '有目录时主路径是按目录划界');
      expect([for (final l in r.lessons) l.title],
          ['第1课 开开心心上学去', '第2课 我向国旗敬个礼', '第3课 老师，您好！']);
      expect([for (final l in r.lessons) l.unit], [
        '第一单元 我是小学生啦',
        '第一单元 我是小学生啦',
        '第二单元 过好校园生活',
      ]);
      expect(r.lessons[0].text,
          '上学啦，真高兴\n学校是你学本领、\n长见识的地方……\n今天你就是小学生啦，祝贺你！');
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
          ['1 北京的春节', '2 腊八粥', '3 古诗三首', '4 藏戏']);
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
          '照北京的老规矩，春节差不多在腊月的初旬就开始了。\n腊七腊八，冻死寒鸦。\n'
          '孩子们准备过年，第一件事是买杂拌儿。\n除夕真热闹。');
    });

    test('目录里页码不增的连续条目是子篇目，并到父条目上', () {
      final r = structureTextbook(miniBook2());
      // 「寒食/迢迢牵牛星/十五夜望月」与《古诗三首》同页（都是书页 10）。
      // 不合并的话它们会算出空正文（end < start），凭空多出三节课。
      expect(r.lessons.any((l) => l.title == '寒食'), false);
      expect(r.lessons[2].title, '3 古诗三首');
      expect(r.lessons[2].text, contains('春城无处不飞花。'));
      expect(r.lessons[2].text, contains('日暮汉宫传蜡烛。'));
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
      expect([for (final l in a.lessons) l.title], ['1 北京的春节', '2 腊八粥']);
      expect(a.lastLessonCutOff, true);
      expect(a.lessons.last.endPage, 10);

      final b = structureTextbook(
        [
          for (final p in miniBook2())
            if (p.pageNumber >= 11) p,
        ],
        knownToc: a.toc,
      );
      // 段首那两页仍是第2课的（跨段续文），不能在本段又出一课「2 腊八粥」
      expect([for (final l in b.lessons) l.title], ['3 古诗三首', '4 藏戏']);
      expect(b.leadingPages, [11, 12]);
      expect(b.leadingText, '八儿想，这粥的味道真好啊。\n晚饭桌边，靠着他妈妈斜立着的八儿。');

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
          ['1 北京的春节', '2 腊八粥', '3 古诗三首']);
      expect(a.lastLessonCutOff, true);

      final b = structureTextbook(
        [
          for (final p in miniBook2())
            if (p.pageNumber >= 14) p,
        ],
        knownToc: a.toc,
      );
      expect([for (final l in b.lessons) l.title], ['4 藏戏'],
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
          ['第2课 我向国旗敬个礼', '第3课 老师，您好！']);
      expect(bare.lessons[0].unit, '',
          reason: '第2课所属单元的扉页不在本段内');

      final withToc = structureTextbook(seg, knownToc: whole.toc);
      expect([for (final l in withToc.lessons) l.title],
          ['第2课 我向国旗敬个礼', '第3课 老师，您好！']);
      expect(withToc.lessons[0].unit, '第一单元 我是小学生啦',
          reason: '本段里没有第一单元的扉页，单元要从目录推');
      expect(withToc.lessons[1].unit, '第二单元 过好校园生活');
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
      expect(b.leadingText, '今天你就是小学生啦，祝贺你！',
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
            '1 北京的春节/2',
            '2 腊八粥/4',
            '3 古诗三首/6',
            '寒食/6',
            '迢迢牵牛星/6',
            '十五夜望月/7',
            '第二单元/9',
            '4 藏戏/8',
            '习作例文：别了，语文课/10',
            '阳光的两种用法/11',
            '古诗词诵读/12',
            '1 采薇（节选）/12',
            '2 送元二使安西/13',
            '写字表/14',
            '词语表/15',
          ]);
      expect(toc.where((t) => t.isUnit).length, 2);
      // 页首的「目录」二字是页面标题，不是条目
      expect(toc.any((t) => t.name.contains('目录')), false);
      // 版面文本里 `◎ 习作例文：` 与 `别了，语文课` 分两行印，要拼成一条
      expect(toc.any((t) => t.name == '习作例文：别了，语文课'), true);
      expect(toc.firstWhere((t) => t.name == '习作例文：别了，语文课').marked,
          true);
    });

    test('末尾的水印不进入目录', () {
      // 页脚水印排在最后一条页码之后，与正文之间还隔着一个空行
      const tail = '\n'
          '供个人学习使用\n'
          '**\n'
          '\n'
          '仅供个人学习使用，未经授权不得另做他用\n';
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
        '1 北京的春节',
        '2 腊八粥',
        '3 古诗三首',
        '4 藏戏',
        '习作例文：别了，语文课',
        '阳光的两种用法',
        '1 采薇（节选）',
        '2 送元二使安西',
        '写字表',
        '词语表',
      ]);
      // 子篇目（寒食/迢迢牵牛星/十五夜望月）不与父条目抢页码，
      // 它们所在的两页都归《古诗三首》
      expect(r.lessons[2].text, contains('春城无处不飞花。'));
      expect(r.lessons[2].text, contains('十五夜望月。'));
      expect(r.lessons[1].endPage, 8, reason: '第2课到第3课前一页为止');
      expect(r.lessons[2].endPage, 10);
      expect(r.unitCount, 2);
    });

    test('古诗词诵读与 1 采薇同页 → 留诗、丢只有标题的板块行', () {
      final b = yuwenBook();
      final r = structureTextbook(b.pages, tocTexts: b.tocTexts);
      expect(r.lessons.any((l) => l.title == '古诗词诵读'), false);
      expect(r.lessons[6].title, '1 采薇（节选）');
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
                if (l.text.startsWith('1北京的春节')) line(140, l.text) else l,
            ],
          ),
      ];
      expect(structureTextbook(moved, tocTexts: b.tocTexts).lessons.length, 10);
      expect(structureTextbook(moved).lessons.length, 0,
          reason: '不带目录文本时，课题不在标题带里就认不出来');
    });
  });
}
