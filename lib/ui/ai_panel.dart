import 'package:flutter/material.dart';
import '../core/scope_guard.dart';
import '../core/worksheet_model.dart';
import '../data/ai_pref_store.dart';
import '../ai/ai_generator.dart';
import '../ai/ai_client.dart';
import 'panel_widgets.dart';
import 'preview_panel.dart';
import 'ai_config_card.dart';

/// AI 出题面板
class AiPanel extends StatefulWidget {
  final int grade;
  final String version;
  final String volume;
  const AiPanel({
    super.key,
    required this.grade,
    required this.version,
    required this.volume,
  });

  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> {
  String _subject = 'math';
  String _diff = 'easy';
  bool _showAnswer = true;
  String _theme = '';
  String _textType = '';
  final Map<String, int> _styles = {};
  List<WsPage> _pages = [];
  bool _loading = false;

  /// 生成后超纲检查的提示（空串表示未发现问题）。
  /// AI 出题只能靠提示词约束，这里兜一道并显式告知用户。
  String _scopeNote = '';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(AiPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 年级/版本/册变了：新组合下多出来的题型要补上默认值。
    // 只补缺失项、不清空——否则用户已取消的勾选会被复活。
    if (oldWidget.grade != widget.grade ||
        oldWidget.version != widget.version ||
        oldWidget.volume != widget.volume) {
      setState(_seedStyles);
    }
  }

  /// 当前科目在当前年级下可用的题型
  /// （唯一来源是 AI_STYLE_OPTIONS 里各选项的 grades 区间）
  List<AiStyleOption> get _validStyles {
    final opts = AI_STYLE_OPTIONS[_subject] ?? AI_STYLE_OPTIONS['math']!;
    return opts.where((o) {
      final r = o.grades;
      return r.isEmpty || (widget.grade >= r[0] && widget.grade <= r[1]);
    }).toList();
  }

  /// 只给「从未设置过」的可用题型补默认值；已存在的值（含 0 = 主动取消）一律尊重。
  ///
  /// 旧实现是 `_styles.clear()` 后整表重播种，于是用户取消掉的题型会自己勾回来。
  void _seedStyles() {
    final valid = _validStyles;
    for (var i = 0; i < valid.length; i++) {
      final id = valid[i].id;
      if (!_styles.containsKey(id)) _styles[id] = i == 0 ? 3 : 1;
    }
  }

  /// 恢复上次的科目 / 题量 / 选项。
  ///
  /// home_page 的 tab 容器是 switch 而非 IndexedStack，离开 AI 标签会销毁本面板；
  /// 不持久化的话，用户为了改年级去一趟设置再回来，勾选和科目就全没了。
  Future<void> _restore() async {
    final subject = await AiPrefStore.loadSubject();
    final loaded = await AiPrefStore.loadStyles(subject ?? _subject);
    final opts = await AiPrefStore.loadOpts();
    if (!mounted) return;
    setState(() {
      if (subject != null && AI_STYLE_OPTIONS.containsKey(subject)) {
        _subject = subject;
      }
      _styles
        ..clear()
        ..addAll(loaded);
      _diff = opts['diff'] as String? ?? _diff;
      _theme = opts['theme'] as String? ?? _theme;
      _textType = opts['textType'] as String? ?? _textType;
      _showAnswer = opts['showAnswer'] as bool? ?? _showAnswer;
      _seedStyles();
    });
  }

  Future<void> _persistStyles() => AiPrefStore.saveStyles(_subject, _styles);

  Future<void> _persistOpts() => AiPrefStore.saveOpts({
        'diff': _diff,
        'theme': _theme,
        'textType': _textType,
        'showAnswer': _showAnswer,
      });

  /// 切换科目：先存下当前科目的题量，再载入目标科目的
  Future<void> _switchSubject(String v) async {
    if (v == _subject) return;
    await _persistStyles();
    final loaded = await AiPrefStore.loadStyles(v);
    await AiPrefStore.saveSubject(v);
    if (!mounted) return;
    setState(() {
      _subject = v;
      _styles
        ..clear()
        ..addAll(loaded);
      _seedStyles();
    });
  }

  Future<void> _generate() async {
    // 只提交当前年级下可用的题型。旧实现直接拿 _styles 的全部条目，
    // 换过年级后残留的失效题型也会被一并发出去。
    final validIds = _validStyles.map((o) => o.id).toSet();
    final specs = _styles.entries
        .where((e) => e.value > 0 && validIds.contains(e.key))
        .map((e) => AiStyleSpec(e.key, e.value))
        .toList();
    if (specs.isEmpty) {
      _showSnack('请至少勾选一种题型并设置题量（题量填 0 表示不选）。');
      return;
    }
    setState(() {
      _loading = true;
      _scopeNote = ''; // 上一轮的提示先清掉，避免误读
    });
    try {
      final sections = await aiGenerateWorksheet(_subject, specs, AiPromptOpts(
        version: widget.version,
        volume: widget.volume,
        grade: widget.grade,
        diff: _diff,
        showAnswer: _showAnswer,
        theme: _subject == 'english' ? _theme : '',
        textType: _subject == 'english' ? _textType : '',
      ));
      // 生成后超纲检查：AI 只能靠提示词约束（软约束），这里兜一道。
      // 检查项见 lib/core/scope_guard.dart —— 只查能可靠判定的（数学数值越界、
      // 语文字词题的生字越界），英语词汇不做（词表是 headword 形式，误报率高）。
      _scopeNote = ScopeGuard.inspect(
        [
          for (final s in sections)
            for (final it in s.items)
              ScopeItem(styleIdByLabel(_subject, s.type), '${it.q} ${it.a}'),
        ],
        subject: _subject,
        version: widget.version,
        grade: widget.grade,
        volume: widget.volume,
      );

      _pages = aiRenderPages(sections, AiRenderOpts(
        subject: _subject,
        version: widget.version,
        volume: widget.volume,
        grade: widget.grade,
        showAnswer: _showAnswer,
      ));
      if (_scopeNote.isNotEmpty) _showSnack('⚠️ 可能超纲：$_scopeNote');
    } catch (e) {
      _showSnack('AI 生成失败：${aiFriendlyError(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openApiConfig(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: AiConfigCard(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PanelLayout(
      config: _config(),
      onGenerate: _loading ? null : _generate,
      generateLabel: '🤖 AI 生成作业',
      generateBusy: _loading,
      generateIcon: Icons.auto_awesome,
      preview: WorksheetPreviewPanel(
        pages: _pages,
        label: 'AI作业', loading: _loading,
      ),
    );
  }

  Widget _config() {
    final valid = _validStyles;
    // 只统计当前年级可用的题型——旧实现把 _styles 的全部条目都算进总数，
    // 换过年级后失效题型的题量也被计入。
    final total = valid.fold<int>(0, (s, o) => s + (_styles[o.id] ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🤖 AI 智能出题',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('大模型随机出题，避免照搬课本/题库，达到举一反三',
            style: TextStyle(fontSize: 12, color: Color(0xff888888))),
        const SizedBox(height: 12),
        // 生成后超纲检查的提示：AI 靠提示词约束，可能不听话，这里显式告知
        if (_scopeNote.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xfffff4e5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xffe0a458)),
            ),
            child: Text(
              '⚠️ 可能超纲：$_scopeNote\n'
              '可调低难度或换一批重出；若反复出现，请检查所选年级与题型。',
              style: const TextStyle(fontSize: 12, color: Color(0xff8a5300)),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // API 设置（可折叠）
        Card(
          margin: EdgeInsets.zero,
          color: const Color(0xfff8f9fa),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_outlined, size: 18, color: Color(0xff2f6fd0)),
                    const SizedBox(width: 6),
                    const Text('API 连接设置',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _openApiConfig(context),
                      icon: const Icon(Icons.settings, size: 16),
                      label: const Text('配置'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('首次使用需配置大模型 API（DeepSeek / OpenAI 等）',
                    style: TextStyle(fontSize: 12, color: Color(0xff888888))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        FormGroup(
          label: '科目',
          child: SegButtons(
            options: const [
              ('math', '数学'),
              ('english', '英语'),
              ('chinese', '语文'),
            ],
            value: _subject,
            onChanged: _switchSubject,
          ),
        ),
        FormGroup(
          label: '题型（可多选，分别设置题量）',
          child: Column(
            children: [
              for (final o in valid)
                TypeRow(
                  label: o.label,
                  checked: (_styles[o.id] ?? 0) > 0,
                  count: _styles[o.id] ?? 0,
                  onChecked: (v) {
                    setState(() {
                      if (v && (_styles[o.id] ?? 0) <= 0) {
                        _styles[o.id] = 1;
                      } else if (!v) { _styles[o.id] = 0; }
                    });
                    _persistStyles();
                  },
                  onCount: (n) {
                    setState(() => _styles[o.id] = n);
                    _persistStyles();
                  },
                ),
              Text('共 $total 题（各题型题量可单独调整，0 表示不选该题型）',
                  style: const TextStyle(fontSize: 12, color: Color(0xffaaaaaa))),
            ],
          ),
        ),
        FormGroup(
          label: '难度',
          child: SegButtons(
            options: const [('easy', '简单'), ('mid', '中等'), ('hard', '较难')],
            value: _diff,
            onChanged: (v) {
              setState(() => _diff = v);
              _persistOpts();
            },
          ),
        ),
        if (_subject == 'english') ...[
          FormGroup(
            label: '主题语境（2022 课标）',
            child: SegButtons(
              options: const [
                ('', '不限'),
                ('人与自我', '人与自我'),
                ('人与社会', '人与社会'),
                ('人与自然', '人与自然'),
              ],
              value: _theme,
              onChanged: (v) {
                setState(() => _theme = v);
                _persistOpts();
              },
            ),
          ),
          FormGroup(
            label: '语篇类型',
            child: SegButtons(
              options: const [
                ('', '不限'),
                ('歌谣', '歌谣'),
                ('配图故事', '配图故事'),
                ('说明文', '说明文'),
                ('应用文', '应用文'),
              ],
              value: _textType,
              onChanged: (v) {
                setState(() => _textType = v);
                _persistOpts();
              },
            ),
          ),
        ],
        CheckLabel(
          label: '同时生成答案（附参考答案页；关闭则只出题不给答案）',
          value: _showAnswer,
          onChanged: (v) {
            setState(() => _showAnswer = v);
            _persistOpts();
          },
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('⏳ 正在调用大模型生成，请稍候…',
                style: TextStyle(fontSize: 14, color: Color(0xff2f6fd0))),
          ),
      ],
    );
  }
}
