/// PDF 教材导入 · 第二段：把清洗后的页还原成「单元 / 课 / 正文」。
///
/// 结构与页码来自**教材自己的目录页**，而不是猜测：
/// 目录把「第一单元 我是小学生啦 / 1」「第1课 开开心心上学去 / 2」这样的
/// 条目连同书页码一起印在书上，正则一比即可拿到全部单元与课名。
///
/// 每课的正文范围由「页面上的标题行」划界，不用目录页码：
/// 目录页码依赖「PDF 页 − 书页」的固定偏移，而偏移取决于封面/版权/目录
/// 占了几页，不同教材不一样；标题行则是印在页面上的直接证据。
/// 偏移只用来做一次交叉校验，写进结果里便于诊断。
///
/// 边界规则（实测于人教社《道德与法治》一年级上册）：
/// - **课首页**：首行形如「第N课XXX」，且落在页面上部（top 45–92pt）
/// - **单元扉页**：首行形如「第X单元XXX」，同一高度区间
/// - 章节正文 = 课首页 → 下一个边界（课首页或单元扉页）的前一页
///
/// 页眉（top≈30）与正文（top>100）都在区间之外，所以不会被误认成标题。
library;

import 'dart:math' as math;

import 'pdf_page_cleaner.dart';

// ---------------------------------------------------------------------------
// 页码偏移与标题行的位置窗口
// ---------------------------------------------------------------------------

/// 标题行允许的纵向区间（pt，自页面顶边起）。
///
/// 实测四者的位置：**页眉 top≈30、课题 top≈58、单元扉页 top≈70、正文 top>100**。
/// 取 45–92 恰好只圈住两个标题行，靠位置区分即可，不必猜字号
/// （课题与正文用的是同一个字体，字号也一样）。
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

/// 目录里的一条：单元标题或课题，附教材上印的书页码。
class TocEntry {
  final bool isUnit;

  /// 「第一单元」/「第1课」
  final String label;

  /// 「我是小学生啦」/「开开心心上学去」
  final String name;

  /// 教材上印的书页码（不是 PDF 页序）
  final int bookPage;

  const TocEntry({
    required this.isUnit,
    required this.label,
    required this.name,
    required this.bookPage,
  });

  String get title => '$label $name';

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

/// 整本教材的解析结果。
class TextbookParseResult {
  /// 建议的语料库名（如「道德与法治 一年级上册」）
  final String name;

  /// 目录条目，按教材顺序
  final List<TocEntry> toc;

  final List<TextbookLesson> lessons;

  /// PDF 页 − 书页；由目录页码与标题行位置交叉算出，识别不出为 null
  final int? pageOffset;

  /// 识别到的目录页（1-based）
  final List<int> tocPages;

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

  const TextbookParseResult({
    required this.name,
    required this.toc,
    required this.lessons,
    required this.pageOffset,
    required this.tocPages,
    this.leadingText = '',
    this.leadingPages = const [],
    this.pageCount = 0,
    this.firstPageNo = 0,
    this.lastPageNo = 0,
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

final RegExp _tocEntry = RegExp(
    r'(第[一二三四五六七八九十百0-9]+(?:单元|课))([^/0-9]{1,24})/([0-9]{1,3})');
final RegExp _tocPageHits = RegExp(r'/[0-9]{1,3}');
final RegExp _lessonHead = RegExp(r'^第([0-9]{1,2})课(.+)$');
final RegExp _unitLabel = RegExp(r'^第[一二三四五六七八九十]+单元$');
final RegExp _digitsOnly = RegExp(r'^[0-9]{1,3}$');

String _normalize(String s) => s.replaceAll(RegExp(r'[\s\u3000]'), '');

/// 目录页的判据：页面里有 ≥ 3 条「…/页码」。
///
/// 比「含『目录』二字」稳：目录常跨页，而延续页并不重复印「目录」这个标题
/// （实测第 4 页有「目录」、第 5 页没有，只认标题就会漏掉后半本的书目）。
bool looksLikeTocPage(Iterable<String> lines) {
  final joined = _normalize(lines.join());
  return _tocPageHits.allMatches(joined).length >= 3;
}

/// 从目录页文本里解析出单元与课。
List<TocEntry> parseTableOfContents(Iterable<String> pageTexts) {
  final flat = _normalize(pageTexts.join());
  final out = <TocEntry>[];
  for (final m in _tocEntry.allMatches(flat)) {
    final label = m.group(1)!;
    out.add(TocEntry(
      isUnit: label.endsWith('单元'),
      label: label,
      name: m.group(2)!,
      bookPage: int.parse(m.group(3)!),
    ));
  }
  return out;
}

// ---------------------------------------------------------------------------
// 结构化
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
/// 年级与册次是封面的硬特征（教科书一定印），据它判断「这是不是封面」最省事；
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

/// 把清洗后的页解析成「单元 / 课 / 正文」。
///
/// [knownToc] 用于**分段导入**：教材目录只印在前几页，第二段起页面里没有目录，
/// 传上一段探测到的目录进来，后半本一样能正确切分（否则只有第一段能切出课）。
TextbookParseResult structureTextbook(
  List<CleanedPage> pages, {
  String? fallbackName,
  List<TocEntry>? knownToc,
}) {
  // ---- 1) 目录 ----
  final tocPages = <int>[];
  for (final p in pages) {
    if (looksLikeTocPage(p.lines.map((l) => l.text))) tocPages.add(p.pageNumber);
  }
  final parsedToc = parseTableOfContents([
    for (final p in pages)
      if (tocPages.contains(p.pageNumber)) p.lines.map((l) => l.text).join(),
  ]);
  final toc = parsedToc.isNotEmpty ? parsedToc : (knownToc ?? const <TocEntry>[]);

  // ---- 2) 标题行 ----
  // 扫「标题带」里的所有行，**不看 `lines.first`**：页码印在版心最左，分列时
  // 它自成一列并排在全页最前（实测第 7 页的 `lines.first` 是页脚页码 "2"，
  // top=695.9）。只认第一行会漏掉所有「标题不在最前」的页 —— 实测漏 8/16 课
  // 与全部 4 个单元。
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
      if (_lessonHead.hasMatch(t)) {
        lessonHeads[p.pageNumber] = t;
        isLesson = true;
        break;
      }
      if (unitLabel == null) {
        if (_unitLabel.hasMatch(t)) unitLabel = t;
        continue;
      }
      unitName ??= t;
      isUnitTitle = true;
    }
    if (isLesson || unitLabel == null || !isUnitTitle) continue;
    unitHeads[p.pageNumber] = '$unitLabel $unitName';
  }

  // ---- 3) 偏移校验 ----
  final offsets = <int>[];
  for (final e in lessonHeads.entries) {
    final no = _lessonHead.firstMatch(e.value)!.group(1)!;
    for (final t in toc) {
      if (!t.isUnit && t.label == '第$no课') {
        offsets.add(e.key - t.bookPage);
        break;
      }
    }
  }

  // ---- 4) 划范围 + 拼正文 ----
  // 一律按 `pageNumber` 取页，**不用下标**：分段导入时页号是全书绝对页号
  // （第二段从 36 起），拿它当数组下标会直接越界。
  final byNo = <int, CleanedPage>{for (final p in pages) p.pageNumber: p};
  final lastPageNo = pages.isEmpty ? 0 : pages.last.pageNumber;
  final bounds = <int>{...lessonHeads.keys, ...unitHeads.keys}.toList()..sort();
  final sorted = lessonHeads.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  final lessons = <TextbookLesson>[];
  for (final e in sorted) {
    final start = e.key;
    final no = int.parse(_lessonHead.firstMatch(e.value)!.group(1)!);
    final bounded = bounds.any((b) => b > start);
    final end = _endOf(bounds, start, lastPageNo);
    final title = _splitLabel(e.value, '第$no课');
    var unit = _unitFor(unitHeads, start);
    if (unit.isEmpty) unit = _unitFromToc(toc, no);

    final buf = <String>[];
    final used = <int>[];
    for (var p = start; p <= end; p++) {
      final page = byNo[p];
      // 封面 / 单元扉页 / 后记 / 致谢都没有页脚页码 —— 用页码判定最省事
      if (page == null || page.printedPageNo == null) continue;
      used.add(p);
      for (final line in page.lines) {
        final t = line.text.trim();
        if (t.isEmpty) continue;
        if (line.top < kHeadMinTop) continue; // 页眉
        if (_digitsOnly.hasMatch(t)) continue; // 页脚页码 / 插图序号气泡
        // 课题行已入 title（按「是本课标题的一部分」判断，不是整行相等 ——
        // 标题若跨了段，整行相等就漏掉了）
        final nt = _normalize(t);
        if (p == start && nt.isNotEmpty && e.value.contains(nt)) continue;
        buf.add(t);
      }
    }

    lessons.add(TextbookLesson(
      unit: unit,
      title: title,
      text: buf.join('\n'),
      startPage: start,
      endPage: end,
      contentPages: used,
      // 三个条件缺一不可：后面没有新边界 + 终点就是区间末页 + 末页上确实还有
      // 本课正文。整本导入时末课终点也等于末页，但它后面是无页码的后记页，
      // 正文其实已经完整 —— 少了第三个条件就会误报「未完」。
      cutOff: !bounded && end == lastPageNo && used.contains(lastPageNo),
    ));
  }

  // ---- 5) 段首正文 ----
  // 本段第一个课题之前的正文。整本导入时这里是封面/版权/目录，都会被
  // 「没有页脚页码」挡掉，所以通常为空；分段导入时它属于上一段的最后一课。
  final firstHead = sorted.isEmpty ? lastPageNo + 1 : sorted.first.key;
  final lead = <String>[];
  final leadPages = <int>[];
  for (final page in pages) {
    if (page.pageNumber >= firstHead) break;
    if (tocPages.contains(page.pageNumber)) continue; // 目录条目不是课文
    if (page.printedPageNo == null) continue;
    final inner = <String>[];
    for (final line in page.lines) {
      final t = line.text.trim();
      if (t.isEmpty) continue;
      if (line.top < kHeadMinTop) continue;
      if (_digitsOnly.hasMatch(t)) continue;
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
    pageOffset: _modeOffset(offsets),
    tocPages: tocPages,
    leadingText: lead.join('\n'),
    leadingPages: leadPages,
    pageCount: pages.length,
    firstPageNo: pages.isEmpty ? 0 : pages.first.pageNumber,
    lastPageNo: lastPageNo,
  );
}
