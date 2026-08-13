import 'package:flutter/material.dart';
import '../data/app_data.dart';
import 'calligraphy_panel.dart';
import 'chinese_panel.dart';
import 'math_panel.dart';
import 'english_panel.dart';
import 'ai_panel.dart';
import 'ai_help_panel.dart';
import 'ai_config_card.dart';
import 'about_panel.dart';

/// 主页面：教材版本/学期/年级选择 + 标签页 + 配置面板 + 预览
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _version = 'renjiao';
  String _volume = '上';
  int _grade = 1;
  String _tab = 'calligraphy';

  bool _dataReady = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AppData().load();
    if (mounted) setState(() => _dataReady = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_dataReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      body: Column(
        children: [
          _topBar(),
          _versionBar(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: AiConfigCard(),
          ),
          _tabs(),
          Expanded(
            child: _panel(),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: const Color(0xff2f6fd0),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '📖 小学作业生成器  v${AppData.version}',
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text('一键生成 · 可打印 · 支持导出 PDF',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _versionBar() {
    final versions = [
      ('renjiao', '人教版'),
      ('hebei', '冀教版'),
      ('waiyanYQ', '外研·一起点'),
      ('waiyanSQ', '外研·三起点'),
    ];
    final volumes = [('上', '上册'), ('下', '下册')];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xfff6f3ec),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('教材版本', style: TextStyle(fontSize: 13)),
          for (final (k, l) in versions)
            _chip(l, k == _version, () {
              setState(() {
                _version = k;
                _normalizeGrade();
              });
            }),
          const Text('学期', style: TextStyle(fontSize: 13)),
          for (final (k, l) in volumes)
            _chip(l, k == _volume, () {
              setState(() => _volume = k);
            }),
          const Text('选择年级', style: TextStyle(fontSize: 13)),
          for (var g = 1; g <= 6; g++)
            _chip('$g年级', g == _grade, () {
              setState(() => _grade = g);
            }),
        ],
      ),
    );
  }

  void _normalizeGrade() {
    final data = AppData();
    final support = data.versionSupport[_version] ?? data.versionSupport['renjiao']!;
    final allowed = <int>{};
    for (final key in ['cally', 'math', 'eng']) {
      final r = support[key];
      if (r != null) {
        for (var g = r[0]; g <= r[1]; g++) allowed.add(g);
      }
    }
    if (allowed.isNotEmpty && !allowed.contains(_grade)) {
      _grade = allowed.reduce((a, b) => a < b ? a : b);
    }
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xff2f6fd0) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active ? const Color(0xff2f6fd0) : const Color(0xffcccccc)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                color: active ? Colors.white : const Color(0xff444444))),
      ),
    );
  }

  Widget _tabs() {
    final tabs = [
      ('calligraphy', '✍️ 练字帖'),
      ('chinese', '📖 语文作业'),
      ('math', '🔢 数学作业'),
      ('english', '🇬🇧 英语作业'),
      ('ai', '🤖 AI 出题'),
      ('aihelp', '💡 AI 帮答题'),
      ('about', 'ℹ️ 关于'),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (k, l) in tabs)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () => setState(() => _tab = k),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _tab == k
                          ? const Color(0xff2f6fd0)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(l,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _tab == k
                                ? Colors.white
                                : const Color(0xff444444))),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _panel() {
    switch (_tab) {
      case 'calligraphy':
        return CalligraphyPanel(grade: _grade, version: _version, volume: _volume);
      case 'chinese':
        return ChinesePanel(grade: _grade, version: _version, volume: _volume);
      case 'math':
        return MathPanel(grade: _grade, version: _version, volume: _volume);
      case 'english':
        return EnglishPanel(grade: _grade, version: _version, volume: _volume);
      case 'ai':
        return AiPanel(grade: _grade, version: _version, volume: _volume);
      case 'aihelp':
        return AiHelpPanel(grade: _grade, version: _version, volume: _volume);
      case 'about':
        return const AboutPanel();
      default:
        return const SizedBox();
    }
  }
}
