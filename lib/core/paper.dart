/// 纸张尺寸：预览、导出、打印共用的单一来源。
///
/// - [PaperSize.a4]：A4 纵向，794x1123 px（96dpi CSS 口径），一页一纸。
/// - [PaperSize.a3]：A3 横向（试卷版），1588x1123 px，双栏并排——
///   每栏即一个 A4 页槽（794 宽），对应真实试卷「8K 横放、两栏、
///   标题与得分栏只出现在第一栏」的版式。
///
/// 分页逻辑不变：各科目生成器仍按 A4 可用高度分页，A3 只是把
/// 这些「栏」两两拼上一张纸，并省略非第一栏的重复主标题。
enum PaperSize { a4, a3 }

extension PaperSizeX on PaperSize {
  /// 纸面宽度（px @96dpi）
  double get pageWidth => this == PaperSize.a4 ? 794 : 1588;

  /// 纸面高度（px @96dpi）
  double get pageHeight => 1123.0;

  /// 单栏宽度（= A4 页宽，生成器分页宽度不变）
  double get columnWidth => 794.0;

  String get label => this == PaperSize.a4 ? 'A4' : 'A3';

  /// 把页序列按栏拼到纸上：返回每张纸的 (左栏页号, 右栏页号?)。
  /// A4 时每页独占一张纸；A3 奇数页时最后一张右栏留空。
  List<(int, int?)> sheetSlots(int pageCount) {
    if (this == PaperSize.a4) {
      return [for (var i = 0; i < pageCount; i++) (i, null)];
    }
    final sheets = <(int, int?)>[];
    for (var i = 0; i < pageCount; i += 2) {
      sheets.add((i, i + 1 < pageCount ? i + 1 : null));
    }
    return sheets;
  }
}
