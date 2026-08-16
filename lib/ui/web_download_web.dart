/// Web 平台：用浏览器触发文件下载（dart:html）
import 'dart:typed_data';
import 'dart:html' as html;

void webDownloadBytes(Uint8List bytes, String filename, {String mimeType = 'audio/mpeg'}) {
  final anchor = html.AnchorElement(
    href: Uri.dataFromBytes(bytes, mimeType: mimeType).toString(),
  )
    ..download = filename;
  anchor.click();
}
