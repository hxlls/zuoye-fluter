import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/core/pdf_text_extract.dart';

void main() {
  group('PDF 文本质量评分 scoreChineseQuality', () {
    test('空文本 → empty（扫描件/图片版 PDF 的典型情况）', () {
      final q = scoreChineseQuality('');
      expect(q.verdict, PdfTextVerdict.empty);
      expect(q.total, 0);
      expect(q.usable, false);
    });

    test('全是空白 → tooShort', () {
      final q = scoreChineseQuality('   \n\n   ');
      expect(q.verdict, PdfTextVerdict.tooShort);
      expect(q.usable, false);
    });

    test('过短（不足 10 字）→ tooShort', () {
      expect(scoreChineseQuality('第一单元').verdict, PdfTextVerdict.tooShort);
    });

    test('干净的中文课文 → clean', () {
      // 这段就是前置实验里造的样本内容，在 Python 侧实测判为 clean
      const text = '第一单元  1 春\n人教版语文七年级上册\n'
          '盼望着，盼望着，东风来了，春天的脚步近了。\n'
          '一切都像刚睡醒的样子，欣欣然张开了眼。山朗润起来了，水涨起来了，太阳的脸红起来了。';
      final q = scoreChineseQuality(text);
      expect(q.verdict, PdfTextVerdict.clean);
      expect(q.usable, true);
      expect(q.cjk, greaterThan(50));
      expect(q.cjkRatio, greaterThan(0.5));
      expect(q.privateUse, 0);
      expect(q.replacement, 0);
      expect(q.badRatio, 0);
    });

    test('整页私用区字符 → garbage（字体子集化未映射）', () {
      // U+E000–U+F8FF 私用区：ToUnicode CMap 缺失时的典型产物
      final text = String.fromCharCodes(List.generate(80, (i) => 0xE000 + i));
      final q = scoreChineseQuality(text);
      expect(q.verdict, PdfTextVerdict.garbage);
      expect(q.privateUse, 80);
      expect(q.badRatio, 1.0);
      expect(q.usable, false);
    });

    test('整页替换符 → garbage', () {
      final text = '\uFFFD' * 60;
      final q = scoreChineseQuality(text);
      expect(q.verdict, PdfTextVerdict.garbage);
      expect(q.replacement, 60);
    });

    test('边界：乱码占比 50% 仍判 garbage（钉住 0.3 这个阈值）', () {
      // 关键：前两个 garbage 用例的 badRatio 都是 1.0，
      // 把阈值从 0.3 改成 0.99 它们照样通过 —— 等于没卡住阈值。
      // 这里取 0.42，正好落在 (0.3, 0.99) 之间，阈值一改就会失败。
      final body = '盼望着，盼望着，东风来了，春天的脚步近了。' * 2;
      final pua = String.fromCharCodes(List.generate(31, (i) => 0xE000 + i));
      final text = body + pua;
      // 显式钉住长度：以后改文案导致占比漂移时，这里会立刻报警，
      // 而不是让测试悄悄退化成「测不到阈值」。
      expect(body.length, 42);
      expect(text.length, 73);
      final q = scoreChineseQuality(text);
      expect(q.badRatio, greaterThan(0.3));
      expect(q.badRatio, lessThan(0.99));
      expect(q.verdict, PdfTextVerdict.garbage);
    });

    test('边界：乱码占比低于 2% 仍判 clean（钉住 0.02 这个阈值）', () {
      // 为什么需要这条：只有「阈值上方」的用例钉不住阈值 ——
      // 把 0.02 放宽到 0.001，那些用例照样是 partial，测试全过。
      // 必须有一条落在**阈值下方**且要求 clean 的用例。
      // 语义上这也成立：偶发一两个乱码字符不该让整页回落视觉模型。
      final body = '盼望着，盼望着，东风来了，春天的脚步近了。' * 4; // 84 字
      final text = body + String.fromCharCode(0xE001);
      expect(body.length, 84);
      expect(text.length, 85);
      final q = scoreChineseQuality(text);
      expect(q.privateUse, 1);
      expect(q.badRatio, lessThan(0.02));
      expect(q.verdict, PdfTextVerdict.clean);
      expect(q.usable, true);
    });

    test('边界：乱码占比刚过 2% 就判 partial（钉住 0.02 这个阈值）', () {
      // 42 个汉字 + 1 个私用区 = 43 → badRatio ≈ 0.0233，刚过 0.02。
      // （最初写成 50 字 + 1 乱码 → 1/51 ≈ 0.0196 < 0.02，判成 clean，
      //   测试自己先失败了 —— 所以这里把长度断言写出来。）
      final body = '盼望着，盼望着，东风来了，春天的脚步近了。' * 2;
      final text = body + String.fromCharCode(0xE001);
      expect(body.length, 42);
      expect(text.length, 43);
      final q = scoreChineseQuality(text);
      expect(q.privateUse, 1);
      expect(q.badRatio, greaterThan(0.02));
      expect(q.badRatio, lessThan(0.3));
      expect(q.verdict, PdfTextVerdict.partial);
    });

    test('混排：少量乱码混在正常课文里 → partial', () {
      // 60 个汉字 + 3 个私用区 → badRatio ≈ 0.045 > 0.02
      final text = '春天的脚步近了，山朗润起来了，水涨起来了，太阳的脸红起来了。'
          '小草偷偷地从土里钻出来，嫩嫩的，绿绿的。园子里，田野里，瞧去。'
          '${String.fromCharCodes([0xE001, 0xE002, 0xE003])}';
      final q = scoreChineseQuality(text);
      expect(q.verdict, PdfTextVerdict.partial);
      expect(q.privateUse, 3);
      expect(q.badRatio, greaterThan(0.02));
      expect(q.badRatio, lessThan(0.3));
      expect(q.usable, false);
    });

    test('几乎没有汉字的长文本 → partial（提错了语言层）', () {
      final text = 'abcdefghijklmnopqrstuvwxyz 0123456789 ' * 5;
      final q = scoreChineseQuality(text);
      expect(q.verdict, PdfTextVerdict.partial);
      expect(q.cjk, 0);
      expect(q.badRatio, 0);
    });

    test('中文标点与全角符号不算问题字符', () {
      const text = '盼望着，盼望着，东风来了，春天的脚步近了。'
          '（人教版）《春》——朱自清著；１２３４５６７８９０！？、：';
      final q = scoreChineseQuality(text);
      expect(q.verdict, PdfTextVerdict.clean);
      expect(q.badRatio, 0);
      expect(q.privateUse, 0);
      expect(q.replacement, 0);
    });

    test('英文教材页会被判 partial —— 已知取舍，记录在此', () {
      // 英语教材正文是 ASCII。本函数按「中文占比」判定，会把纯英文判为 partial
      // → 走视觉兜底。这是**保守但安全**的选择：宁可多一次调用，
      // 也不要把「其实没提到中文」的页当成功。接英语教材时需在此处特判。
      const text = 'Lesson 1  My Family\n'
          'This is my father. He is a doctor. This is my mother. She is a teacher.';
      final q = scoreChineseQuality(text);
      expect(q.verdict, PdfTextVerdict.partial);
      expect(q.usable, false);
    });

    test('评分不改变入参，且各字段自洽', () {
      const text = '盼望着，盼望着，东风来了，春天的脚步近了。';
      final q = scoreChineseQuality(text);
      expect(q.total, text.length);
      expect(q.cjk, lessThanOrEqualTo(q.total));
      expect(q.cjkRatio, closeTo(q.cjk / q.total, 1e-9));
      expect(q.badRatio, closeTo((q.privateUse + q.replacement) / q.total, 1e-9));
    });
  });
}
