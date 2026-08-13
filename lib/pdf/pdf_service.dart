import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
      final image = await boundary.toImage(pixelRatio: 2.0);
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

  /// 保存 PDF（桌面端直接存下载目录，移动端弹出分享/保存对话框）
  static Future<String?> savePdf(List<GlobalKey> pageKeys, String filename) async {
    final data = await buildPdf(pageKeys);
    if (kIsWeb) {
      await Printing.layoutPdf(onLayout: (_) => data, name: filename);
      return null;
    }
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) {
        final file = File('${dir.path}/$filename.pdf');
        await file.writeAsBytes(data, flush: true);
        return file.path;
      }
    } catch (_) {}
    // 无下载目录（如部分 Android 环境）时走分享/打印对话框
    await Printing.layoutPdf(onLayout: (_) => data, name: filename);
    return null;
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
