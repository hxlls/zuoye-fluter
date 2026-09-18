import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 科目面板的「选项」持久化（难度、附答案、显示标题栏、练字帖参数…）。
///
/// 为什么需要：科目面板是从主页 push 出来的全屏页，返回时会被销毁。
/// 此前只有题量持久化（见 TypeCountStore），这些选项每次重进都回到默认值。
///
/// 与题量的取舍**不同**：这些选项按面板全局记一份，不按 版本/年级/册 分档——
/// 它们是「我习惯怎么排版」，跨年级不变；而题量是跟题型绑定的偏好。
class PanelPrefStore {
  PanelPrefStore._();

  static String _key(String panel) => 'panel_opts_$panel';

  static Future<Map<String, dynamic>> load(String panel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(panel));
      if (raw == null) return <String, dynamic>{};
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> save(String panel, Map<String, dynamic> opts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(panel), json.encode(opts));
    } catch (_) {
      // 保存失败不影响本次使用
    }
  }
}
