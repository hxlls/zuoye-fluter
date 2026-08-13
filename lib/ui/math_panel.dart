import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../core/math_worksheet.dart';
import '../core/worksheet_model.dart';
import 'panel_widgets.dart';
import 'preview_panel.dart';

/// 数学作业面板
class MathPanel extends StatefulWidget {
  final int grade;
  final String version;
  final String volume;
  const MathPanel({
    super.key,
    required this.grade,
    required this.version,
    required this.volume,
  });

  @override
  State<MathPanel> createState() => _MathPanelState();
}

class _MathPanelState extends State<MathPanel> {
  final Map<String, int> _counts = {};
  String _diff = 'easy';
  bool _showAnswer = true;
  bool _showTitle = true;
  List<WsPage> _pages = [];
  bool _loading = false;

  List<MathType> get _cfg =>
      AppData().vol(widget.version, widget.grade, widget.volume, 'math')?.math ??
      [];

  @override
  void initState() {
    super.initState();
    _ensureCounts();
    _regenerate();
  }

  @override
  void didUpdateWidget(MathPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grade != widget.grade ||
        oldWidget.version != widget.version ||
        oldWidget.volume != widget.volume) {
      _ensureCounts();
      _regenerate();
    }
  }

  void _ensureCounts() {
    final valid = _cfg.map((t) => t.id).toSet();
    _counts.removeWhere((k, v) => !valid.contains(k));
    final fallback = _cfg.isEmpty ? 0 : (30 / _cfg.length).ceil();
    for (final t in _cfg) {
      if (!_counts.containsKey(t.id) || _counts[t.id]! < 1) {
        _counts[t.id] = fallback;
      }
    }
  }

  void _regenerate() {
    _pages = mathRenderPages(MathOptions(
      grade: widget.grade,
      version: widget.version,
      volume: widget.volume,
      types: _cfg.map((t) => t.id).toList(),
      counts: Map.of(_counts),
      diff: _diff,
      showAnswer: _showAnswer,
      showTitle: _showTitle,
    ));
  }

  void _refresh() {
    setState(() {
      _regenerate();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PanelLayout(
      config: _config(),
      preview: WorksheetPreviewPanel(
        pages: _pages,
        label: '数学作业', loading: _loading,
      ),
    );
  }

  Widget _config() {
    final cfg = _cfg;
    final total = _counts.values.fold<int>(0, (s, v) => s + v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('数学作业设置',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('📚 题型对应人教版数学教材各年级单元',
            style: TextStyle(fontSize: 12, color: Color(0xff888888))),
        const SizedBox(height: 14),
        FormGroup(
          label: '题型（可多选，每种题型可单独设置题量）',
          child: Column(
            children: [
              for (final t in cfg)
                TypeRow(
                  label: t.label,
                  sub: t.unit,
                  checked: (_counts[t.id] ?? 0) > 0,
                  count: _counts[t.id] ?? 0,
                  onChecked: (v) {
                    setState(() {
                      if (v && (_counts[t.id] ?? 0) <= 0) {
                        _counts[t.id] = 10;
                      } else if (!v) {
                        _counts[t.id] = 0;
                      }
                      _regenerate();
                    });
                  },
                  onCount: (n) {
                    setState(() {
                      _counts[t.id] = n;
                      _regenerate();
                    });
                  },
                ),
              Text('共 $total 题（每种题型可单独调整题量，0 表示不选该题型）',
                  style: const TextStyle(fontSize: 12, color: Color(0xffaaaaaa))),
            ],
          ),
        ),
        FormGroup(
          label: '难度',
          child: SegButtons(
            options: [('easy', '简单'), ('mid', '中等'), ('hard', '较难')],
            value: _diff,
            onChanged: (v) {
              setState(() {
                _diff = v;
                _regenerate();
              });
            },
          ),
        ),
        FormGroup(
          label: '选项',
          child: Column(
            children: [
              CheckLabel(
                label: '附答案',
                value: _showAnswer,
                onChanged: (v) {
                  setState(() {
                    _showAnswer = v;
                    _regenerate();
                  });
                },
              ),
              CheckLabel(
                label: '显示标题栏',
                value: _showTitle,
                onChanged: (v) {
                  setState(() {
                    _showTitle = v;
                    _regenerate();
                  });
                },
              ),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _refresh,
            child: const Text('生成预览'),
          ),
        ),
      ],
    );
  }
}
