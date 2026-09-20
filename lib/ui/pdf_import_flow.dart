/// 「导入教材 PDF」的界面流程。
///
/// 与逻辑层（`core/pdf_textbook_import.dart`）分工：那边只管「字节 → 结构化
/// 教材」，这边只管「选文件 → 报页码 → 走进度 → 勾选预览」。
/// **入库不在本文件**：条目交回调用方（`chinese_panel.dart`），复用既有的
/// `_mergeItems` 合并去重 —— 再写一份就必然出现「同一份数据两处定义」。
///
/// 为什么要有页码范围这一步：教材动辄上百页，一次全跑既慢也吃内存
/// （实测 70 页约 9.5s / 136ms 一页，内存峰值随页数线性上涨）。
/// 让用户自己填「第几页到第几页」，既能把一次导入控制在可接受的范围，
/// 也能让他在识别结果不对时只重跑那一段。
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
// ValueListenable 在 foundation 里，material 并未转出（ValueNotifier 才是）
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/pdf_textbook_import.dart';
import '../core/textbook_structurer.dart';

const Color _kBlue = Color(0xff2f6fd0);
const Color _kGrey = Color(0xff888888);
const Color _kLightGrey = Color(0xffaaaaaa);

/// 一次 PDF 导入的产出。返回 null 表示用户取消，或已在流程内提示过原因。
class PdfImportOutcome {
  /// 已按用户勾选筛过的条目，可直接交给语料库合并
  final List<Map<String, dynamic>> items;

  /// 本次勾选保留的课（用来显示「未完」等提示）
  final List<TextbookLesson> picked;

  /// 本教材**全部**已解析的段（含本次），下次续接要原样传回来
  final List<TextbookParseResult> segments;

  /// 封面识别出的教材名（识别不到时为「导入教材」）
  final String corpusName;

  /// 本次提取的页码区间（1-based，闭区间）
  final int firstPage;
  final int lastPage;

  /// PDF 总页数
  final int totalPages;

  /// 合并后整本累计的课数（含之前几段）
  final int totalLessons;

  /// 导入后还有下一段可导时，给出建议的起始页；否则为 0
  final int suggestNextPage;

  const PdfImportOutcome({
    required this.items,
    required this.picked,
    required this.segments,
    required this.corpusName,
    required this.firstPage,
    required this.lastPage,
    required this.totalPages,
    required this.totalLessons,
    required this.suggestNextPage,
  });
}

/// 打开「选 PDF → 报页码范围 → 提取解析 → 勾选预览」的全流程。
///
/// [previous] 是同一本教材此前已解析过的段：既用来把被区间切断的课续接起来，
/// 也用来给出「上次导入到第 N 页，本次从 N+1 页继续」的默认值。
Future<PdfImportOutcome?> importTextbookPdf(
  BuildContext context, {
  List<TextbookParseResult> previous = const [],
  String? fallbackName,
}) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    withData: true,
  );
  // 每个 await 之后都要重新确认宿主还在：拿着已卸载的 context 去弹窗会抛
  // 「Looking up a deactivated widget's ancestor」。用户中途返回上一页、
  // 或在提取的几秒里切走，都会走到这里。
  if (picked == null || picked.files.isEmpty) return null;
  if (!context.mounted) return null;
  final file = picked.files.first;
  final bytes = file.bytes;
  if (bytes == null) {
    _snack(context, '读不到这个文件的内容，请换一个来源（如文件管理器）再试。');
    return null;
  }

  // ---- 1) 开书前的廉价探测：总页数 + 书名 + 目录 ----
  final probeProgress = PdfImportProgress('正在打开《${file.name}》…');
  TextbookProbe probe;
  try {
    probe = await _runWithProgress(
      context,
      probeProgress,
      cancellable: false,
      task: () => probeTextbookPdf(bytes),
    );
  } catch (e) {
    if (context.mounted) _snack(context, '这个 PDF 打不开：$e');
    return null;
  }
  if (!context.mounted) return null;
  if (probe.pageCount == 0) {
    _snack(context, '这个 PDF 里没有页面。');
    return null;
  }

  // ---- 2) 页码区间 ----
  final defaultStart = previous.isEmpty ? 1 : previous.last.nextPage;
  final range = await _askPageRange(
    context,
    pageCount: probe.pageCount,
    defaultStart: defaultStart.clamp(1, probe.pageCount),
    probe: probe,
    hasPrevious: previous.isNotEmpty,
  );
  if (range == null || !context.mounted) return null;

  // ---- 3) 提取 + 解析（可取消） ----
  final progress = PdfImportProgress('正在提取第 ${range.$1}–${range.$2} 页…');
  TextbookParseResult segment;
  try {
    segment = await _runWithProgress(
      context,
      progress,
      cancellable: true,
      task: () => parseTextbookPdf(
        bytes,
        firstPage: range.$1 - 1, // 界面 1-based，接口 0-based
        lastPage: range.$2 - 1,
        knownToc: probe.result.toc,
        fallbackName: fallbackName ?? probe.result.name,
        onProgress: (done, total) {
          progress.text.value = '正在提取第 ${range.$1 + done - 1} 页 · $done/$total';
          progress.value.value = total == 0 ? null : done / total;
        },
        isCancelled: () => progress.cancelled.value,
      ),
    );
  } catch (e) {
    if (context.mounted) _snack(context, '提取失败：$e');
    return null;
  }
  if (!context.mounted) return null;
  if (progress.cancelled.value) {
    _snack(context, '已取消提取。');
    return null;
  }
  if (segment.lessons.isEmpty && segment.leadingText.isEmpty) {
    await _showNoLessonDialog(context, segment, range.$1, range.$2);
    return null;
  }

  // ---- 4) 与之前几段合并（续接被切断的课） ----
  final segments = _appendSegment(previous, segment);
  final lessons = mergeSegments(segments);
  if (lessons.isEmpty) {
    await _showNoLessonDialog(context, segment, range.$1, range.$2);
    return null;
  }

  // ---- 5) 预览勾选 ----
  final chosen = await _pickLessons(
    context,
    lessons: lessons,
    firstPage: range.$1,
    lastPage: range.$2,
    totalPages: probe.pageCount,
    corpusName: segment.name,
    unreadablePages: segment.unreadablePages,
  );
  if (chosen == null || !context.mounted) return null;
  if (chosen.isEmpty) {
    _snack(context, '没有选中任何课，未归档。');
    return null;
  }

  return PdfImportOutcome(
    items: [for (final l in chosen) l.toCorpusItem()],
    picked: chosen,
    segments: segments,
    corpusName: segment.name,
    firstPage: range.$1,
    lastPage: range.$2,
    totalPages: probe.pageCount,
    totalLessons: lessons.length,
    suggestNextPage: range.$2 < probe.pageCount ? range.$2 + 1 : 0,
  );
}

/// 「一节课都切不出来」时的诊断文案。
///
/// 三种情况要给完全相反的建议，所以必须先分清：
/// - **扫描图片版**（文字量不够）→ 先 OCR，或改用「拍照导入」；
/// - **不是中文教材**（文字够但正文是外文）→ 换中文教材；改 OCR 或拍照都没用；
/// - **中文教材但没有成篇课文**（数学教材）→ 导入这条路本来就不通，
///   应该去「数学」面板出题，而不是继续折腾 PDF。
///
/// 实测英语教材（人教社·三年级起点 六年级下册）是第二种：81 页、35548 个字符
/// 全部提取成功，但汉字只占 2.3%，一节课都切不出来。原来只报「请确认这本 PDF
/// 带文本层」，会把用户引向完全错误的方向。
///
/// 第三种实测于《数学》四年级下册：汉字 52.6%（正常）、数字 28.0%、课数 0。
/// 它的汉字占比完全看不出异常，所以必须靠数字占比单独认出来，
/// 否则用户会收到「请确认带文本层」这种与事实相反的建议。
String noLessonMessage(TextbookParseResult seg, int first, int last) {
  final lang = seg.language;
  // 整页读不出的情况优先说 —— 它可能是「一篇都切不出来」的真正原因。
  // 三条支路都必须带上它：静默不提，用户会以为整本书都读到了
  // （见 TextbookParseResult.unreadablePages 的说明）。
  final unreadable = seg.unreadablePages.isEmpty
      ? ''
      : '另有 ${seg.unreadablePages.length} 页整页读不出文字'
          '（第 ${seg.unreadablePages.join('、')} 页）。';
  if (lang.looksNonChinese) {
    final pct = (lang.hanRatio * 100).toStringAsFixed(
        lang.hanRatio < 0.095 ? 1 : 0);
    return '第 $first–$last 页提取到 ${lang.totalChars} 个字符'
        '（其中汉字 ${lang.hanChars} 个，占 $pct%）——这本 PDF 的正文不是中文，'
        '看起来不是中文教材。$unreadable'
        '教材导入是按中文课文设计的，'
        '其他语种的教材请用「拍照导入」（走视觉识别，不受语种限制）。';
  }
  // 中文、文字量也够，却切不出一课。数学教材就长这样：按单元编排，
  // 通篇是算式、图示和练习，没有语文教材那种成篇课文可切。
  if (lang.enoughText) {
    final digitPct = (lang.digitRatio * 100).toStringAsFixed(1);
    final guess = lang.looksMathLike
        ? '数字占到 $digitPct%，看起来就是数学教材'
        : '数字占到 $digitPct%，多半也是数学、科学这类按单元编排的教材';
    return '第 $first–$last 页提取到 ${lang.totalChars} 个字符'
        '（汉字 ${lang.hanChars} 个），文字是够的、也不是外文，'
        '但里面没有成篇的课文 —— $guess。'
        '$unreadable这类教材通篇是算式、图示和练习，'
        '「按课文切分」无物可切，所以一节课都切不出来。\n'
        '数学作业不需要课本正文：把版本、年级、册选对，'
        '到「数学」面板勾选这次要练的题型即可出题；'
        '本册的教材单元会显示在面板顶部，可以拿来核对册次有没有选错。';
  }
  return '第 $first–$last 页里没有识别到课文。$unreadable'
      '若这些页本来就是封面、目录或插图，属正常；'
      '否则请确认这本 PDF 带文本层（扫描图片版需要先做 OCR，'
      '或用「拍照导入」）。';
}

/// 弹出「一节课都切不出来」的诊断。
///
/// 用对话框而不是 SnackBar：这段文案有三四行，SnackBar 6 秒就消失，
/// 用户还没读到关键那句就没了 —— 而「让用户读到」正是它存在的理由。
Future<void> _showNoLessonDialog(
  BuildContext context,
  TextbookParseResult segment,
  int first,
  int last,
) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('没能按课文切分'),
      content: SingleChildScrollView(
        child: Text(noLessonMessage(segment, first, last)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

/// 把新段并入已解析的段：页码区间完全相同的旧段被替换，避免重复导入同一段时
/// 课文在合并结果里出现两次（同一课只可能被区间切开一次，不同区间的段不会重叠）。
List<TextbookParseResult> _appendSegment(
  List<TextbookParseResult> previous,
  TextbookParseResult segment,
) {
  final out = <TextbookParseResult>[
    for (final s in previous)
      if (!(s.firstPageNo == segment.firstPageNo &&
          s.lastPageNo == segment.lastPageNo))
        s,
  ];
  out.add(segment);
  out.sort((a, b) => a.firstPageNo.compareTo(b.firstPageNo));
  return out;
}

/// 页码区间选择。返回 (起始页, 结束页)，1-based 闭区间；取消返回 null。
Future<(int, int)?> _askPageRange(
  BuildContext context, {
  required int pageCount,
  required int defaultStart,
  required TextbookProbe probe,
  required bool hasPrevious,
}) async {
  final startCtrl = TextEditingController(text: '$defaultStart');
  final endCtrl = TextEditingController(text: '$pageCount');
  // 一行提示：填对了显示预计耗时，填错了显示错在哪。随输入实时更新，
  // 「开始提取」在填错时拒绝关窗 —— 于是这里就是唯一的校验出口。
  final hint = ValueNotifier<String>('');

  void recalc() {
    final a = int.tryParse(startCtrl.text.trim());
    final b = int.tryParse(endCtrl.text.trim());
    if (a == null || b == null) {
      hint.value = '请填 $pageCount 以内的页码';
      return;
    }
    if (a < 1 || a > pageCount || b < 1 || b > pageCount) {
      hint.value = '页码要在 1–$pageCount 之间';
      return;
    }
    if (b < a) {
      hint.value = '起始页不能大于结束页';
      return;
    }
    hint.value = '本次 ${b - a + 1} 页 · '
        '预计约 ${(estimateMillis(b - a + 1) / 1000).toStringAsFixed(1)} 秒';
  }

  startCtrl.addListener(recalc);
  endCtrl.addListener(recalc);
  recalc();

  bool valid() {
    final a = int.tryParse(startCtrl.text.trim());
    final b = int.tryParse(endCtrl.text.trim());
    return a != null && b != null && a >= 1 && b <= pageCount && b >= a;
  }

  final unitCount = probe.result.toc.where((t) => t.isUnit).length;
  final lessonCount = probe.result.toc.where((t) => !t.isUnit).length;

  final result = await showDialog<(int, int)>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('导入教材 PDF'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('这本 PDF 共 $pageCount 页',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                probe.hasToc
                    ? '目录：$unitCount 个单元 / $lessonCount 课'
                    : '未找到目录页：课还切得出来，但「属于哪个单元」会空着',
                style: TextStyle(
                    fontSize: 12,
                    color: probe.hasToc ? _kGrey : const Color(0xffb47a00),
                    height: 1.4),
              ),
              if (hasPrevious) ...[
                const SizedBox(height: 6),
                const Text('上次已导入到前面几页，默认从下一页接着导；'
                    '两段之间会自动把被切断的那一课拼回去。',
                    style: TextStyle(fontSize: 12, color: _kBlue, height: 1.4)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: startCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '起始页',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('到'),
                  ),
                  Expanded(
                    child: TextField(
                      controller: endCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '结束页',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<String>(
                valueListenable: hint,
                builder: (_, t, __) => Text(
                  t,
                  style: TextStyle(
                      fontSize: 12,
                      color: valid() ? _kLightGrey : const Color(0xffc0392b)),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '建议按课与课的分界分段（封面、目录页不必导入）。'
                '一次全跑上百页会明显变慢、也更吃内存。\n'
                '若换到新一次使用后再接着导，把页码范围覆盖到上次导入处即可 ——'
                '同一课会用更完整的正文覆盖，不会重复。',
                style: TextStyle(fontSize: 11, color: _kLightGrey, height: 1.5),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(
          onPressed: () {
            if (!valid()) return; // 提示已在窗内，这里不关窗
            Navigator.pop(ctx, (
              int.parse(startCtrl.text.trim()),
              int.parse(endCtrl.text.trim()),
            ));
          },
          child: const Text('开始提取'),
        ),
      ],
    ),
  );

  // 同样不手动释放控制器与通知量：对话框刚 pop，退场动画期间它们还在被用
  return result;
}

/// 预览勾选。返回选中的课；取消返回 null。
Future<List<TextbookLesson>?> _pickLessons(
  BuildContext context, {
  required List<TextbookLesson> lessons,
  required int firstPage,
  required int lastPage,
  required int totalPages,
  required String corpusName,
  List<int> unreadablePages = const [],
}) async {
  final selected = <int>{for (var i = 0; i < lessons.length; i++) i};
  final charTotal = lessons.fold(0, (a, b) => a + b.charCount);

  return showDialog<List<TextbookLesson>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final pickedChars = [
          for (var i = 0; i < lessons.length; i++)
            if (selected.contains(i)) lessons[i].charCount,
        ].fold(0, (a, b) => a + b);
        return AlertDialog(
          title: const Text('导入预览'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$corpusName · 第 $firstPage–$lastPage 页 / 共 $totalPages 页',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '全书累计 ${lessons.length} 课 · $charTotal 字；'
                  '本次勾选 ${selected.length} 课 · $pickedChars 字',
                  style: const TextStyle(fontSize: 12, color: _kGrey),
                ),
                if (unreadablePages.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '⚠️ 有 ${unreadablePages.length} 页整页读不出文字'
                    '（第 ${unreadablePages.join('、')} 页，多为插图或表格页），'
                    '这些页的内容没有进来。若缺的正是课文页，请减小页码区间重导。',
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xffb47a00), height: 1.5),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setLocal(() => selected.addAll(
                          [for (var i = 0; i < lessons.length; i++) i])),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: () => setLocal(selected.clear),
                      child: const Text('全不选'),
                    ),
                    const Spacer(),
                    const Text('去掉识别错的课再归档',
                        style: TextStyle(fontSize: 11, color: _kLightGrey)),
                  ],
                ),
                const Divider(height: 8),
                // Flexible + maxHeight：屏幕矮时列表自己压缩并滚动，
                // 固定高度会让 Column 撑破对话框（小屏 + 分屏下必现）
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: lessons.length,
                      itemBuilder: (_, i) {
                        final l = lessons[i];
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          value: selected.contains(i),
                          onChanged: (v) => setLocal(() {
                            if (v == true) {
                              selected.add(i);
                            } else {
                              selected.remove(i);
                            }
                          }),
                          title: Text(
                            l.title,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              if (l.unit.isNotEmpty) l.unit,
                              '页 ${l.startPage}–${l.endPage}',
                              '${l.charCount} 字',
                              if (l.cutOff) '未完·下次接着导',
                            ].join(' · '),
                            style: TextStyle(
                                fontSize: 11,
                                color:
                                    l.cutOff ? const Color(0xffb47a00) : _kGrey),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '⚠️ 请只导入您拥有合法使用权的教材内容。',
                  style: TextStyle(fontSize: 11, color: _kLightGrey, height: 1.5),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, [
                for (var i = 0; i < lessons.length; i++)
                  if (selected.contains(i)) lessons[i],
              ]),
              child: Text('归档所选（${selected.length} 课）'),
            ),
          ],
        );
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// 进度对话框
// ---------------------------------------------------------------------------

/// 进度对话框的驱动句柄：流程代码只改这几个通知量，不碰 State。
///
/// **不要 `dispose`**：任务结束时对话框才刚开始退场动画（约 150ms），
/// 退场中的 `ValueListenableBuilder` 还在监听这些通知量，
/// 提前释放会报「A ValueNotifier was used after being disposed」。
/// 它们没有外部资源，交给 GC 即可。
class PdfImportProgress {
  final ValueNotifier<String> text;

  /// null 表示不确定进度（进度条走循环动画，如「正在打开」）
  final ValueNotifier<double?> value;
  final ValueNotifier<bool> cancelled;

  PdfImportProgress(String initial)
      : text = ValueNotifier(initial),
        value = ValueNotifier(null),
        cancelled = ValueNotifier(false);
}

/// 把一段异步任务包在模态进度框里跑。
///
/// [cancellable] 为 true 时给「取消」按钮；按钮只是把 [PdfImportProgress.cancelled]
/// 置位，**任务自己决定在哪里停下**（提取阶段是逐页检查，所以按下就能停，
/// 已提取的部分按设计丢弃）。
///
/// 关闭方式：任务结束后置位 [closed]，**由对话框自己 pop 自己**。
/// 不用「拿外部 Navigator 直接 pop」：那样一旦对话框已经不在了，
/// pop 掉的就是面板本身（root navigator 上还有别的路由，`canPop` 也拦不住）。
Future<T> _runWithProgress<T>(
  BuildContext context,
  PdfImportProgress progress, {
  required bool cancellable,
  required Future<T> Function() task,
}) async {
  final closed = ValueNotifier<bool>(false);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProgressDialog(
      progress: progress,
      cancellable: cancellable,
      closed: closed,
    ),
  ));
  try {
    return await task();
  } finally {
    closed.value = true;
  }
}

class _ProgressDialog extends StatefulWidget {
  final PdfImportProgress progress;
  final bool cancellable;
  final ValueListenable<bool> closed;

  const _ProgressDialog({
    required this.progress,
    required this.cancellable,
    required this.closed,
  });

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  @override
  void initState() {
    super.initState();
    widget.closed.addListener(_close);
    // 任务可能在对话框首帧之前就结束（如空 PDF、瞬间失败），
    // 此时监听刚挂上，值已经是 true —— 补一次关闭，否则框会一直挂着。
    if (widget.closed.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.closed.removeListener(_close);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: widget.progress.text,
              builder: (_, msg, __) =>
                  Text(msg, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<double?>(
              valueListenable: widget.progress.value,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: const Color(0xffeeeeee),
                valueColor: const AlwaysStoppedAnimation(_kBlue),
              ),
            ),
          ],
        ),
        actions: widget.cancellable
            ? [
                ValueListenableBuilder<bool>(
                  valueListenable: widget.progress.cancelled,
                  builder: (_, c, __) => TextButton(
                    onPressed:
                        c ? null : () => widget.progress.cancelled.value = true,
                    child: Text(c ? '正在停止…' : '取消'),
                  ),
                ),
              ]
            : null,
      ),
    );
  }
}

void _snack(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
  );
}
