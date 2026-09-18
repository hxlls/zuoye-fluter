import 'package:shared_preferences/shared_preferences.dart';

/// 「工作上下文」持久化：教材版本 / 学期 / 年级。
///
/// 这三个是全局选一次、各科目共用的设置。此前只在内存里，
/// 于是**每次重开 App 都回到「人教版 · 上册 · 1 年级」**，
/// 用户每周都要重选一遍——比面板级的丢失更烦人。
class WorkContextStore {
  WorkContextStore._();

  static const String _versionKey = 'ctx_version';
  static const String _volumeKey = 'ctx_volume';
  static const String _gradeKey = 'ctx_grade';

  /// 读取上次的上下文；从未保存过返回 null
  static Future<({String version, String volume, int grade})?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_versionKey);
      final vol = prefs.getString(_volumeKey);
      final g = prefs.getInt(_gradeKey);
      if (v == null || vol == null || g == null) return null;
      return (version: v, volume: vol, grade: g);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save({
    required String version,
    required String volume,
    required int grade,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_versionKey, version);
      await prefs.setString(_volumeKey, volume);
      await prefs.setInt(_gradeKey, grade);
    } catch (_) {
      // 保存失败不影响本次使用
    }
  }
}
