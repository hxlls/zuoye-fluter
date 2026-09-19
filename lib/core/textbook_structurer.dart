/// PDF 教材导入 · 第二段：把清洗后的页还原成「单元 / 课 / 正文」。
///
/// **划界依据是教材自己的目录页。** 目录把「第1课 开开心心上学去 / 2」或
/// 「1北京的春节 ……… 2」这样的条目连同书页码印在书上，这是版面无关的
/// 权威来源；页面上的标题行只是旁证。
///
/// 原方案靠「扫标题带」划界，在第二本教材上整本失效，原因有三：
/// - 标题带的纵向位置**逐书不同**。人教社《道德与法治》一年级上册：
///   课题 top≈58、单元扉页 top≈70；《语文》六年级下册：课题 top=62.2、
///   单元标签 top≈33（印在右上角 x≈523）。没有一个窗口同时套得住两本。
/// - 正文首行与课题行可以只差几 pt。六年级下册正文首行 top=58.2–58.4、
///   课题 top=62.2，相差 3.8pt，靠位置分不开标题与正文。
/// - 六年级下册的「阅读材料」里有子篇目（`4狱中联欢`、`7春天的故事`），
///   形态与正课标题一模一样；「寒食/迢迢牵牛星/十五夜望月」是《古诗三首》
///   的子篇，与父条目同页。这些只有目录能区分。
///
/// 划界规则：
/// - 课首页 = 目录页码 + 偏移，偏移取「PDF 页序 − 页脚页码」的众数
/// - 课的正文 = 课首页 → 下一课首页的前一页
/// - 目录里页码不增的连续条目是「父条目 + 子条目」，合并到父条目上 ——
///   否则子条目会算出空正文（与父条目同页，end < start）
/// - 单元归属按目录顺序推：单元条目之后、下一个单元条目之前的课都归它
///
/// 没有目录页、或偏移推不出来时，回落到「扫标题带」的旧路径（见 [_planByHeads]）。
library;

import 'dart:math' as math;

import 'pdf_page_cleaner.dart';

// ---------------------------------------------------------------------------
// 标题带的位置窗口（只给兜底路径用）
// ---------------------------------------------------------------------------

/// 标题行允许的纵向区间（pt，自页面顶边起）。
///
/// 实测人教社《道德与法治》一年级上册：**页眉 top≈30、课题 top≈58、
/// 单元扉页 top≈70、正文 top>100**；取 45–92 恰好只圈住两个标题行。
///
/// ⚠️ 这套数值**只对那一本成立**。《语文》六年级下册的单元标签在 top≈33，
/// 用这个窗口取不到。所以它只用于「连目录都没有」的兜底场景。
const double kHeadMinTop = 45;
const double kHeadMaxTop = 92;

/// 判定「带内两行属于同一视觉行」的 top 容差（pt）。
///
/// 单元扉页的「第一单元」与「我是小学生啦」实测 top 只差 1.0pt ——
/// 它们本就是同一视觉行，被列聚类拆成了两个 [PdfLine]。拼回时按此容差分组。
const double kHeadRowTol = 3.0;

// ---------------------------------------------------------------------------
// 目录
// ---------------------------------------------------------------------------

/// 目录里的一条：单元标题或课，附教材上印的书页码。
class TocEntry {
  final bool isUnit;

  /// 行首的编号：「第1课」/「第一单元」/「12」；没有编号的板块（「写字表」）
  /// 为空串
  final String label;

  /// 条目名：「开开心心上学去」/「我是小学生啦」/「为人民服务」
  final String name;

  /// 教材上印的书页码（不是 PDF 页序）
  final int bookPage;

  /// 目录里带记号（`◎ 口语交际`、`＊略读课文`）的板块。
  ///
  /// 只用于划界时的条目分类（见 [_planByToc]）：有记号的板块即便没有编号，
  /// 也是独立条目，而不是「编号课目下面挂的无名篇目」。
  final bool marked;

  const TocEntry({
    required this.isUnit,
    required this.label,
    required this.name,
    required this.bookPage,
    this.marked = false,
  });

  String get title {
    final parts = [label, name].where((s) => s.trim().isNotEmpty);
    return parts.join(' ');
  }

  @override
  String toString() => 'TocEntry($title, 书页 $bookPage)';
}

/// 一课的最终产物，字段与语料库条目对齐。
class TextbookLesson {
  /// 所属单元名（含「第X单元」前缀）；识别不到时为空串
  final String unit;
  final String title;
  final String text;

  /// 1-based PDF 页序
  final int startPage;
  final int endPage;

  /// 该课实际取到内容的页（排除封面、扉页、后记等无页码的页）
  final List<int> contentPages;

  /// 正文是否被提取区间截断（分段导入时，本段最后一课常为 true）。
  /// 为 true 表示「接着导入下一段」时应把后续文字续到这一课上。
  final bool cutOff;

  const TextbookLesson({
    required this.unit,
    required this.title,
    required this.text,
    required this.startPage,
    required this.endPage,
    required this.contentPages,
    this.cutOff = false,
  });

  int get charCount => text.replaceAll('\n', '').length;

  /// 追加后续段的正文（分段导入：上一段末尾那课的续文）。
  TextbookLesson extendedBy(String more, {required List<int> pages}) {
    final extra = more.trim();
    if (extra.isEmpty && pages.isEmpty) return this;
    return TextbookLesson(
      unit: unit,
      title: title,
      text: extra.isEmpty ? text : '$text\n$extra'.trim(),
      startPage: startPage,
      endPage: pages.isEmpty ? endPage : pages.last,
      contentPages: [...contentPages, ...pages],
      cutOff: false,
    );
  }

  Map<String, dynamic> toCorpusItem() => {
        'unit': unit,
        'title': title,
        'author': '',
        'text': text,
        'questions': <dynamic>[],
      };

  @override
  String toString() =>
      'TextbookLesson($title, 页 $startPage-$endPage, $charCount 字'
      '${cutOff ? ", 未完" : ""})';
}

/// 提取到的文字里汉字占多少 —— 「一节课都切不出来」时用来把原因说准。
///
/// 为什么需要它：切不出课有两种完全不同的原因，而给用户的建议是相反的：
/// - **扫描图片版**（没有文本层）→ 建议先 OCR 或改用「拍照导入」；
/// - **不是中文教材**（有文本层但正文是外文）→ 建议换中文教材，
///   改 OCR 或拍照都没用。
///
/// 实测三本书的非空白字符里汉字占比：《道德与法治》一年级上册 **77.1%**、
/// 《语文》六年级下册 **83.0%**、英语《英语（三年级起点）》六年级下册 **2.3%**。
/// 差距这么大，阈值取 [kChineseHanRatio] 有极宽的安全边。
class TextLanguageProfile {
  /// 清洗后正文的非空白字符数（含汉字、字母、数字、标点）
  final int totalChars;

  /// 其中汉字的个数
  final int hanChars;

  const TextLanguageProfile({
    required this.totalChars,
    required this.hanChars,
  });

  double get hanRatio => totalChars == 0 ? 0 : hanChars / totalChars;

  /// 文本量是否够下「这是不是中文教材」的结论。
  ///
  /// 用户可能只选了封面与版权页（本来就几乎没有课文），
  /// 此时无论比例多少都不该断言「这不是中文教材」。
  bool get enoughText => totalChars >= kLangVerdictMinChars;

  /// 看起来不是中文教材：文本量足够，但汉字占比低得离谱。
  bool get looksNonChinese => enoughText && hanRatio < kChineseHanRatio;

  @override
  String toString() => 'TextLanguageProfile($totalChars 字符, '
      '汉字 $hanChars, ${(hanRatio * 100).toStringAsFixed(1)}%)';
}

/// 下「不是中文教材」结论所需的最少字符数。
///
/// 取整页正文的量级：一页教材正文实测 300–500 字（《语文》130 页 51687 字）。
const int kLangVerdictMinChars = 300;

/// 判「是中文教材」的汉字占比下限。
///
/// 实测中文教材 77%–83%、英语教材 2.3%，取 30% 两边各有极大余量：
/// 即使一本中文教材夹了大量英文（双语读物、附英文原文的书），
/// 汉字占比也远高于 30%；而外文教材要凑到 30% 汉字几乎不可能。
const double kChineseHanRatio = 0.3;

/// 统计清洗后正文的语言画像。
TextLanguageProfile profileLanguage(Iterable<CleanedPage> pages) {
  var total = 0;
  var han = 0;
  for (final p in pages) {
    for (final l in p.lines) {
      for (final r in l.text.runes) {
        if (r == 0x20 || r == 0x0A || r == 0x0D || r == 0x09) continue;
        total++;
        if (r >= 0x4E00 && r <= 0x9FFF) han++;
      }
    }
  }
  return TextLanguageProfile(totalChars: total, hanChars: han);
}

/// 整本教材的解析结果。
class TextbookParseResult {
  /// 建议的语料库名（如「道德与法治 一年级上册」）
  final String name;

  /// 目录条目，按教材顺序
  final List<TocEntry> toc;

  final List<TextbookLesson> lessons;

  /// PDF 页 − 书页；由页脚页码与页序的差算出，识别不出为 null
  final int? pageOffset;

  /// 识别到的目录页（1-based）
  final List<int> tocPages;

  /// 本次划界用的是目录（true）还是标题带兜底（false）。
  /// 兜底时单元归属常常为空，界面据此提示用户。
  final bool plannedByToc;

  /// 本段第一个课题**之前**的正文 —— 分段导入时它属于上一段的最后一课。
  /// 首段（从封面开始）通常为空。
  final String leadingText;

  /// [leadingText] 取自哪几页（用来在合并时修正上一课的终点页）
  final List<int> leadingPages;

  /// 本次实际解析的页数
  final int pageCount;

  /// 本次解析区间的首/末绝对页号（空结果为 0）。
  /// 分段导入靠它算「下一段从第几页起」，并识别重复导入的同一段。
  final int firstPageNo;
  final int lastPageNo;

  /// 整本 PDF 的总页数（分段导入时大于 [lastPageNo]）。
  /// 判「末课是否被区间切断」要用它。
  final int totalPages;

  /// 提取到的文字的语言画像 —— 只在「一节课都切不出来」时用来把诊断说准。
  final TextLanguageProfile language;

  const TextbookParseResult({
    required this.name,
    required this.toc,
    required this.lessons,
    required this.pageOffset,
    required this.tocPages,
    this.plannedByToc = false,
    this.leadingText = '',
    this.leadingPages = const [],
    this.pageCount = 0,
    this.firstPageNo = 0,
    this.lastPageNo = 0,
    this.totalPages = 0,
    this.language = const TextLanguageProfile(totalChars: 0, hanChars: 0),
  });

  /// 接着导入时建议的起始页（1-based）。
  int get nextPage => lastPageNo + 1;

  int get unitCount => toc.where((e) => e.isUnit).length;
  int get charCount => lessons.fold(0, (a, b) => a + b.charCount);

  /// 本段最后一课是否被区间截断（要继续导入下一段）。
  bool get lastLessonCutOff => lessons.isNotEmpty && lessons.last.cutOff;

  @override
  String toString() => 'TextbookParseResult($name, '
      '${lessons.length} 课 / $unitCount 单元, $charCount 字'
      '${plannedByToc ? ", 按目录划界" : ", 按标题带兜底"}'
      '${lastLessonCutOff ? ", 末课未完" : ""})';
}

/// 把多段解析结果拼成整本（分段导入）。
///
/// 规则只有一条：**后一段开头、第一个课题之前的正文，续到前一段的最后一课上**。
/// 同一课只可能被区间切开一次，所以不需要按标题去重合并。
List<TextbookLesson> mergeSegments(List<TextbookParseResult> segments) {
  final out = <TextbookLesson>[];
  for (final seg in segments) {
    if (out.isNotEmpty && seg.leadingText.trim().isNotEmpty) {
      final prev = out.removeLast();
      out.add(prev.extendedBy(seg.leadingText, pages: seg.leadingPages));
    }
    out.addAll(seg.lessons);
  }
  return out;
}

// ---------------------------------------------------------------------------
// 目录解析
// ---------------------------------------------------------------------------

final RegExp _tocPageHits = RegExp(r'(?:/|[.·]{2,})[0-9]{1,3}');

/// 目录条目的尾部：`…/2` 或 `………2`。
///
/// 两种连接方式都是实测到的：
/// - 斜杠 —— 人教社《道德与法治》一年级上册 `第1课开开心心上学去/2`
/// - 点线 —— 人教社《语文》六年级下册 `1北京的春节...............2`
///
/// 点线**要求至少两个点**：书名里常有单个间隔号（`汤姆·索亚历险记`、
/// `卜算子·送鲍浩然之浙东`），一个点的规则会把书名劈开。
final RegExp _tocLine = RegExp(r'^(.*?)(?:/|[.·]{2,})([0-9]{1,3})$');

/// 单元条目：`第一单元` / `第一单元我是小学生啦`
final RegExp _unitWithName =
    RegExp(r'^(第[一二三四五六七八九十]+单元)[\s\u3000]*(.*)$');

/// 课条目：`第1课开开心心上学去` → 编号 + 课名
final RegExp _lessonNo = RegExp(r'^第([0-9]{1,2})课[\s\u3000]*(.*)$');

/// 行首纯序号：`12为人民服务` / `1北京的春节` / `3古诗三首`
final RegExp _leadingNo = RegExp(r'^([0-9]{1,2})[\s\u3000]*(.+)$');

final RegExp _digitsOnly = RegExp(r'^[0-9]{1,3}$');

String _normalize(String s) => s.replaceAll(RegExp(r'[\s\u3000]'), '');

/// 目录页的判据：页面里有 ≥ 3 条「…页码」。
///
/// 比「含『目录』二字」稳：目录常跨页，延续页并不重复印「目录」这个标题
/// （实测《语文》六年级下册第 5 页就没有「目录」而只有条目）。
bool looksLikeTocPage(Iterable<String> lines) {
  final joined = _normalize(lines.join());
  return _tocPageHits.allMatches(joined).length >= 3;
}

/// 从目录页解析出单元与课，按教材顺序。
///
/// 输入是**页**而不是拉平的文本，原因有两个：
/// - 目录常排成**双栏**。实测《语文》六年级下册第 4 页左栏 y=215–623、
///   右栏 y=215–627，两栏纵向完全重叠；按 y 全局排序会读成「左1 右1 左2
///   右2…」，单元分组全乱。
/// - 行聚类在目录页并不可靠：点线是长串独立的词，实测会出现
///   `"寒食..........................11迢迢牵牛星"` 这种把两条目并成一行、
///   内容前后错位的结果。所以分栏之后**按坐标重新拼行**，不信任 [PdfLine]。
List<TocEntry> parseTableOfContents(List<CleanedPage> tocPages) {
  final out = <TocEntry>[];
  for (final page in tocPages) {
    for (final column in _columnsOf(page.lines)) {
      final words = [for (final l in column) ...l.words];
      for (final row in _rowsByTop(words)) {
        final e = _tocEntryOf(row);
        if (e != null) out.add(e);
      }
    }
  }
  return out;
}

/// 把一页的行按 x 分成若干栏（通常 1 栏或 2 栏）。
///
/// 判据是「相邻行 centerX 的最大间隙」：既要占整页宽度足够比例，又要有
/// 绝对下限，否则单栏页面里一句居中标题就会被当成两栏。
List<List<PdfLine>> _columnsOf(List<PdfLine> lines) {
  if (lines.length < 4) return [lines];
  final byX = [...lines]..sort((a, b) => a.centerX.compareTo(b.centerX));
  var bestGap = 0.0;
  var cut = -1;
  for (var i = 0; i + 1 < byX.length; i++) {
    final g = byX[i + 1].centerX - byX[i].centerX;
    if (g > bestGap) {
      bestGap = g;
      cut = i;
    }
  }
  final span = byX.last.centerX - byX.first.centerX;
  if (cut < 0 || span <= 0 || bestGap < span * 0.2 || bestGap < 60) {
    return [lines];
  }
  return [byX.sublist(0, cut + 1), byX.sublist(cut + 1)];
}

/// 按 top 把词重新拼成行（容差小，只在同一视觉行内合并）。
///
/// 容差取 3pt：实测目录行距约 24pt，而行内汉字与数字的 top 差 < 2pt。
List<String> _rowsByTop(List<PdfWord> words, {double tol = 3.0}) {
  if (words.isEmpty) return const [];
  final ws = [...words]..sort((a, b) => a.top.compareTo(b.top));
  final rows = <List<PdfWord>>[];
  for (final w in ws) {
    if (rows.isEmpty || (w.top - rows.last.first.top).abs() > tol) {
      rows.add([w]);
    } else {
      rows.last.add(w);
    }
  }
  return [
    for (final r in rows)
      ([...r]..sort((a, b) => a.left.compareTo(b.left)))
          .map((w) => w.text)
          .join(),
  ];
}

/// 一行目录文本 → 条目；不像目录条目则返回 null。
TocEntry? _tocEntryOf(String raw) {
  final m = _tocLine.firstMatch(raw);
  if (m == null) return null;
  final head = m.group(1)!.trim();
  if (head.isEmpty) return null;
  final bookPage = int.tryParse(m.group(2)!);
  if (bookPage == null) return null;

  final u = _unitWithName.firstMatch(head);
  if (u != null) {
    return TocEntry(
      isUnit: true,
      label: u.group(1)!,
      name: u.group(2)!.trim(),
      bookPage: bookPage,
    );
  }
  final l = _lessonNo.firstMatch(head);
  if (l != null) {
    return TocEntry(
      isUnit: false,
      label: '第${l.group(1)}课',
      name: l.group(2)!.trim(),
      bookPage: bookPage,
    );
  }
  final n = _leadingNo.firstMatch(head);
  if (n != null) {
    return TocEntry(
      isUnit: false,
      label: n.group(1)!,
      name: n.group(2)!.trim(),
      bookPage: bookPage,
    );
  }
  // 没有编号的板块：`口语交际：即兴发言`、`写字表`、`古诗词诵读`
  return TocEntry(isUnit: false, label: '', name: head, bookPage: bookPage);
}

// ---------------------------------------------------------------------------
// 目录解析（版面文本版 · 主路径）
// ---------------------------------------------------------------------------

/// 点线行：`..............`，可能与本条目的页码同行（`...........41`）。
///
/// 点线里除 ASCII `.` 外，还收 CJK 排版常用的一/二点引导符
/// （U+2024 / U+2025）与省略号 —— 换一本教材就可能换一种。
final RegExp _dotsLine = RegExp(r'^[.·…\u2024\u2025\u2027\s]{2,}([0-9]{1,3})?$');

/// 从**版面文本**解析目录条目。
///
/// 为什么不用坐标：实测《语文》六年级下册第 4 页，syncfusion 报的词坐标与
/// PyMuPDF 对不上 —— `快乐读书吧` 的 y 差了整整一行、`鲁滨逊漂流记` 的 x 差
/// 134pt，部分词的 `right` 甚至小于 `left`（负宽度）。据此分栏拼行会得到
/// 前后错位的条目。而 `extractText(layoutText: true)` 的输出顺序**完全正确**：
/// 「条目 / 点线 / 页码」三行一组，双栏也按栏内顺序排。
///
/// 所以主路径只认文本顺序，不碰坐标；坐标版 [parseTableOfContents] 退为兜底。
///
/// 输入的每一页文本按页序排列（目录常跨页）。
List<TocEntry> parseTableOfContentsText(Iterable<String> pageTexts) {
  final out = <TocEntry>[];
  for (final text in pageTexts) {
    final buf = <String>[];
    var expectPage = false;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        // 空行是版面分隔（如正文与页脚水印之间），不是条目的一部分
        buf.clear();
        expectPage = false;
        continue;
      }
      final d = _dotsLine.firstMatch(line);
      if (d != null) {
        if (d.group(1) != null) {
          _emitToc(out, buf, int.parse(d.group(1)!));
          buf.clear();
          expectPage = false;
        } else {
          expectPage = true;
        }
        continue;
      }
      if (_digitsOnly.hasMatch(line)) {
        if (expectPage) {
          _emitToc(out, buf, int.parse(line));
          buf.clear();
          expectPage = false;
        }
        continue; // 游离的页码（如图例、插图序号）
      }
      buf.add(line);
    }
  }
  return out;
}

void _emitToc(List<TocEntry> out, List<String> buf, int bookPage) {
  final lines = [...buf];
  // 页首的「目录」二字是这一页的标题，不是条目的一部分
  while (lines.isNotEmpty && _normalize(lines.first) == '目录') {
    lines.removeAt(0);
  }
  if (lines.isEmpty || bookPage <= 0) return;
  // 条目名可能印成两行（`◎ 快乐读书吧：` + `漫步世界名著花园`），拼成一条
  out.add(_tocEntryOfHead(lines.join(), bookPage));
}

/// 去掉「点线+页码」之后的条目头 → [TocEntry]。
TocEntry _tocEntryOfHead(String head, int bookPage) {
  final raw = head.trim();
  final marked = _tocMarker.hasMatch(raw);
  final h = raw.replaceFirst(_tocMarker, '').trim();
  final u = _unitWithName.firstMatch(h);
  if (u != null) {
    return TocEntry(
      isUnit: true,
      label: u.group(1)!,
      name: u.group(2)!.trim(),
      bookPage: bookPage,
    );
  }
  final l = _lessonNo.firstMatch(h);
  if (l != null) {
    return TocEntry(
      isUnit: false,
      label: '第${l.group(1)}课',
      name: l.group(2)!.trim(),
      bookPage: bookPage,
      marked: marked,
    );
  }
  final n = _leadingNo.firstMatch(h);
  if (n != null) {
    return TocEntry(
      isUnit: false,
      label: n.group(1)!,
      name: n.group(2)!.trim(),
      bookPage: bookPage,
      marked: marked,
    );
  }
  return TocEntry(
    isUnit: false,
    label: '',
    name: h,
    bookPage: bookPage,
    marked: marked,
  );
}

/// 目录里板块前的记号（`◎ 口语交际`、`＊略读课文`）。
///
/// `*` 在文本层里常与后面的字分开（`标*的是略读课文`），所以这里只按
/// **行首**判定，且把常见的圆点/星号/省略号都收进来。
final RegExp _tocMarker = RegExp(r'^[◎○●※＊*·\u25cf\u25cb\u25c6\u2022\s]+');

// ---------------------------------------------------------------------------
// 教材名
// ---------------------------------------------------------------------------

const List<String> _subjectWords = [
  '道德与法治',
  '道德与法制',
  '义务教育教科书',
  '体育与健康',
  '信息科技',
  '语文',
  '数学',
  '英语',
  '科学',
  '音乐',
  '美术',
  '劳动',
  '体育',
];

/// 在第 1–3 页里找出科目名 + 年级 + 册次，拼成建议的语料库名。
///
/// 要求「年级或册次」**必须**命中才认。只认科目词不行：分段导入时这几页是
/// 正文，实测一段正文里的「你课后参加美术小组吧！」就让整段被命名成「美术」。
/// 判不出来就交给调用方传名（分段导入时由首段探测结果提供）。
String guessTextbookName(List<CleanedPage> pages, {String fallback = '导入教材'}) {
  final head = _normalize([
    for (var i = 0; i < math.min(3, pages.length); i++)
      pages[i].lines.map((l) => l.text).join(),
  ].join());
  final grade = RegExp(r'[一二三四五六]年级').firstMatch(head)?.group(0) ?? '';
  final vol = RegExp(r'[上下]册').firstMatch(head)?.group(0) ?? '';
  if (grade.isEmpty && vol.isEmpty) return fallback;

  var subject = '';
  for (final s in _subjectWords) {
    if (s == '义务教育教科书') continue;
    if (head.contains(s)) {
      subject = s;
      break;
    }
  }
  final name = '$subject $grade$vol'.trim();
  return name.isEmpty ? fallback : name;
}

// ---------------------------------------------------------------------------
// 兜底：扫标题带
// ---------------------------------------------------------------------------

/// 取出页面上部「标题带」里的行，排成稳定的阅读顺序。
///
/// 排序而不是直接拼接：单元扉页的「第一单元」与「我是小学生啦」实测 top 只差
/// 1.0pt（同一视觉行），却被列聚类拆成了两个 [PdfLine]；按 (top, centerX)
/// 分组排序，才能稳定拿到「标签在前、名字在后」。
List<PdfLine> headBand(CleanedPage p) {
  final band = <PdfLine>[
    for (final l in p.lines)
      if (l.top >= kHeadMinTop && l.top <= kHeadMaxTop) l,
  ];
  if (band.isEmpty) return const [];
  band.sort((a, b) => a.top.compareTo(b.top));
  final out = <PdfLine>[];
  var i = 0;
  while (i < band.length) {
    final row = <PdfLine>[band[i]];
    var j = i + 1;
    while (j < band.length && band[j].top - band[i].top <= kHeadRowTol) {
      row.add(band[j]);
      j++;
    }
    row.sort((a, b) => a.centerX.compareTo(b.centerX));
    out.addAll(row);
    i = j;
  }
  return out;
}

final RegExp _unitLabelOnly = RegExp(r'^第[一二三四五六七八九十]+单元$');
final RegExp _lessonHeadRe = RegExp(r'^第([0-9]{1,2})课(.+)$');

// ---------------------------------------------------------------------------
// 结构化
// ---------------------------------------------------------------------------

/// 一课的划界结果（内部中间结构，正文尚未收集）。
class _Plan {
  final String unit;

  /// 带编号的完整标题（`第1课 开开心心上学去` / `1 北京的春节`）
  final String title;

  /// 不带编号的课名（`开开心心上学去`）—— 用来在页面上核对该课首页对不对
  final String name;

  final int start;
  final int end;

  /// 终点就是本次解析的末页，且后面还有内容 → 正文被区间切断
  final bool cutOff;

  const _Plan({
    required this.unit,
    required this.title,
    required this.name,
    required this.start,
    required this.end,
    required this.cutOff,
  });
}

/// 把清洗后的页解析成「单元 / 课 / 正文」。
///
/// [knownToc] 用于**分段导入**：教材目录只印在前几页，第二段起页面里没有目录，
/// 传上一段探测到的目录进来，后半本一样能正确切分（否则只有第一段能切出课）。
///
/// [tocTexts] 是目录页的**版面文本**（键为 PDF 页序）。给了它就走文本解析
/// [parseTableOfContentsText]，比按坐标拼行可靠得多 —— 见该函数的说明。
///
/// [totalPages] 是整本 PDF 的总页数。分段导入时本段只是全书的一段，
/// 「末课是否被切断」要靠它与全书末页比较才判得准；缺省按本段末页算。
TextbookParseResult structureTextbook(
  List<CleanedPage> pages, {
  String? fallbackName,
  List<TocEntry>? knownToc,
  Map<int, String>? tocTexts,
  int? totalPages,
}) {
  final byNo = <int, CleanedPage>{for (final p in pages) p.pageNumber: p};
  final lastPageNo = pages.isEmpty ? 0 : pages.last.pageNumber;
  final firstPageNo = pages.isEmpty ? 0 : pages.first.pageNumber;
  // 本段只是全书的一段时，总页数比本段末页大
  final total = math.max(totalPages ?? lastPageNo, lastPageNo);
  final blank = TextbookParseResult(
    name: fallbackName ?? '导入教材',
    toc: const [],
    lessons: const [],
    pageOffset: null,
    tocPages: const [],
    firstPageNo: firstPageNo,
    lastPageNo: lastPageNo,
    totalPages: total,
  );
  if (pages.isEmpty) return blank;

  // ---- 1) 目录 ----
  // 三条路的优先级：本段目录页的版面文本 > 上一段传下来的已知目录 > 按坐标拼行。
  //
  // 第二优先是有原因的：分段导入时本段的页面里根本没有目录，而正文页里偶然
  // 出现的「省略号+数字」会被误判成目录页，拼出半份假目录 —— 拿它顶掉已知
  // 目录，后半本就会一节课都切不出来（实测《语文》六年级下册从第 80 页切段
  // 时正是如此，整段 1.7 万字全被算成「段首正文」）。
  final textTocPages = <int>[];
  final textToc = <TocEntry>[];
  if (tocTexts != null && tocTexts.isNotEmpty) {
    for (final e in tocTexts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      if (!looksLikeTocPage(e.value.split('\n'))) continue;
      textTocPages.add(e.key);
      textToc.addAll(parseTableOfContentsText([e.value]));
    }
  }

  final coordTocPages = <int>[];
  for (final p in pages) {
    if (looksLikeTocPage(p.lines.map((l) => l.text))) coordTocPages.add(p.pageNumber);
  }
  final coordToc = parseTableOfContents([
    for (final p in pages)
      if (coordTocPages.contains(p.pageNumber)) p,
  ]);

  final List<TocEntry> toc;
  final List<int> tocPages;
  var tocFromSegment = true;
  if (textToc.isNotEmpty) {
    toc = textToc;
    tocPages = textTocPages;
  } else if (knownToc != null && knownToc.isNotEmpty) {
    toc = knownToc;
    tocPages = coordTocPages;
    tocFromSegment = false;
  } else {
    toc = coordToc;
    tocPages = coordTocPages;
  }

  // ---- 2) 偏移：目录页码是「书页」，正文按 PDF 页序取 ----
  // 用页脚页码与页序之差取众数 —— 与目录无关，最稳，且能容忍个别页读错
  // （实测《语文》六年级下册第 4 页目录页的页码被读成 60，是明显的离群值）。
  final offset = _modeOffset([
    for (final p in pages)
      if (p.printedPageNo != null) p.pageNumber - p.printedPageNo!,
  ]);

  // ---- 3) 划界 ----
  var plannedByToc = false;
  var plans = const <_Plan>[];
  if (toc.isNotEmpty && offset != null) {
    final byToc = _planByToc(toc, offset, firstPageNo, lastPageNo, total);
    // 三重自校验，全过才敢用目录：
    //   ① 切出了课  ② 第一课在目录页之后（否则页码体系对不上）
    //   ③ 课首页上确实印着这一课的名字（命中率 ≥ 一半）
    // ③ 是关键：它拿页面内容去核对目录页码，而不是只信算术。
    // ② 只在本段的目录页上成立时才检查 —— 目录是上一段传下来的时候，
    // 本段的「目录页」全是误判，拿它当参照只会误杀。
    final firstStart = _firstLessonStart(toc, offset);
    final maxTocPage = tocPages.isEmpty ? 0 : tocPages.reduce(math.max);
    final ok = byToc.isNotEmpty &&
        firstStart != null &&
        (!tocFromSegment || firstStart > maxTocPage) &&
        _titleHitRate(byNo, byToc, firstPageNo) >= 0.5;
    if (ok) {
      plans = byToc;
      plannedByToc = true;
    }
  }
  if (!plannedByToc) {
    plans = _planByHeads(pages, tocPages, firstPageNo, lastPageNo, total, toc);
  }

  // ---- 4) 拼正文 ----
  // 第一课在本次区间之前就已开始 → 它在本段里的那几页是**上一段的续文**
  // （分段导入），不进本段的课列表，由 mergeSegments 拼回上一课。
  final continuing = plans.isNotEmpty && plans.first.start < firstPageNo;
  final begin = continuing ? 1 : 0;

  final lessons = <TextbookLesson>[];
  for (var i = begin; i < plans.length; i++) {
    final pl = plans[i];
    final buf = <String>[];
    final used = <int>[];
    for (var p = pl.start; p <= pl.end; p++) {
      final page = byNo[p];
      // 封面 / 单元扉页 / 后记 / 致谢都没有页脚页码 —— 用页码判定最省事
      if (page == null || page.printedPageNo == null) continue;
      used.add(p);
      for (final line in page.lines) {
        final t = line.text.trim();
        if (t.isEmpty) continue;
        if (line.top < kHeadMinTop) continue; // 页眉
        if (_digitsOnly.hasMatch(t)) continue; // 页码 / 插图序号气泡
        if (p == pl.start && _isLessonTitleLine(t, pl, line.top)) continue;
        if (t.length <= 1 && !_hasHan.hasMatch(t)) continue;
        buf.add(t);
      }
    }

    lessons.add(TextbookLesson(
      unit: pl.unit,
      title: pl.title,
      text: buf.join('\n'),
      startPage: pl.start,
      endPage: pl.end,
      contentPages: used,
      // 只有真取到「本段末页」的正文，才算被区间切断 —— 末页若是无页码的
      // 后记/致谢，正文其实已经结束（实测《道德与法治》一年级上册末课就是这样）
      cutOff: pl.cutOff && used.isNotEmpty && used.last == lastPageNo,
    ));
  }

  // ---- 5) 段首正文 ----
  // 本段第一个课题之前的正文。整本导入时这里是封面/版权/目录/单元扉页，
  // 都会被「没有页脚页码」或「属目录页」挡掉；分段导入时它属于上一段的最后一课。
  final leadEnd = plans.isEmpty
      ? lastPageNo
      : (continuing
          ? math.min(plans.first.end, lastPageNo)
          : math.min(plans.first.start - 1, lastPageNo));
  final lead = <String>[];
  final leadPages = <int>[];
  for (final page in pages) {
    if (page.pageNumber < firstPageNo) continue;
    if (page.pageNumber > leadEnd) break;
    if (tocPages.contains(page.pageNumber)) continue; // 目录条目不是课文
    if (page.printedPageNo == null) continue;
    final inner = <String>[];
    for (final line in page.lines) {
      final t = line.text.trim();
      if (t.isEmpty) continue;
      if (line.top < kHeadMinTop) continue;
      if (_digitsOnly.hasMatch(t)) continue;
      if (t.length <= 1 && !_hasHan.hasMatch(t)) continue;
      inner.add(t);
    }
    if (inner.isEmpty) continue;
    leadPages.add(page.pageNumber);
    lead.addAll(inner);
  }

  return TextbookParseResult(
    name: guessTextbookName(pages, fallback: fallbackName ?? '导入教材'),
    toc: toc,
    lessons: lessons,
    pageOffset: offset,
    tocPages: tocPages,
    plannedByToc: plannedByToc,
    leadingText: lead.join('\n'),
    leadingPages: leadPages,
    pageCount: pages.length,
    firstPageNo: firstPageNo,
    lastPageNo: lastPageNo,
    totalPages: total,
    language: profileLanguage(pages),
  );
}

final RegExp _hasHan = RegExp(r'[\u4e00-\u9fff]');

/// 这一行是不是「本课的标题行」—— 是则该行进标题而不进正文。
///
/// 挡两种情况：
/// - 整行等于标题（`第1课开开心心上学去`）—— 与位置无关
/// - 标题被列聚类拆开后的残片（`开开心心上学去` 单独成行）—— **只在标题带内**认
///
/// 残片判定必须限定位置：实测《道德与法治》一年级上册第3课的正文首行就叫
/// `老师，您好！`，与课名一模一样；不限位置的话这一行会被当成标题残片删掉。
/// 编号那一位（`1` 单独成行）由 `digitsOnly` 挡，不归这里管。
bool _isLessonTitleLine(String text, _Plan pl, double top) {
  final nt = _normalize(text);
  if (nt.isEmpty) return false;
  final tn = _normalize(pl.title);
  if (nt == tn) return true;
  if (top < kHeadMinTop || top > kHeadMaxTop) return false;
  return nt.length >= 2 && tn.contains(nt);
}

/// 目录里第一课的起始页（PDF 页序）；目录里一课都没有时返回 null。
int? _firstLessonStart(List<TocEntry> toc, int offset) {
  for (final t in toc) {
    if (!t.isUnit) return t.bookPage + offset;
  }
  return null;
}

/// 目录推出的课首页上，印着这一课名字的比例。
///
/// 这是把「目录页码 + 偏移」这套算术**拿页面内容去核对**的一步：
/// 偏移推错、或这本教材的目录页码根本不是书页体系时，命中率会立刻掉下来，
/// 于是退回标题带兜底 —— 比只检查「有没有切出课」可信得多。
///
/// 起于本段之前的课（分段导入的续文）不参与核对：它的首页不在本段里，
/// 拿本段的页去比只会凭空拉低命中率。
double _titleHitRate(Map<int, CleanedPage> byNo, List<_Plan> plans, int firstPageNo) {
  var total = 0;
  var hit = 0;
  for (final pl in plans) {
    if (pl.start < firstPageNo) continue;
    final name = _normalize(pl.name);
    if (name.length < 2) continue; // 没有课名的板块（`写字表`）不参与核对
    total++;
    // 课名偶尔会溢到次页一行，所以看两页
    for (final p in [pl.start, pl.start + 1]) {
      final page = byNo[p];
      if (page == null) continue;
      if (page.lines.any((l) => _normalize(l.text).contains(name))) {
        hit++;
        break;
      }
    }
  }
  return total == 0 ? 1 : hit / total;
}

/// 编号条目：`12 为人民服务`（label=`12`）或 `第1课 开开心心上学去`（label=`第1课`）
final RegExp _numberedLabel = RegExp(r'^(?:[0-9]{1,2}|第[0-9]{1,2}课)$');

bool _isNumbered(TocEntry t) => !t.isUnit && _numberedLabel.hasMatch(t.label);

/// 「这一条确定是独立条目」：有编号、有记号、或是单元行。
bool _isStrong(TocEntry t) => t.isUnit || t.marked || _isNumbered(t);

/// 用目录划界。返回的课页范围**已与本次解析区间求过交**。
///
/// 目录里条目并不都是「课」，分三级处理：
///
/// - **单元行**（`第一单元`）只切换归属，不单独成条；
/// - **子条目** —— 编号课目下面挂的无名篇目，并入所属那一课。
///   实测《语文》六年级下册：《古诗三首》下挂 `寒食/迢迢牵牛星/十五夜望月`
///   （三条书页 11/11/12）、`文言文二则` 下挂 `学弈/两小儿辩日`（80/81）、
///   另一处《古诗三首》下挂 `马诗/石灰吟/竹石`（58/58/59）。
///   拆成独立条目的话父条目 `end < start` 会被整条丢掉 —— 一次印三首诗的
///   《古诗三首》就整课消失了，所以必须合并。
///   判据：本身没有编号、上一条是编号课目、且后面还有条目落在更后的页上。
///   （末一条排除了 `写字表`/`词语表` 这类印在书末的独立板块 —— 它们后面
///   没有任何「强条目」了。）
/// - 其余各自成条（含 `◎ 口语交际`、`写字表`、`古诗词诵读`）。
///
/// 同页两条时保留「强」的那条：`古诗词诵读` 与 `1 采薇（节选）` 都印在书页
/// 111，留下诗、丢掉只有标题的板块行。
List<_Plan> _planByToc(
  List<TocEntry> toc,
  int offset,
  int firstPageNo,
  int lastPageNo,
  int totalPages,
) {
  var unit = '';
  final rows = <(TocEntry, String, int)>[];
  for (final t in toc) {
    if (t.isUnit) {
      unit = t.title;
      continue;
    }
    final start = t.bookPage + offset;
    if (start < 1) continue;
    rows.add((t, unit, start));
  }

  // 每行后面最近一条「强条目」的页号（没有则 0）—— 子条目判定的右界
  final nextStrong = List<int>.filled(rows.length, 0);
  var seen = 0;
  for (var i = rows.length - 1; i >= 0; i--) {
    nextStrong[i] = seen;
    if (_isStrong(rows[i].$1)) seen = rows[i].$3;
  }

  final items = <(TocEntry, String, int)>[];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    if (!_isStrong(r.$1) &&
        items.isNotEmpty &&
        _isNumbered(items.last.$1) &&
        nextStrong[i] > r.$3) {
      continue; // 子条目：并入上一课
    }
    if (items.isNotEmpty) {
      if (r.$3 < items.last.$3) continue; // 真子条目（页号不增）
      if (r.$3 == items.last.$3) {
        if (_isStrong(r.$1) && !_isStrong(items.last.$1)) {
          items.removeLast(); // 同页：留下强条目
        } else {
          continue;
        }
      }
    }
    items.add(r);
  }

  final out = <_Plan>[];
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final start = it.$3;
    if (start > lastPageNo) continue;
    // 自然终点 = 下一课的起始页减一；本课是全书最后一课时看作「到全书末页」
    final naturalEnd = i + 1 < items.length ? items[i + 1].$3 - 1 : totalPages;
    final end = math.min(naturalEnd, lastPageNo);
    if (end < start || end < firstPageNo) continue; // 与本次区间不相交
    out.add(_Plan(
      unit: it.$2,
      title: it.$1.title,
      name: it.$1.name,
      start: start,
      end: end,
      cutOff: naturalEnd > lastPageNo,
    ));
  }
  return out;
}

/// 兜底：扫页面上的标题带划界（原方案）。
///
/// 只在「没有目录」或「目录页码对不上正文」时使用 —— 这套规则依赖逐书不同的
/// 版面参数，换一本教材就可能全灭（见文件头）。
List<_Plan> _planByHeads(
  List<CleanedPage> pages,
  List<int> tocPages,
  int firstPageNo,
  int lastPageNo,
  int totalPages,
  List<TocEntry> toc,
) {
  final lessonHeads = <int, String>{};
  final unitHeads = <int, String>{};
  for (final p in pages) {
    if (tocPages.contains(p.pageNumber)) continue;
    final band = headBand(p);
    if (band.isEmpty) continue;

    var isLesson = false;
    var isUnitTitle = false;
    String? unitLabel;
    String? unitName;
    for (final l in band) {
      final t = _normalize(l.text);
      if (t.isEmpty || _digitsOnly.hasMatch(t)) continue; // 插图序号气泡
      if (_lessonHeadRe.hasMatch(t)) {
        lessonHeads[p.pageNumber] = t;
        isLesson = true;
        break;
      }
      if (unitLabel == null) {
        if (_unitLabelOnly.hasMatch(t)) unitLabel = t;
        continue;
      }
      unitName ??= t;
      isUnitTitle = true;
    }
    if (isLesson || unitLabel == null || !isUnitTitle) continue;
    unitHeads[p.pageNumber] = '$unitLabel $unitName';
  }

  final bounds = <int>{...lessonHeads.keys, ...unitHeads.keys}.toList()..sort();
  final sorted = lessonHeads.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  final out = <_Plan>[];
  // 课号从标题行取；单元名优先用扉页，扉页没有时从目录推
  for (final e in sorted) {
    final start = e.key;
    final no = int.parse(_lessonHeadRe.firstMatch(e.value)!.group(1)!);
    // 自然终点按「下一个边界」算（边界含单元扉页），再与本次区间求交
    final naturalEnd = _endOf(bounds, start, totalPages);
    final end = math.min(naturalEnd, lastPageNo);
    if (end < start) continue;
    var unitName = _unitFor(unitHeads, start);
    if (unitName.isEmpty) unitName = _unitFromToc(toc, no);
    out.add(_Plan(
      unit: unitName,
      title: _splitLabel(e.value, '第$no课'),
      name: e.value.substring('第$no课'.length),
      start: start,
      end: end,
      cutOff: naturalEnd > lastPageNo,
    ));
  }
  return out;
}

String _splitLabel(String text, String label) =>
    text.startsWith(label) ? '$label ${text.substring(label.length)}' : text;

int _endOf(List<int> bounds, int start, int total) {
  for (final b in bounds) {
    if (b > start) return b - 1;
  }
  return total;
}

String _unitFor(Map<int, String> unitHeads, int page) {
  var bestKey = -1;
  var best = '';
  for (final e in unitHeads.entries) {
    if (e.key <= page && e.key > bestKey) {
      bestKey = e.key;
      best = e.value;
    }
  }
  return best;
}

/// 单元名从**目录**里推 —— 分段导入时，某一段里可能一页单元扉页都没有。
///
/// 目录里「第一单元 我是小学生啦 / 1」之后、下一个单元条目之前的所有课都归它，
/// 所以找到「第N课」的位置再往前找最近的单元条目即可。
String _unitFromToc(List<TocEntry> toc, int lessonNo) {
  var current = '';
  for (final t in toc) {
    if (t.isUnit) {
      current = t.title;
    } else if (t.label == '第$lessonNo课') {
      return current;
    }
  }
  return '';
}

/// 偏移取众数：单个课可能因目录条目错位而算出异常值，多数一致才可信。
int? _modeOffset(List<int> xs) {
  if (xs.isEmpty) return null;
  final count = <int, int>{};
  for (final x in xs) {
    count[x] = (count[x] ?? 0) + 1;
  }
  var best = xs.first;
  var bestCount = 0;
  count.forEach((v, c) {
    if (c > bestCount || (c == bestCount && v < best)) {
      best = v;
      bestCount = c;
    }
  });
  return best;
}
