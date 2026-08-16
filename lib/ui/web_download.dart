/// 非 Web 平台：无下载动作（移动/桌面用系统文件对话框保存）
import 'dart:typed_data';

void webDownloadBytes(Uint8List bytes, String filename, {String mimeType = 'audio/mpeg'}) {
  // 非 web 平台由 _saveAudioBytes 的分支处理
}
