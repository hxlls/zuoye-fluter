import 'package:flutter/material.dart';
import '../core/worksheet_model.dart';
import '../core/calligraphy_worksheet.dart';
import '../core/paper.dart';
import '../pdf/pdf_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'worksheet_view.dart';

/// 纸张偏好持久化（SharedPreferences，全局一份，两个预览面板共用）
class PaperPref {
  static const _key = 'paperSize';

  static Future<PaperSize> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) == 'a3' ? PaperSize.a3 : PaperSize.a4;
  }

  static Future<void> save(PaperSize p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, p == PaperSize.a3 ? 'a3' : 'a4');
  }
}

/// 作业预览区（滚动显示所有 A4 页 + PDF/打印按钮）
class WorksheetPreviewPanel extends StatefulWidget {
  final List<WsPage> pages;
  final String label;
  final bool loading;

  /// 初始纸张（探测入口用）；为空时加载持久化偏好
  final PaperSize? initialPaper;
  const WorksheetPreviewPanel({
    super.key,
    this.pages = const [],
    this.label = '',
    this.loading = false,
    this.initialPaper,
  });

  @override
  State<WorksheetPreviewPanel> createState() => _WorksheetPreviewPanelState();
}

class _WorksheetPreviewPanelState extends State<WorksheetPreviewPanel> {
  final List<GlobalKey> _keys = [];
  bool _exporting = false;
  late PaperSize _paper = widget.initialPaper ?? PaperSize.a4;

  @override
  void initState() {
    super.initState();
    if (widget.initialPaper == null) {
      PaperPref.load().then((p) {
        if (mounted) setState(() => _paper = p);
      });
    }
  }

  @override
  void didUpdateWidget(WorksheetPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pages.length != widget.pages.length) {
      _keys.clear();
      for (var i = 0; i < widget.pages.length; i++) {
        _keys.add(GlobalKey());
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_keys.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final path = await PdfService.savePdf(_keys, '小学作业-${widget.label}', paper: _paper);
      if (mounted && path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF 已导出：$path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出 PDF 失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _print() async {
    if (_keys.isEmpty) return;
    setState(() => _exporting = true);
    try {
      await PdfService.printPdf(_keys, paper: _paper);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打印失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 预扫描所有页：算出每页大题序号的起始值，以及全卷大题的中文序号。
  ///
  /// 试卷的大题序号「一、二、三」要**跨页连续**，而页面是独立渲染的，
  /// 所以在预览层统一算好再传给各页。这样四个科目都不用改生成逻辑。
  ({List<int> offsets, List<String> columns}) _scanSections() {
    final offsets = <int>[];
    var n = 0;
    for (final p in widget.pages) {
      offsets.add(n);
      // 参考答案页不算大题：它不是题目，不该出现在得分栏里。
      // noSpread 在各科目里都专用于答案页（已核实）。
      if (p.noSpread) continue;
      for (final node in p.nodes) {
        if (WorksheetPageView.isSectionStart(node)) n++;
      }
    }
    return (
      offsets: offsets,
      columns: [for (var i = 0; i < n; i++) cnNumber(i)],
    );
  }

  Widget _pageView(int i, ({List<int> offsets, List<String> columns}) scan) {
    return WorksheetPageView(
      page: widget.pages[i],
      sectionOffset: scan.offsets[i],
      // 得分栏只出现在第一页（试卷惯例）
      scoreColumns: i == 0 ? scan.columns : const <String>[],
    );
  }

  /// 手机端点击预览放大查看（桌面端宽度足够，不启用）
  void _openZoom(int index, ({List<int> offsets, List<String> columns}) scan) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ZoomPage(
        title: '${widget.label} · 第 ${index + 1}/${widget.pages.length} 页',
        page: _pageView(index, scan),
      ),
    ));
  }

  /// 单个预览页插槽。RepaintBoundary 必须保留——PDF 就是截取它。
  Widget _pageSlot(BuildContext context, int i,
      ({List<int> offsets, List<String> columns}) scan) {
    final body = FittedBox(
      fit: BoxFit.fitWidth,
      child: RepaintBoundary(
        key: _keys[i],
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 300, maxWidth: 794),
          child: _pageView(i, scan),
        ),
      ),
    );
    // 手机端预览被缩得很小，点一下放大看（桌面端不启用，避免误触）
    if (MediaQuery.of(context).size.width >= 760) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openZoom(i, scan),
      child: body,
    );
  }

  /// A3 试卷版整幅纸：双栏并排，每栏 = 一个 A4 页槽。
  /// 标题/得分栏只在第一栏（真实试卷惯例）；栏内容沿用 A4 分页结果。
  /// RepaintBoundary 包整张纸，PDF 按 A3 横向逐纸截图。
  Widget _a3Sheet(BuildContext context, int sheetIndex, (int, int?) slots,
      ({List<int> offsets, List<String> columns}) scan) {
    Widget column(int idx) => SizedBox(
          width: _paper.columnWidth,
          child: WorksheetPageView(
            page: widget.pages[idx],
            sectionOffset: scan.offsets[idx],
            scoreColumns: idx == 0 ? scan.columns : const <String>[],
            showChrome: idx == 0,
            bare: true,
          ),
        );
    return FittedBox(
      fit: BoxFit.fitWidth,
      child: RepaintBoundary(
        key: _keys[sheetIndex],
        child: Container(
          width: _paper.pageWidth,
          constraints: BoxConstraints(minHeight: _paper.pageHeight),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 10,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column(slots.$1),
              if (slots.$2 != null) column(slots.$2!),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheets = _paper.sheetSlots(widget.pages.length);
    if (_keys.length != sheets.length) {
      _keys.clear();
      for (var i = 0; i < sheets.length; i++) {
        _keys.add(GlobalKey());
      }
    }
    final scan = _scanSections();
    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xffe9e6df),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: Column(
                  children: [
                    if (widget.loading)
                      const Padding(
                        padding: EdgeInsets.all(30),
                        child: CircularProgressIndicator(),
                      )
                    else if (widget.pages.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Text('点击「生成预览」查看作业',
                            style:
                                TextStyle(color: Color(0xff888888), fontSize: 15)),
                      )
                    else
                      for (var s = 0; s < sheets.length; s++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _paper == PaperSize.a4
                              ? _pageSlot(context, sheets[s].$1, scan)
                              : _a3Sheet(context, s, sheets[s], scan),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.pages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  runAlignment: WrapAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('纸张',
                              style: TextStyle(
                                  fontSize: 13, color: Color(0xff666666))),
                          const SizedBox(width: 4),
                          ChoiceChip(
                            label:
                                const Text('A4', style: TextStyle(fontSize: 13)),
                            selected: _paper == PaperSize.a4,
                            onSelected: (_) {
                                setState(() => _paper = PaperSize.a4);
                                PaperPref.save(PaperSize.a4);
                              },
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: const Text('A3 试卷版',
                                style: TextStyle(fontSize: 13)),
                            selected: _paper == PaperSize.a3,
                            onSelected: (_) {
                                setState(() => _paper = PaperSize.a3);
                                PaperPref.save(PaperSize.a3);
                              },
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: FilledButton.icon(
                        onPressed: _exporting ? null : _exportPdf,
                        icon: const Icon(Icons.download, size: 18),
                        label: Text(_exporting ? '导出中…' : '下载 PDF（${widget.label}）'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: OutlinedButton.icon(
                        onPressed: _exporting ? null : _print,
                        icon: const Icon(Icons.print, size: 18),
                        label: const Text('打印'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
    );
  }
}

/// 练字帖预览面板（渲染田字格行）
class CalligraphyPreviewPanel extends StatefulWidget {
  final List<CalligraphyPageData> pages;
  final String label;
  final bool loading;
  const CalligraphyPreviewPanel({
    super.key,
    this.pages = const [],
    this.label = '练字帖',
    this.loading = false,
  });

  @override
  State<CalligraphyPreviewPanel> createState() => _CalligraphyPreviewPanelState();
}

class _CalligraphyPreviewPanelState extends State<CalligraphyPreviewPanel> {
  final List<GlobalKey> _keys = [];
  bool _exporting = false;
  PaperSize _paper = PaperSize.a4;

  @override
  void initState() {
    super.initState();
    PaperPref.load().then((p) {
      if (mounted) setState(() => _paper = p);
    });
  }

  @override
  void didUpdateWidget(CalligraphyPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pages.length != widget.pages.length) {
      _keys.clear();
      for (var i = 0; i < widget.pages.length; i++) {
        _keys.add(GlobalKey());
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_keys.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final path = await PdfService.savePdf(_keys, '小学作业-${widget.label}', paper: _paper);
      if (mounted && path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF 已导出：$path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出 PDF 失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 单个练字帖预览页插槽（保留 RepaintBoundary 供 PDF 截取）
  Widget _callySlot(BuildContext context, int i) {
    final body = FittedBox(
      fit: BoxFit.fitWidth,
      child: RepaintBoundary(
        key: _keys[i],
        child: _CalligraphyPageView(page: widget.pages[i]),
      ),
    );
    if (MediaQuery.of(context).size.width >= 760) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ZoomPage(
          title: '${widget.label} · 第 ${i + 1}/${widget.pages.length} 页',
          page: _CalligraphyPageView(page: widget.pages[i]),
        ),
      )),
      child: body,
    );
  }

  /// A3 试卷版整幅纸（练字帖）：两页并排，标题只保留第一页。
  Widget _a3CallySheet(
      BuildContext context, int sheetIndex, (int, int?) slots) {
    Widget column(int idx) => SizedBox(
          width: _paper.columnWidth,
          child: _CalligraphyPageView(
            page: widget.pages[idx],
            showChrome: idx == 0,
            bare: true,
          ),
        );
    return FittedBox(
      fit: BoxFit.fitWidth,
      child: RepaintBoundary(
        key: _keys[sheetIndex],
        child: Container(
          width: _paper.pageWidth,
          constraints: BoxConstraints(minHeight: _paper.pageHeight),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 10,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column(slots.$1),
              if (slots.$2 != null) column(slots.$2!),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheets = _paper.sheetSlots(widget.pages.length);
    if (_keys.length != sheets.length) {
      _keys.clear();
      for (var i = 0; i < sheets.length; i++) {
        _keys.add(GlobalKey());
      }
    }
    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xffe9e6df),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: Column(
                  children: [
                    if (widget.loading)
                      const Padding(
                        padding: EdgeInsets.all(30),
                        child: CircularProgressIndicator(),
                      )
                    else if (widget.pages.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Text('点击「生成预览」查看练字帖',
                            style:
                                TextStyle(color: Color(0xff888888), fontSize: 15)),
                      )
                    else
                      for (var s = 0; s < sheets.length; s++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _paper == PaperSize.a4
                              ? _callySlot(context, sheets[s].$1)
                              : _a3CallySheet(context, s, sheets[s]),
                        ),
                  ],
                ),
              ),
            ),
            ),
            if (widget.pages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  runAlignment: WrapAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('纸张',
                              style: TextStyle(
                                  fontSize: 13, color: Color(0xff666666))),
                          const SizedBox(width: 4),
                          ChoiceChip(
                            label:
                                const Text('A4', style: TextStyle(fontSize: 13)),
                            selected: _paper == PaperSize.a4,
                            onSelected: (_) {
                                setState(() => _paper = PaperSize.a4);
                                PaperPref.save(PaperSize.a4);
                              },
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: const Text('A3 试卷版',
                                style: TextStyle(fontSize: 13)),
                            selected: _paper == PaperSize.a3,
                            onSelected: (_) {
                                setState(() => _paper = PaperSize.a3);
                                PaperPref.save(PaperSize.a3);
                              },
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: FilledButton.icon(
                        onPressed: _exporting ? null : _exportPdf,
                        icon: const Icon(Icons.download, size: 18),
                        label: Text(_exporting ? '导出中…' : '下载 PDF（${widget.label}）'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
    );
  }
}

class _CalligraphyPageView extends StatelessWidget {
  final CalligraphyPageData page;

  /// 是否渲染「写字练习」标题。A3 双栏时只保留第一栏。
  final bool showChrome;

  /// 去掉白底与投影（A3 双栏时由整幅纸容器统一承担）。
  final bool bare;
  const _CalligraphyPageView(
      {required this.page, this.showChrome = true, this.bare = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 794,
      height: 1123,
      padding: const EdgeInsets.fromLTRB(56, 44, 56, 44),
      decoration: bare
          ? null
          : BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(color: Color(0x26000000), blurRadius: 10, offset: Offset(0, 2)),
              ],
            ),
      child: Column(
        children: [
          if (showChrome && page.showTitle) ...[
            const Text('写字练习',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4)),
            const SizedBox(height: 22),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final row in page.rows)
                  _CalligraphyRow(cells: row, cellW: page.cellW, showPinyin: page.showPinyin),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CalligraphyRow extends StatelessWidget {
  final List<TianziCell> cells;
  final int cellW;
  final bool showPinyin;
  const _CalligraphyRow({
    required this.cells,
    required this.cellW,
    required this.showPinyin,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final c in cells)
            _TianziCell(cell: c, size: cellW.toDouble(), showPinyin: showPinyin),
        ],
      ),
    );
  }
}

class _TianziCell extends StatelessWidget {
  final TianziCell cell;
  final double size;
  final bool showPinyin;
  const _TianziCell({
    required this.cell,
    required this.size,
    required this.showPinyin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xff111111), width: 2),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: size / 2 - 0.75,
            top: 0,
            bottom: 0,
            child: Container(width: 1.5, color: const Color(0xbbaaaaaa)),
          ),
          Positioned(
            top: size / 2 - 0.75,
            left: 0,
            right: 0,
            child: Container(height: 1.5, color: const Color(0xbbaaaaaa)),
          ),
          if (showPinyin && cell.demo && cell.py.isNotEmpty)
            Positioned(
              top: -22,
              left: 0,
              right: 0,
              child: Text(
                cell.py,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xff555555), height: 1),
              ),
            ),
          if (cell.demo)
            Center(
              child: Text(
                cell.ch,
                style: TextStyle(
                  fontSize: size * 0.72,
                  color: const Color(0xffc8c8c8),
                  fontFamily: 'KaiTi',
                  height: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 手机端点击预览后的放大查看页：可双指缩放、拖动。
///
/// 初始缩放到「整页宽度适配屏幕」，再让用户放大看细节——
/// 直接 1:1 展示的话 794px 宽在手机上只能看到左半边。
class _ZoomPage extends StatefulWidget {
  final String title;
  final Widget page;
  const _ZoomPage({required this.title, required this.page});

  @override
  State<_ZoomPage> createState() => _ZoomPageState();
}

class _ZoomPageState extends State<_ZoomPage> {
  final _ctrl = TransformationController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final w = MediaQuery.of(context).size.width;
      const pageW = 794.0;
      final s = ((w - 20) / pageW).clamp(0.3, 1.0);
      _ctrl.value = Matrix4.identity()..scale(s);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff2b2b2b),
      appBar: AppBar(
        backgroundColor: const Color(0xff2b2b2b),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 14)),
      ),
      body: InteractiveViewer(
        transformationController: _ctrl,
        constrained: false,
        minScale: 0.3,
        maxScale: 6,
        boundaryMargin: const EdgeInsets.all(80),
        child: widget.page,
      ),
    );
  }
}
