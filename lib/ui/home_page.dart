import 'package:flutter/material.dart';
import '../data/app_data.dart';
import 'calligraphy_panel.dart';
import 'chinese_panel.dart';
import 'math_panel.dart';
import 'english_panel.dart';
import 'ai_panel.dart';
import 'ai_help_panel.dart';
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
    final wide = MediaQuery.of(context).size.width >= 760;
    if (wide) {
      return Scaffold(
        body: Column(
          children: [
            _topBar(),
            _versionBar(),
            _tabs(),
            Expanded(
              child: _panel(),
            ),
          ],
        ),
      );
    }
    // 手机：底部导航栏 + 精简顶栏
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff2f6fd0),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📖 小学作业生成器 v${AppData.version}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Text('一键生成 · 可打印 · 支持导出 PDF',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
      body: Column(
        children: [
          _versionBarMobile(),
          Expanded(child: _panel()),
        ],
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  Widget _bottomNav() {
    final items = [
      ('calligraphy', Icons.edit, '练字帖'),
      if (_supportedSubjects().contains('cally')) ('chinese', Icons.menu_book, '语文'),
      if (_supportedSubjects().contains('math')) ('math', Icons.calculate, '数学'),
      if (_supportedSubjects().contains('eng')) ('english', Icons.language, '英语'),
      ('ai', Icons.auto_awesome, 'AI'),
      ('aihelp', Icons.chat, '帮答'),
      ('about', Icons.info_outline, '关于'),
    ];
    final idx = items.indexWhere((e) => e.$1 == _tab);
    return BottomNavigationBar(
      currentIndex: idx < 0 ? 0 : idx,
      onTap: (i) => setState(() => _tab = items[i].$1),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: const Color(0xff2f6fd0),
      unselectedItemColor: const Color(0xff999999),
      items: [
        for (final (_, icon, label) in items)
          BottomNavigationBarItem(icon: Icon(icon), label: label),
      ],
    );
  }

  Widget _versionBarMobile() {
    final versions = [
      ('renjiao', '人教版'),
      ('hebei', '冀教版'),
      ('waiyanYQ', '外研·一起点'),
      ('waiyanSQ', '外研·三起点'),
    ];
    final volumes = [('上', '上册'), ('下', '下册')];
    final grades = _allowedGrades();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xfff6f3ec),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _dropdownGroup(
              label: '教材',
              value: _version,
              items: versions,
              onChanged: (k) {
                setState(() {
                  _version = k;
                  _normalizeGrade();
                  _normalizeTab();
                });
              },
            ),
            const SizedBox(width: 10),
            _dropdownGroup(
              label: '册',
              value: _volume,
              items: volumes,
              onChanged: (k) => setState(() => _volume = k),
            ),
            const SizedBox(width: 10),
            _dropdownGroup(
              label: '年级',
              value: '$_grade',
              items: [for (final g in grades) ('$g', '${g}年级')],
              onChanged: (k) => setState(() => _grade = int.parse(k)),
            ),
          ],
        ),
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
    final grades = _allowedGrades();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xfff6f3ec),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _dropdownGroup(
            label: '教材版本',
            value: _version,
            items: versions,
            onChanged: (k) {
              setState(() {
                _version = k;
                _normalizeGrade();
                _normalizeTab();
              });
            },
          ),
          _dropdownGroup(
            label: '学期',
            value: _volume,
            items: volumes,
            onChanged: (k) => setState(() => _volume = k),
          ),
          _dropdownGroup(
            label: '年级',
            value: '$_grade',
            items: [for (final g in grades) ('$g', '${g}年级')],
            onChanged: (k) => setState(() => _grade = int.parse(k)),
          ),
        ],
      ),
    );
  }

  /// 当前版本支持的年级（按各科目支持范围求并集，保证至少有可选年级）
  List<int> _allowedGrades() {
    final data = AppData();
    final support = data.versionSupport[_version] ?? data.versionSupport['renjiao']!;
    final allowed = <int>{};
    for (final key in ['cally', 'math', 'eng']) {
      final r = support[key];
      if (r != null) {
        for (var g = r[0]; g <= r[1]; g++) allowed.add(g);
      }
    }
    if (allowed.isEmpty) allowed.addAll([1, 2, 3, 4, 5, 6]);
    final list = allowed.toList()..sort();
    return list;
  }

  Widget _dropdownGroup({
    required String label,
    required String value,
    required List<(String, String)> items,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xff666666))),
        const SizedBox(width: 6),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xffcccccc)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isDense: true,
                style: const TextStyle(fontSize: 14, color: Color(0xff333333)),
                items: [
                  for (final (k, l) in items)
                    DropdownMenuItem(value: k, child: Text(l)),
                ],
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _normalizeGrade() {
    final allowed = _allowedGrades();
    if (allowed.isNotEmpty && !allowed.contains(_grade)) {
      _grade = allowed.first;
    }
  }

  /// 当前版本支持的科目（外研版仅英语，冀教版语文为 null 等）
  Set<String> _supportedSubjects() {
    final data = AppData();
    final support = data.versionSupport[_version] ?? data.versionSupport['renjiao']!;
    final set = <String>{};
    if (support['cally'] != null) set.add('cally');
    if (support['math'] != null) set.add('math');
    if (support['eng'] != null) set.add('eng');
    return set;
  }

  /// 版本切换后归一化标签页：当前标签对应的科目若不再支持，切回第一个可用标签
  void _normalizeTab() {
    final s = _supportedSubjects();
    final curSubject = switch (_tab) {
      'chinese' => 'cally',
      'math' => 'math',
      'english' => 'eng',
      _ => null,
    };
    if (curSubject != null && !s.contains(curSubject)) {
      _tab = _visibleTabKeys().firstWhere((t) => t != null, orElse: () => 'calligraphy')!;
    }
  }

  /// 当前版本可见的标签 key（按支持科目过滤）
  List<String?> _visibleTabKeys() {
    final s = _supportedSubjects();
    return [
      'calligraphy',
      if (s.contains('cally')) 'chinese',
      if (s.contains('math')) 'math',
      if (s.contains('eng')) 'english',
      'ai',
      'aihelp',
      'about',
    ];
  }

  Widget _tabs() {
    final tabs = [
      ('calligraphy', '✍️ 练字帖'),
      if (_supportedSubjects().contains('cally')) ('chinese', '📖 语文作业'),
      if (_supportedSubjects().contains('math')) ('math', '🔢 数学作业'),
      if (_supportedSubjects().contains('eng')) ('english', '🇬🇧 英语作业'),
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

  /// 各标签页面板（IndexedStack 常驻，切换标签不丢各面板的设置/预览状态）
  Widget _panel() {
    final widgets = <String, Widget>{
      'calligraphy': CalligraphyPanel(grade: _grade, version: _version, volume: _volume),
      if (_supportedSubjects().contains('cally'))
        'chinese': ChinesePanel(grade: _grade, version: _version, volume: _volume),
      if (_supportedSubjects().contains('math'))
        'math': MathPanel(grade: _grade, version: _version, volume: _volume),
      if (_supportedSubjects().contains('eng'))
        'english': EnglishPanel(grade: _grade, version: _version, volume: _volume),
      'ai': AiPanel(grade: _grade, version: _version, volume: _volume),
      'aihelp': AiHelpPanel(grade: _grade, version: _version, volume: _volume),
      'about': const AboutPanel(),
    };
    final keys = _visibleTabKeys().whereType<String>().toList();
    final list = [for (final k in keys) widgets[k]!];
    final idx = keys.indexOf(_tab);
    return IndexedStack(
      index: idx < 0 ? 0 : idx,
      children: list,
    );
  }
}
