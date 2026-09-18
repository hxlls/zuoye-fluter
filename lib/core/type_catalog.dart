import 'chinese_worksheet.dart' show CHINESE_TYPES_LABELS;
import '../data/app_data.dart';

/// 科目维度：题型规则按科目分开。
enum Subject { math, chinese, english }

/// 一个题型在给定「版本 × 年级 × 册」下的规格。
class TypeSpec {
  /// 题型 id（与 assets/data.json 及渲染层保持一致）
  final String id;

  /// 显示名
  final String label;

  /// 单元或范围提示（数学用；语文/英语为空）
  final String? unit;

  /// 在当前「版本 × 年级 × 册」下是否可用
  final bool available;

  /// 首次使用时是否默认勾选
  final bool defaultOn;

  /// 首次使用时的默认题量
  final int defaultQty;

  const TypeSpec({
    required this.id,
    required this.label,
    this.unit,
    required this.available,
    required this.defaultOn,
    required this.defaultQty,
  });
}

/// 「哪些题型在给定 版本/年级/册 下可用」的唯一事实来源。
///
/// 这套规则此前散落在三个面板里（math_panel / chinese_panel / english_panel），
/// 而 english_worksheet 的渲染层又独立实现了一遍。任何一处改漏，就会出现
/// 「界面上能勾的题型」与「实际出的题」不一致。统一到此处后二者共用一份规则。
class TypeCatalog {
  TypeCatalog._();

  /// 英语题型顺序（与 english_panel 的 _typeIds 一致）
  static const List<String> engOrder = <String>[
    'alphabet', 'trace', 'match', 'cn2en', 'en2cn',
    'spell', 'listening', 'aiyuedu', 'ailistening',
  ];

  /// 语文题型顺序
  static const List<String> cnOrder = <String>[
    'pinyin2char', 'char2pinyin', 'zuci', 'gushiFill',
    'chengyuFill', 'chengyuGuess', 'mingjuFill', 'duanwen', 'aiyuedu',
  ];

  static const Map<String, int> _defaultQty = <String, int>{
    'math': 10,
    'chinese': 6,
    'english': 8,
  };

  static bool _inRange(List<int>? r, int grade) =>
      r == null || (grade >= r[0] && grade <= r[1]);

  /// 英语题型的版本规则。
  ///
  /// - `listening`：外研三起点三年级才学英语，仅 3-6 年级开放；其余版本 1-6 年级均可。
  /// - `ailistening`：需要一定听力理解能力，3-6 年级开放（该题型不在 ENG_TYPE_GRADES 里，
  ///   只由这条规则决定）。
  /// - `spell`：外研三起点 3-4 年级黑体词为「三会」（听、说、读），5-6 年级才要求
  ///   「四会」（听写拼写）；其余版本三年级起要求拼写。
  static bool engTypeAllowed(String id, String version, int grade) {
    if (id == 'listening') return !(version == 'waiyanSQ' && grade < 3);
    if (id == 'ailistening') return grade >= 3;
    if (id != 'spell') return true;
    if (version == 'waiyanSQ') return grade >= 5;
    return grade >= 3;
  }

  /// 英语默认勾选题型：一年级字母+描红，其余描红+连线。
  static List<String> defaultEngTypes(int grade) => grade == 1
      ? const <String>['alphabet', 'trace']
      : const <String>['trace', 'match'];

  /// 唯一入口：某科目在给定 版本/年级/册 下的题型清单。
  ///
  /// [includeUnavailable] 为 true 时，当前不可用的题型也会返回（`available == false`），
  /// 便于界面说明「为什么少了几个」，而不是让选项凭空消失。
  static List<TypeSpec> of(
    Subject subject, {
    required String version,
    required int grade,
    String volume = '',
    bool includeUnavailable = false,
  }) =>
      switch (subject) {
        Subject.math => _math(version, grade, volume),
        Subject.chinese => _chinese(grade, includeUnavailable),
        Subject.english => _english(version, grade, includeUnavailable),
      };

  /// 当前可用的题型 id 列表（顺序与 [of] 一致）
  static List<String> idsOf(
    Subject subject, {
    required String version,
    required int grade,
    String volume = '',
  }) =>
      of(subject, version: version, grade: grade, volume: volume)
          .map((t) => t.id)
          .toList();

  /// 数学：`CONTENT[版本][年级][册].math` 的列表本身就是该组合下的可用题型，
  /// 不需要再按年级过滤。
  static List<TypeSpec> _math(String version, int grade, String volume) {
    final list =
        AppData().vol(version, grade, volume, 'math')?.math ?? const [];
    return <TypeSpec>[
      for (final t in list)
        TypeSpec(
          id: t.id,
          label: t.label,
          unit: t.unit,
          available: true,
          defaultOn: true,
          defaultQty: _defaultQty['math']!,
        ),
    ];
  }

  /// 语文：按 `CN_TYPE_GRADES` 的年级区间过滤。
  static List<TypeSpec> _chinese(int grade, bool includeUnavailable) {
    final grades = AppData().cnTypeGrades;
    final out = <TypeSpec>[];
    for (final id in cnOrder) {
      final ok = _inRange(grades[id], grade);
      if (!ok && !includeUnavailable) continue;
      out.add(TypeSpec(
        id: id,
        label: CHINESE_TYPES_LABELS[id] ?? id,
        available: ok,
        defaultOn: true,
        defaultQty: _defaultQty['chinese']!,
      ));
    }
    return out;
  }

  /// 英语：`ENG_TYPE_GRADES` 的年级区间 **加上** [engTypeAllowed] 的版本规则。
  static List<TypeSpec> _english(
      String version, int grade, bool includeUnavailable) {
    final grades = AppData().engTypeGrades;
    final labels = AppData().engTypeLabels;
    final defaults = defaultEngTypes(grade);
    final out = <TypeSpec>[];
    for (final id in engOrder) {
      final ok = _inRange(grades[id], grade) && engTypeAllowed(id, version, grade);
      if (!ok && !includeUnavailable) continue;
      final on = ok && defaults.contains(id);
      out.add(TypeSpec(
        id: id,
        // 一年级把「单词抄写」显示为「单词描红」——一年级以描红为主，不要求独立书写
        label: (grade == 1 && id == 'trace') ? '单词描红' : (labels[id] ?? id),
        available: ok,
        defaultOn: on,
        defaultQty: on ? _defaultQty['english']! : 0,
      ));
    }
    return out;
  }
}

/// 依据目录补齐缺失的题量：**只对从未设置过的题型**填默认值，
/// 已存在的值（包括 0 = 用户主动取消）一律尊重。
///
/// 旧实现用 `count < 1` 判断「没设置过」，会把用户主动取消勾选的题型重新填回默认题量，
/// 这里修正为 `containsKey` 判断。
Map<String, int> seedTypeCounts(List<TypeSpec> specs, Map<String, int> stored) {
  for (final s in specs) {
    if (!s.available) continue;
    if (!stored.containsKey(s.id)) {
      stored[s.id] = s.defaultOn ? s.defaultQty : 0;
    }
  }
  return stored;
}
