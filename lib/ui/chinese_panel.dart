import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../data/app_data.dart';
import '../data/corpus_store.dart';
import '../data/type_count_store.dart';
import '../core/chinese_worksheet.dart';
import '../core/type_catalog.dart';
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

  /// 多语料：具名语料集合
  List<Corpus> _corpora = [];
  /// 当前活跃语料（驱动生成）
  String? _activeId;
  /// 常驻采集目标（sticky：导入/拍照归档到此，跨会话保持）
  String? _captureId;
  // 内置课文现以「内置语料」形式直接出现在语料下拉中，无需回退开关

  @override
  void initState() {
    super.initState();
    // 选「统编版」时，阅读理解默认基于统编版课文出题（课文阅读）
    _useTextbook = const {'tongbiao', 'hebei', 'renjiao'}.contains(widget.version);
    _loadCounts();
    _initCorpora();
  }

  /// 加载语料集合 + 活跃/采集目标，并做校验与默认初始化
  Future<void> _initCorpora() async {
    await AppData().load();
    final stored = await CorpusStore.loadCorpora();
    // 用户语料（持久化在 SharedPreferences）；内置课文为 bundled，运行时由 AppData 合成，不持久化
    final userCorpora = stored.where((c) => c.origin != 'bundled').toList();
    final bundled = _buildBundledCorpora();

    if (userCorpora.isEmpty) {
      // 首次使用：自动建一个与当前面板对应的空语料，作为默认采集/生成目标
      final c = Corpus(
        name: _defaultCorpusName(),
        version: widget.version,
        grade: widget.grade,
        volume: widget.volume,
        origin: 'imported-json',
      );
      userCorpora.add(c);
      _activeId = c.id;
      _captureId = c.id;
    } else {
      // 活跃/采集目标仅在用户语料范围内解析（内置课文需用户显式选择，不与导入语料混淆）
      if (_activeId == null || !userCorpora.any((c) => c.id == _activeId)) {
        _activeId = _resolveActiveId();
      }
      if (_captureId == null || !userCorpora.any((c) => c.id == _captureId)) {
        _captureId = _activeId;
      }
    }
    _corpora = [...bundled, ...userCorpora]; // 先赋值，供 _resolveActiveId 使用
    await CorpusStore.saveCorpora(userCorpora);
    await CorpusStore.saveActiveId(_activeId);
    await CorpusStore.saveCaptureId(_captureId);
    _loadCorpusStatus();
    _regenerate();
    if (mounted) setState(() {});
  }

  String _defaultCorpusName() {
    final tb = AppData().textbooks[widget.version];
    final gname = AppData().gradeNames[widget.grade] ?? '第${widget.grade}年级';
    final volName = widget.volume == '下' ? '下册' : '上册';
    return '${tb?.name ?? '教材'}$gname$volName';
  }

  Corpus? _activeCorpus() {
    if (_activeId == null) return null;
    for (final c in _corpora) {
      if (c.id == _activeId) return c;
    }
    return null;
  }

  Corpus? _captureCorpus() {
    if (_captureId == null) return null;
    for (final c in _corpora) {
      if (c.id == _captureId) return c;
    }
    return null;
  }

  /// 内置课文语料：从 AppData 按当前版本/年级/册取出真实课文，合成与导入语料同结构的 Corpus。
  /// 不持久化（每次按当前面板范围合成，始终与内置数据一致）；出现在「生成用语料」下拉中即可直接选。
  List<Corpus> _buildBundledCorpora() {
    final data = AppData();
    const versions = ['tongbiao', 'hebei', 'renjiao']; // 含正文的语文内置课文
    final gname = data.gradeNames[widget.grade] ?? '第${widget.grade}年级';
    final volName = widget.volume == '下' ? '下册' : '上册';
    final out = <Corpus>[];
    for (final v in versions) {
      final texts = data.yuwenTextsFor(v, widget.grade, widget.volume);
      if (texts.isEmpty) continue;
      final items = <Map<String, dynamic>>[];
      for (final t in texts) {
        if (t.text.trim().isEmpty) continue;
        items.add({
          'grade': t.grade,
          'volume': t.volume,
          'unit': t.unit,
          'title': t.title,
          'text': t.text,
          'source': 'builtin',
        });
      }
      if (items.isEmpty) continue;
      final tb = data.textbooks[v];
      out.add(Corpus(
        id: 'builtin:$v',
        name: '${tb?.name ?? '教材'}内置课文（$gname$volName）',
        version: v,
        grade: widget.grade,
        volume: widget.volume,
        source: 'builtin',
        origin: 'bundled',
        items: items,
      ));
    }
    return out;
  }

  /// 根据当前面板 version/grade/volume 解析应使用哪个语料作为活跃语料。
  /// 优先级（非空优先，避免跳到空语料导致「暂无外置语料」）：
  ///   精确非空 > 同版本非空 > 当前活跃非空 > 精确(可空) > 同版本(可空) > 首个非空 > 首个。
  String? _resolveActiveId() {
    if (_corpora.isEmpty) return null;
    Corpus? exactNE, verNE, curNE, exactAny, verAny, firstNE;
    final cur = _activeCorpus();
    for (final c in _corpora) {
      if (c.origin == 'bundled') continue;
      final exact = c.version == widget.version &&
          c.grade == widget.grade &&
          c.volume == widget.volume;
      final sameVer = c.version == widget.version;
      final ne = c.items.isNotEmpty;
      if (exact && ne) exactNE ??= c;
      if (sameVer && ne) verNE ??= c;
      if (exact) exactAny ??= c;
      if (sameVer) verAny ??= c;
      if (ne) {
        firstNE ??= c;
        if (cur != null && c.id == cur.id) curNE = c;
      }
    }
    final pick = exactNE ??
        verNE ??
        curNE ??
        exactAny ??
        verAny ??
        firstNE ??
        _corpora.first;
    return pick.id;
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
      // 切换版本/年级/册时重新解析活跃语料，否则 _activeId 会停留在旧范围，
      // 导致「选统编却显示旧语料」或外置语料阅读被 grade/volume 过滤掉。
      // 重新合成内置课文语料（按新版本/年级/册），保持与当前面板一致
      final userCorpora = _corpora.where((c) => c.origin != 'bundled').toList();
      final bundled = _buildBundledCorpora();
      _corpora = [...bundled, ...userCorpora];
      CorpusStore.saveCorpora(userCorpora);
      // 活跃/采集目标仅在用户语料范围内解析（内置需显式选择）
      if (_activeId == null || !userCorpora.any((c) => c.id == _activeId)) {
        _activeId = _resolveActiveId();
      }
      if (_captureId == null || !userCorpora.any((c) => c.id == _captureId)) {
        _captureId = _activeId;
      }
      CorpusStore.saveActiveId(_activeId);
      CorpusStore.saveCaptureId(_captureId);
      _loadCounts();
    }
  }

  /// 当前年级下可用的题型。唯一来源：TypeCatalog。
  List<TypeSpec> get _specs => TypeCatalog.of(
        Subject.chinese,
        version: widget.version,
        grade: widget.grade,
      );

  List<String> get _typeIds => _specs.map((t) => t.id).toList();

  /// 当前年级不可用的题型。用于在界面上说明「为什么少了几个」，
  /// 而不是让选项凭空消失（旧实现是 removeWhere 静默丢弃）。
  List<TypeSpec> get _hiddenSpecs => TypeCatalog.of(
        Subject.chinese,
        version: widget.version,
        grade: widget.grade,
        includeUnavailable: true,
      ).where((t) => !t.available).toList();

  /// 读取全局题量偏好并按当前目录补齐缺失项。
  ///
  /// 已存在的值（含 0 = 用户主动取消）一律保留——旧实现用 `removeWhere` 直接丢弃
  /// 失效题型、又不持久化，切一次版本就全没了。
  Future<void> _loadCounts() async {
    final seeded = await TypeCountStore.loadSeeded(Subject.chinese, _specs);
    if (!mounted) return;
    setState(() {
      _counts
        ..clear()
        ..addAll(seeded);
    });
    _regenerate();
  }

  Future<void> _persistCounts() =>
      TypeCountStore.save(Subject.chinese, _counts);

  List<ReadingBlockData> get _corpus {
    final c = _activeCorpus();
    if (c == null) return [];
    final corpusSrc = c.source;
    final corpusVer = c.version;
    return [
      for (final it in c.items)
        ReadingBlockData(
          title: '${it['title'] ?? ''}',
          author: '${it['author'] ?? ''}',
          text: '${it['text'] ?? ''}',
          en: it['en'] == true,
          isListening: it['isListening'] == true,
          grade: it['grade'] is num ? (it['grade'] as num).toInt() : null,
          volume: it['volume'] is String ? it['volume'] as String : null,
          version: (() {
            final v = '${it['version'] ?? ''}';
            return v.isNotEmpty ? v : (corpusVer.isNotEmpty ? corpusVer : null);
          })(),
          source: (() {
            final s = '${it['source'] ?? ''}';
            return s.isNotEmpty ? s : corpusSrc;
          })(),
          questions: [
            for (final q in (it['questions'] is List ? it['questions'] as List : []))
              if (q is Map)
                ReadingQuestion('${q['q'] ?? ''}', '${q['a'] ?? ''}')
          ],
        )
    ];
  }

  // ---- 语料合并 / 去重辅助 ----
  /// 去重键包含 version，避免不同版本同册同标题撞车
  String _itemKey(Map<String, dynamic> m) {
    final ver = '${m['version'] ?? ''}'.trim();
    final g = m['grade'];
    final v = '${m['volume'] ?? ''}'.trim();
    final u = '${m['unit'] ?? ''}'.trim();
    final t = '${m['title'] ?? ''}'.trim().toLowerCase();
    return '$ver#$g#$v#$u#$t';
  }

  List<dynamic> _mergeQuestions(dynamic eq, dynamic iq) {
    final out = <dynamic>[];
    final seen = <String>{};
    void addQ(dynamic q) {
      if (q is! Map) return;
      final qq = '${q['q'] ?? ''}'.trim();
      if (qq.isEmpty) return;
      if (seen.contains(qq)) return;
      seen.add(qq);
      out.add(q);
    }
    if (eq is List) {
      for (final q in eq) {
        addQ(q);
      }
    }
    if (iq is List) {
      for (final q in iq) {
        addQ(q);
      }
    }
    return out;
  }

  /// 合并两组条目：按 (version,grade,volume,unit,title) 去重；命中则合并字段（取更长正文、合并题目）。
  /// corpus 的 version/grade/volume 作为缺省为缺值项盖章，保证去重键一致且覆盖度可算。
  /// 返回 (合并后条目, 新增数, 更新数)。
  (List<Map<String, dynamic>>, int, int) _mergeItems(
      List<Map<String, dynamic>> existing,
      List<Map<String, dynamic>> incoming,
      {String fileSource = '',
      String corpusVersion = '',
      int? corpusGrade,
      String? corpusVolume}) {
    final map = <String, Map<String, dynamic>>{};
    for (final e in existing) {
      final m = <String, dynamic>{};
      e.forEach((k, v) => m[k] = v);
      map[_itemKey(m)] = m;
    }
    var added = 0, updated = 0;
    for (final inc in incoming) {
      final m = <String, dynamic>{};
      inc.forEach((k, v) => m[k] = v);
      if (corpusVersion.isNotEmpty && '${m['version'] ?? ''}'.isEmpty) {
        m['version'] = corpusVersion;
      }
      if (corpusGrade != null && m['grade'] == null) m['grade'] = corpusGrade;
      if (corpusVolume != null && '${m['volume'] ?? ''}'.isEmpty) {
        m['volume'] = corpusVolume;
      }
      final k = _itemKey(m);
      if (map.containsKey(k)) {
        final ex = map[k]!;
        final et = '${ex['text'] ?? ''}', it = '${m['text'] ?? ''}';
        if (it.length > et.length) ex['text'] = it;
        if ('${ex['unit'] ?? ''}'.isEmpty) ex['unit'] = m['unit'];
        if ('${ex['author'] ?? ''}'.isEmpty) ex['author'] = m['author'];
        ex['grade'] = ex['grade'] ?? m['grade'];
        if ('${ex['volume'] ?? ''}'.isEmpty) ex['volume'] = m['volume'];
        final es = '${ex['source'] ?? ''}', ins = '${m['source'] ?? ''}';
        ex['source'] = es.isNotEmpty ? es : ins;
        ex['questions'] = _mergeQuestions(ex['questions'], m['questions']);
        updated++;
      } else {
        if ('${m['source'] ?? ''}'.isEmpty) m['source'] = fileSource;
        map[k] = m;
        added++;
      }
    }
    return (map.values.toList(), added, updated);
  }

  String _sourceTag(String s) {
    if (s == 'original') return '原创·非版权';
    if (s == 'licensed') return '版权自负·已确认授权';
    if (s == 'builtin') return '内置课文';
    return '版权自负';
  }

  /// 基于内置教材目录计算覆盖度（已录入/总课数）；缺版本或年级/册时无意义则返回 ''
  String _coverageHint(Corpus c) {
    if (c.version.isEmpty || c.grade == null || c.volume == null) return '';
    final idx = AppData().yuwenTextsFor(c.version, c.grade!, c.volume!);
    if (idx.isEmpty) return '';
    final have = <String>{};
    for (final it in c.items) {
      final t = '${it['title'] ?? ''}'.trim().toLowerCase();
      if (t.isNotEmpty) have.add(t);
    }
    final covered =
        idx.where((t) => have.contains(t.title.trim().toLowerCase())).length;
    return ' ｜ 覆盖 $covered/${idx.length} 课';
  }

  Future<void> _loadCorpusStatus() async {
    final c = _activeCorpus();
    if (mounted) {
      setState(() {
        if (c == null) {
          _corpusStatus = '未创建语料库';
          return;
        }
        final n = c.items.length;
        _corpusStatus = '当前语料：${c.name}（$n 篇，${_sourceTag(c.source)}）'
            '${_coverageHint(c)}';
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
      customCorpus: _corpus,
    );
  }

  void _refresh() {
    setState(_regenerate);
  }

  /// 当前活跃语料是否存在「没有预置题目」的条目（内置课文语料即属于此类）。
  bool get _corpusNeedsQuestions {
    final c = _activeCorpus();
    if (c == null) return false;
    return c.items.any((it) {
      if (it['_qaSkip'] == true) return false; // 已重试仍失败，避免每次生成都重复调用
      final qs = it['questions'];
      return qs is! List || qs.isEmpty;
    });
  }

  /// 为活跃语料中「无题目」的条目用 AI 基于本地正文逐篇补题。
  /// 题目直接写回语料条目（内存态），随后 _regenerate 即渲染带题目的阅读页。
  Future<void> _enrichCorpusQuestions() async {
    final c = _activeCorpus();
    if (c == null) {
      _refresh();
      return;
    }
    if (mounted) setState(() => _loading = true);
    final cfg = await AiStore.load();
    if (cfg.base.isEmpty || cfg.model.isEmpty) {
      _showSnack('该语料尚无题目：请先在顶部「AI 智能出题设置」中配置 API 与模型，'
          '再点「生成预览」即可自动为课文生成阅读理解题与答案。');
      return;
    }
    try {
      final items = c.items;
      final targets = <int>[];
      for (var i = 0; i < items.length; i++) {
        final qs = items[i]['questions'];
        if (qs is! List || qs.isEmpty) targets.add(i);
      }
      if (targets.isEmpty) {
        _regenerate();
        return;
      }
      var skipped = 0;
      for (final i in targets) {
        final it = items[i];
        final text = '${it['text'] ?? ''}'.trim();
        if (text.isEmpty) continue;
        final title = '${it['title'] ?? ''}';
        var gen = await aiGenerateQuestionsForPassage(
          title: title,
          text: text,
          grade: widget.grade,
          count: 3,
        );
        if (gen.isEmpty) {
          // 弱模型偶发空返回，重试一次以提高成功率（直接命中用户「答案不生成」的痛点）
          gen = await aiGenerateQuestionsForPassage(
            title: title,
            text: text,
            grade: widget.grade,
            count: 3,
          );
        }
        if (gen.isEmpty) {
          skipped++;
          items[i] = <String, dynamic>{...it, '_qaSkip': true};
          continue;
        }
        items[i] = <String, dynamic>{
          ...it,
          'questions': [
            for (final q in gen) {'q': q.q, 'a': q.a}
          ],
        };
      }
      if (skipped > 0) {
        _showSnack('有 $skipped 篇未生成题目（模型返回为空），可稍后重试');
      }
      _regenerate();
    } catch (e) {
      _showSnack('语料出题失败：${aiFriendlyError(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    final wantAI = (_counts['aiyuedu'] ?? 0) > 0;
    final wantCorpus = (_counts['duanwen'] ?? 0) > 0;
    // 语料（课文阅读）条目若无题目，先用 AI 基于本地正文补题，再渲染
    if (wantCorpus && _corpusNeedsQuestions) {
      await _enrichCorpusQuestions(); // 内部已 _regenerate
      if (wantAI) await _generateAIReading();
      return;
    }
    if (wantAI) {
      await _generateAIReading();
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
      final decoded = json.decode(utf8.decode(f.bytes!));
      if (decoded is! Map<String, dynamic> || decoded['items'] is! List) {
        _showSnack('格式不正确：需包含 items 数组');
        return;
      }
      String fileSource = '${decoded['source'] ?? ''}';
      if (fileSource != 'original' && fileSource != 'licensed') {
        final name = '${decoded['name'] ?? ''}';
        if (name.contains('原创') ||
            name.contains('非版权') ||
            name.contains('原创生成')) {
          fileSource = 'original';
        } else {
          fileSource = '';
        }
      }
      final incoming = <Map<String, dynamic>>[];
      for (final e in decoded['items'] as List) {
        if (e is Map) {
          final m = <String, dynamic>{};
          (e).forEach((k, v) => m['$k'] = v);
          incoming.add(m);
        }
      }
      // 合并进「常驻采集目标」（sticky），分多次导入始终落到同一本
      final target = _captureCorpus();
      if (target == null) {
        _showSnack('无采集目标，请先新建语料库');
        return;
      }
      if (target.items.isNotEmpty) {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('导入到「${target.name}」'),
            content: const Text('该语料已有内容。要合并到现有语料，还是替换为该文件？'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'merge'),
                  child: const Text('合并')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'replace'),
                  child: const Text('替换')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text('取消')),
            ],
          ),
        );
        if (choice == null || choice == 'cancel') {
          _showSnack('已取消导入');
          return;
        }
        if (choice == 'merge') {
          final res = _mergeItems(target.items, incoming,
              fileSource: fileSource,
              corpusVersion: target.version,
              corpusGrade: target.grade,
              corpusVolume: target.volume);
          target.items = res.$1;
          _showSnack('已合并：新增 ${res.$2} 篇 / 更新 ${res.$3} 篇');
        } else {
          target.items = incoming;
          for (final m in target.items) {
            if ('${m['source'] ?? ''}'.isEmpty) m['source'] = fileSource;
          }
          _showSnack('已替换：${target.items.length} 篇');
        }
      } else {
        final res = _mergeItems([], incoming,
            fileSource: fileSource,
            corpusVersion: target.version,
            corpusGrade: target.grade,
            corpusVolume: target.volume);
        target.items = res.$1;
        _showSnack('已导入：${target.items.length} 篇');
      }
      // 导入成功后让该语料成为「活跃语料」，保证「导入即出阅读」（阅读读取活跃语料，避免采集目标与活跃不一致时读不到）
      _activeId = target.id;
      // 采集目标保持为该语料（sticky）
      _captureId = target.id;
      await CorpusStore.saveActiveId(_activeId);
      await CorpusStore.saveCaptureId(_captureId);
      await CorpusStore.saveCorpora(_corpora.where((c) => c.origin != 'bundled').toList());
      _loadCorpusStatus();
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
        imageBase64: b64,
        jsonMode: true,
      );
      final data = aiExtractJson(content);
      final items = data['items'];
      if (items is! List || items.isEmpty) {
        _showSnack('未识别到课文，请换一张更清晰或正文更完整的页面试试。');
        return;
      }
      // 合并进「常驻采集目标」（分页/重拍可累积，按课文身份去重；sticky 保证多次拍摄落到同一本）
      final target = _captureCorpus();
      if (target == null) {
        _showSnack('无采集目标，请先新建语料库');
        return;
      }
      final incoming = <Map<String, dynamic>>[];
      for (final e in items) {
        if (e is Map) {
          final m = <String, dynamic>{};
          (e).forEach((k, v) => m['$k'] = v);
          incoming.add(m);
        }
      }
      final res = _mergeItems(target.items, incoming,
          fileSource: 'licensed',
          corpusVersion: target.version,
          corpusGrade: target.grade,
          corpusVolume: target.volume);
      target.items = res.$1;
      if (target.source.isEmpty) target.source = 'licensed';
      target.origin = 'photo';
      // 导入成功后让该语料成为「活跃语料」，保证「导入即出阅读」
      _activeId = target.id;
      // 采集目标保持为该语料（sticky）
      _captureId = target.id;
      await CorpusStore.saveActiveId(_activeId);
      await CorpusStore.saveCaptureId(_captureId);
      await CorpusStore.saveCorpora(_corpora.where((c) => c.origin != 'bundled').toList());
      await _loadCorpusStatus();
      _regenerate();
      if (mounted) setState(() {});
      _showSnack('已识别并归档：新增 ${res.$2} 篇 / 更新 ${res.$3} 篇'
          '（累计 ${target.items.length} 篇）');
    } catch (e) {
      _showSnack('拍照导入失败：${aiFriendlyError(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearCorpus() async {
    final c = _activeCorpus();
    if (c == null) {
      _showSnack('无语料可清除');
      return;
    }
    if (c.origin == 'bundled') {
      _showSnack('内置课文语料为应用预置，不可清除');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清除'),
        content: Text('确定要清除「${c.name}」的所有课文吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirmed != true) return;
    c.items = [];
    await CorpusStore.saveCorpora(_corpora.where((c) => c.origin != 'bundled').toList());
    await _loadCorpusStatus();
    _regenerate();
    if (mounted) setState(() {});
  }

  /// 导出当前活跃课文库为 .json，方便多端导入导出
  Future<void> _exportCorpus() async {
    final c = _activeCorpus();
    final items = c?.items ?? [];
    if (items.isEmpty) {
      _showSnack('当前语料为空：请先「拍照导入」或「导入语料(.json)」再导出。');
      return;
    }
    final obj = <String, dynamic>{
      'name': c!.name,
      'version': c.version,
      'grade': c.grade,
      'volume': c.volume,
      'source': c.source,
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

  /// 切换当前活跃语料（驱动生成）
  Future<void> _switchActive(Corpus c) async {
    _activeId = c.id;
    await CorpusStore.saveActiveId(_activeId);
    _loadCorpusStatus();
    _regenerate();
    if (mounted) setState(() {});
  }

  /// 新建语料库（默认按当前面板版本/年级/册），并切换为活跃+采集目标
  Future<void> _newCorpus() async {
    final ctrl = TextEditingController(text: _defaultCorpusName());
    final created = await showDialog<Corpus>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建语料库'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('名称', style: TextStyle(fontSize: 13, color: Color(0xff888888))),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: '如 统编版语文三年级上册',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '将按当前版本/年级/册创建：${AppData().textbooks[widget.version]?.name ?? widget.version} · '
              '${AppData().gradeNames[widget.grade] ?? '第${widget.grade}年级'} · ${widget.volume == '下' ? '下册' : '上册'}',
              style: const TextStyle(fontSize: 12, color: Color(0xff999999)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              final c = Corpus(
                name: name.isNotEmpty ? name : _defaultCorpusName(),
                version: widget.version,
                grade: widget.grade,
                volume: widget.volume,
                origin: 'imported-json',
              );
              Navigator.pop(ctx, c);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (created == null) return;
    _corpora = [..._corpora, created];
    _activeId = created.id;
    _captureId = created.id;
    await CorpusStore.saveCorpora(_corpora.where((c) => c.origin != 'bundled').toList());
    await CorpusStore.saveActiveId(_activeId);
    await CorpusStore.saveCaptureId(_captureId);
    _loadCorpusStatus();
    _regenerate();
    if (mounted) setState(() {});
    _showSnack('已新建语料库：${created.name}');
  }

  /// 选择「常驻采集目标」（拍照/导入归档到此），可一键更改
  Future<void> _pickCaptureTarget() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择归档目标'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in _corpora.where((x) => x.origin != 'bundled'))
                RadioListTile<String>(
                  title: Text(c.name),
                  subtitle: Text('${c.items.length} 篇 · ${_sourceTag(c.source)}',
                      style: const TextStyle(fontSize: 12, color: Color(0xff888888))),
                  value: c.id,
                  groupValue: _captureId,
                  onChanged: (id) => Navigator.pop(ctx, id),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('新建语料库'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _newCorpus();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
    if (picked == null) return;
    _captureId = picked;
    await CorpusStore.saveCaptureId(_captureId);
    if (mounted) setState(() {});
    final c = _captureCorpus();
    _showSnack('归档目标：${c?.name ?? ''}');
  }

  /// 覆盖度视图：比对内置教材目录，展示已录入/缺课文
  void _showCoverage() {
    final c = _activeCorpus();
    if (c == null) {
      _showSnack('无语料');
      return;
    }
    if (c.version.isEmpty || c.grade == null || c.volume == null) {
      _showSnack('该语料未标注版本/年级/册，无法比对内置目录');
      return;
    }
    final idx = AppData().yuwenTextsFor(c.version, c.grade!, c.volume!);
    if (idx.isEmpty) {
      _showSnack('该版本/年级/册暂无内置课文目录');
      return;
    }
    final have = <String>{};
    for (final it in c.items) {
      final t = '${it['title'] ?? ''}'.trim().toLowerCase();
      if (t.isNotEmpty) have.add(t);
    }
    final missing =
        idx.where((t) => !have.contains(t.title.trim().toLowerCase())).toList();
    final covered = idx.length - missing.length;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Text('覆盖度 · ${c.name}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('$covered/${idx.length} 课',
                        style: const TextStyle(fontSize: 13, color: Color(0xff2f6fd0))),
                    IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: missing.isEmpty
                    ? const Center(
                        child: Text('🎉 已录入全部课文', style: TextStyle(fontSize: 14)))
                    : ListView.builder(
                        itemCount: missing.length,
                        itemBuilder: (ctx, i) => ListTile(
                          leading: const Icon(Icons.circle_outlined,
                              size: 18, color: Color(0xffbbbbbb)),
                          title: Text(missing[i].title,
                              style: const TextStyle(fontSize: 14)),
                          subtitle: missing[i].unit.isNotEmpty
                              ? Text(missing[i].unit,
                                  style: const TextStyle(fontSize: 12, color: Color(0xff888888)))
                              : null,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
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
                      title: Text(item.title,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      subtitle: Text(
                        '${item.grade ?? '?'}年级${item.volume ?? '?'} · ${item.author}',
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
      "note": "这是示例格式，请参照此格式准备您自己的语料。顶层可加 \"source\" 字段声明来源：'original'(AI/人工原创·非版权) / 'licensed'(您声明拥有合法使用权的课本) / 不填(未声明，按版权自负处理)。",
      "source": "licensed",
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
      onGenerate: _loading ? null : () => _generate(),
      generateLabel: '生成预览',
      generateBusy: _loading,
      preview: WorksheetPreviewPanel(
        pages: _pages,
        label: '语文作业', loading: _loading,
      ),
    );
  }

  Widget _config() {
    final total = _counts.values.fold<int>(0, (s, v) => s + v);
    final validTypes = _specs;
    final hidden = _hiddenSpecs;

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
              if (hidden.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${widget.grade} 年级不提供 '
                    '${hidden.map((t) => t.label).join('、')}，已隐藏。'
                    '题量设置会保留，切回对应年级即可恢复。',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xff888888)),
                  ),
                ),
              for (final t in validTypes)
                TypeRow(
                  label: t.label,
                  checked: (_counts[t.id] ?? 0) > 0,
                  count: _counts[t.id] ?? 0,
                  onChecked: (v) {
                    setState(() {
                      if (v && (_counts[t.id] ?? 0) <= 0) {
                        _counts[t.id] = t.defaultQty;
                      } else if (!v) { _counts[t.id] = 0; }
                      _regenerate();
                    });
                    _persistCounts();
                  },
                  onCount: (n) {
                    setState(() {
                      _counts[t.id] = n;
                      _regenerate();
                    });
                    _persistCounts();
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
              if (const {'tongbiao', 'hebei', 'renjiao', 'waiyanYQ', 'waiyanSQ'}
                  .contains(widget.version))
                CheckLabel(
                  label: widget.version.startsWith('waiyan')
                      ? '✨ 基于外研课文（本版本）出英文阅读理解题'
                      : '✨ 基于课文（本版本）出阅读理解题',
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
                    _persistCounts();
                  },
                ),
              if (const {'tongbiao', 'hebei', 'renjiao', 'waiyanYQ', 'waiyanSQ'}
                  .contains(widget.version))
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4),
                  child: Text(
                    _useTextbook
                        ? (widget.version == 'tongbiao'
                            ? '已开启：阅读理解将围绕统编版真实课文出题（课文库已覆盖 1–6 年级上下册，共 287 篇）'
                            : (widget.version.startsWith('waiyan')
                                ? '已开启：将依据外研课文 Module/Unit 篇目，由 AI 原创适龄英文短文出题（A档目录模式，正文可用「拍照导入」补充）'
                                : '已开启：将依据本版本课文篇目，由 AI 原创适龄短文出题（A档目录模式，正文可用「拍照导入」补充）'))
                        : '未开启：阅读理解为 AI 原创短文模式',
                    style: const TextStyle(fontSize: 11, color: Color(0xff999999), height: 1.4),
                  ),
                ),
            ],
          ),
        ),
        FormGroup(
          label: '生成用语料（课文·阅读）',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  '阅读题将使用此语料生成。选哪个语料就用哪个——内置课文已作为语料出现在下拉中（标注「内置课文」），直接选它即可出题，无需导入。',
                  style: TextStyle(fontSize: 11, color: Color(0xff999999), height: 1.4),
                ),
              ),
              // 生成用语料切换 + 新建 + 覆盖度
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<Corpus>(
                      isExpanded: true,
                      value: _activeCorpus(),
                      hint: const Text('选择生成用语料'),
                      items: [
                        for (final c in _corpora)
                          DropdownMenuItem(
                            value: c,
                            child: Text(c.name, overflow: TextOverflow.ellipsis),
                          )
                      ],
                      onChanged: (c) {
                        if (c != null) _switchActive(c);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _newCorpus,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('新建'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _showCoverage,
                    icon: const Icon(Icons.pie_chart, size: 16),
                    label: const Text('覆盖度'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 常驻采集目标（sticky）：拍照/导入始终归档到此
              InkWell(
                onTap: _pickCaptureTarget,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xffcccccc)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.login, size: 16, color: Color(0xff2f6fd0)),
                      const SizedBox(width: 6),
                      const Text('归档到：', style: TextStyle(fontSize: 13)),
                      Expanded(
                        child: Text(_captureCorpus()?.name ?? '未选择',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const Icon(Icons.arrow_drop_down,
                          size: 18, color: Color(0xff888888)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  '推荐：拿手机拍下课本页面（或选相册图），AI 自动识别课文并归档到上方目标；也可导入 .json 语料文件。分多次拍同一本会自动合并去重。',
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
                    label: const Text('清除当前'),
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
