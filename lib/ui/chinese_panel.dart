import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_data.dart';
import '../core/chinese_worksheet.dart';
import '../core/worksheet_model.dart';
import '../ai/ai_generator.dart';
import '../ai/ai_client.dart';
import 'panel_widgets.dart';
import 'preview_panel.dart';

/// 语文作业面板
class ChinesePanel extends StatefulWidget {
  final int grade;
  final String version;
  final String volume;
  const ChinesePanel({
    super.key,
    required this.grade,
    required this.version,
    required this.volume,
  });

  @override
  State<ChinesePanel> createState() => _ChinesePanelState();
}

class _ChinesePanelState extends State<ChinesePanel> {
  final Map<String, int> _counts = {};
  bool _showAnswer = true;
  bool _showTitle = true;
  List<WsPage> _pages = [];
  bool _loading = false;
  List<ReadingBlockData> _aiItems = [];
  String _corpusStatus = '未导入';

  static const _corpusKey = 'customCorpus';

  @override
  void initState() {
    super.initState();
    _ensureCounts();
    _loadCorpusStatus();
    _regenerate();
  }

  @override
  void didUpdateWidget(ChinesePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grade != widget.grade ||
        oldWidget.version != widget.version ||
        oldWidget.volume != widget.volume) {
      _ensureCounts();
      _regenerate();
    }
  }

  List<String> get _typeIds =>
      ['pinyin2char', 'char2pinyin', 'zuci', 'gushiFill', 'chengyuFill', 'chengyuGuess', 'mingjuFill', 'duanwen', 'aiyuedu'];

  void _ensureCounts() {
    // 按年级过滤题型
    final data = AppData();
    final valid = _typeIds
        .where((id) {
          final r = data.cnTypeGrades[id];
          return r == null || (widget.grade >= r[0] && widget.grade <= r[1]);
        })
        .toList();
    _counts.removeWhere((k, v) => !valid.contains(k));
    for (final t in valid) {
      if (!_counts.containsKey(t)) _counts[t] = 6;
    }
  }

  List<ReadingBlockData> get _corpus {
    final c = _cachedCorpus;
    if (c == null) return [];
    final items = c['items'];
    if (items is! List) return [];
    return [
      for (final it in items)
        if (it is Map)
          ReadingBlockData(
            title: '${it['title'] ?? ''}',
            author: '${it['author'] ?? ''}',
            text: '${it['text'] ?? ''}',
            grade: it['grade'] is num ? (it['grade'] as num).toInt() : null,
            volume: it['volume'] is String ? it['volume'] as String : null,
            questions: [
              for (final q in (it['questions'] is List ? it['questions'] as List : []))
                if (q is Map)
                  ReadingQuestion('${q['q'] ?? ''}', '${q['a'] ?? ''}')
            ],
          )
    ];
  }

  Map<String, dynamic>? _cachedCorpus;

  Future<void> _loadCorpus() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_corpusKey);
    if (raw != null) {
      try {
        _cachedCorpus = json.decode(raw) as Map<String, dynamic>;
      } catch (e) {
        _cachedCorpus = null;
      }
    } else {
      _cachedCorpus = null;
    }
  }

  Future<void> _loadCorpusStatus() async {
    await _loadCorpus();
    final c = _cachedCorpus;
    final n = c != null && c['items'] is List ? (c['items'] as List).length : 0;
    if (mounted) {
      setState(() {
        _corpusStatus = c != null
            ? '已导入：${c['name'] ?? '未命名'}（$n 篇，版权自负）'
            : '未导入（导入后可生成"课文·阅读"理解题）';
      });
    }
  }

  void _regenerate() {
    _pages = chineseRenderPages(
      ChineseOptions(
        grade: widget.grade,
        version: widget.version,
        volume: widget.volume,
        types: _typeIds,
        counts: Map.of(_counts),
        showAnswer: _showAnswer,
        showTitle: _showTitle,
        aiReadingItems: _aiItems.isEmpty ? null : _aiItems,
      ),
      customCorpus: _cachedCorpus == null ? null : _corpus,
    );
  }

  void _refresh() {
    setState(_regenerate);
  }

  Future<void> _importCorpus() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    try {
      final obj = json.decode(utf8.decode(f.bytes!));
      if (obj is! Map<String, dynamic> || obj['items'] is! List) {
        _showSnack('格式不正确：需包含 items 数组');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_corpusKey, json.encode(obj));
      _cachedCorpus = obj;
      await _loadCorpusStatus();
      _regenerate();
      if (mounted) setState(() {});
    } catch (e) {
      _showSnack('导入失败：$e');
    }
  }

  Future<void> _clearCorpus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_corpusKey);
    _cachedCorpus = null;
    await _loadCorpusStatus();
    _regenerate();
    if (mounted) setState(() {});
  }

  Future<void> _generateAIReading() async {
    setState(() => _loading = true);
    try {
      final items = await aiGenerateReading(AiPromptOpts(
        version: widget.version,
        volume: widget.volume,
        grade: widget.grade,
        diff: 'easy',
        showAnswer: true,
        readingCount: (_counts['aiyuedu'] ?? 2).clamp(1, 4),
      ));
      _aiItems = items;
      _regenerate();
    } catch (e) {
      _showSnack('AI 阅读理解生成失败：${aiFriendlyError(e)}');
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
      preview: WorksheetPreviewPanel(
        pages: _pages,
        label: '语文作业', loading: _loading,
      ),
    );
  }

  Widget _config() {
    final total = _counts.values.fold<int>(0, (s, v) => s + v);
    final data = AppData();
    final validTypes = _typeIds.where((id) {
      final r = data.cnTypeGrades[id];
      return r == null || (widget.grade >= r[0] && widget.grade <= r[1]);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('语文作业设置',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('📚 生字参考人教版语文各年级生字表',
            style: TextStyle(fontSize: 12, color: Color(0xff888888))),
        const SizedBox(height: 14),
        FormGroup(
          label: '题型（可多选，每种题型可单独设置题量）',
          child: Column(
            children: [
              for (final t in validTypes)
                TypeRow(
                  label: CHINESE_TYPES_LABELS[t] ?? t,
                  checked: (_counts[t] ?? 0) > 0,
                  count: _counts[t] ?? 0,
                  onChecked: (v) {
                    setState(() {
                      if (v && (_counts[t] ?? 0) <= 0) _counts[t] = 6;
                      else if (!v) _counts[t] = 0;
                      _regenerate();
                    });
                  },
                  onCount: (n) {
                    setState(() {
                      _counts[t] = n;
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
        FormGroup(
          label: '外置语料库（课文·阅读）',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _importCorpus,
                    child: const Text('📂 导入语料文件(.json)'),
                  ),
                  OutlinedButton(
                    onPressed: _clearCorpus,
                    child: const Text('清除语料库'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_corpusStatus,
                    style: const TextStyle(fontSize: 12, color: Color(0xffaaaaaa))),
              ),
              const SizedBox(height: 6),
              const Text('⚠️ 请只导入您拥有合法使用权的课文内容，使用受版权保护的课文请自行向版权方付费。',
                  style: TextStyle(fontSize: 11, color: Color(0xff999999), height: 1.5)),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              if ((_counts['aiyuedu'] ?? 0) > 0) {
                _generateAIReading();
              } else {
                _refresh();
              }
            },
            child: const Text('生成预览'),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('⏳ AI 正在生成阅读理解，请稍候…',
                style: TextStyle(fontSize: 14, color: Color(0xff2f6fd0))),
          ),
      ],
    );
  }
}
