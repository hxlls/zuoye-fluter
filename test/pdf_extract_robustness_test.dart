/// PDF 提取的健壮性：真实样本上**不能因为单页读不出就整本失败**。
///
/// 实测《数学》四年级下册第 48 页会让 `syncfusion` 的 `extractTextLines`
/// 抛空指针（同页的 `extractText(layoutText: true)` 正常），修之前
/// 整本导入直接崩掉、用户只看到一句「提取失败：Null check operator…」。
/// 这里的断言是行为契约（少数页可失败、绝大多数页必须成功），
/// 而不是「第 48 页一定失败」——库哪天修好了，本测试照样该通过。
///
/// 样本只存在于开发机，CI 上自动跳过。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/core/pdf_textbook_import.dart';
import 'package:zuoye_fluter/core/textbook_structurer.dart';
import 'package:zuoye_fluter/data/app_data.dart';

const _math = '/home/ling/samples/_math4x.pdf';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  test('数学教材：整本解析不抛异常，且绝大多数字都取得到', () async {
    final bytes = await File(_math).readAsBytes();

    // 修复前这一步会抛 Null check operator used on a null value
    final TextbookParseResult r = await parseTextbookPdf(bytes);

    expect(r.totalPages, greaterThan(50));
    expect(r.unreadablePages.length, lessThanOrEqualTo(2),
        reason: '只允许个别页读不出：${r.unreadablePages}');
    expect(r.language.totalChars, greaterThan(10000),
        reason: '绝大多数页的文字应当都取到了');
  }, skip: File(_math).existsSync() ? false : '本机无数学教材样本');

  test('数学教材不会被误判成外文教材', () async {
    // 数学教材数字与符号远多于汉字，曾经担心 hanRatio 掉到 30% 以下
    // 从而给出「其他语种请用拍照导入」这种方向完全错误的建议。
    // 实测 52.6%，安全边很宽 —— 这条把它钉住。
    final r = await parseTextbookPdf(
      await File(_math).readAsBytes(),
      firstPage: 6,
      lastPage: 40,
    );
    expect(r.language.enoughText, isTrue);
    expect(r.language.hanRatio, greaterThan(kChineseHanRatio),
        reason: '汉字占比实测 0.53，距阈值 0.30 有余量');
    expect(r.language.looksNonChinese, isFalse);
  }, skip: File(_math).existsSync() ? false : '本机无数学教材样本');

  test('探测阶段也不崩（它只扫前几页，但同样走逐页提取）', () async {
    final probe = await probeTextbookPdf(await File(_math).readAsBytes());
    expect(probe.pageCount, greaterThan(50));
    expect(probe.result.name, contains('数学'));
  }, skip: File(_math).existsSync() ? false : '本机无数学教材样本');
}
