import 'package:flutter/material.dart';
import '../core/worksheet_model.dart';
import '../ai/ai_generator.dart';
import '../ai/ai_client.dart';
import 'panel_widgets.dart';
import 'preview_panel.dart';

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
  final Map<String, int> _styles = {};
  List<WsPage> _pages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ensureStyles();
  }

  void _ensureStyles() {
    final opts = AI_STYLE_OPTIONS[_subject] ?? AI_STYLE_OPTIONS['math']!;
    final valid = opts.where((o) {
      final r = o.grades;
      return r.isEmpty || (widget.grade >= r[0] && widget.grade <= r[1]);
    }).toList();
    _styles.clear();
    for (var i = 0; i < valid.length; i++) {
      _styles[valid[i].id] = i == 0 ? 3 : 1;
    }
  }

  Future<void> _generate() async {
    final specs = _styles.entries
        .where((e) => e.value > 0)
        .map((e) => AiStyleSpec(e.key, e.value))
        .toList();
    if (specs.isEmpty) {
      _showSnack('请至少勾选一种题型并设置题量（题量填 0 表示不选）。');
      return;
    }
    setState(() => _loading = true);
    try {
      final sections = await aiGenerateWorksheet(_subject, specs, AiPromptOpts(
        version: widget.version,
        volume: widget.volume,
        grade: widget.grade,
        diff: _diff,
        showAnswer: _showAnswer,
      ));
      _pages = aiRenderPages(sections, AiRenderOpts(
        subject: _subject,
        version: widget.version,
        volume: widget.volume,
        grade: widget.grade,
        showAnswer: _showAnswer,
      ));
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

  @override
  Widget build(BuildContext context) {
    return PanelLayout(
      config: _config(),
      mobileAction: FilledButton.icon(
        onPressed: _loading ? null : _generate,
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: Text(_loading ? '⏳ 正在生成…' : '🤖 AI 生成作业'),
      ),
      preview: WorksheetPreviewPanel(
        pages: _pages,
        label: 'AI作业', loading: _loading,
      ),
    );
  }

  Widget _config() {
    final opts = AI_STYLE_OPTIONS[_subject] ?? AI_STYLE_OPTIONS['math']!;
    final valid = opts.where((o) {
      final r = o.grades;
      return r.isEmpty || (widget.grade >= r[0] && widget.grade <= r[1]);
    }).toList();
    final total = _styles.values.fold<int>(0, (s, v) => s + v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AI 出题设置',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('🤖 大模型随机出题，避免照搬课本/题库，达到举一反三',
            style: TextStyle(fontSize: 12, color: Color(0xff888888))),
        const SizedBox(height: 14),
        FormGroup(
          label: '科目',
          child: SegButtons(
            options: [
              ('math', '数学'),
              ('english', '英语'),
              ('chinese', '语文'),
            ],
            value: _subject,
            onChanged: (v) {
              setState(() {
                _subject = v;
                _ensureStyles();
              });
            },
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
                      if (v && (_styles[o.id] ?? 0) <= 0) _styles[o.id] = 1;
                      else if (!v) _styles[o.id] = 0;
                    });
                  },
                  onCount: (n) {
                    setState(() => _styles[o.id] = n);
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
            options: [('easy', '简单'), ('mid', '中等'), ('hard', '较难')],
            value: _diff,
            onChanged: (v) => setState(() => _diff = v),
          ),
        ),
        CheckLabel(
          label: '同时生成答案（附参考答案页；关闭则只出题不给答案）',
          value: _showAnswer,
          onChanged: (v) => setState(() => _showAnswer = v),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('🤖 AI 生成'),
          ),
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
