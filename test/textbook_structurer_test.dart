/// 教材结构化（`textbook_structurer.dart`）的单元测试。
///
/// 用一本**合成小书**当夹具，它的版面参数抄自真实教材的实测值：
/// 页眉 top≈30、课题 top≈58、单元扉页 top≈70（标签与名字只差 1pt）、
/// 正文 top>100、页脚页码在带里。把这些真实特征写进夹具，
/// 才能测出「标题带」「单元标签跨行」「分段续接」这些真实踩过的坑。
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
      final toc = parseTableOfContents([
        for (final i in [2, 3]) book[i].lines.map((l) => l.text).join(),
      ]);
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
}
