import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 多语料存储键
const String _corporaKey = 'customCorpora'; // List<Corpus>
const String _activeCorpusKey = 'activeCorpusId';
const String _captureTargetKey = 'captureTargetId';
const String _legacyCorpusKey = 'customCorpus'; // 旧单槽，首次启动时迁移

/// 语料库：一个具名、带版本、带来源的集合
class Corpus {
  final String id;
  String name;
  String version; // 教材版本 key：tongbiao/hebei/renjiao/waiyanYQ/waiyanSQ/''（未知）
  int? grade;
  String? volume;
  // 语料级来源声明：'' 未声明(版权自负) / 'original' AI原创·非版权 / 'licensed' 用户声明授权
  String source;
  // 进入方式：bundled(内置) / imported-json / imported-pdf / photo / ai
  String origin;
  List<Map<String, dynamic>> items;

  Corpus({
    String? id,
    required this.name,
    this.version = '',
    this.grade,
    this.volume,
    this.source = '',
    this.origin = 'imported-json',
    List<Map<String, dynamic>>? items,
  })  : id = id ?? newCorpusId(),
        items = items ?? [];

  static Corpus fromJson(Map<String, dynamic> j) {
    final rawItems = j['items'];
    final items = <Map<String, dynamic>>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          final m = <String, dynamic>{};
          (e as Map).forEach((k, v) => m['$k'] = v);
          items.add(m);
        }
      }
    }
    return Corpus(
      id: '${j['id'] ?? newCorpusId()}',
      name: '${j['name'] ?? '我的课文库'}',
      version: '${j['version'] ?? ''}',
      grade: j['grade'] is num ? (j['grade'] as num).toInt() : null,
      volume: j['volume'] is String ? j['volume'] as String : null,
      source: _normSource('${j['source'] ?? ''}'),
      origin: '${j['origin'] ?? 'imported-json'}',
      items: items,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'grade': grade,
        'volume': volume,
        'source': source,
        'origin': origin,
        'items': items,
      };
}

String _normSource(String s) {
  if (s == 'original' || s == 'licensed') return s;
  if (s.contains('原创') || s.contains('非版权') || s.contains('原创生成')) {
    return 'original';
  }
  return '';
}

/// 文件名里的来源暗示（老格式没写 `source` 时靠它兜底）。
String _sourceFromName(String name) {
  if (name.contains('原创') || name.contains('非版权') || name.contains('原创生成')) {
    return 'original';
  }
  return '';
}

// ---------------------------------------------------------------------------
// 语料条目合并（「导入 PDF / 导入 JSON / 拍照」三条路共用）
// ---------------------------------------------------------------------------

/// 语料条目的**身份键**：同一本书分次导入时靠它去重。
///
/// 带上 `version/grade/volume` —— 不同册会有同名课文（各册都有「语文园地」之类）。
String corpusItemKey(Map<String, dynamic> m) {
  final ver = '${m['version'] ?? ''}'.trim();
  final g = m['grade'];
  final v = '${m['volume'] ?? ''}'.trim();
  final u = '${m['unit'] ?? ''}'.trim();
  final t = '${m['title'] ?? ''}'.trim().toLowerCase();
  return '$ver#$g#$v#$u#$t';
}

/// 合并两组题目：按题干去重，保留先出现的。
List<dynamic> mergeQuestions(dynamic existing, dynamic incoming) {
  final out = <dynamic>[];
  final seen = <String>{};
  void addQ(dynamic q) {
    if (q is! Map) return;
    final qq = '${q['q'] ?? ''}'.trim();
    if (qq.isEmpty) return;
    if (seen.contains(qq)) return;
    seen.add(qq);
    out.add(q);
  }

  if (existing is List) {
    for (final q in existing) {
      addQ(q);
    }
  }
  if (incoming is List) {
    for (final q in incoming) {
      addQ(q);
    }
  }
  return out;
}

/// 合并两组语料条目，返回 `(合并后条目, 新增数, 更新数)`。
///
/// 按 [corpusItemKey] 去重；命中则取更长的正文、补齐缺失的单元/作者/册次/来源、
/// 并合并题目（[mergeQuestions]）。
///
/// `corpusVersion` / `corpusGrade` / `corpusVolume` 是给**缺标签的条目盖章的缺省值**：
/// 同一本书两次导入若一次带标签一次不带，算出的键会不同，于是凭空多出一份重复课文。
///
/// 放在数据层是为了让三条导入路径共用同一份逻辑，也便于单测
/// （见 `test/corpus_exchange_test.dart`）。
(List<Map<String, dynamic>>, int, int) mergeCorpusItems(
  List<Map<String, dynamic>> existing,
  List<Map<String, dynamic>> incoming, {
  String fileSource = '',
  String corpusVersion = '',
  int? corpusGrade,
  String? corpusVolume,
}) {
  final map = <String, Map<String, dynamic>>{};
  for (final e in existing) {
    final m = <String, dynamic>{};
    e.forEach((k, v) => m[k] = v);
    map[corpusItemKey(m)] = m;
  }
  var added = 0, updated = 0;
  for (final inc in incoming) {
    final m = <String, dynamic>{};
    inc.forEach((k, v) => m[k] = v);
    if (corpusVersion.isNotEmpty && '${m['version'] ?? ''}'.isEmpty) {
      m['version'] = corpusVersion;
    }
    if (corpusGrade != null && m['grade'] == null) m['grade'] = corpusGrade;
    if (corpusVolume != null && '${m['volume'] ?? ''}'.isEmpty) {
      m['volume'] = corpusVolume;
    }
    final k = corpusItemKey(m);
    if (map.containsKey(k)) {
      final ex = map[k]!;
      final et = '${ex['text'] ?? ''}', it = '${m['text'] ?? ''}';
      if (it.length > et.length) ex['text'] = it;
      if ('${ex['unit'] ?? ''}'.isEmpty) ex['unit'] = m['unit'];
      if ('${ex['author'] ?? ''}'.isEmpty) ex['author'] = m['author'];
      ex['grade'] = ex['grade'] ?? m['grade'];
      if ('${ex['volume'] ?? ''}'.isEmpty) ex['volume'] = m['volume'];
      final es = '${ex['source'] ?? ''}', ins = '${m['source'] ?? ''}';
      ex['source'] = es.isNotEmpty ? es : ins;
      ex['questions'] = mergeQuestions(ex['questions'], m['questions']);
      updated++;
    } else {
      if ('${m['source'] ?? ''}'.isEmpty) m['source'] = fileSource;
      map[k] = m;
      added++;
    }
  }
  return (map.values.toList(), added, updated);
}

/// 语料库来源的中文标签（列表与提示里用）。
String corpusSourceTag(String s) {
  if (s == 'original') return '原创·非版权';
  if (s == 'licensed') return '版权自负·已确认授权';
  if (s == 'builtin') return '内置课文';
  return '版权自负';
}

/// 语料库进入方式的中文标签。
String corpusOriginTag(String o) {
  switch (o) {
    case 'bundled':
      return '内置';
    case 'imported-pdf':
      return '教材 PDF';
    case 'imported-json':
      return '语料文件';
    case 'photo':
      return '拍照识别';
    case 'ai':
      return 'AI 生成';
    default:
      return '未知';
  }
}


/// 交换文件的格式版本键。
const String kCorpusSchemaKey = 'schemaVersion';

/// 当前交换文件的格式版本。
const int kCorpusSchemaVersion = 1;

/// 解析后的语料文件内容。
class CorpusFileData {
  final String name;

  /// 教材版本 key（tongbiao/hebei/…）；手写文件可能为空
  final String version;
  final int? grade;
  final String? volume;

  /// 已归一化的来源：'' / 'original' / 'licensed'
  final String source;

  final List<Map<String, dynamic>> items;

  /// 文件里写的格式版本；**手写/老文件是 0**（没有这个键）
  final int schemaVersion;

  const CorpusFileData({
    required this.name,
    required this.version,
    required this.grade,
    required this.volume,
    required this.source,
    required this.items,
    required this.schemaVersion,
  });
}

/// 语料交换格式：`Corpus` ⇄ 可写文件的 JSON 对象。
///
/// 编解码都放在这一层（而不是 UI 里），是为了能单测 —— 导出与导入必须**严格对称**，
/// 任何一边加字段都要在 `test/corpus_exchange_test.dart` 里先对上。
///
/// 写入比读取多：文件里还会带 `id` / `origin` / `exportedAt` 供人看与将来迁移，
/// 但导入只消费它需要的字段（不认 `origin`，因为「成为用户语料」是导入方的决定）。
abstract final class CorpusFile {
  static const String schemaKey = kCorpusSchemaKey;
  static const int schemaVersion = kCorpusSchemaVersion;

  /// 把一个语料库编成可落盘的对象。
  ///
  /// **自包含**：库元数据 + 全部条目（含已补的题目）都在里面，
  /// 所以换台设备选这个文件就能回到同样的状态，不必先手动建库。
  ///
  /// 条目是**深拷一层**的：导出即快照，之后改原库不会影响已经编好的对象
  /// （`test/corpus_exchange_test.dart` 锁住这一点）。
  static Map<String, dynamic> encode(Corpus c) => {
        schemaKey: schemaVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'id': c.id,
        'name': c.name,
        'version': c.version,
        'grade': c.grade,
        'volume': c.volume,
        'source': c.source,
        'origin': c.origin,
        'items': [
          for (final it in c.items) Map<String, dynamic>.of(it),
        ],
      };

  /// 解析一个语料文件对象。
  ///
  /// 返回 null 表示**格式不对**（不是对象，或缺 `items` 数组）——
  /// 调用方据此提示「格式不正确」。`items` 为空数组是合法解析，由调用方判断。
  ///
  /// 入参只要是个 `Map` 就收（`json.decode` 给的是 `Map<String, dynamic>`，
  /// 但手写/别处构造的可能是 `Map<String, List>` 之类），先归一化成
  /// `Map<String, dynamic>` 再走存储层那套解析 —— 保证「存进去」与
  /// 「导回来」永远是同一套语义。
  static CorpusFileData? decode(Object? decoded) {
    if (decoded is! Map) return null;
    final m = <String, dynamic>{};
    decoded.forEach((k, v) => m['$k'] = v);
    if (m['items'] is! List) return null;
    final c = Corpus.fromJson(m);
    var source = c.source;
    // 老格式（或手写文件）没写 source 时，沿用文件名里的暗示
    if (source.isEmpty) source = _sourceFromName(c.name);
    return CorpusFileData(
      name: c.name,
      version: c.version,
      grade: c.grade,
      volume: c.volume,
      source: source,
      items: c.items,
      schemaVersion:
          m[schemaKey] is num ? (m[schemaKey] as num).toInt() : 0,
    );
  }
}

String newCorpusId() =>
    'c_${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().microsecondsSinceEpoch % 1000)}';

/// 语料持久化层（SharedPreferences，无数据库依赖）
class CorpusStore {
  static Future<List<Corpus>> loadCorpora() async {
    final prefs = await SharedPreferences.getInstance();
    // 迁移旧单槽 customCorpus → 单个 Corpus
    final legacy = prefs.getString(_legacyCorpusKey);
    if (legacy != null) {
      try {
        final obj = json.decode(legacy) as Map<String, dynamic>;
        final items = obj['items'];
        if (items is List && items.isNotEmpty) {
          final c = Corpus(
            name: obj['name'] is String && (obj['name'] as String).isNotEmpty
                ? obj['name'] as String
                : '我的课文库',
            version: '',
            grade: null,
            volume: null,
            source: _normSource('${obj['source'] ?? ''}'),
            origin: 'imported-json',
            items: [
              for (final e in items)
                if (e is Map)
                  () {
                    final m = <String, dynamic>{};
                    (e as Map).forEach((k, v) => m['$k'] = v);
                    return m;
                  }()
            ],
          );
          await prefs.remove(_legacyCorpusKey);
          await saveCorpora([c]);
          return [c];
        }
      } catch (_) {
        // 解析失败则丢弃旧槽
      }
      await prefs.remove(_legacyCorpusKey);
    }
    final raw = prefs.getString(_corporaKey);
    if (raw == null) return [];
    try {
      final list = json.decode(raw) as List;
      return [
        for (final e in list)
          if (e is Map) Corpus.fromJson(e as Map<String, dynamic>)
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveCorpora(List<Corpus> corpora) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _corporaKey, json.encode([for (final c in corpora) c.toJson()]));
  }

  static Future<String?> loadActiveId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeCorpusKey);
  }

  static Future<void> saveActiveId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_activeCorpusKey);
    } else {
      await prefs.setString(_activeCorpusKey, id);
    }
  }

  static Future<String?> loadCaptureId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_captureTargetKey);
  }

  static Future<void> saveCaptureId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_captureTargetKey);
    } else {
      await prefs.setString(_captureTargetKey, id);
    }
  }
}
