import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 出题面板的偏好持久化。
///
/// 为什么必须有：`home_page` 的 tab 容器是 `switch`（不是 `IndexedStack`），
/// 离开 AI 标签会**销毁** `AiPanel`，回来时 `initState` 重跑。
/// 状态只放内存的话，用户切走一次（例如去设置里改年级）就全丢了，表现就是：
/// - 「取消的勾选又自己勾上」——因为重新播种时全部置为勾选
/// - 「科目变回数学」——`_subject` 回到默认值，用户看的其实已不是他选的科目
///
/// 存储布局：
/// - `ai_subject`            上次选的科目（跨会话记住）
/// - `ai_styles_<subject>`   题量偏好，按「科目 + 题型 id」全局记忆
///   （与 TypeCountStore 的取舍一致：用户的偏好是跨年级的，
///   题型本身已按年级裁剪，所以按题型记忆不会串味）
/// - `ai_opts`               难度 / 主题语境 / 语篇类型 / 是否附答案
class AiPrefStore {
  AiPrefStore._();

  static const String _subjectKey = 'ai_subject';
  static const String _stylesPrefix = 'ai_styles_';
  static const String _optsKey = 'ai_opts';

  static String _stylesKey(String subject) => '$_stylesPrefix$subject';

  /// 上次选择的科目；从未选过返回 null
  static Future<String?> loadSubject() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_subjectKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSubject(String subject) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_subjectKey, subject);
    } catch (_) {
      // 保存失败不影响本次使用
    }
  }

  /// 读取某科目的题量偏好。
  /// 只返回用户**显式设置过**的题型，调用方据此用 containsKey 区分
  /// 「从未设置」与「设为 0（主动取消）」。
  static Future<Map<String, int>> loadStyles(String subject) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_stylesKey(subject));
      if (raw == null) return <String, int>{};
      final m = json.decode(raw) as Map<String, dynamic>;
      return <String, int>{
        for (final e in m.entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      };
    } catch (_) {
      return <String, int>{};
    }
  }

  static Future<void> saveStyles(
      String subject, Map<String, int> styles) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stylesKey(subject), json.encode(styles));
    } catch (_) {
      // 保存失败不影响本次使用
    }
  }

  static Future<Map<String, dynamic>> loadOpts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_optsKey);
      if (raw == null) return <String, dynamic>{};
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> saveOpts(Map<String, dynamic> opts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_optsKey, json.encode(opts));
    } catch (_) {
      // 保存失败不影响本次使用
    }
  }

  // ---------- AI 帮答 ----------
  //
  // 同样因为 tab 是 switch 而非 IndexedStack：离开 AI 标签会销毁 AiHelpPanel。
  // 不持久化的话，用户问完一题、切去看看别处再回来，**整个对话就没了**。

  static const String _helpSubjectKey = 'ai_help_subject';
  static const String _helpMsgsKey = 'ai_help_messages';

  static Future<String?> loadHelpSubject() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_helpSubjectKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveHelpSubject(String subject) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_helpSubjectKey, subject);
    } catch (_) {
      // 保存失败不影响本次使用
    }
  }

  /// 读取上次的对话（(role, content) 列表）。无记录返回空列表。
  static Future<List<(String, String)>> loadHelpMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_helpMsgsKey);
      if (raw == null) return <(String, String)>[];
      final list = json.decode(raw) as List<dynamic>;
      return [
        for (final e in list)
          if (e is List && e.length >= 2) ('${e[0]}', '${e[1]}'),
      ];
    } catch (_) {
      return <(String, String)>[];
    }
  }

  static Future<void> saveHelpMessages(
      List<(String, String)> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _helpMsgsKey,
        json.encode([
          for (final m in messages) [m.$1, m.$2],
        ]),
      );
    } catch (_) {
      // 保存失败不影响本次使用
    }
  }
}
