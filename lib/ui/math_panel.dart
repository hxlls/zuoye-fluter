import 'package:flutter/material.dart';
import '../core/math_worksheet.dart';
import '../core/type_catalog.dart';
import '../core/worksheet_model.dart';
import '../data/type_count_store.dart';
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
  final bool _loading = false;

  /// 当前「版本 × 年级 × 册」下的题型清单。唯一来源：TypeCatalog。
  List<TypeSpec> get _specs => TypeCatalog.of(
        Subject.math,
        version: widget.version,
        grade: widget.grade,
        volume: widget.volume,
      );

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  @override
  void didUpdateWidget(MathPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grade != widget.grade ||
        oldWidget.version != widget.version ||
        oldWidget.volume != widget.volume) {
      _loadCounts();
    }
  }

  /// 读取全局题量偏好并按当前目录补齐缺失项。
  ///
  /// 已存在的值（含 0 = 用户主动取消）一律保留——旧实现用 `count < 1` 判断
  /// 「没设置过」，会把用户取消勾选的题型重新填回默认题量。
  Future<void> _loadCounts() async {
    final seeded = await TypeCountStore.loadSeeded(Subject.math, _specs);
    if (!mounted) return;
    setState(() {
      _counts
        ..clear()
        ..addAll(seeded);
    });
    _regenerate();
  }

  Future<void> _persist() => TypeCountStore.save(Subject.math, _counts);

  void _regenerate() {
    _pages = mathRenderPages(MathOptions(
      grade: widget.grade,
      version: widget.version,
      volume: widget.volume,
      types: _specs.map((t) => t.id).toList(),
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
      onGenerate: _refresh,
      generateLabel: '生成预览',
      preview: WorksheetPreviewPanel(
        pages: _pages,
        label: '数学作业', loading: _loading,
      ),
    );
  }

  Widget _config() {
    final cfg = _specs;
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
              if (cfg.isEmpty)
                const Text('当前教材版本/年级/册没有数学题型数据。',
                    style: TextStyle(fontSize: 12, color: Color(0xff888888))),
              for (final t in cfg)
                TypeRow(
                  label: t.label,
                  sub: t.unit,
                  checked: (_counts[t.id] ?? 0) > 0,
                  count: _counts[t.id] ?? 0,
                  onChecked: (v) {
                    setState(() {
                      if (v && (_counts[t.id] ?? 0) <= 0) {
                        _counts[t.id] = t.defaultQty;
                      } else if (!v) {
                        _counts[t.id] = 0;
                      }
                      _regenerate();
                    });
                    _persist();
                  },
                  onCount: (n) {
                    setState(() {
                      _counts[t.id] = n;
                      _regenerate();
                    });
                    _persist();
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
            options: const [('easy', '简单'), ('mid', '中等'), ('hard', '较难')],
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
      ],
    );
  }
}
