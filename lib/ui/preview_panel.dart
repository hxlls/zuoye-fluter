import 'package:flutter/material.dart';
import '../core/worksheet_model.dart';
import '../core/calligraphy_worksheet.dart';
import '../pdf/pdf_service.dart';
import 'worksheet_view.dart';

/// 作业预览区（滚动显示所有 A4 页 + PDF/打印按钮）
class WorksheetPreviewPanel extends StatefulWidget {
  final List<WsPage> pages;
  final String label;
  final bool loading;
  const WorksheetPreviewPanel({
    super.key,
    this.pages = const [],
    this.label = '',
    this.loading = false,
  });

  @override
  State<WorksheetPreviewPanel> createState() => _WorksheetPreviewPanelState();
}

class _WorksheetPreviewPanelState extends State<WorksheetPreviewPanel> {
  final List<GlobalKey> _keys = [];
  bool _exporting = false;

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
      final path = await PdfService.savePdf(_keys, '小学作业-${widget.label}');
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
      await PdfService.printPdf(_keys);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打印失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_keys.length != widget.pages.length) {
      _keys.clear();
      for (var i = 0; i < widget.pages.length; i++) {
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
                        child: Text('点击「生成预览」查看作业',
                            style:
                                TextStyle(color: Color(0xff888888), fontSize: 15)),
                      )
                    else
                      for (var i = 0; i < widget.pages.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: FittedBox(
                            fit: BoxFit.fitWidth,
                            child: RepaintBoundary(
                              key: _keys[i],
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                    minWidth: 300, maxWidth: 794),
                                child: WorksheetPageView(page: widget.pages[i]),
                              ),
                            ),
                          ),
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
      final path = await PdfService.savePdf(_keys, '小学作业-${widget.label}');
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

  @override
  Widget build(BuildContext context) {
    if (_keys.length != widget.pages.length) {
      _keys.clear();
      for (var i = 0; i < widget.pages.length; i++) {
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
                      for (var i = 0; i < widget.pages.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: FittedBox(
                            fit: BoxFit.fitWidth,
                            child: RepaintBoundary(
                              key: _keys[i],
                              child: _CalligraphyPageView(page: widget.pages[i]),
                            ),
                          ),
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
  const _CalligraphyPageView({required this.page});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 794,
      height: 1123,
      padding: const EdgeInsets.fromLTRB(56, 44, 56, 44),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(color: Color(0x26000000), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          if (page.showTitle) ...[
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
