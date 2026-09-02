// Web 端：通过浏览器下载导出文件
import 'dart:convert';
import 'dart:html' as html;

/// 将文本以指定文件名触发浏览器下载（Web 专用）
Future<void> saveJsonFile(String fileName, String content, String mimeType) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob(<dynamic>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  html.document.body?.children.remove(anchor);
  html.Url.revokeObjectUrl(url);
}
