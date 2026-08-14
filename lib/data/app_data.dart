import 'dart:convert';
import 'package:flutter/services.dart';

/// 教材版本定义
class Textbook {
  final String key;
  final String name;
  final String cally;
  final String math;
  final String eng;

  Textbook({
    required this.key,
    required this.name,
    required this.cally,
    required this.math,
    required this.eng,
  });

  factory Textbook.fromJson(String key, Map<String, dynamic> j) => Textbook(
        key: key,
        name: j['name'] as String,
        cally: j['cally'] as String,
        math: j['math'] as String,
        eng: j['eng'] as String,
      );
}

/// 数学题型定义（教材配置）
class MathType {
  final String id;
  final String label;
  final String unit;

  MathType({required this.id, required this.label, required this.unit});

  factory MathType.fromJson(Map<String, dynamic> j) => MathType(
        id: j['id'] as String,
        label: j['label'] as String,
        unit: j['unit'] as String,
      );
}

/// 年级-册 数据（生字/词汇/数学题型）
class VolumeData {
  final List<List<String>>? cally;
  final List<MathType>? math;
  final List<List<String>>? eng;

  VolumeData({this.cally, this.math, this.eng});
}

/// 全局数据仓库
class AppData {
  static const String version = "1.70.0";

  late Map<String, Textbook> textbooks;
  late Map<int, String> gradeNames;
  late Map<String, List<int>> cnTypeGrades;
  late Map<String, String> engTypeLabels;
  late Map<String, List<int>> engTypeGrades;
  late Map<String, Map<String, List<int>>> versionSupport;

  /// CONTENT[version][grade][subject(cally/math/eng)][volume(上/下)]
  late Map<String, Map<int, Map<String, Map<String, VolumeData>>>> content;

  /// MATH_TYPE_DETAILS: id -> {desc, vertical, inline, cols, itemH}
  late Map<String, MathDetail> mathDetails;

  /// UNIT_CONV
  late List<UnitConv> unitConv;

  /// YUWEN_CORPUS: gushi/chengyu/mingju -> grade -> list
  late Map<int, List<GushiItem>> corpusGushi;
  late Map<int, List<ChengyuItem>> corpusChengyu;
  late Map<int, List<MingjuItem>> corpusMingju;

  /// MATH_INSTRUCTION
  late Map<String, String> mathInstruction;

  static final AppData _instance = AppData._();

  factory AppData() => _instance;

  AppData._();

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/data.json');
    final Map<String, dynamic> j = json.decode(raw) as Map<String, dynamic>;

    textbooks = {
      for (final e in (j['TEXTBOOKS'] as Map<String, dynamic>).entries)
        e.key: Textbook.fromJson(e.key, e.value as Map<String, dynamic>)
    };
    gradeNames = {
      for (final e in (j['GRADE_NAMES'] as Map<String, dynamic>).entries)
        int.parse(e.key): e.value as String
    };
    cnTypeGrades = _parseIntListMap(j['CN_TYPE_GRADES']);
    engTypeLabels = (j['ENG_TYPE_LABELS'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as String));
    engTypeGrades = _parseIntListMap(j['ENG_TYPE_GRADES']);
    versionSupport = _parseSupport(j['VERSION_SUPPORT']);

    content = {};
    final contentJson = j['CONTENT'] as Map<String, dynamic>;
    for (final verEntry in contentJson.entries) {
      content[verEntry.key] = {};
      final gJson = verEntry.value as Map<String, dynamic>;
      for (final gEntry in gJson.entries) {
        final grade = int.parse(gEntry.key);
        final subJson = gEntry.value as Map<String, dynamic>;
        content[verEntry.key]![grade] = {};
        for (final subEntry in subJson.entries) {
          final v = subEntry.value;
          if (v == null) {
            content[verEntry.key]![grade]![subEntry.key] = {};
            continue;
          }
          final vj = v as Map<String, dynamic>;
          final subject = subEntry.key;
          content[verEntry.key]![grade]![subEntry.key] = {
            for (final volEntry in vj.entries)
              volEntry.key: _parseVolume(subject, volEntry.value),
          };
        }
      }
    }

    mathDetails = {};
    final mdJson = j['MATH_TYPE_DETAILS'] as Map<String, dynamic>;
    for (final e in mdJson.entries) {
      mathDetails[e.key] = MathDetail.fromJson(e.key, e.value as Map<String, dynamic>);
    }

    unitConv = [
      for (final u in (j['UNIT_CONV'] as List<dynamic>))
        UnitConv.fromJson(u as Map<String, dynamic>)
    ];

    corpusGushi = {};
    corpusChengyu = {};
    corpusMingju = {};
    final corpus = j['YUWEN_CORPUS'] as Map<String, dynamic>;
    final gushi = corpus['gushi'] as Map<String, dynamic>;
    for (final g in gushi.entries) {
      corpusGushi[int.parse(g.key)] = [
        for (final it in (g.value as List<dynamic>))
          GushiItem(
            t: (it as Map<String, dynamic>)['t'] as String,
            a: it['a'] as String,
            full: it['full'] as String,
          )
      ];
    }
    final cy = corpus['chengyu'] as Map<String, dynamic>;
    for (final g in cy.entries) {
      corpusChengyu[int.parse(g.key)] = [
        for (final it in (g.value as List<dynamic>))
          ChengyuItem(
            w: (it as Map<String, dynamic>)['w'] as String,
            m: it['m'] as String,
          )
      ];
    }
    final mj = corpus['mingju'] as Map<String, dynamic>;
    for (final g in mj.entries) {
      corpusMingju[int.parse(g.key)] = [
        for (final it in (g.value as List<dynamic>))
          MingjuItem(
            t: (it as Map<String, dynamic>)['t'] as String,
            s: it['s'] as String,
          )
      ];
    }

    mathInstruction = {};
    final mi = j['MATH_INSTRUCTION'];
    if (mi != null) {
      mathInstruction = (mi as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String));
    }

    _loaded = true;
  }

  Map<String, List<int>> _parseIntListMap(dynamic j) {
    final out = <String, List<int>>{};
    if (j == null) return out;
    for (final e in (j as Map<String, dynamic>).entries) {
      out[e.key] = [
        for (final v in (e.value as List<dynamic>)) (v as num).toInt()
      ];
    }
    return out;
  }

  Map<String, Map<String, List<int>>> _parseSupport(dynamic j) {
    final out = <String, Map<String, List<int>>>{};
    for (final e in (j as Map<String, dynamic>).entries) {
      final sub = <String, List<int>>{};
      final subJson = e.value as Map<String, dynamic>;
      for (final se in subJson.entries) {
        final v = se.value;
        if (v != null) {
          sub[se.key] = [
            for (final x in (v as List<dynamic>)) (x as num).toInt()
          ];
        }
      }
      out[e.key] = sub;
    }
    return out;
  }

  List<List<String>>? _parsePairs(dynamic j) {
    if (j == null) return null;
    return [
      for (final p in (j as List<dynamic>))
        [(p as List<dynamic>)[0] as String, p[1] as String]
    ];
  }

  List<MathType>? _parseMathTypes(dynamic j) {
    if (j == null) return null;
    return [
      for (final t in (j as List<dynamic>))
        MathType.fromJson(t as Map<String, dynamic>)
    ];
  }

  VolumeData _parseVolume(String subject, dynamic v) {
    if (subject == 'math') {
      return VolumeData(math: _parseMathTypes(v));
    }
    return VolumeData(cally: subject == 'cally' ? _parsePairs(v) : null,
        eng: subject == 'eng' ? _parsePairs(v) : null);
  }

  /// 获取某版本某年级某册某科目的 VolumeData
  VolumeData? vol(String ver, int grade, String vol, String subject) {
    return content[ver]?[grade]?[subject]?[vol];
  }
}

class MathDetail {
  final String id;
  final String desc;
  final bool vertical;
  final bool inline;
  final int? cols;
  final int? itemH;

  MathDetail({
    required this.id,
    required this.desc,
    required this.vertical,
    required this.inline,
    this.cols,
    this.itemH,
  });

  factory MathDetail.fromJson(String id, Map<String, dynamic> j) => MathDetail(
        id: id,
        desc: j['desc'] as String,
        vertical: (j['vertical'] as bool?) ?? false,
        inline: (j['inline'] as bool?) ?? false,
        cols: (j['cols'] as num?)?.toInt(),
        itemH: (j['itemH'] as num?)?.toInt(),
      );
}

class UnitConv {
  final String from;
  final String to;
  final int mul;
  final List<int> grades;

  UnitConv({
    required this.from,
    required this.to,
    required this.mul,
    required this.grades,
  });

  factory UnitConv.fromJson(Map<String, dynamic> j) => UnitConv(
        from: j['from'] as String,
        to: j['to'] as String,
        mul: (j['mul'] as num).toInt(),
        grades: [
          for (final g in (j['grades'] as List<dynamic>)) (g as num).toInt()
        ],
      );
}

class GushiItem {
  final String t;
  final String a;
  final String full;

  GushiItem({required this.t, required this.a, required this.full});
}

class ChengyuItem {
  final String w;
  final String m;

  ChengyuItem({required this.w, required this.m});
}

class MingjuItem {
  final String t;
  final String s;

  MingjuItem({required this.t, required this.s});
}
