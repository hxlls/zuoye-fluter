import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/type_catalog.dart';

/// 题量偏好的全局记忆：按「科目 + 题型 id」存一份，跨版本/年级/册共用。
///
/// 为什么不做成按「版本/年级/册」各存一份（英语旧实现的做法）：
/// 用户的心智是「我习惯每次出 10 道口算」，这是跨年级的偏好，不是某个年级的属性。
/// 题型本身已由 [TypeCatalog] 按年级裁剪，所以按题型记忆不会串味。
/// 好处是换年级不必重调一遍，切回来也不会丢。
class TypeCountStore {
  TypeCountStore._();

  static String _key(Subject s) => 'type_counts_${s.name}';

  /// 读取某科目的题量偏好。
  ///
  /// 返回的 Map **只包含用户显式设置过的题型**——调用方据此用 `containsKey`
  /// 区分「从未设置」与「设为 0（主动取消）」，这是修掉「取消勾选被复活」的关键。
  static Future<Map<String, int>> load(Subject subject) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(subject));
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

  static Future<void> save(Subject subject, Map<String, int> counts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(subject), json.encode(counts));
    } catch (_) {
      // 保存失败不影响本次使用
    }
  }

  /// 一次完成「读取 -> 按当前目录补齐缺失项」。
  static Future<Map<String, int>> loadSeeded(
    Subject subject,
    List<TypeSpec> specs,
  ) async {
    final stored = await load(subject);
    seedTypeCounts(specs, stored);
    return stored;
  }
}
