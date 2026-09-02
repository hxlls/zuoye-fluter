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
  static const String version = "3.0.4";

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

  /// YUWEN_BOOKS: 整本书阅读推荐书目（按学段 low/mid/high）
  late Map<String, List<BookItem>> corpusBooks;

  /// ENG_505: 2022 课标小学英语词汇表（二级·约505词），按单词列表存储
  late List<String> eng505;

  /// GUSHI_RECITATION: 2022 课标「背诵优秀诗文」推荐篇目（1-6年级·75篇）
  late List<RecItem> recitation;

  /// MATH_INSTRUCTION
  late Map<String, String> mathInstruction;

  /// MATH_PROJECTS：2022 课标「综合与实践」项目式学习原生题库（按学段 low/mid/high）
  late List<ProjItem> mathProjects;

  /// MATH_CULTURE：2022 课标「数学文化」原生题库（故事·历史·思想，按学段 low/mid/high）
  late List<CultureItem> mathCulture;

  /// YUWEN_PRACTICAL：2022 课标「实用性阅读与交流」应用文格式与例文原生库
  late List<PracticalItem> practical;

  /// YUWEN_TEXTS：统编版语文课文库（篇目·单元·正文），供「基于课文」阅读理解生成使用
  late List<YuwenText> yuwenTexts;

  /// 取某年级/册下、且有正文的统编版课文（供阅读理解基于课文生成）
  List<YuwenText> yuwenTextsFor(int grade, String volume) =>
      yuwenTexts.where((t) => t.grade == grade && t.volume == volume && t.text.trim().isNotEmpty).toList();

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

    corpusBooks = {};
    final books = j['YUWEN_BOOKS'] as Map<String, dynamic>?;
    if (books != null) {
      for (final seg in books.entries) {
        corpusBooks[seg.key] = [
          for (final it in (seg.value as List<dynamic>))
            BookItem(
              t: (it as Map<String, dynamic>)['t'] as String,
              a: (it as Map<String, dynamic>)['a'] as String? ?? '',
            )
        ];
      }
    }

    mathInstruction = {};
    final mi = j['MATH_INSTRUCTION'];
    if (mi != null) {
      mathInstruction = (mi as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String));
    }

    // ENG_505：2022 课标小学英语词汇表（二级）
    eng505 = [];
    final e505 = j['ENG_505'];
    if (e505 is List) {
      for (final it in e505) {
        if (it is Map && it['w'] is String) {
          eng505.add(it['w'] as String);
        } else if (it is String) {
          eng505.add(it);
        }
      }
    }

    // MATH_PROJECTS：2022 课标综合与实践项目式学习题库
    mathProjects = [];
    final mp = j['MATH_PROJECTS'];
    if (mp is List) {
      for (final it in mp) {
        if (it is Map) {
          mathProjects.add(ProjItem(
            t: '${it['t'] ?? ''}',
            d: '${it['d'] ?? ''}',
            seg: '${it['seg'] ?? 'low'}',
          ));
        }
      }
    }

    // MATH_CULTURE：2022 课标数学文化题库
    mathCulture = [];
    final mc = j['MATH_CULTURE'];
    if (mc is List) {
      for (final it in mc) {
        if (it is Map) {
          mathCulture.add(CultureItem(
            t: '${it['t'] ?? ''}',
            c: '${it['c'] ?? ''}',
            q: '${it['q'] ?? ''}',
            a: '${it['a'] ?? ''}',
            seg: '${it['seg'] ?? 'low'}',
          ));
        }
      }
    }

    // YUWEN_PRACTICAL：2022 课标实用性阅读与交流·应用文格式与例文
    practical = [];
    final yp = j['YUWEN_PRACTICAL'];
    if (yp is List) {
      for (final it in yp) {
        if (it is Map) {
          practical.add(PracticalItem(
            type: '${it['type'] ?? ''}',
            title: '${it['title'] ?? ''}',
            format: '${it['format'] ?? ''}',
            example: '${it['example'] ?? ''}',
            tip: '${it['tip'] ?? ''}',
          ));
        }
      }
    }

    // YUWEN_TEXTS：统编版语文课文库（篇目·单元·正文）
    yuwenTexts = [];
    final yt = j['YUWEN_TEXTS'];
    if (yt is Map) {
      for (final gEntry in (yt as Map).entries) {
        final grade = int.tryParse('${gEntry.key}') ?? 0;
        final vols = gEntry.value;
        if (vols is Map) {
          for (final vEntry in vols.entries) {
            final volume = '${vEntry.key}';
            final arr = vEntry.value;
            if (arr is List) {
              for (final it in arr) {
                if (it is Map) {
                  yuwenTexts.add(YuwenText(
                    grade: grade,
                    volume: volume,
                    unit: '${it['unit'] ?? ''}',
                    title: '${it['title'] ?? ''}',
                    text: '${it['text'] ?? ''}',
                  ));
                }
              }
            }
          }
        }
      }
    }

    // GUSHI_RECITATION：2022 课标背诵优秀诗文推荐篇目（按学段 low/mid/high 分段）
    recitation = [];
    final gr = j['GUSHI_RECITATION'];
    if (gr is List) {
      for (final it in gr) {
        if (it is Map) {
          recitation.add(RecItem(
            t: '${it['t'] ?? ''}',
            a: '${it['a'] ?? ''}',
            seg: '${it['seg'] ?? 'low'}',
          ));
        }
      }
    }

    _loaded = true;
  }

  /// 该年级英语词汇（2022 课标对齐）：三年级起使用 ENG_505 二级词汇表，
  /// 一、二年级沿用各册配套词汇。返回单词列表。
  List<String> eng505Words(int grade) {
    if (grade >= 3) return eng505;
    final list = vol('renjiao', grade, '上', 'eng')?.eng ??
        vol('renjiao', grade, '下', 'eng')?.eng ??
        [];
    return list.map((w) => w[0]).toList();
  }

  /// 2022 背诵篇目标题集合（用于古诗填空优先选用官方篇目）
  Set<String> recitationTitleSet() =>
      recitation.map((r) => r.t).toSet();

  /// 按学段取背诵篇目（low=1-2年级 / mid=3-4年级 / high=5-6年级）
  List<RecItem> recitationBySeg(String seg) =>
      recitation.where((r) => r.seg == seg).toList();

  /// 按学段取综合与实践项目（low=1-2 / mid=3-4 / high=5-6）
  List<ProjItem> mathProjectsBySeg(String seg) =>
      mathProjects.where((p) => p.seg == seg).toList();

  /// 按学段取数学文化条目（low=1-2年级 / mid=3-4年级 / high=5-6年级）
  List<CultureItem> mathCultureBySeg(String seg) =>
      mathCulture.where((p) => p.seg == seg).toList();

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

  /// 整本书阅读推荐书目（按年级归入学段：低段1-2 / 中段3-4 / 高段5-6）
  List<BookItem> bookList(int grade) {
    final seg = grade <= 2 ? 'low' : grade <= 4 ? 'mid' : 'high';
    return corpusBooks[seg] ?? [];
  }
}

class BookItem {
  final String t;
  final String a;
  BookItem({required this.t, this.a = ''});
}

class RecItem {
  final String t;
  final String a;
  final String seg;
  RecItem({required this.t, required this.a, this.seg = 'low'});
}

class ProjItem {
  final String t;
  final String d;
  final String seg;
  ProjItem({required this.t, required this.d, this.seg = 'low'});
}

class CultureItem {
  final String t;
  final String c;
  final String q;
  final String a;
  final String seg;
  CultureItem(
      {required this.t, required this.c, required this.q, required this.a, this.seg = 'low'});
}

class PracticalItem {
  final String type;
  final String title;
  final String format;
  final String example;
  final String tip;
  PracticalItem(
      {required this.type,
      required this.title,
      required this.format,
      required this.example,
      required this.tip});
}

class YuwenText {
  final int grade;
  final String volume;
  final String unit;
  final String title;
  final String text;
  YuwenText(
      {required this.grade,
      required this.volume,
      required this.unit,
      required this.title,
      required this.text});
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
