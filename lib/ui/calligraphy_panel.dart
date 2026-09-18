import 'package:flutter/material.dart';
import '../core/calligraphy_worksheet.dart';
import '../data/panel_pref_store.dart';
import 'panel_widgets.dart';
import 'preview_panel.dart';

/// 练字帖面板
class CalligraphyPanel extends StatefulWidget {
  final int grade;
  final String version;
  final String volume;
  const CalligraphyPanel({
    super.key,
    required this.grade,
    required this.version,
    required this.volume,
  });

  @override
  State<CalligraphyPanel> createState() => _CalligraphyPanelState();
}

class _CalligraphyPanelState extends State<CalligraphyPanel> {
  final _opts = CalligraphyOptions();
  List<CalligraphyPageData> _pages = [];
  final bool _loading = false;

  @override
  void initState() {
    super.initState();
    _regenerate();   // 先用默认值渲染，避免首帧空白
    _loadOpts();     // 再异步覆盖为用户上次的选择
  }

  /// 恢复上次的练字帖选项。面板是 push 出来的全屏页，返回时会被销毁，
  /// 不持久化的话每次重进都回到默认值（字数/每行格数/练习遍数/拼音/标题栏…）。
  Future<void> _loadOpts() async {
    final o = await PanelPrefStore.load('calligraphy');
    if (!mounted || o.isEmpty) return;
    setState(() {
      _opts.source = o['source'] as String? ?? _opts.source;
      _opts.charCount = o['charCount'] as int? ?? _opts.charCount;
      _opts.customText = o['customText'] as String? ?? _opts.customText;
      _opts.practice = o['practice'] as int? ?? _opts.practice;
      _opts.perRow = o['perRow'] as int? ?? _opts.perRow;
      _opts.rows = o['rows'] as int? ?? _opts.rows;
      _opts.showPinyin = o['showPinyin'] as bool? ?? _opts.showPinyin;
      _opts.showTitle = o['showTitle'] as bool? ?? _opts.showTitle;
      _regenerate();
    });
  }

  Future<void> _persistOpts() => PanelPrefStore.save('calligraphy', {
        'source': _opts.source,
        'charCount': _opts.charCount,
        'customText': _opts.customText,
        'practice': _opts.practice,
        'perRow': _opts.perRow,
        'rows': _opts.rows,
        'showPinyin': _opts.showPinyin,
        'showTitle': _opts.showTitle,
      });

  @override
  void didUpdateWidget(CalligraphyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grade != widget.grade ||
        oldWidget.version != widget.version ||
        oldWidget.volume != widget.volume) {
      _regenerate();
    }
  }

  void _regenerate() {
    _pages = calligraphyRenderPages(CalligraphyOptions(
      source: _opts.source,
      charCount: _opts.charCount,
      customText: _opts.customText,
      practice: _opts.practice,
      perRow: _opts.perRow,
      rows: _opts.rows,
      showPinyin: _opts.showPinyin,
      showTitle: _opts.showTitle,
      grade: widget.grade,
      version: widget.version,
      volume: widget.volume,
    ));
  }

  void _regenerateWith(void Function() f) {
    setState(() {
      f();
      _regenerate();
    });
    _persistOpts();
  }

  @override
  Widget build(BuildContext context) {
    return PanelLayout(
      config: _config(),
      onGenerate: () => setState(() => _regenerate()),
      generateLabel: '生成预览',
      preview: CalligraphyPreviewPanel(
        pages: _pages,
        label: '练字帖', loading: _loading,
      ),
    );
  }

  Widget _config() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('练字帖设置',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('📚 生字参考人教版语文各年级生字表',
            style: TextStyle(fontSize: 12, color: Color(0xff888888))),
        const SizedBox(height: 14),
        FormGroup(
          label: '内容来源',
          child: SegButtons(
            options: const [('grade', '年级生字'), ('custom', '自定义文字')],
            value: _opts.source,
            onChanged: (v) => _regenerateWith(() => _opts.source = v),
          ),
        ),
        if (_opts.source == 'grade')
          FormGroup(
            label: '生字数量',
            child: CountSlider(
              value: _opts.charCount,
              min: 4,
              max: 40,
              divisions: 18,
              onChanged: (v) => _regenerateWith(() => _opts.charCount = v),
            ),
          ),
        if (_opts.source == 'custom')
          FormGroup(
            label: '输入要练的文字（每个字单独成例）',
            child: TextField(
              maxLines: 3,
              controller: TextEditingController(text: _opts.customText),
              decoration: const InputDecoration(
                hintText: '例如：我爱我的祖国，天天向上',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _regenerateWith(() => _opts.customText = v),
            ),
          ),
        FormGroup(
          label: '每字练习次数',
          child: NumDropdown(
            value: _opts.practice,
            min: 1,
            max: 10,
            fillWidth: true,
            onChanged: (v) => _regenerateWith(() => _opts.practice = v),
          ),
        ),
        FormGroup(
          label: '每行字数（列）',
          child: NumDropdown(
            value: _opts.perRow,
            min: 1,
            max: 10,
            fillWidth: true,
            onChanged: (v) => _regenerateWith(() => _opts.perRow = v),
          ),
        ),
        FormGroup(
          label: '每页行数',
          child: NumDropdown(
            value: _opts.rows,
            min: 1,
            max: 10,
            fillWidth: true,
            onChanged: (v) => _regenerateWith(() => _opts.rows = v),
          ),
        ),
        FormGroup(
          label: '显示选项',
          child: Column(
            children: [
              CheckLabel(
                label: '显示拼音',
                value: _opts.showPinyin,
                onChanged: (v) => _regenerateWith(() => _opts.showPinyin = v),
              ),
              CheckLabel(
                label: '显示标题栏（姓名/日期）',
                value: _opts.showTitle,
                onChanged: (v) => _regenerateWith(() => _opts.showTitle = v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
