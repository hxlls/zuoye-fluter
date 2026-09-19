/// PDF 教材导入 · 第一段：把「一页页原始词」清洗成「可读的正文行」。
///
/// 为什么不直接调 `extractText()`：真实出版社教材的版面噪声有三类，
/// 每一类都必须在**词**这一级处理（`TextWord` 恰好暴露了 `fontName` 与
/// `bounds` 两个字段），而 `extractText()` 只给一坨字符串，无从下手。
///
/// | 噪声 | 表现 | 判据 |
/// |---|---|---|
/// | 拼音注音 | 每个汉字都带一行注音，而注音字体的 ToUnicode 是错的，字形被错映射成 ASCII 字母（`第dK1课kF开kQi`） | 该字体的非空白词**全部**为纯英文字母 |
/// | 版权水印 | 每页一行完全相同的文字（实测出现 68/70 次） | 跨页重复行统计 |
/// | 符号图标 | 图标字体的子集化错误产出随机 Unicode 区块的字符（实测见过 U+0337 组合符、U+0A93 泰米尔文、U+1093 缅甸文、U+1518 加拿大音节、U+429D 彝文、U+1B62） | 正文合法字符**白名单** |
///
/// 还有两个版面问题，靠字符层面解决不了，必须动用坐标：
///
/// 1. **注音会打断正文行** —— 所以先按 y 粗聚成「带」，带内再按 x 间隙切「段」。
/// 2. **插图对话框与正文并排时基线略有差异**（实测左右两栏中心相差 6pt，
///    字高的 0.45 倍容差分不开）—— 所以最后按段的横向位置分「列」，
///    列内按 y 排序、列间按 x 排序，才能还原出正确阅读顺序。
///
/// 顺序不能换：不先剔注音就没法聚类；不先聚成段就没法分列。
///
/// 本文件**不依赖任何 PDF 库**，输入只有 [PdfWord]，因此可以用纯 Dart 单测
/// 覆盖全部逻辑（接线在 `pdf_service.dart`）。
library;

import 'dart:math' as math;

/// PDF 里最小的可独立定位的文本单元。
class PdfWord {
  final String text;
  final String font;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const PdfWord(this.text, this.font, this.left, this.top, this.right,
      this.bottom);

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;

  @override
  String toString() => 'PdfWord("$text", $font)';
}

/// 同一视觉行内、横向连续的一段文字。
class PdfSegment {
  final List<PdfWord> words; // 已按 x 升序

  const PdfSegment(this.words);

  String get text => words.map((w) => w.text).join();
  double get centerX =>
      words.map((w) => w.centerX).reduce((a, b) => a + b) / words.length;
  double get centerY =>
      words.map((w) => w.centerY).reduce((a, b) => a + b) / words.length;
  double get top => words.map((w) => w.top).reduce(math.min);

  @override
  String toString() => 'PdfSegment("$text")';
}

/// 一个视觉行。分列之后每个 [PdfLine] 只含一个 [PdfSegment]。
class PdfLine {
  final List<PdfSegment> segments; // 已按 x 升序

  const PdfLine(this.segments);

  List<PdfWord> get words => [for (final s in segments) ...s.words];
  String get text => segments.map((s) => s.text).join();
  double get top => segments.map((s) => s.top).reduce(math.min);
  double get centerX =>
      segments.map((s) => s.centerX).reduce((a, b) => a + b) / segments.length;
  double get centerY =>
      segments.map((s) => s.centerY).reduce((a, b) => a + b) / segments.length;

  @override
  String toString() => 'PdfLine("$text")';
}

/// 一页清洗结果。
class CleanedPage {
  /// 1-based，与 PDF 页序一致
  final int pageNumber;

  /// 已按阅读顺序排好的正文行（不含页眉/页脚/水印）
  final List<PdfLine> lines;

  /// 页脚印的页码。等于教材书页码，也用来判定「这是不是正文页」——
  /// 封面、单元扉页、后记、致谢都没有页脚页码。
  final int? printedPageNo;

  const CleanedPage({
    required this.pageNumber,
    required this.lines,
    required this.printedPageNo,
  });

  @override
  String toString() =>
      'CleanedPage($pageNumber, ${lines.length} 行, 书页 $printedPageNo)';
}

// ---------------------------------------------------------------------------
// 字体画像与注音识别
// ---------------------------------------------------------------------------

/// 某个字体在全书的用字统计。
class FontProfile {
  final String name;
  final int wordCount;

  /// 不是「纯英文字母」的词数（含汉字、数字、标点、符号都算）
  final int nonLetterWords;

  const FontProfile({
    required this.name,
    required this.wordCount,
    required this.nonLetterWords,
  });

  @override
  String toString() => 'FontProfile($name, $wordCount 词, '
      '$nonLetterWords 非纯字母)';
}

final RegExp _pureLetters = RegExp(r'^[A-Za-z]+$');

/// 统计全书每个字体排了多少词、其中多少不是纯字母。
List<FontProfile> profileFonts(Iterable<List<PdfWord>> pages) {
  final total = <String, int>{};
  final nonLetter = <String, int>{};
  for (final page in pages) {
    for (final w in page) {
      if (w.text.trim().isEmpty) continue;
      total[w.font] = (total[w.font] ?? 0) + 1;
      if (!_pureLetters.hasMatch(w.text)) {
        nonLetter[w.font] = (nonLetter[w.font] ?? 0) + 1;
      }
    }
  }
  final out = <FontProfile>[
    for (final e in total.entries)
      FontProfile(
        name: e.key,
        wordCount: e.value,
        nonLetterWords: nonLetter[e.key] ?? 0,
      ),
  ];
  out.sort((a, b) => b.wordCount.compareTo(a.wordCount));
  return out;
}

/// 注音字体的识别门槛（词数）。
///
/// 两个条件缺一不可，缺了任何一个都会删错东西：
/// - **只**看「全部纯字母」→ 封面的书名拼音（实测 Arial，12 词）会被当成注音，
///   把书名删掉；
/// - **只**看词数 → 正文主力字体入选，整本书被清空。
const int kAnnotationMinWords = 20;

/// 找出「整本书里只排纯英文字母」的字体 —— 在中文教材里这就是拼音注音。
///
/// 实测（人教社《道德与法治》一年级上册）：全书 27 个字体中只有注音字体
/// 命中，而含数字的 Times、含点号的 AdobeSongStd、词数不足的封面 Arial
/// 全部落选，正文与数字因此毫发无损。
Set<String> detectAnnotationFonts(
  List<FontProfile> profiles, {
  int minWords = kAnnotationMinWords,
}) {
  return {
    for (final p in profiles)
      if (p.wordCount >= minWords && p.nonLetterWords == 0) p.name,
  };
}

// ---------------------------------------------------------------------------
// 正文合法字符白名单
// ---------------------------------------------------------------------------

/// 该码点是否属于「正文里可能出现的字符」。
///
/// 用白名单而不是黑名单：符号字体的错映射散落在任意 Unicode 区块
/// （见文件头的实测清单），黑名单永远列不全，而正文用到的字符是有限的。
bool isAllowedBodyChar(int rune) {
  if (rune == 0x09 || rune == 0x0A || rune == 0x0D) return true; // 制表/换行
  if (rune == 0x20 || rune == 0x00A0) return true; // 空格、不换行空格
  if (rune == 0x2002 || rune == 0x2003) return true; // en/em space
  if (rune >= 0x21 && rune <= 0x7E) return true; // ASCII 可打印
  if (rune >= 0x4E00 && rune <= 0x9FFF) return true; // 汉字
  if (rune >= 0x3000 && rune <= 0x303F) return true; // CJK 标点
  if (rune >= 0xFF00 && rune <= 0xFFEF) return true; // 全角
  if (rune >= 0x2010 && rune <= 0x201F) return true; // – — ‘ ’ “ ”
  if (rune == 0x2022) return true; // •
  if (rune == 0x2026) return true; // …
  if (rune == 0x00B7 || rune == 0x00D7) return true; // · ×
  if (rune == 0x221A) return true; // √（教材里的勾选项）
  return false;
}

/// 去掉正文里不该出现的字符。
String stripNoise(String s) {
  final buf = StringBuffer();
  for (final r in s.runes) {
    if (isAllowedBodyChar(r)) buf.writeCharCode(r);
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// 聚类：带 → 段 → 列
// ---------------------------------------------------------------------------

double _median(List<double> xs) {
  if (xs.isEmpty) return 0;
  final s = List<double>.from(xs)..sort();
  return s[s.length ~/ 2];
}

/// 把一个词列表排成阅读顺序的行。
///
/// 三步（顺序不可换）：
/// 1. 按 y 粗聚成**带**（容差 = 字高中位数 × 0.5）—— 注音与汉字同一视觉行
///    但 y 不同，不聚就会把正文切成单字行；
/// 2. 带内按 x 间隙切成**段**（间隙 > 字高 × 2）；
/// 3. 段按横向中心分**列**（容差 = 版心宽 × 0.2），列内按 y、列间按 x 输出。
///
/// 第 3 步是必需的：并排的插图对话框与正文基线相差约 6pt，前两步分不开，
/// 不按列归位就会读出「这是爸爸 我的书包是奶奶送给我的，」这种交错。
List<PdfLine> clusterLines(List<PdfWord> words) {
  final ws = [
    for (final w in words)
      if (w.text.trim().isNotEmpty) w,
  ];
  if (ws.isEmpty) return const [];

  final h = _median([for (final w in ws) w.height]);
  final rowTol = math.max(h * 0.5, 2.0);
  final gap = math.max(h * 2.0, 6.0);

  // 1) 带
  final sortedY = List<PdfWord>.from(ws)
    ..sort((a, b) => a.centerY.compareTo(b.centerY));
  final bands = <List<PdfWord>>[];
  for (final w in sortedY) {
    if (bands.isNotEmpty) {
      final b = bands.last;
      final ref = b.map((x) => x.centerY).reduce((a, c) => a + c) / b.length;
      if ((ref - w.centerY).abs() <= rowTol) {
        b.add(w);
        continue;
      }
    }
    bands.add(<PdfWord>[w]);
  }

  // 2) 段
  final segments = <PdfSegment>[];
  for (final b in bands) {
    b.sort((a, c) => a.left.compareTo(c.left));
    var cur = <PdfWord>[b.first];
    for (var i = 1; i < b.length; i++) {
      final prev = b[i - 1];
      final w = b[i];
      if (w.left - prev.right > gap) {
        segments.add(PdfSegment(cur));
        cur = <PdfWord>[w];
      } else {
        cur.add(w);
      }
    }
    segments.add(PdfSegment(cur));
  }

  // 3) 列
  final minX = ws.map((w) => w.left).reduce(math.min);
  final maxX = ws.map((w) => w.right).reduce(math.max);
  // 下限取 3 倍字高：版心很窄时（测试用小样张、单栏窄栏）纯比例值会过小，
  // 把同一栏内相邻的短段误判成两栏，读出来的顺序就乱了。
  final colTol = math.max((maxX - minX) * 0.2, h * 3.0);

  final byX = List<PdfSegment>.from(segments)
    ..sort((a, b) => a.centerX.compareTo(b.centerX));
  final columns = <List<PdfSegment>>[];
  for (final s in byX) {
    if (columns.isNotEmpty) {
      final c = columns.last;
      final ref = c.map((x) => x.centerX).reduce((a, b) => a + b) / c.length;
      if ((ref - s.centerX).abs() <= colTol) {
        c.add(s);
        continue;
      }
    }
    columns.add(<PdfSegment>[s]);
  }

  final lines = <PdfLine>[];
  for (final c in columns) {
    c.sort((a, b) => a.centerY.compareTo(b.centerY));
    for (final s in c) {
      lines.add(PdfLine([s]));
    }
  }
  return lines;
}

/// 跨页重复行（水印 / 页眉 / 页脚）的出现次数门槛，按总页数的比例。
const double kRepeatedLineRatio = 0.4;

/// 找出出现在至少 [ratio] 比例页面里的行文本。
Set<String> detectRepeatedLines(
  Iterable<List<PdfLine>> pages, {
  double ratio = kRepeatedLineRatio,
}) {
  final list = pages.toList();
  if (list.isEmpty) return const {};
  final count = <String, int>{};
  for (final ls in list) {
    for (final l in ls) {
      final t = l.text.trim();
      if (t.isEmpty) continue;
      count[t] = (count[t] ?? 0) + 1;
    }
  }
  final threshold = math.max((list.length * ratio).floor(), 2);
  return {
    for (final e in count.entries)
      if (e.value >= threshold) e.key,
  };
}

// ---------------------------------------------------------------------------
// 整本清洗
// ---------------------------------------------------------------------------

final RegExp _digitsOnly = RegExp(r'^[0-9]{1,3}$');

/// 页脚区高度：从该页最底部往上多少 pt 之内的纯数字算页码。
const double kFooterBand = 60;

/// 页脚带上沿。正文与页脚的分界，只用来**读页码**。
///
/// ⚠️ **不要拿它整段切掉页脚区。** 实测人教社《道德与法治》一年级上册
/// （页高 737pt）：正文最大底边 **685.2pt**，而带上沿在 673.0pt —— 正文自己
/// 就伸进带里 12pt，整段切会切掉每页最后一行的下半截；带内除水印与页码之外
/// 也确实还有零星正文（实测第 64 页一个「？」低到 696.6pt）。
///
/// 之所以容易看走眼：正文是一个字一个 `TextWord`，水印却是 19 个字的整词
/// （`仅供个人学习使用，未经授权不得另做他用`），于是「带内有没有长中文」
/// 这种粗筛只会看到水印，看着像带内很干净。**量噪声时务必把页码与水印排除。**
///
/// 页脚里那两样东西各有更精确的去处：
/// - 水印 → 跨页重复行检测（实测出现 69/70 次）
/// - 页码 → 结构化阶段的 `digitsOnly` 过滤
double _footerTop(List<PdfWord> ws) {
  if (ws.isEmpty) return double.maxFinite;
  return ws.map((w) => w.bottom).reduce(math.max) - kFooterBand;
}

/// 取页脚带里的页码，取不到返回 null。
///
/// 取**最大**的一个而不是最后一个：目录页、扉页的页脚区可能还印着别的数字，
/// 页码是其中最大的那一个（且 ≤ 3 位），这样结果不依赖词的遍历顺序。
int? _printedPageNo(List<PdfWord> ws, double footerTop) {
  int? best;
  for (final w in ws) {
    if (w.top > footerTop && _digitsOnly.hasMatch(w.text)) {
      final v = int.tryParse(w.text);
      if (v != null && (best == null || v > best)) best = v;
    }
  }
  return best;
}

/// 把整本 PDF 的词列表清洗成可读页。
///
/// [annotationFonts] 留空则自动识别（常规用法）；显式传入便于单测。
List<CleanedPage> cleanDocument(
  List<List<PdfWord>> rawPages, {
  Set<String>? annotationFonts,
  bool stripNoiseChars = true,
}) {
  final fonts = annotationFonts ?? detectAnnotationFonts(profileFonts(rawPages));

  // 1) 剔注音字体 + 过滤符号噪声；顺便记下页脚页码
  //    噪声在**词**这一级就滤掉，后面就不必再重建行对象。
  //    页脚只读页码、不做切除，原因见 kFooterBand 的注释。
  final kept = <int, List<PdfWord>>{};
  final printed = <int, int?>{};
  for (var i = 0; i < rawPages.length; i++) {
    final pageNo = i + 1;
    final body = <PdfWord>[];
    for (final w in rawPages[i]) {
      if (fonts.contains(w.font)) continue;
      if (!stripNoiseChars) {
        body.add(w);
        continue;
      }
      final t = stripNoise(w.text);
      if (t.trim().isEmpty) continue; // 整个词都是符号噪声
      body.add(t == w.text
          ? w
          : PdfWord(t, w.font, w.left, w.top, w.right, w.bottom));
    }
    printed[pageNo] = _printedPageNo(body, _footerTop(body));
    kept[pageNo] = body;
  }

  // 2) 聚类
  final clustered = <int, List<PdfLine>>{};
  for (var i = 0; i < rawPages.length; i++) {
    final pageNo = i + 1;
    clustered[pageNo] = clusterLines(kept[pageNo]!);
  }

  // 3) 跨页重复行
  final repeated = detectRepeatedLines(clustered.values);

  // 4) 成页
  final out = <CleanedPage>[];
  for (var i = 0; i < rawPages.length; i++) {
    final pageNo = i + 1;
    final lines = <PdfLine>[];
    for (final l in clustered[pageNo]!) {
      final t = l.text.trim();
      if (t.isEmpty) continue;
      if (repeated.contains(t)) continue;
      lines.add(l); // 文本已在第 1 步滤净，行对象可直接复用
    }
    out.add(CleanedPage(
      pageNumber: pageNo,
      lines: lines,
      printedPageNo: printed[pageNo],
    ));
  }
  return out;
}
