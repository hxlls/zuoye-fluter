/// 页清洗（`pdf_page_cleaner.dart`）的单元测试。
///
/// 第 7 页那 41 个词是从**真实教材**里导出来的原始数据
/// （人教社《道德与法治》一年级上册，`syncfusion_flutter_pdf` 的 `TextWord`），
/// 不是手编的：坐标一旦手编，就测不出「注音与汉字是否合行」「页码会不会
/// 被排到全页最前」这类只有真实版面才有的问题 —— 而这两个正是实测踩到的坑。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zuoye_fluter/core/pdf_page_cleaner.dart';

/// 真实教材 PDF 第 7 页：文本 / 字体 / left / top / right / bottom
const List<List<Object>> kPage7 = [
  ['第', 'FZLTZHUNHK', 42.52, 60.34, 63.52, 81.34],
  ['dK', 'HanyuXi', 47.96, 39.34, 58.29, 52.34],
  ['1课', 'FZLTZHUNHK', 68.98, 60.34, 106.28, 81.34],
  ['kF', 'HanyuXi', 89.78, 39.34, 101.96, 52.34],
  ['开', 'FZKTK', 129.38, 57.99, 156.38, 84.99],
  ['kQi', 'HanyuXi', 134.77, 39.34, 150.99, 52.34],
  ['开', 'FZKTK', 163.13, 57.99, 190.13, 84.99],
  ['kQi', 'HanyuXi', 168.52, 39.34, 184.74, 52.34],
  ['心', 'FZKTK', 196.88, 57.99, 223.88, 84.99],
  ['xUn', 'HanyuXi', 202.79, 39.34, 217.96, 52.34],
  ['心', 'FZKTK', 230.63, 57.99, 257.63, 84.99],
  ['xUn', 'HanyuXi', 236.54, 39.34, 251.71, 52.34],
  ['上', 'FZKTK', 264.38, 57.99, 291.38, 84.99],
  ['shSng', 'HanyuXi', 261.63, 39.34, 294.13, 52.34],
  ['学', 'FZKTK', 298.13, 57.99, 325.13, 84.99],
  ['xuR', 'HanyuXi', 302.37, 39.34, 320.89, 52.34],
  ['去', 'FZKTK', 331.88, 57.99, 358.88, 84.99],
  ['qM', 'HanyuXi', 338.67, 39.34, 352.09, 52.34],
  ['上', 'FZKTK', 58.11, 149.70, 79.11, 170.70],
  ['shSng', 'HanyuXi', 53.11, 134.10, 83.11, 146.10],
  ['学', 'FZKTK', 84.36, 149.70, 105.36, 170.70],
  ['xuR', 'HanyuXi', 86.31, 134.10, 103.41, 146.10],
  ['啦', 'FZKTK', 110.61, 149.70, 131.61, 170.70],
  ['la', 'HanyuXi', 116.39, 134.10, 125.83, 146.10],
  ['，真', 'FZKTK', 131.61, 149.70, 173.46, 170.70],
  ['zhEn', 'HanyuXi', 151.14, 134.10, 174.78, 146.10],
  ['高', 'FZKTK', 178.71, 149.70, 199.71, 170.70],
  ['gQo', 'HanyuXi', 179.06, 134.10, 199.37, 146.10],
  ['兴', 'FZKTK', 204.96, 149.70, 225.96, 170.70],
  ['xKng', 'HanyuXi', 205.11, 134.10, 225.81, 146.10],
  [' 学校是你学本领、', 'FZKTK', 79.68, 206.53, 210.18, 219.53],
  ['长见识的地方……', 'FZKTK', 79.68, 229.53, 183.68, 242.53],
  [' 今天你就是小学生', 'FZKTK', 79.68, 291.47, 209.68, 304.47],
  ['啦，祝贺你！', 'FZKTK', 79.68, 314.47, 157.68, 327.47],
  [' 学校什么', 'FZKTK', 300.47, 223.23, 379.83, 236.23],
  ['样呢？', 'FZKTK', 300.47, 246.23, 339.47, 259.23],
  ['快走，上学啦！', 'FZKTK', 294.36, 525.61, 385.36, 538.61],
  ['1', 'DINAlternate', 189.18, 366.26, 196.95, 382.46],
  ['2', 'DINAlternate', 339.22, 645.25, 347.00, 661.45],
  ['2', 'FZDBSK', 33.78, 695.91, 40.78, 709.91],
  ['仅供个人学习使用，未经授权不得另做他用', 'SimSun', 89.79, 716.91, 431.79, 734.91],
];

const String kWatermark = '仅供个人学习使用，未经授权不得另做他用';

List<PdfWord> page7() => [
      for (final w in kPage7)
        PdfWord(w[0] as String, w[1] as String, w[2] as double, w[3] as double,
            w[4] as double, w[5] as double),
    ];

/// 造若干个同一字体的词，横向排开。
List<PdfWord> run(String font, List<String> texts) => [
      for (var i = 0; i < texts.length; i++)
        PdfWord(texts[i], font, i * 20.0, 0, i * 20.0 + 18, 18),
    ];

void main() {
  group('字体画像与注音识别', () {
    test('profileFonts 按字体统计词数与非纯字母词数', () {
      final p = profileFonts([page7()]);
      expect(p.first.name, 'FZKTK', reason: '正文字体词数最多，应排第一');

      final hanyu = p.firstWhere((e) => e.name == 'HanyuXi');
      expect(hanyu.wordCount, 15);
      expect(hanyu.nonLetterWords, 0, reason: '注音字体全是纯英文字母');

      final body = p.firstWhere((e) => e.name == 'FZKTK');
      expect(body.wordCount, 20);
      expect(body.nonLetterWords, 20, reason: '正文字体一个纯字母词都没有');

      final simsun = p.firstWhere((e) => e.name == 'SimSun');
      expect(simsun.wordCount, 1);
      expect(simsun.nonLetterWords, 1, reason: '水印含汉字与标点');
    });

    test('detectAnnotationFonts：必须同时满足「全字母」与「词数门槛」', () {
      final profiles = profileFonts([
        run('HanyuXi', List.filled(30, 'kQi')), // 注音：全字母且够多
        run('FZKTK', List.filled(30, '第')), // 正文：一个字母都没有
        // 数字混排的字体：含数字就不是「全字母」，不入选
        run('Times', [...List.generate(20, (i) => '$i'), '第']),
        // 封面书名拼音：全字母但只有 12 个词，不够门槛
        run('Arial', List.filled(12, 'DAODEYUFAZHI')),
      ]);

      expect(detectAnnotationFonts(profiles), {'HanyuXi'});

      // 门槛是可调的，证明上面 Arial 落选的原因是词数而不是别的
      expect(detectAnnotationFonts(profiles, minWords: 5),
          containsAll({'HanyuXi', 'Arial'}));
    });

    test('词数门槛的下限是有意义的：真实教材里注音有 1648 个词', () {
      expect(kAnnotationMinWords, greaterThan(12),
          reason: '门槛必须高于封面书名拼音的词数（实测 12），否则会删掉书名');
    });
  });

  group('正文合法字符白名单', () {
    test('保留正文会用到的字符', () {
      const keep = 'abcXYZ019，。！？、；：“”‘’（）《》—…·×√％＋';
      expect(stripNoise(keep), keep);
      expect(stripNoise('第1课开开心心上学去'), '第1课开开心心上学去');
    });

    test('剔除实测见过的错映射符号', () {
      // 真实教材里符号字体的错映射散落在任意 Unicode 区块
      const dirty = '开\u0337心\u0A93上\u1093学\u1518去\u429D啦\u1B62';
      expect(stripNoise(dirty), '开心上学去啦');
      expect(stripNoise('\uFFFD\uFFFD'), '', reason: '替换符不是正文');
    });

    test('整词是符号时返回空串，调用方据此丢词', () {
      expect(stripNoise('\u1B62\u0337').trim(), '');
    });
  });

  group('聚类（真实第 7 页）', () {
    test('注音与汉字合行：标题还原成完整一行', () {
      final lines = clusterLines(page7());
      final title = lines.firstWhere((l) => l.text.contains('开开心心上学去'));
      // 注音在 top=39.34、汉字在 top=57.99，中心差 25.7pt；
      // 靠「字高中位数 × 0.5」的容差把它们聚成同一视觉行，
      // 否则标题会被切成「第」「开」「开」「心」…… 一堆单字行。
      expect(title.text, '第1课开开心心上学去');
    });

    test('同一视觉行的多个段按 x 拼回', () {
      final lines = clusterLines(page7());
      expect(lines.map((l) => l.text), contains('上学啦，真高兴'));
    });

    test('按列归位：页脚页码自成首列，正文左栏排在右栏旁注之前', () {
      // 走生产路径：注音在这一步之前已按字体整体剔掉
      // （`clusterLines` 的输入永远是剔过的词，不会带拼音）。
      final body = [
        for (final w in page7())
          if (w.font != 'HanyuXi') w,
      ];
      final lines = clusterLines(body);

      // 页码印在版心最左（centerX=37.3），离正文栏 81pt、超过列容差 79.6，
      // 于是它自成一列并被排到全页最前 —— `lines.first` 因此**不是**标题行。
      // 结构化阶段必须扫「标题带」而不是取首行，根因就在这里。
      expect(lines.first.words.first.font, 'FZDBSK');
      expect(lines.first.text.trim(), '2');

      final texts = lines.map((l) => l.text).toList();
      final title = texts.indexWhere((t) => t.contains('开开心心上学去'));
      final leftBody = texts.indexWhere((t) => t.contains('学校是你学本领'));
      final rightNote = texts.indexWhere((t) => t.contains('学校什么'));
      // 右栏的问句与左栏正文基线只差几 pt（实测段心 131.7 / 141.9 / 144.9
      // 属同一栏，右栏 320 起），不按列分开就会读成
      // 「学校是你学本领、学校什么长见识的地方…………」这种交错
      expect(title, lessThan(leftBody));
      expect(leftBody, lessThan(rightNote));
    });
  });

  group('跨页重复行', () {
    test('出现比例达到阈值的行被判为水印/页眉', () {
      final pages = [
        for (var i = 0; i < 10; i++)
          [
            const PdfLine([
              PdfSegment([PdfWord(kWatermark, 'SimSun', 0, 700, 300, 718)])
            ]),
            PdfLine([
              PdfSegment([PdfWord('第$i段正文', 'FZKTK', 40, 100, 200, 114)])
            ]),
          ],
      ];
      expect(detectRepeatedLines(pages), {kWatermark});
    });

    test('只出现一两次的行不算重复', () {
      final pages = [
        for (var i = 0; i < 10; i++)
          [
            PdfLine([
              PdfSegment([PdfWord('第$i段正文', 'FZKTK', 40, 100, 200, 114)])
            ]),
            if (i < 2)
              const PdfLine([
                PdfSegment([PdfWord('偶尔出现的行', 'FZKTK', 40, 130, 200, 144)])
              ]),
          ],
      ];
      expect(detectRepeatedLines(pages), isEmpty);
    });
  });

  group('整页清洗（真实第 7 页）', () {
    test('剔注音、记页码、正文行完整', () {
      final pages = cleanDocument([page7()], annotationFonts: {'HanyuXi'});
      expect(pages.length, 1);
      final p = pages.first;
      final texts = p.lines.map((l) => l.text).toList();

      expect(p.printedPageNo, 2, reason: '页脚那个「2」是书页码');

      expect(texts, contains('第1课开开心心上学去'));
      expect(texts, contains('上学啦，真高兴'));

      // 注音已按字体整体剔除，一个音节都不该残留
      for (final t in texts) {
        expect(RegExp(r'^[A-Za-z]+$').hasMatch(t), false,
            reason: '残留了纯字母行：$t');
      }
    });

    test('单页导入时水印去不掉（重复行检测需要多页）', () {
      final pages = cleanDocument([page7()], annotationFonts: {'HanyuXi'});
      final texts = pages.first.lines.map((l) => l.text);
      expect(texts, contains(kWatermark),
          reason: '只出现一次的行不会被判为重复 —— 这是已知的边界，'
              '整本/分段导入时它出现 69 次，会被剔除');
    });

    test('多页时水印被剔除，页码行留下（由结构化阶段过滤）', () {
      final pages = cleanDocument([
        for (var i = 0; i < 5; i++)
          [
            const PdfWord(kWatermark, 'SimSun', 89.79, 716.91, 431.79, 734.91),
            PdfWord('第${i + 1}段正文', 'FZKTK', 42.52, 120.0, 358.88, 134.0),
            PdfWord('${i + 2}', 'FZDBSK', 33.78, 695.91, 40.78, 709.91),
          ],
      ], annotationFonts: const {});
      final all = [for (final p in pages) ...p.lines.map((l) => l.text)];
      expect(all, isNot(contains(kWatermark)));
      expect(all, contains('第1段正文'));
      expect(pages.map((p) => p.printedPageNo), [2, 3, 4, 5, 6]);
    });

    test('不整段切页脚：版心下方伸进带里的正文必须保留', () {
      // 实测正文最大底边 685.2pt、页脚带上沿 673.0pt —— 正文自己就伸进带里
      // 12pt。若按「带」整段切，这一行会被吃掉。带内除水印与页码之外也确实
      // 还有零星正文（实测第 64 页一个「？」低到 696.6pt）。
      final words = [
        const PdfWord(kWatermark, 'SimSun', 89.79, 716.91, 431.79, 734.91),
        const PdfWord('最后', 'FZKTK', 40, 679.0, 80, 693.0), // top 679 > 673
        const PdfWord('一行', 'FZKTK', 80, 679.0, 120, 693.0),
        const PdfWord('2', 'FZDBSK', 33.78, 695.91, 40.78, 709.91),
      ];
      final pages = cleanDocument([words], annotationFonts: const {});
      final texts = pages.first.lines.map((l) => l.text).toList();
      expect(texts, contains('最后一行'));
      expect(pages.first.printedPageNo, 2);
    });
  });
}
