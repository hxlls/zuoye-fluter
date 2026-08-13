import '../data/app_data.dart';
import 'rand_gen.dart';

/// 练字帖选项
class CalligraphyOptions {
  String source; // grade / custom
  int charCount;
  String customText;
  int practice;
  int perRow;
  int rows;
  bool showPinyin;
  bool showTitle;
  int grade;
  String version;
  String volume;

  CalligraphyOptions({
    this.source = 'grade',
    this.charCount = 16,
    this.customText = '',
    this.practice = 2,
    this.perRow = 5,
    this.rows = 5,
    this.showPinyin = true,
    this.showTitle = true,
    this.grade = 1,
    this.version = 'renjiao',
    this.volume = '上',
  });
}

/// 田字格单元格
class TianziCell {
  final bool demo;
  final String ch;
  final String py;
  TianziCell({required this.demo, required this.ch, required this.py});
}

/// 练字帖页面数据（每页多行，每行多格）
class CalligraphyPageData {
  final List<List<TianziCell>> rows; // 每行 cells
  final int cellW; // 单元格边长 px
  final bool showPinyin;
  final bool showTitle;
  CalligraphyPageData({
    required this.rows,
    required this.cellW,
    required this.showPinyin,
    required this.showTitle,
  });
}

List<CalligraphyPageData> calligraphyRenderPages(CalligraphyOptions opts) {
  final chars = collectCalligraphyChars(opts);
  final perRow = opts.perRow;
  final practice = opts.practice;
  final rowsPerPage = opts.rows;

  const contentW = 682;
  const gap = 6;
  final cellWByCols = ((contentW - (perRow - 1) * gap) / perRow).floor();

  final pinyinH = opts.showPinyin ? 24 : 0;
  const padH = 88;
  final titleH = opts.showTitle ? 82 : 0;
  final usable = 1123 - padH - titleH;
  final cellWByRows = ((usable / rowsPerPage - pinyinH)).floor();

  final cellW = cellWByCols < cellWByRows ? cellWByCols : cellWByRows;
  final cw = cellW < 36 ? 36 : cellW;

  final cells = <TianziCell>[];
  for (final c in chars) {
    cells.add(TianziCell(demo: true, ch: c[0], py: c.length > 1 ? c[1] : ''));
    for (var k = 0; k < practice; k++) {
      cells.add(TianziCell(demo: false, ch: '', py: ''));
    }
  }

  final rows = <List<TianziCell>>[];
  for (var i = 0; i < cells.length; i += perRow) {
    rows.add(cells.sublist(i, i + perRow > cells.length ? cells.length : i + perRow));
  }
  if (rows.isNotEmpty && rows.last.length < perRow) {
    while (rows.last.length < perRow) {
      rows.last.add(TianziCell(demo: false, ch: '', py: ''));
    }
  }

  final pages = <CalligraphyPageData>[];
  for (var p = 0; p < rows.length; p += rowsPerPage) {
    final end = p + rowsPerPage > rows.length ? rows.length : p + rowsPerPage;
    pages.add(CalligraphyPageData(
      rows: rows.sublist(p, end),
      cellW: cw,
      showPinyin: opts.showPinyin,
      showTitle: opts.showTitle,
    ));
  }
  return pages;
}

List<List<String>> collectCalligraphyChars(CalligraphyOptions opts) {
  final data = AppData();
  if (opts.source == 'custom') {
    final text = opts.customText.replaceAll(RegExp(r'\s+'), '');
    final seen = <String>{};
    final out = <String>[];
    for (final ch in text.runes.map(String.fromCharCode)) {
      if (!seen.contains(ch)) {
        seen.add(ch);
        out.add(ch);
      }
    }
    return out.map((ch) => [ch, pinyinLookup(ch) ?? '']).toList();
  }
  final list = data.vol(opts.version, opts.grade, opts.volume, 'cally')?.cally ?? [];
  final n = opts.charCount;
  final selected = <List<String>>[];
  final used = <String>{};
  final rng = RandGen(grade: opts.grade);
  var guard = 0;
  while (selected.length < n && used.length < list.length && guard++ < 5000) {
    final idx = rng.rand(0, list.length - 1);
    final item = list[idx];
    final key = '${item[0]}|${item[1]}';
    if (!used.contains(key)) {
      used.add(key);
      selected.add(item);
    }
  }
  return selected;
}

/// 拼音查询（跨全部版本查）
String? pinyinLookup(String ch) {
  final data = AppData();
  for (final ver in data.content.values) {
    for (var g = 1; g <= 6; g++) {
      final vols = ver[g];
      if (vols == null) continue;
      final callyMap = vols['cally'];
      if (callyMap == null) continue;
      for (final v in ['上', '下']) {
        final list = callyMap[v]?.cally ?? [];
        for (final c in list) {
          if (c[0] == ch && c.length > 1 && c[1].isNotEmpty) return c[1];
        }
      }
    }
  }
  return null;
}
