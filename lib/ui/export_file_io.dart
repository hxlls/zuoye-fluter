// 非 Web 端（Android / iOS / Windows / Linux / macOS）：用系统保存对话框导出
import 'dart:io' show File;
import 'package:file_selector/file_selector.dart';

/// 通过系统「保存文件」对话框导出文本（非 Web 专用）
Future<void> saveJsonFile(String fileName, String content, String mimeType) async {
  final location = await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON', extensions: <String>['json']),
    ],
  );
  if (location == null) return; // 用户取消
  final file = File(location.path);
  await file.writeAsString(content);
}
