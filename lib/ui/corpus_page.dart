/// 教材语料库（设置页入口）。
///
/// 「导入教材」是**全局能力**，不属于任何一个科目 —— 教材不止语文有，
/// 导入又是一次性的重操作（选文件 → 填页码范围 → 预览勾选）。
/// 所以入口放在设置里；科目面板只留「选哪个语料出题」这一个出题参数。
///
/// 这一页是语料库的**唯一**管理入口：导入（教材 PDF / 语料 JSON / 拍照）、
/// 导出、新建 / 重命名 / 删除 / 清空、设为当前、归档目标。
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ai/ai_client.dart';
import '../ai/ai_generator.dart';
import '../core/textbook_structurer.dart';
import '../data/app_data.dart';
import '../data/corpus_store.dart';
import 'export_file.dart';
import 'pdf_import_flow.dart';

const _kBlue = Color(0xff2f6fd0);
const _kGrey = Color(0xff888888);
const _kLightGrey = Color(0xff999999);

class CorpusPage extends StatefulWidget {
  /// 当前「教材与进度」的选择 —— 新导入的语料按它打版本/年级/册标签。
  final String version;
  final int grade;
  final String volume;

  const CorpusPage({
    super.key,
    required this.version,
    required this.grade,
    required this.volume,
  });

  @override
  State<CorpusPage> createState() => _CorpusPageState();
}

class _CorpusPageState extends State<CorpusPage> {
  /// 只放用户语料 —— 内置课文语料是应用按当前年级/册现合成的，不在这儿管
  List<Corpus> _corpora = [];
  String? _activeId;
  String? _captureId;

  /// 分段导入的进度（每个语料各自一份），只活在本次会话里
  final Map<String, List<TextbookParseResult>> _segments = {};

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await CorpusStore.loadCorpora();
    final active = await CorpusStore.loadActiveId();
    final capture = await CorpusStore.loadCaptureId();
    if (!mounted) return;
    setState(() {
      _corpora = [
        for (final c in all)
          if (c.origin != 'bundled') c,
      ];
      _activeId = active;
      _captureId = capture;
    });
  }

  Corpus? _byId(String? id) {
    if (id == null) return null;
    for (final c in _corpora) {
      if (c.id == id) return c;
    }
    return null;
  }

  Corpus? get _active => _byId(_activeId);
  Corpus? get _capture => _byId(_captureId);

  Future<void> _persist() async {
    await CorpusStore.saveCorpora(_corpora);
    await CorpusStore.saveActiveId(_activeId);
    await CorpusStore.saveCaptureId(_captureId);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _gradeName(int? g) =>
      g == null ? '' : (AppData().gradeNames[g] ?? '$g年级');

  String _defaultName() =>
      '${AppData().textbooks[widget.version]?.name ?? widget.version}'
      '${_gradeName(widget.grade)}'
      '${widget.volume == '下' ? '下册' : '上册'}';

  String get _contextText => '${AppData().textbooks[widget.version]?.name ?? widget.version}'
      ' · ${_gradeName(widget.grade)} · ${widget.volume == '下' ? '下册' : '上册'}';

  // -------------------------------------------------------------------------
  // 列表操作
  // -------------------------------------------------------------------------

  Future<void> _setActive(Corpus c) async {
    setState(() {
      _activeId = c.id;
      _captureId ??= c.id; // 没设过归档目标时跟着走
    });
    await _persist();
    _snack('当前语料已切到「${c.name}」，语文面板将用它出题');
  }

  Future<void> _setCapture(Corpus c) async {
    setState(() => _captureId = c.id);
    await CorpusStore.saveCaptureId(_captureId);
    _snack('导入的课文将归档到「${c.name}」');
  }

  Future<Corpus?> _newCorpus() async {
    final ctrl = TextEditingController(text: _defaultName());
    final created = await showDialog<Corpus>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建语料库'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('名称',
                style: TextStyle(fontSize: 13, color: _kGrey)),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: '如 统编版语文三年级上册',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('将按当前「教材与进度」创建：$_contextText',
                style: const TextStyle(fontSize: 12, color: _kLightGrey)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              Navigator.pop(
                ctx,
                Corpus(
                  name: name.isNotEmpty ? name : _defaultName(),
                  version: widget.version,
                  grade: widget.grade,
                  volume: widget.volume,
                  origin: 'imported-json',
                ),
              );
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (created == null) return null;
    setState(() {
      _corpora = [..._corpora, created];
      _activeId = created.id;
      _captureId = created.id;
    });
    await _persist();
    _snack('已新建语料库：${created.name}');
    return created;
  }

  Future<void> _rename(Corpus c) async {
    final ctrl = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名语料库'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == c.name) return;
    setState(() => c.name = name);
    await CorpusStore.saveCorpora(_corpora);
    _snack('已重命名为「$name」');
  }

  /// 删除语料库（连同它的内容）。
  Future<void> _delete(Corpus c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除语料库'),
        content: Text('确定删除「${c.name}」（${c.items.length} 篇）吗？此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _corpora = [
        for (final x in _corpora)
          if (x.id != c.id) x,
      ];
      _segments.remove(c.id);
      if (_activeId == c.id) _activeId = _corpora.isEmpty ? null : _corpora.first.id;
      if (_captureId == c.id) _captureId = _activeId;
    });
    await _persist();
    _snack('已删除「${c.name}」');
  }

  /// 清空内容但保留语料库本身。
  Future<void> _clear(Corpus c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空内容'),
        content: Text('确定清空「${c.name}」的 ${c.items.length} 篇课文吗？语料库本身会保留。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      c.items = [];
      _segments.remove(c.id);
    });
    await CorpusStore.saveCorpora(_corpora);
    _snack('已清空「${c.name}」');
  }

  /// 导出语料库为 .json，可原样导回并直接使用（见 `_importJson`）。
  Future<void> _export(Corpus c) async {
    if (c.items.isEmpty) {
      _snack('「${c.name}」还没有内容，无需导出。');
      return;
    }
    final content = json.encode(CorpusFile.encode(c));
    final safe = c.name.replaceAll(RegExp(r'''[\\/:*?"<>|\s]+'''), '_');
    final ts = DateTime.now().millisecondsSinceEpoch;
    try {
      await saveJsonFile('课文库_${safe}_$ts.json', content, 'application/json');
      _snack('已导出「${c.name}」（${c.items.length} 篇）。'
          '该文件可在任意设备的「导入语料(.json)」里直接导入使用。');
    } catch (e) {
      _snack('导出失败：$e');
    }
  }

  // -------------------------------------------------------------------------
  // 导入
  // -------------------------------------------------------------------------

  /// 确保有归档目标；没有就先问要不要新建。
  Future<Corpus?> _ensureTarget() async {
    final t = _capture;
    if (t != null) return t;
    if (_corpora.isEmpty) {
      final created = await _newCorpus();
      return created;
    }
    setState(() => _captureId = _corpora.first.id);
    await CorpusStore.saveCaptureId(_captureId);
    _snack('已把「${_corpora.first.name}」设为归档目标');
    return _corpora.first;
  }

  /// 导入教材 PDF：整本或按页码范围 → 结构化课文 → 合并归档。
  ///
  /// **零 AI 成本**：走 PDF 自带文本层（剔拼音注音、按坐标拼回被注音打断的行、
  /// 去跨页水印），不调用任何模型。对扫描图片版无效 —— 那种得先 OCR，或改用拍照导入。
  Future<void> _importPdf() async {
    final target = await _ensureTarget();
    if (target == null || !mounted) return;
    final previous = _segments[target.id] ?? const <TextbookParseResult>[];
    if (mounted) setState(() => _busy = true);
    try {
      final outcome = await importTextbookPdf(
        context,
        previous: previous,
        fallbackName: target.name,
      );
      if (outcome == null) return; // 用户取消，或流程内已提示过原因

      final res = mergeCorpusItems(
        target.items,
        outcome.items,
        fileSource: 'licensed',
        corpusVersion: target.version,
        corpusGrade: target.grade,
        corpusVolume: target.volume,
      );
      target.items = res.$1;
      if (target.source.isEmpty) target.source = 'licensed';
      target.origin = 'imported-pdf';
      _segments[target.id] = outcome.segments;

      setState(() {
        _activeId = target.id;
        _captureId = target.id;
      });
      await _persist();

      final cut = outcome.picked.where((l) => l.cutOff).toList();
      _snack('已导入第 ${outcome.firstPage}–${outcome.lastPage} 页'
          '（共 ${outcome.totalPages} 页）：新增 ${res.$2} 篇 / 更新 ${res.$3} 篇，'
          '该教材累计 ${outcome.totalLessons} 课。'
          '${cut.isEmpty ? '' : '「${cut.first.title}」正文被页码区间切断。'}'
          '${outcome.suggestNextPage == 0 ? '已到最后一页，导入完成。' : '下次可从第 ${outcome.suggestNextPage} 页继续导入。'}');
    } catch (e) {
      _snack('PDF 导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;

    Object? decoded;
    try {
      decoded = json.decode(utf8.decode(f.bytes!));
    } catch (e) {
      _snack('这个文件不是合法 JSON：$e');
      return;
    }
    final data = CorpusFile.decode(decoded);
    if (data == null) {
      _snack('格式不正确：需包含 items 数组');
      return;
    }
    if (data.items.isEmpty) {
      _snack('这个文件里没有条目，未导入。');
      return;
    }
    if (!mounted) return;

    // 默认「新建同名语料库」—— 导出的文件在任何设备上都该能直接导入使用
    final same = <Corpus>[
      for (final c in _corpora)
        if (c.name == data.name) c,
    ];
    final choice = await _askImportTarget(
      data: data,
      sameName: same.isEmpty ? null : same.first,
      active: _active,
    );
    if (choice == null) {
      _snack('已取消导入');
      return;
    }

    try {
      late final Corpus target;
      var note = '';
      if (choice == 'new') {
        target = Corpus(
          name: data.name,
          version: data.version,
          grade: data.grade,
          volume: data.volume,
          source: data.source,
          origin: 'imported-json',
          items: data.items,
        );
        _corpora.add(target);
      } else {
        target = choice == 'same' ? same.first : _active!;
        if (choice == 'replace') {
          target.items = data.items;
        } else {
          final res = mergeCorpusItems(
            target.items,
            data.items,
            fileSource: data.source,
            corpusVersion: data.version.isEmpty ? target.version : data.version,
            corpusGrade: data.grade ?? target.grade,
            corpusVolume: data.volume ?? target.volume,
          );
          target.items = res.$1;
          note = '（新增 ${res.$2} 篇 / 更新 ${res.$3} 篇）';
        }
        // 库级元数据也补齐，否则将来「按册过滤出题范围」拿不到册次
        if (target.version.isEmpty && data.version.isNotEmpty) {
          target.version = data.version;
        }
        if (target.grade == null && data.grade != null) target.grade = data.grade;
        if (target.volume == null && data.volume != null) {
          target.volume = data.volume;
        }
        if (target.source.isEmpty) target.source = data.source;
      }

      setState(() {
        _activeId = target.id;
        _captureId = target.id;
      });
      await _persist();
      _snack('已导入「${target.name}」$note，共 ${target.items.length} 篇，'
          '并已设为当前语料，可直接出题。');
    } catch (e) {
      _snack('导入失败：$e');
    }
  }

  Future<String?> _askImportTarget({
    required CorpusFileData data,
    required Corpus? sameName,
    required Corpus? active,
  }) async {
    final meta = <String>[
      '${data.items.length} 篇',
      if (data.version.isNotEmpty) data.version,
      if (data.grade != null) '${_gradeName(data.grade)}${data.volume ?? ''}',
      if (data.source == 'licensed')
        '已声明课本授权'
      else if (data.source == 'original')
        '原创内容',
    ];
    final options = <(String, String, String)>[
      if (sameName != null)
        ('same', '覆盖同名语料库「${sameName.name}」',
            '现有 ${sameName.items.length} 篇将被文件内容替换')
      else
        ('new', '新建语料库「${data.name}」', '导入后直接设为当前语料'),
      if (active != null)
        ('merge', '合并到「${active.name}」',
            '现有 ${active.items.length} 篇，按课文去重后并入'),
      if (active != null)
        ('replace', '替换「${active.name}」的内容',
            '现有 ${active.items.length} 篇将被文件内容替换'),
    ];

    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('导入「${data.name}」'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(meta.join(' · '),
                style: const TextStyle(fontSize: 12, color: _kGrey)),
          ),
          for (final o in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, o.$1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.$2, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(o.$3,
                      style: const TextStyle(fontSize: 11, color: _kLightGrey)),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 拍照 / 相册导入：视觉模型把课本页照片结构化成课文条目。
  Future<void> _importPhoto(ImageSource source) async {
    final target = await _ensureTarget();
    if (target == null) return;
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    if (file == null) return;
    if (mounted) setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final incoming = await _structurePage(b64);
      if (incoming == null) return; // 已在内部提示过原因
      final res = mergeCorpusItems(
        target.items,
        incoming,
        fileSource: 'licensed',
        corpusVersion: target.version,
        corpusGrade: target.grade,
        corpusVolume: target.volume,
      );
      target.items = res.$1;
      if (target.source.isEmpty) target.source = 'licensed';
      target.origin = 'photo';
      setState(() {
        _activeId = target.id;
        _captureId = target.id;
      });
      await _persist();
      _snack('已识别并归档到「${target.name}」：新增 ${res.$2} 篇 / 更新 ${res.$3} 篇'
          '（累计 ${target.items.length} 篇）');
    } catch (e) {
      _snack('拍照导入失败：${aiFriendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 一页课本图片 → 结构化条目。
  ///
  /// 返回 null 表示**已在内部提示过原因**，调用方直接返回、不要重复报错。
  /// 入库合并由调用方负责 —— 这里只做「图片 → 条目」这一件事。
  Future<List<Map<String, dynamic>>?> _structurePage(String imageBase64) async {
    final cfg = await AiStore.load();
    if (cfg.base.isEmpty || cfg.model.isEmpty) {
      _snack('请先在设置 →「AI 模型」中填好 API 与模型，并选用支持看图的多模态大模型'
          '（如 qwen-vl-max / glm-4v / gpt-4o）；纯文本模型无法识别图片。');
      return null;
    }
    const prompt = '你是一名小学课本排版识别助手。下面是小学课本（语文或英语）的一页照片。'
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
      imageBase64: imageBase64,
      jsonMode: true,
    );
    final data = aiExtractJson(content);
    final items = data['items'];
    if (items is! List || items.isEmpty) {
      _snack('未识别到课文，请换一张更清晰或正文更完整的页面试试。');
      return null;
    }
    final out = <Map<String, dynamic>>[];
    for (final e in items) {
      if (e is Map) {
        final m = <String, dynamic>{};
        e.forEach((k, v) => m['$k'] = v);
        out.add(m);
      }
    }
    return out;
  }

  /// 下载一份语料文件模板，便于手写/程序生成。
  Future<void> _downloadSample() async {
    final sample = json.encode({
      CorpusFile.schemaKey: CorpusFile.schemaVersion,
      'name': '我的课文库',
      'version': widget.version,
      'grade': widget.grade,
      'volume': widget.volume,
      'source': 'licensed',
      'items': [
        {
          'unit': '第一单元',
          'title': '示例课文标题',
          'author': '',
          'text': '课文正文（请填入你拥有合法使用权的材料）。',
          'questions': [
            {'q': '示例问题？', 'a': '示例答案'}
          ],
        }
      ],
    });
    try {
      await saveJsonFile('课文库_模板.json', sample, 'application/json');
      _snack('已下载模板。填入内容后可用「导入语料(.json)」导回。');
    } catch (e) {
      _snack('下载模板失败：$e');
    }
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('教材语料库')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          const Text(
            '导入教材是全局设置：选哪个语料，语文面板就用它出课文阅读题。'
            '教材不止语文有，所以入口在这里，不在某个科目面板里。',
            style: TextStyle(fontSize: 12, color: _kLightGrey, height: 1.6),
          ),
          const SizedBox(height: 4),
          Text('当前「教材与进度」：$_contextText（导入的语料按它打版本/年级/册标签）',
              style: const TextStyle(fontSize: 12, color: _kLightGrey, height: 1.6)),
          const SizedBox(height: 14),

          // ---- 导入 ----
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('导入',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Text(
                    '归档到：${_capture?.name ?? '（未选择，导入时会先让你建一个）'}',
                    style: const TextStyle(fontSize: 12, color: _kGrey),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _importPdf,
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: const Text('导入教材 PDF（自动切分单元与课）'),
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '带文本层的教材 PDF（出版社电子版）走上面这条：零 AI 成本，可按页码范围分次导入。\n'
                    '其余方式：拍照 / 相册由 AI 识别并归档；也可导入 .json 语料文件。',
                    style: TextStyle(
                        fontSize: 11, color: _kLightGrey, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _importPhoto(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: const Text('拍照导入'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _importPhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library, size: 16),
                        label: const Text('相册导入'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _importJson,
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: const Text('导入语料(.json)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _downloadSample,
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('下载模板'),
                      ),
                    ],
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('正在处理，请稍候…',
                            style: TextStyle(fontSize: 12, color: _kBlue)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ---- 语料库列表 ----
          Row(
            children: [
              const Text('语料库',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              Text('${_corpora.length} 个',
                  style: const TextStyle(fontSize: 12, color: _kLightGrey)),
              const Spacer(),
              TextButton.icon(
                onPressed: _busy ? null : _newCorpus,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_corpora.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '还没有语料库。点上面的「导入教材 PDF」，或右上角「新建」先建一个空库。',
                style: TextStyle(fontSize: 13, color: _kLightGrey, height: 1.6),
              ),
            )
          else
            for (final c in _corpora) _corpusCard(c),

          const SizedBox(height: 14),
          const Text(
            '⚠️ 请只导入您拥有合法使用权的课文内容，使用受版权保护的课文请自行向版权方付费。',
            style: TextStyle(fontSize: 11, color: _kLightGrey, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _corpusCard(Corpus c) {
    final isActive = c.id == _activeId;
    final isCapture = c.id == _captureId;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: isActive ? _kBlue : const Color(0xffe0e0e0),
            width: isActive ? 1.2 : 0.5),
      ),
      child: InkWell(
        onTap: () => _setActive(c),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(c.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xffe8f0fc),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('当前',
                          style: TextStyle(fontSize: 11, color: _kBlue)),
                    ),
                  if (isCapture)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Text('归档目标',
                          style: TextStyle(fontSize: 11, color: Color(0xff2e7d32))),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                [
                  '${c.items.length} 篇',
                  corpusOriginTag(c.origin),
                  corpusSourceTag(c.source),
                  if (c.grade != null) '${_gradeName(c.grade)}${c.volume ?? ''}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: _kGrey),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _setActive(c),
                    child: const Text('设为当前', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: () => _setCapture(c),
                    child: const Text('设为归档目标',
                        style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: () => _export(c),
                    child: const Text('导出', style: TextStyle(fontSize: 12)),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    onSelected: (v) {
                      switch (v) {
                        case 'rename':
                          _rename(c);
                          break;
                        case 'clear':
                          _clear(c);
                          break;
                        case 'delete':
                          _delete(c);
                          break;
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'clear', child: Text('清空内容')),
                      PopupMenuItem(value: 'delete', child: Text('删除语料库')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
