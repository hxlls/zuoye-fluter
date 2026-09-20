// Web 端：通过浏览器下载导出文件
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

/// 将文本以指定文件名触发浏览器下载（Web 专用）。
///
/// `file_picker.saveFile` 在 Web 上不支持，所以这里单独实现。
/// Blob 不受 localStorage 配额限制，所以大文件导出在 Web 上反而是安全的。
Future<void> saveJsonFile(
    String fileName, String content, String mimeType) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob(<dynamic>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  html.document.body?.children.remove(anchor);
  // ⚠️ 不能紧接着 revoke：`click()` 只是把下载**排进队列**，真正取数在之后，
  // 同步撤销对象 URL 会让下载落空（文件越大越容易踩到，WebView 上更明显）。
  // 留一拍再释放。
  unawaited(Future<void>.delayed(const Duration(seconds: 1), () {
    html.Url.revokeObjectUrl(url);
  }));
}
