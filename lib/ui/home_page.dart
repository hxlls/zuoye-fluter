import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../data/work_context_store.dart';
import 'about_panel.dart';
import 'ai_config_card.dart';
import 'ai_help_panel.dart';
import 'ai_panel.dart';
import 'calligraphy_panel.dart';
import 'chinese_panel.dart';
import 'corpus_page.dart';
import 'english_panel.dart';
import 'math_panel.dart';
import 'panel_widgets.dart';

/// 主页面：出题 / AI / 设置 三个标签
///
/// 信息架构调整说明：
/// - 底部导航固定 3 项，不再随教材版本增减，图标位置稳定
/// - 科目（练字帖/语文/数学/英语）从导航级降为首页卡片，语义层级更清晰
/// - 教材版本/学期/年级收进「设置」，全局选一次，各科目共用
/// - AI 出题与 AI 帮答合并到「AI」标签内分段切换
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// 科目定义
class _Subject {
  final String key; // 面板 key
  final String support; // versionSupport 中的科目键：cally / math / eng
  final String emoji;
  final String name;
  final String desc;
  const _Subject(this.key, this.support, this.emoji, this.name, this.desc);
}

const _kSubjects = <_Subject>[
  _Subject('calligraphy', 'cally', '✍️', '练字帖', '田字格描红 · 教材生字或自定义'),
  _Subject('chinese', 'cally', '📖', '语文作业', '看拼音写词 · 古诗成语填空'),
  _Subject('math', 'math', '🔢', '数学作业', '口算 · 竖式 · 应用题'),
  _Subject('english', 'eng', '🇬🇧', '英语作业', '字母书写 · 单词拼写 · 连线'),
];

const _kVersions = <(String, String)>[
  ('renjiao', '人教版'),
  ('tongbiao', '统编版'),
  ('hebei', '冀教版'),
  ('waiyanYQ', '外研·一起点'),
  ('waiyanSQ', '外研·三起点'),
];

class _HomePageState extends State<HomePage> {
  String _version = 'renjiao';
  String _volume = '上';
  int _grade = 1;
  String _tab = 'home'; // home | ai | settings
  String _aiMode = 'gen'; // gen | help

  bool _dataReady = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AppData().load();
    final ctx = await WorkContextStore.load();
    if (!mounted) return;
    setState(() {
      if (ctx != null) {
        // 防御：版本可能在后续版本里被移除；年级可能不被该版本支持
        _version = AppData().textbooks.containsKey(ctx.version)
            ? ctx.version
            : 'renjiao';
        _volume = ctx.volume == '下' ? '下' : '上';
        _grade = ctx.grade.clamp(1, 6);
        _normalizeGrade();
      }
      _dataReady = true;
    });
  }

  /// 教材版本/学期/年级任一变化后落盘，下次启动直接恢复
  Future<void> _saveContext() => WorkContextStore.save(
        version: _version,
        volume: _volume,
        grade: _grade,
      );

  // ---------------- 数据查询 ----------------

  String _versionName(String k) {
    for (final (key, label) in _kVersions) {
      if (key == k) return label;
    }
    return k;
  }

  /// 当前版本支持的年级（按各科目支持范围求并集）
  List<int> _allowedGrades() {
    final data = AppData();
    final support =
        data.versionSupport[_version] ?? data.versionSupport['renjiao']!;
    final allowed = <int>{};
    for (final key in ['cally', 'math', 'eng']) {
      final r = support[key];
      if (r != null) {
        for (var g = r[0]; g <= r[1]; g++) {
          allowed.add(g);
        }
      }
    }
    if (allowed.isEmpty) allowed.addAll([1, 2, 3, 4, 5, 6]);
    return allowed.toList()..sort();
  }

  /// 当前版本支持的科目
  Set<String> _supportedSubjects() {
    final data = AppData();
    final support =
        data.versionSupport[_version] ?? data.versionSupport['renjiao']!;
    final set = <String>{};
    for (final key in ['cally', 'math', 'eng']) {
      if (support[key] != null) set.add(key);
    }
    return set;
  }

  /// 年级归一化；返回是否发生了改变，便于提示用户
  bool _normalizeGrade() {
    final allowed = _allowedGrades();
    if (allowed.isNotEmpty && !allowed.contains(_grade)) {
      _grade = allowed.first;
      return true;
    }
    return false;
  }

  void _setVersion(String k) {
    if (k == _version) return;
    final before = _grade;
    setState(() {
      _version = k;
      _normalizeGrade();
    });
    _saveContext();
    if (_grade != before) {
      _toast('${_versionName(k)} 没有 $before 年级，已切到 $_grade 年级');
    }
  }

  void _setVolume(String v) {
    if (v == _volume) return;
    setState(() => _volume = v);
    _saveContext();
  }

  void _setGrade(int g) {
    if (g == _grade) return;
    setState(() => _grade = g);
    _saveContext();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  String _ctxText() =>
      '${_versionName(_version)} · $_volume册 · $_grade年级';

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    if (!_dataReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // 系统返回键：非「出题」标签时先回到「出题」，已在出题页才允许退出应用。
    //
    // 科目面板不在这里处理——它已经是一个**独立路由**（见 _openSubject），
    // 返回键由路由栈自然弹出。
    //
    // 为什么当初必须改成路由：面板若只是本页换个子树渲染，就没有路由可弹，
    // 按返回会直接退出应用；而且嵌套 PopScope 会**同时触发所有处理器**
    // （不是内层优先），于是「预览页返回」会连带把 _subject 置空、直接跳回首页。
    return PopScope(
      canPop: _tab == 'home',
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tab != 'home') setState(() => _tab = 'home');
      },
      child: _buildBody(context),
    );
  }

  /// 页面主体（原 build 的内容）
  Widget _buildBody(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 760;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff2f6fd0),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('📖 小学作业生成器 v${AppData.version}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Text('一键生成 · 可打印 · 支持导出 PDF',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_tab != 'settings') _ctxBar(),
          Expanded(child: _tabBody(wide)),
        ],
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  /// 当前教材/年级上下文条，点击直达设置
  Widget _ctxBar() {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => setState(() => _tab = 'settings'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xffe6e2d8))),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: Color(0xff1f9d55), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _ctxText(),
                  style: const TextStyle(fontSize: 13, color: Color(0xff5a6270)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Text('切换',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xff2f6fd0),
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  int get _tabIndex => switch (_tab) {
        'ai' => 1,
        'settings' => 2,
        _ => 0,
      };

  /// 用 [IndexedStack] 而不是 `switch`：切 Tab **不再销毁**子树。
  ///
  /// 原先用 switch 时，每次离开标签都会把面板整棵销毁、回来再重建，
  /// 由此派生出一整类问题（AI 面板勾选丢失、科目回退、对话清空、
  /// 已生成的预览消失、异步恢复期间闪一下默认值…）。
  /// 之前是靠给每个面板补持久化来兜，现在从根上不再销毁。
  /// 持久化仍然保留——它管的是「重开 App 后还在」，两者互补。
  Widget _tabBody(bool wide) {
    return IndexedStack(
      index: _tabIndex,
      children: [
        _homeBody(wide),
        _aiBody(),
        _settingsBody(),
      ],
    );
  }

  Widget _bottomNav() {
    const items = <(String, IconData, String)>[
      ('home', Icons.edit_note, '出题'),
      ('ai', Icons.auto_awesome, 'AI'),
      ('settings', Icons.settings_outlined, '设置'),
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

  // ---------------- 出题首页 ----------------

  Widget _homeBody(bool wide) {
    final supported = _supportedSubjects();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: const BoxDecoration(
              color: Color(0xffe8f0fc),
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(9),
                bottomRight: Radius.circular(9),
              ),
              border: Border(
                  left: BorderSide(color: Color(0xff2f6fd0), width: 3)),
            ),
            child: const Text(
              '教材、年级在「设置」里选一次，四个科目共用，不用每科重选。',
              style: TextStyle(
                  fontSize: 12.5, color: Color(0xff1d4f96), height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          _secTitle('生成作业'),
          // 用固定行高（mainAxisExtent）而不是 childAspectRatio：
          // 宽高比会让「刚好进入宽屏」的区间（约 760-800px，**iPad 竖屏正是 768px**）
          // 卡片高度不足，实测溢出 3.7px。固定行高在所有宽度下都够用。
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: wide ? 4 : 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 132,
            ),
            itemCount: _kSubjects.length,
            itemBuilder: (_, i) => _subjectCard(
                _kSubjects[i], supported.contains(_kSubjects[i].support)),
          ),
        ],
      ),
    );
  }

  Widget _subjectCard(_Subject s, bool enabled) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled
            ? () => _openSubject(s.key)
            : () => _toast('${_versionName(_version)} 不提供${s.name}'),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x14000000)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: enabled ? 1 : 0.35,
                child: Text(s.emoji, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(height: 6),
              Text(
                s.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? const Color(0xff1f2328)
                      : const Color(0xffb0b6bf),
                ),
              ),
              const SizedBox(height: 3),
              Flexible(
                child: Text(
                  enabled ? s.desc : '当前版本不提供',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xff939aa6), height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- AI ----------------

  Widget _aiBody() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xfffaf8f2),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: SegButtons(
            options: const [('gen', '🤖 AI 出题'), ('help', '💡 AI 帮答')],
            value: _aiMode,
            expand: true,
            onChanged: (v) => setState(() => _aiMode = v),
          ),
        ),
        Expanded(
          // 同理：切「出题 / 帮答」不再销毁对方，
          // 已生成的题目与进行中的对话都留在原地
          child: IndexedStack(
            index: _aiMode == 'gen' ? 0 : 1,
            children: [
              AiPanel(grade: _grade, version: _version, volume: _volume),
              AiHelpPanel(grade: _grade, version: _version, volume: _volume),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- 设置 ----------------

  Widget _settingsBody() {
    final grades = _allowedGrades();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _secTitle('教材与进度'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel('教材版本'),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final (k, l) in _kVersions)
                        _chip(l, _version == k, () => _setVersion(k)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _fieldLabel('学期'),
                  Wrap(
                    spacing: 7,
                    children: [
                      for (final (k, l) in const [('上', '上册'), ('下', '下册')])
                        _chip(l, _volume == k, () => _setVolume(k)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _fieldLabel('年级'),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final g in grades)
                        _chip('$g年级', _grade == g, () => _setGrade(g)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '可选年级随教材版本变化（${_versionName(_version)}：'
                    '${grades.join('、')} 年级）',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xff939aa6), height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _secTitle('教材语料库'),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: const Text('导入与管理'),
              subtitle: const Text(
                  '导入教材 PDF / 语料文件、拍照识别；管理出题用的课文'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CorpusPage(
                  version: _version,
                  grade: _grade,
                  volume: _volume,
                ),
              )),
            ),
          ),
          const SizedBox(height: 20),
          _secTitle('AI 模型'),
          const AiConfigCard(),
          const SizedBox(height: 20),
          _secTitle('关于'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  title: const Text('版本', style: TextStyle(fontSize: 14)),
                  trailing: Text('v${AppData.version}',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xff939aa6))),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  title: const Text('功能说明与免责声明',
                      style: TextStyle(fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right,
                      size: 20, color: Color(0xff939aa6)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const Scaffold(body: SafeArea(child: AboutPanel())),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _secTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xff939aa6),
            letterSpacing: 0.4,
          ),
        ),
      );

  Widget _fieldLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xff333333))),
      );

  Widget _chip(String label, bool on, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: on ? const Color(0xff2f6fd0) : Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: on ? const Color(0xff2f6fd0) : const Color(0xffd8d4c9)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            color: on ? Colors.white : const Color(0xff5a6270),
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ---------------- 科目面板 ----------------

  /// 打开科目面板。
  ///
  /// 刻意用**路由**而不是页面内状态切换：
  /// - 状态切换没有路由可弹，系统返回键只能退出应用；
  /// - 且嵌套 PopScope 会同时触发所有处理器，「预览页返回」会连带跳回首页。
  /// [focusCorpus] 为 true 时，打开后直接落在语文面板的语料分组
  /// （设置页「教材语料库」入口用）。
  void _openSubject(String key) {
    final s = _kSubjects.firstWhere((e) => e.key == key);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _SubjectPanelPage(
        subject: s,
        ctxText: _ctxText(),
        panel: _panelFor(key),
      ),
    ));
  }

  Widget _panelFor(String key) {
    switch (key) {
      case 'chinese':
        return ChinesePanel(
          grade: _grade,
          version: _version,
          volume: _volume,
        );
      case 'math':
        return MathPanel(grade: _grade, version: _version, volume: _volume);
      case 'english':
        return EnglishPanel(grade: _grade, version: _version, volume: _volume);
      default:
        return CalligraphyPanel(
            grade: _grade, version: _version, volume: _volume);
    }
  }
}

/// 科目面板页（独立路由）。
///
/// 做成路由是为了让系统返回键有得可弹：预览页 -> 配置页（面板内部处理），
/// 配置页 -> 首页（路由弹出），首页 -> 退出应用。
class _SubjectPanelPage extends StatelessWidget {
  final _Subject subject;
  final String ctxText;
  final Widget panel;
  const _SubjectPanelPage({
    required this.subject,
    required this.ctxText,
    required this.panel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff2f6fd0),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${subject.emoji} ${subject.name}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            Text(ctxText,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
      body: panel,
    );
  }
}
