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
  // 进入方式：bundled(内置) / imported-json / photo / ai
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
