import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/paper.dart';

/// PDF 导出服务：对每个预览页/整幅纸截图，合成 PDF（等价于原 html2canvas+jsPDF）
///
/// - A4：每个 RepaintBoundary 是一页 A4 (794x1123)，合成 PdfPageFormat.a4。
/// - A3 试卷版：每个 RepaintBoundary 是一张 A3 横向整幅纸 (1588x1123)，
///   合成 PdfPageFormat.a3.landscape；预览层已把两栏拼进同一张纸。
class PdfService {
  /// 把一组页面截图并生成 PDF
  /// [pageKeys] 每个页面对应一个 GlobalKey，A4 时 widget 尺寸 794x1123，
  /// A3 时整幅纸 1588x1123（两者同为 96dpi CSS 口径）。
  static Future<Uint8List> buildPdf(List<GlobalKey> pageKeys,
      {PaperSize paper = PaperSize.a4}) async {
    final pdf = pw.Document();
    // 794px 宽对应 595pt(≈8.27")、1123px 对应 842pt(≈11.69")——
    // 两种纸的基准都是 96dpi，pixelRatio 3.1 ≈ 297 DPI，接近打印标准 300 DPI。
    // 高分辨率截图可避免打印时降采样把细线/浅色冲淡（低于 ~200 DPI 会整体偏淡）。
    const pixelRatio = 3.1;
    final format =
        paper == PaperSize.a4 ? PdfPageFormat.a4 : PdfPageFormat.a3.landscape;
    for (final key in pageKeys) {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) continue;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) continue;
      final provider = pw.MemoryImage(bytes.buffer.asUint8List());
      pdf.addPage(
        pw.Page(
          pageFormat: format,
          build: (ctx) => pw.Image(provider, fit: pw.BoxFit.contain),
        ),
      );
    }
    return pdf.save();
  }

  /// 保存 PDF：弹出系统「另存为」对话框，由用户自由选择存储位置
  static Future<String?> savePdf(List<GlobalKey> pageKeys, String filename,
      {PaperSize paper = PaperSize.a4}) async {
    final data = await buildPdf(pageKeys, paper: paper);
    if (kIsWeb) {
      await Printing.layoutPdf(onLayout: (_) => data, name: filename);
      return null;
    }
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // 移动端：系统文件选择器（Android SAF / iOS 文件 App）
      final path = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          data: data,
          fileName: '$filename.pdf',
          mimeTypesFilter: const ['application/pdf'],
        ),
      );
      return path;
    }
    // 桌面端（Windows/macOS/Linux）：系统另存为对话框
    final location = await getSaveLocation(
      suggestedName: '$filename.pdf',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
    );
    if (location == null) return null; // 用户取消
    final file = File(location.path);
    await file.writeAsBytes(data, flush: true);
    return file.path;
  }

  /// 直接保存到下载目录（Android / Linux）
  static Future<String?> saveToDownloads(
      List<GlobalKey> pageKeys, String filename,
      {PaperSize paper = PaperSize.a4}) async {
    final data = await buildPdf(pageKeys, paper: paper);
    final dir = await getDownloadsDirectory();
    final file = File('${dir?.path ?? '.'}/$filename.pdf');
    await file.writeAsBytes(data, flush: true);
    return file.path;
  }

  /// 打印
  static Future<void> printPdf(List<GlobalKey> pageKeys,
      {PaperSize paper = PaperSize.a4}) async {
    final data = await buildPdf(pageKeys, paper: paper);
    await Printing.layoutPdf(onLayout: (_) => data);
  }
}
