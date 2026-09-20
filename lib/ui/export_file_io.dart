// 非 Web 端（Android / iOS / Windows / Linux / macOS）：导出文本文件
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';

/// 导出文本文件（非 Web 专用）。
///
/// ⚠️ **移动端必须走 `file_picker`，不能用 `file_selector.getSaveLocation`。**
/// `file_selector_android`（0.5.1+12）与 `file_selector_ios`（0.5.3+1）都**没有实现**
/// `getSaveLocation`（只有 openFile / openFiles / getDirectoryPath），
/// 而 `file_selector_platform_interface` 的基类默认实现是直接
/// `throw UnimplementedError('getSavePath() has not been implemented.')` ——
/// 所以旧实现在手机上点一次就是「导出失败：UnimplementedError…」，功能等于没有。
///
/// `file_picker.saveFile` 在 Android / iOS 上由插件走 SAF 自己写盘
/// （**bytes 必填**），桌面端则返回路径由调用方写。Web 不支持，另有实现。
Future<void> saveJsonFile(
    String fileName, String content, String mimeType) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await FilePicker.platform.saveFile(
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: utf8.encode(content),
    );
    return;
  }
  final location = await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON', extensions: <String>['json']),
    ],
  );
  if (location == null) return; // 用户取消
  await File(location.path).writeAsString(content);
}
