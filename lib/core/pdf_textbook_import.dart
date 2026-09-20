/// PDF 教材导入 · 第三段：syncfusion 接线。
///
/// 全项目**唯一**接触 PDF 库的地方。清洗与结构化逻辑只依赖 [PdfWord]，
/// 因此可以用纯 Dart 单测覆盖，不必造真 PDF（见 `pdf_page_cleaner.dart`
/// 与 `textbook_structurer.dart` 的文件头说明）。
///
/// 命名注意：仓库里已有一个 `lib/pdf/pdf_service.dart`，那是**导出** PDF
/// （作业单 → A4 → 文件），与导入无关，别混。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'pdf_page_cleaner.dart';
import 'textbook_structurer.dart';

/// 一次 PDF 文本提取的结果。
class PdfTextbookExtraction {
  /// 已按请求区间裁剪后的逐页词列表
  final List<List<PdfWord>> pages;

  /// PDF 实际总页数（与 [pages] 长度不同即为裁剪过）
  final int totalPages;

  /// 本次提取的起始页（0-based）
  final int firstPageIndex;

  /// **目录页**的版面文本（键为 1-based 绝对页序）。
  ///
  /// 只对疑似目录页取，成本可忽略；目录解析走文本顺序而不碰坐标 ——
  /// 实测这本 PDF 的目录页上词坐标不可信（见 `textbook_structurer.dart`）。
  final Map<int, String> layoutTexts;

  /// 取不出词的页（1-based 绝对页序）。
  ///
  /// `syncfusion` 的 `extractTextLines` 在个别页上会抛空指针 —— 实测《数学》
  /// 四年级下册第 48 页（插图以 XObject 形式嵌入的那一页），而同一页的
  /// `extractText` / `extractText(layoutText: true)` 都正常。
  /// **一页读不出不该让整本导入崩掉**，所以这里隔离掉并把页码带出来，
  /// 由调用方决定怎么提示（静默丢页会让用户以为整本书都导进来了）。
  final List<int> failedPages;

  const PdfTextbookExtraction({
    required this.pages,
    required this.totalPages,
    required this.firstPageIndex,
    this.layoutTexts = const {},
    this.failedPages = const [],
  });

  int get extractedCount => pages.length;
}

/// 只在全书前部找目录 —— 教材目录总在封面之后、正文之前。
///
/// 顺带挡掉两种误判：正文页里偶然出现的「省略号+数字」，以及分段导入时
/// 把后面的页误当目录页。
const int kTocScanPages = 16;

/// 取一页的词。**读不出来时返回 null，不往外抛** —— 见 `failedPages` 的说明。
List<PdfWord>? _pageWords(PdfTextExtractor ex, int index) {
  try {
    final ws = <PdfWord>[];
    for (final line
        in ex.extractTextLines(startPageIndex: index, endPageIndex: index)) {
      for (final w in line.wordCollection) {
        if (w.text.trim().isEmpty) continue;
        final b = w.bounds;
        ws.add(PdfWord(w.text, w.fontName, b.left, b.top, b.right, b.bottom));
      }
    }
    return ws;
  } catch (_) {
    return null;
  }
}

/// 逐页取出词。
///
/// 必须**逐页**调 `extractTextLines`（不要一次传整本）：整本提取会先把全书
/// 文本一次性堆进内存。实测 70 页教材逐页提取耗时约 9.5s（≈136ms/页），
/// 逐页还能顺便上报进度，也不至于让大 PDF 把内存顶爆。
Future<PdfTextbookExtraction> extractPdfWords(
  Uint8List bytes, {
  int? firstPage,
  int? lastPage,
  void Function(int done, int total)? onProgress,
}) async {
  final doc = PdfDocument(inputBytes: bytes);
  try {
    final count = doc.pages.count;
    if (count == 0) {
      return const PdfTextbookExtraction(
        pages: [],
        totalPages: 0,
        firstPageIndex: 0,
      );
    }
    final last = count - 1;
    final from = (firstPage ?? 0).clamp(0, last);
    final to = (lastPage ?? last).clamp(from, last);
    final extractor = PdfTextExtractor(doc);
    final out = <List<PdfWord>>[];
    final failed = <int>[];
    for (var i = from; i <= to; i++) {
      final ws = _pageWords(extractor, i);
      // 读不出的页用空页占位：页序不能错位，后面全靠它算边界与页码偏移
      if (ws == null) {
        failed.add(i + 1);
        out.add(const []);
      } else {
        out.add(ws);
      }
      onProgress?.call(i - from + 1, to - from + 1);
      // 让出事件循环，UI 才有机会刷新进度
      await Future<void>.delayed(Duration.zero);
      // 用户中途取消：已经提取的部分照样返回，交给上层决定要不要用
    }

    // 目录页的版面文本：只对疑似目录页再取一次（每页几毫秒）。
    // 判据用词文本拼起来测 —— 目录条目的「点线+页码」在词级也是连着的。
    // 词为空的页也取一次：它们可能是「本来无文字」，也可能是词提取失败，
    // 而 layoutText 在这两种页上都还能用（实测失败页的 layoutText 正常）。
    final layoutTexts = <int, String>{};
    for (var i = 0; i < out.length; i++) {
      final absNo = from + i + 1; // 1-based 绝对页序
      if (absNo > kTocScanPages) break;
      final wordsOk = out[i].isNotEmpty;
      if (wordsOk && !looksLikeTocPage(out[i].map((w) => w.text))) continue;
      try {
        layoutTexts[absNo] = extractor.extractText(
          startPageIndex: from + i,
          endPageIndex: from + i,
          layoutText: true,
        );
      } catch (_) {
        // 单页取不到版面文本不该让整次导入失败：退回到坐标版解析
      }
    }

    return PdfTextbookExtraction(
      pages: out,
      totalPages: count,
      firstPageIndex: from,
      layoutTexts: layoutTexts,
      failedPages: failed,
    );
  } finally {
    doc.dispose();
  }
}

/// 把相对页号平移到 PDF 绝对页号。
///
/// 只提取区间时页号从 1 重新数起，而结构化阶段要的是全书页序
/// （封面、封面后那几页都是靠页序算边界与「有没有页脚页码」的）。
List<CleanedPage> _shiftPages(List<CleanedPage> pages, int delta) {
  if (delta == 0) return pages;
  return [
    for (final p in pages)
      CleanedPage(
        pageNumber: p.pageNumber + delta,
        lines: p.lines,
        printedPageNo: p.printedPageNo,
      ),
  ];
}

/// 字节 → 结构化教材。清洗与识别一键完成。
///
/// [knownToc] 只在**分段导入**时需要：教材目录印在前几页，第二段起页面里
/// 没有目录，把首段探测到的目录传进来，后半本才能正确切分（否则一块都切不出）。
Future<TextbookParseResult> parseTextbookPdf(
  Uint8List bytes, {
  int? firstPage,
  int? lastPage,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
  String? fallbackName,
  List<TocEntry>? knownToc,
}) async {
  final ex = await extractPdfWords(
    bytes,
    firstPage: firstPage,
    lastPage: lastPage,
    onProgress: onProgress,
  );
  if (isCancelled?.call() ?? false) {
    return structureTextbook(const [],
        fallbackName: fallbackName, knownToc: knownToc);
  }
  final cleaned = _shiftPages(
    cleanDocument(ex.pages),
    ex.firstPageIndex, // 页号从 1 起算，平移量即起始下标
  );
  return structureTextbook(
    cleaned,
    fallbackName: fallbackName,
    knownToc: knownToc,
    tocTexts: ex.layoutTexts,
    // 分段导入时本段末页不是全书末页，「末课是否被切断」要靠全书总页数判
    totalPages: ex.totalPages,
    // 少数页可能整页读不出（库在这些页上抛空指针）—— 带出去让界面如实说明
    unreadablePages: ex.failedPages,
  );
}

/// 选完文件后的**廉价探测**结果。
class TextbookProbe {
  /// 全书总页数 —— 用来提示「这本书共 N 页」并让用户填区间
  final int pageCount;

  /// 只扫了前若干页的解析结果（名称 / 目录 / 前几课）
  final TextbookParseResult result;

  const TextbookProbe({required this.pageCount, required this.result});

  bool get hasToc => result.toc.isNotEmpty;

  @override
  String toString() => 'TextbookProbe(${result.name}, $pageCount 页, '
      '${result.toc.length} 条目录)';
}

/// 只扫前 [scanPages] 页，拿到「总页数 + 书名 + 目录」。
///
/// 目录实测印在第 4–5 页，所以扫前 12 页足够；成本是一次小程序打开
/// （实测 363ms）加 12 页提取（≈1.6s）。用户据此填页码范围，
/// 后续每段都复用这份目录。
Future<TextbookProbe> probeTextbookPdf(
  Uint8List bytes, {
  int scanPages = 12,
}) async {
  final ex = await extractPdfWords(bytes, lastPage: scanPages - 1);
  final cleaned = _shiftPages(cleanDocument(ex.pages), ex.firstPageIndex);
  return TextbookProbe(
    pageCount: ex.totalPages,
    result: structureTextbook(
      cleaned,
      tocTexts: ex.layoutTexts,
      totalPages: ex.totalPages,
      unreadablePages: ex.failedPages,
    ),
  );
}

/// 解析出的教材要不要回落到视觉模型。
///
/// 判据是「有没有识别到任何课」。提取到一堆文字但一节课都切不出来，
/// 说明这份 PDF 的版面跟预期差太远（或干脆是扫描件、整本都是图片），
/// 与其给用户一份乱七八糟的结果，不如明确说清楚。
bool needsVisualFallback(TextbookParseResult r) => r.lessons.isEmpty;

/// 估算整本导入的耗时（毫秒），用于按钮旁的成本说明。
int estimateMillis(int pageCount) => math.max(pageCount, 0) * 136;
