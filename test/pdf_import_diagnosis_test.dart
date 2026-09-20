/// 「一节课都切不出来」的诊断文案（`noLessonMessage`）。
///
/// 三种原因的处置**正好相反**，文案必须分得开、也不能互相串：
/// 扫描图片版 → 先 OCR / 拍照导入；外文教材 → 换中文教材；
/// 数学教材 → 别在 PDF 上折腾了，去「数学」面板出题。
///
/// 数字占比全部取自真实教材的实测输出（见 `kMathDigitRatio` 的注释），
/// 不是随手编的比例 —— 这段文案直接把比例报给用户，报错就是把原因说错。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zuoye_fluter/core/textbook_structurer.dart';
import 'package:zuoye_fluter/ui/pdf_import_flow.dart';

/// 一本「切不出课」的样本：无目录、无课，只带语言画像与读不出的页。
TextbookParseResult _broken(
  TextLanguageProfile lang, {
  List<int> unreadable = const [],
}) =>
    TextbookParseResult(
      name: '样本',
      toc: const [],
      lessons: const [],
      pageOffset: null,
      tocPages: const [],
      language: lang,
      unreadablePages: unreadable,
    );

const _math = TextLanguageProfile(
    totalChars: 30683, hanChars: 16146, digitChars: 8593);
const _yuwen = TextLanguageProfile(
    totalChars: 51687, hanChars: 42907, digitChars: 756);
const _eng = TextLanguageProfile(
    totalChars: 35548, hanChars: 807, digitChars: 755);
const _scan = TextLanguageProfile(totalChars: 120, hanChars: 60);

void main() {
  test('数学教材：报出数字占比，并指向「数学」面板', () {
    final msg = noLessonMessage(_broken(_math), 6, 40);

    expect(msg, contains('28.0%'), reason: '把证据（数字占比）报出来');
    expect(msg, contains('数学教材'));
    expect(msg, contains('「数学」面板'), reason: '给出真正可行的下一步');
    expect(msg, isNot(contains('拍照导入')),
        reason: '数学教材拍照导入一样切不出课，不能把用户送进死路');
    expect(msg, isNot(contains('文本层')),
        reason: '文字已经全部取到，再提「文本层」就是把原因说反了');
  });

  test('中文、数字也不算多：仍指向「没有成篇课文」，不提 OCR', () {
    // 道德与法治一年级上册的实测值：汉字 77.1%、数字 5.2%、切出 16 课。
    // 数字占比够不上数学阈值，所以措辞留有余地（「多半也是」），
    // 但结论同样是「导入这条路不通」，而不是「去 OCR」。
    final msg = noLessonMessage(
      _broken(const TextLanguageProfile(
          totalChars: 6121, hanChars: 4719, digitChars: 321)),
      4,
      20,
    );

    expect(msg, contains('5.2%'));
    expect(msg, contains('按单元编排'));
    expect(msg, isNot(contains('文本层')));
  });

  test('外文教材：换教材 + 拍照导入，且绝不提数学', () {
    final msg = noLessonMessage(_broken(_eng), 1, 81);

    expect(msg, contains('不是中文教材'));
    expect(msg, contains('拍照导入'));
    expect(msg, isNot(contains('数学')),
        reason: '外文教材的问题跟数学无关，两条支路不能串');
  });

  test('文字量不够（扫描图片版）：才提文本层、OCR 与拍照导入', () {
    final msg = noLessonMessage(_broken(_scan), 1, 3);

    expect(msg, contains('文本层'));
    expect(msg, contains('OCR'));
    expect(msg, isNot(contains('数学')));
  });

  test('整页读不出的页号，三种原因下都要如实带上', () {
    for (final lang in [_math, _eng, _scan]) {
      final msg = noLessonMessage(_broken(lang, unreadable: [7, 9]), 1, 10);
      expect(msg, contains('另有 2 页整页读不出文字'));
      expect(msg, contains('第 7、9 页'));
    }
  });

  test('语文教材的实测值不会误落到任何一条「切不出课」的支路说明里', () {
    // 语文 6 下实测汉字 83.0%、数字 1.5%，且有 46 课 —— 它本就不该走到这里，
    // 这里只是把「万一」钉住：判据不能把它说成数学或外文。
    expect(_yuwen.looksNonChinese, false);
    expect(_yuwen.looksMathLike, false);
  });
}
