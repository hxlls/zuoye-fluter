import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_data.dart';
import '../core/chinese_worksheet.dart';
import '../core/worksheet_model.dart';
import '../ai/ai_generator.dart';
import '../ai/ai_client.dart';
import 'panel_widgets.dart';
import 'preview_panel.dart';
import 'recitation_panel.dart';
import 'book_list_panel.dart';
import 'practical_panel.dart';
import 'export_file.dart';
import 'ai_config_card.dart';

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
  /// 是否「基于统编版课文」生成阅读理解（true 时从 YUWEN_TEXTS 取真实课文出题）
  bool _useTextbook = false;

  static const _corpusKey = 'customCorpus';

  @override
  void initState() {
    super.initState();
    // 选「统编版」时，阅读理解默认基于统编版课文出题（课文阅读）
    _useTextbook = const {'tongbiao', 'hebei', 'renjiao'}.contains(widget.version);
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
      // 切换到「统编版」则默认开启课文模式；切走则关闭（用户手动开关在同版本内仍有效）
      if (oldWidget.version != widget.version) {
        _useTextbook = const {'tongbiao', 'hebei', 'renjiao'}.contains(widget.version);
      }
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

  void _generate() {
    if ((_counts['aiyuedu'] ?? 0) > 0) {
      _generateAIReading();
    } else {
      _refresh();
    }
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

  /// 拍照/相册导入：识别课本页面照片 → 视觉模型结构化 → 合并归档进语料库
  Future<void> _importCorpusFromImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    if (file == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final bytes = await file.readAsBytes();
      final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final cfg = await AiStore.load();
      if (cfg.base.isEmpty || cfg.model.isEmpty) {
        _showSnack('请先在顶部「AI 智能出题设置」中填写 API 地址，并选用支持看图的多模态大模型'
            '（如 qwen-vl-max / glm-4v / gpt-4o）；纯文本模型无法识别图片。');
        return;
      }
      final prompt = '你是一名小学课本排版识别助手。下面是小学课本（语文或英语）的一页照片。'
          '请识别页面中的课文/对话，并严格按以下 JSON 输出：\n'
          '{"name":"识别到的课本名（如 冀教版语文三年级上册）",'
          '"items":[{"grade":3,"volume":"上","unit":"第一单元","title":"课文标题",'
          '"author":"作者/出处","text":"课文正文（尽量完整抄录，多课分别列出）","questions":[]}]}\n'
          '要求：1) grade 用数字（一年级=1…六年级=6），volume 用"上"或"下"，依据页眉/封面判断；'
          '2) 一页含多篇课文时分别列出，unit 填所属单元名；'
          '3) text 尽量完整抄录原文（含标点），不要改写；只显示部分则抄录可见部分；'
          '4) questions 固定为空数组；5) 只输出一个 JSON 对象，不要其他文字。';
      final content = await AiClient.chat(
        cfg,
        [AiChatMessage('user', prompt)],
        imageBase64: b64,
        jsonMode: true,
      );
      final data = aiExtractJson(content);
      final items = data['items'];
      if (items is! List || items.isEmpty) {
        _showSnack('未识别到课文，请换一张更清晰或正文更完整的页面试试。');
        return;
      }
      // 合并进现有语料库（多次拍照可累积）
      await _loadCorpus();
      final existing = _cachedCorpus ??
          <String, dynamic>{'name': '我的课文库', 'items': <dynamic>[]};
      final existingItems = (existing['items'] is List)
          ? List<dynamic>.from(existing['items'] as List)
          : <dynamic>[];
      existingItems.addAll(items);
      final merged = <String, dynamic>{
        'name': (existing['name'] as String?)?.isNotEmpty == true
            ? existing['name']
            : (data['name'] is String ? data['name'] : '我的课文库'),
        'items': existingItems,
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_corpusKey, json.encode(merged));
      _cachedCorpus = merged;
      await _loadCorpusStatus();
      _regenerate();
      if (mounted) setState(() {});
      _showSnack('已识别并归档 ${items.length} 篇课文（累计 ${existingItems.length} 篇）');
    } catch (e) {
      _showSnack('拍照导入失败：${aiFriendlyError(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearCorpus() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('确定要清除已导入的语料库吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_corpusKey);
    _cachedCorpus = null;
    await _loadCorpusStatus();
    _regenerate();
    if (mounted) setState(() {});
  }

  /// 导出当前课文库（拍照导入/导入的语料）为 .json，方便多端导入导出
  Future<void> _exportCorpus() async {
    await _loadCorpus();
    final c = _cachedCorpus;
    final items = (c != null && c['items'] is List) ? c['items'] as List : null;
    if (items == null || items.isEmpty) {
      _showSnack('暂无可导出的课文库：请先「拍照导入」或「导入语料(.json)」再导出。');
      return;
    }
    final obj = <String, dynamic>{
      'name': (c != null && c['name'] is String && (c['name'] as String).isNotEmpty)
          ? c['name']
          : '我的课文库',
      'items': items,
    };
    final content = json.encode(obj);
    final ts = DateTime.now().millisecondsSinceEpoch;
    try {
      await saveJsonFile('课文库_$ts.json', content, 'application/json');
      _showSnack('已导出课文库（${items.length} 篇）。该文件可在任意设备的「导入语料(.json)」中重新导入。');
    } catch (e) {
      _showSnack('导出失败：${e.toString()}');
    }
  }

  void _previewCorpus() {
    final corpus = _corpus;
    if (corpus.isEmpty) {
      _showSnack('暂无语料，请先导入');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Text('语料库预览',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('共 ${corpus.length} 篇',
                        style: const TextStyle(fontSize: 13, color: Color(0xff888888))),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: corpus.length,
                  itemBuilder: (ctx, i) {
                    final item = corpus[i];
                    return ExpansionTile(
                      title: Text('${item.title}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      subtitle: Text(
                        '${item.grade ?? '?'}年级${item.volume ?? '?'} · ${item.author ?? ''}',
                        style: const TextStyle(fontSize: 12, color: Color(0xff888888)),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.text,
                                  style: const TextStyle(fontSize: 13, height: 1.6)),
                              if (item.questions.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                const Text('问题：',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                for (final q in item.questions)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('• ${q.q} → ${q.a}',
                                        style: const TextStyle(fontSize: 12)),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _downloadSample() {
    final sample = {
      "name": "示例语料库",
      "note": "这是示例格式，请参照此格式准备您自己的语料",
      "items": [
        {
          "grade": 3,
          "volume": "上",
          "title": "示例课文标题",
          "author": "作者",
          "text": "这里是课文正文内容...",
          "questions": [
            {"q": "问题1？", "a": "答案1"},
            {"q": "问题2？", "a": "答案2"}
          ]
        }
      ]
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(sample);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('示例格式'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('请参照以下JSON格式准备语料文件：',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xfff5f5f5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(jsonStr,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ),
                const SizedBox(height: 12),
                const Text('字段说明：',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const Text('• grade: 年级（1-6）\n• volume: 册别（上/下）\n• title: 课文标题\n• author: 作者\n• text: 正文\n• questions: 问题数组（q=问题, a=答案）',
                    style: TextStyle(fontSize: 11, height: 1.6)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _generateAIReading() async {
    // 基于课文模式：若该年级/册暂无本版本课文库，则回退为原创短文并提示
    final wantTextbook = _useTextbook;
    if (wantTextbook && !AppData().hasTextbook(widget.version, widget.grade, widget.volume)) {
      _showSnack('该年级/册暂无本版本课文库，已改用原创短文模式');
    }
    setState(() => _loading = true);
    try {
      final items = await aiGenerateReading(AiPromptOpts(
        version: widget.version,
        volume: widget.volume,
        grade: widget.grade,
        diff: 'easy',
        showAnswer: true,
        readingCount: (_counts['aiyuedu'] ?? 2).clamp(1, 4),
        useTextbook: wantTextbook && AppData().hasTextbook(widget.version, widget.grade, widget.volume),
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
      mobileAction: FilledButton.icon(
        onPressed: _loading ? null : _generate,
        icon: const Icon(Icons.refresh, size: 18),
        label: Text(_loading ? '⏳ 生成中…' : '生成预览'),
      ),
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
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => RecitationPage(grade: widget.grade)),
          ),
          icon: const Icon(Icons.menu_book, size: 18),
          label: const Text('📜 2022 背诵篇目清单'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xff2f6fd0),
            side: const BorderSide(color: Color(0xff2f6fd0)),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => BookListPage(grade: widget.grade)),
          ),
          icon: const Icon(Icons.auto_stories, size: 18),
          label: const Text('📚 2022 整本书阅读书目'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xff2f6fd0),
            side: const BorderSide(color: Color(0xff2f6fd0)),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PracticalPage()),
          ),
          icon: const Icon(Icons.edit_note, size: 18),
          label: const Text('✉️ 应用文格式与例文'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xff2f6fd0),
            side: const BorderSide(color: Color(0xff2f6fd0)),
          ),
        ),
        const SizedBox(height: 14),
        const AiConfigCard(),
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
              if (const {'tongbiao', 'hebei', 'renjiao'}.contains(widget.version))
                CheckLabel(
                  label: '✨ 基于课文（本版本）出阅读理解题',
                  value: _useTextbook,
                  onChanged: (v) {
                    setState(() {
                      _useTextbook = v;
                      // 统一题型风格：勾选时若未选「阅读理解 (AI)」则自动启用默认题量，
                      // 取消勾选不影响题型勾选；保持与「题型」列表一致的一键体验
                      if (v && (_counts['aiyuedu'] ?? 0) <= 0) {
                        _counts['aiyuedu'] = 3;
                      }
                      _regenerate();
                    });
                  },
                ),
              if (const {'tongbiao', 'hebei', 'renjiao'}.contains(widget.version))
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4),
                  child: Text(
                    _useTextbook
                        ? (widget.version == 'tongbiao'
                            ? '已开启：阅读理解将围绕统编版真实课文出题（课文库已覆盖 1–6 年级上下册，共 287 篇）'
                            : '已开启：将依据本版本课文篇目，由 AI 原创适龄短文出题（A档目录模式，正文请用「拍照导入」补充）')
                        : '未开启：阅读理解为 AI 原创短文模式',
                    style: const TextStyle(fontSize: 11, color: Color(0xff999999), height: 1.4),
                  ),
                ),
            ],
          ),
        ),
        FormGroup(
          label: '外置语料库（课文·阅读）',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: const Text(
                  '推荐：拿手机拍下课本页面（或选相册图），AI 自动识别课文并归档；也可导入 .json 语料文件。',
                  style: TextStyle(fontSize: 11, color: Color(0xff999999), height: 1.4),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _importCorpusFromImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: const Text('📷 拍照导入'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _importCorpusFromImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library, size: 16),
                    label: const Text('🖼️ 相册导入'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _importCorpus,
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: const Text('导入语料(.json)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _previewCorpus,
                    icon: const Icon(Icons.preview, size: 16),
                    label: const Text('预览语料'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _downloadSample,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('下载示例格式'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _clearCorpus,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('清除'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _exportCorpus,
                    icon: const Icon(Icons.file_download, size: 16),
                    label: const Text('导出课文库'),
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
            onPressed: _generate,
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
