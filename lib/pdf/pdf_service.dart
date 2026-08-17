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

/// PDF 导出服务：对每个 A4 预览页截图，合成 PDF（等价于原 html2canvas+jsPDF）
class PdfService {
  /// 把一组 A4 页面截图并生成 PDF 文件
  /// [pageKeys] 每个页面对应一个 GlobalKey，其 widget 尺寸为 A4 (794x1123)
  static Future<Uint8List> buildPdf(List<GlobalKey> pageKeys) async {
    final pdf = pw.Document();
    for (final key in pageKeys) {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) continue;
      // A4 页 794px 宽对应 595pt(≈8.27")，pixelRatio 3.1 ≈ 297 DPI，接近打印标准 300 DPI。
      // 高分辨率截图可避免打印时降采样把细线/浅色冲淡（低于 ~200 DPI 会整体偏淡）。
      final image = await boundary.toImage(pixelRatio: 3.1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) continue;
      final provider = pw.MemoryImage(bytes.buffer.asUint8List());
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Image(provider, fit: pw.BoxFit.contain),
        ),
      );
    }
    return pdf.save();
  }

  /// 保存 PDF：弹出系统「另存为」对话框，由用户自由选择存储位置
  static Future<String?> savePdf(List<GlobalKey> pageKeys, String filename) async {
    final data = await buildPdf(pageKeys);
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
      List<GlobalKey> pageKeys, String filename) async {
    final data = await buildPdf(pageKeys);
    final dir = await getDownloadsDirectory();
    final file = File('${dir?.path ?? '.'}/$filename.pdf');
    await file.writeAsBytes(data, flush: true);
    return file.path;
  }

  /// 打印
  static Future<void> printPdf(List<GlobalKey> pageKeys) async {
    final data = await buildPdf(pageKeys);
    await Printing.layoutPdf(onLayout: (_) => data);
  }
}
