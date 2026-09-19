/// PDF 教材导入：一页文本的**可用性判定**。
///
/// 为什么需要它：中文 PDF 的文本提取质量取决于文件内嵌的 **ToUnicode CMap**。
/// 字体子集化处理不当的 PDF 会提取出乱码或私用区字符。
/// 所以「逐页」判断质量，不合格的页才回落到视觉模型 —— 既省 AI 成本，
/// 又不会把乱码当课文写进语料库。
///
/// 判定阈值与工作区脚本 `_pdf_probe.py` 保持一致（那份已在两份带文本层的
/// 中文 PDF 上实测通过：均判为 clean，提取结果与原文逐字一致）。
library;

/// 一页提取文本的可用性判定。
enum PdfTextVerdict {
  /// 没提到任何文字 —— 多为扫描件或纯图片版 PDF，必须走视觉兜底。
  empty,

  /// 字符太少，不足以判断（空白页、插图页）。同样走视觉兜底。
  tooShort,

  /// 整页乱码 —— 该页必须走视觉兜底。
  garbage,

  /// 部分乱码 —— 可用，但需要人工确认或提高兜底权重。
  partial,

  /// 中文干净 —— 直接采用，零 AI 成本。
  clean,
}

/// 一页文本的质量指标与判定结果。
class ChineseTextQuality {
  /// 总字符数（含空白）
  final int total;

  /// 汉字个数（CJK 统一表意文字 U+4E00–U+9FFF）
  final int cjk;

  /// 汉字占比
  final double cjkRatio;

  /// 私用区字符个数（U+E000–U+F8FF）—— 字体子集化未映射时的典型产物
  final int privateUse;

  /// U+FFFD 替换符个数
  final int replacement;

  /// 问题字符占比（私用区 + 替换符）
  final double badRatio;

  final PdfTextVerdict verdict;

  const ChineseTextQuality({
    required this.total,
    required this.cjk,
    required this.cjkRatio,
    required this.privateUse,
    required this.replacement,
    required this.badRatio,
    required this.verdict,
  });

  /// 这一页是否值得直接采用（无需视觉兜底）
  bool get usable => verdict == PdfTextVerdict.clean;

  @override
  String toString() => 'ChineseTextQuality($verdict, '
      'total=$total, cjk=$cjk(${(cjkRatio * 100).toStringAsFixed(0)}%), '
      'pua=$privateUse, repl=$replacement)';
}

// 私用区：字体子集化处理不当时，未映射的字形会落到这里
final RegExp _pua = RegExp(r'[\uE000-\uF8FF]');
final RegExp _replacement = RegExp('\uFFFD');
// 汉字
final RegExp _cjk = RegExp(r'[\u4E00-\u9FFF]');
// 中文标点与全角符号
final RegExp _cjkPunct = RegExp(r'[\u3000-\u303F\uFF00-\uFFEF]');

/// 判定一页提取文本的质量。
///
/// 判定顺序（与 `_pdf_probe.py` 一致）：
/// 空 → 过短 → 整页乱码 → 部分乱码 → 干净
ChineseTextQuality scoreChineseQuality(String text) {
  final total = text.length;
  if (total == 0) {
    return const ChineseTextQuality(
      total: 0,
      cjk: 0,
      cjkRatio: 0,
      privateUse: 0,
      replacement: 0,
      badRatio: 0,
      verdict: PdfTextVerdict.empty,
    );
  }

  final pua = _pua.allMatches(text).length;
  final repl = _replacement.allMatches(text).length;
  final cjk = _cjk.allMatches(text).length;
  final punct = _cjkPunct.allMatches(text).length;

  // 空白不算问题字符
  var ws = 0;
  for (final r in text.runes) {
    if (r == 0x20 || r == 0x09 || r == 0x0A || r == 0x0D) ws++;
  }

  final bad = pua + repl;
  final cjkRatio = cjk / total;
  final badRatio = bad / total;

  PdfTextVerdict verdict;
  if (total < 10) {
    verdict = PdfTextVerdict.tooShort;
  } else if (badRatio > 0.3) {
    verdict = PdfTextVerdict.garbage;
  } else if (badRatio > 0.02 || cjkRatio < 0.05) {
    verdict = PdfTextVerdict.partial;
  } else {
    verdict = PdfTextVerdict.clean;
  }

  // punct / ws 目前不参与判定，但保留计算以便将来调阈值时可直接用
  assert(punct >= 0 && ws >= 0);

  return ChineseTextQuality(
    total: total,
    cjk: cjk,
    cjkRatio: cjkRatio,
    privateUse: pua,
    replacement: repl,
    badRatio: badRatio,
    verdict: verdict,
  );
}
