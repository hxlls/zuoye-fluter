import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import '../data/app_data.dart';
import '../core/english_worksheet.dart';
import '../core/wav_merge.dart';
import '../core/worksheet_model.dart';
import '../ai/ai_generator.dart';
import '../ai/ai_client.dart';
import 'panel_widgets.dart';
import 'preview_panel.dart';
import 'web_download.dart' if (dart.library.html) 'web_download_web.dart';

/// 英语作业面板
class EnglishPanel extends StatefulWidget {
  final int grade;
  final String version;
  final String volume;
  const EnglishPanel({
    super.key,
    required this.grade,
    required this.version,
    required this.volume,
  });

  @override
  State<EnglishPanel> createState() => _EnglishPanelState();
}

class _EnglishPanelState extends State<EnglishPanel> {
  final Map<String, int> _counts = {};
  bool _showTitle = true;
  bool _showAnswer = true;
  List<WsPage> _pages = [];
  bool _loading = false;
  List<ReadingBlockData> _aiItems = [];

  static const _typeIds = ['alphabet', 'trace', 'match', 'cn2en', 'en2cn', 'spell', 'listening', 'aiyuedu'];

  @override
  void initState() {
    super.initState();
    _ensureCounts();
    _regenerate();
  }

  @override
  void didUpdateWidget(EnglishPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grade != widget.grade ||
        oldWidget.version != widget.version ||
        oldWidget.volume != widget.volume) {
      _ensureCounts();
      _regenerate();
    }
  }

  void _ensureCounts() {
    final valid = allowedEngTypes(widget.version, widget.grade, _typeIds);
    _counts.removeWhere((k, v) => !valid.contains(k));
    for (final t in valid) {
      if (!_counts.containsKey(t)) _counts[t] = 8;
    }
  }

  void _regenerate() {
    _pages = englishRenderPages(EnglishOptions(
      grade: widget.grade,
      version: widget.version,
      volume: widget.volume,
      types: _typeIds,
      counts: Map.of(_counts),
      showTitle: _showTitle,
      showAnswer: _showAnswer,
      aiReadingItems: _aiItems.isEmpty ? null : _aiItems,
    ));
  }

  void _refresh() => setState(_regenerate);

  void _generate() {
    if ((_counts['aiyuedu'] ?? 0) > 0) {
      _generateENReading();
    } else {
      _refresh();
    }
  }

  Future<void> _generateENReading() async {
    setState(() => _loading = true);
    try {
      final items = await aiGenerateReadingEN(AiPromptOpts(
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('AI 英语阅读理解生成失败：${aiFriendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 生成听力音频（AI TTS）：把当前听力题的朗读文本合成为 mp3 供下载
  Future<void> _generateListeningAudio() async {
    final cfg = await AiStore.load();
    if (cfg.base.isEmpty || cfg.voiceModel.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('请先在顶部「AI 智能出题设置」中填写 API 地址与语音模型（如 tts-1 / cosyvoice-v1）。')));
      }
      return;
    }
    // 生成与预览一致的听力题
    final data = AppData();
    final vocab = pickVocab(
        data, widget.grade, _counts['listening'] ?? 8, widget.version, widget.volume);
    final items =
        buildListeningItems(vocab, _counts['listening'] ?? 8, grade: widget.grade);
    if (items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('当前册暂无听力词汇。')));
      }
      return;
    }
    setState(() => _loading = true);
    try {
      // 逐题朗读并生成音频，题间插入约 3.5 秒静音（给学生思考时间）
      final chunks = <Uint8List>[];
      try {
        for (final it in items) {
          final wav = await AiTts.speech(cfg, it.readText, format: 'wav');
          chunks.add(wav);
        }
      } catch (e) {
        // 部分语音接口不支持 wav：回退为 mp3（逐题生成单文件，无静音间隔）
        final mp3 = await AiTts.speech(
            cfg, _listeningText(items), format: 'mp3');
        await _saveAudioBytes(mp3);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('当前语音接口不支持 wav 静音拼接，已改为 mp3 单文件。')));
        }
        return;
      }
      final merged = WavMerge.merge(chunks, silenceMs: 3500);
      await _saveAudioBytes(merged, ext: 'wav');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('听力音频生成失败：${aiFriendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 拼合听力朗读文本（用于 mp3 回退）
  String _listeningText(List<ListeningItem> items) {
    final buf = StringBuffer();
    for (final it in items) {
      buf.writeln(it.readText);
    }
    return buf.toString();
  }

  /// 保存音频字节（跨平台另存为对话框）
  Future<void> _saveAudioBytes(Uint8List bytes, {String ext = 'mp3'}) async {
    final filename = 'listening_g${widget.grade}_${widget.version}.$ext';
    final mime = ext == 'wav' ? 'audio/wav' : 'audio/mpeg';
    if (kIsWeb) {
      webDownloadBytes(bytes, filename, mimeType: mime);
      return;
    }
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          data: bytes,
          fileName: filename,
          mimeTypesFilter: const ['audio/*'],
        ),
      );
      return;
    }
    final location = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: [
        XTypeGroup(label: ext.toUpperCase() == 'WAV' ? 'WAV 音频' : 'MP3 音频',
            extensions: [ext]),
      ],
    );
    if (location == null) return;
    final file = File(location.path);
    await file.writeAsBytes(bytes, flush: true);
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
        label: '英语作业', loading: _loading,
      ),
    );
  }

  Widget _config() {
    final validTypes = allowedEngTypes(widget.version, widget.grade, _typeIds);
    final total = _counts.values.fold<int>(0, (s, v) => s + v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('英语作业设置',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('📚 词汇参考人教PEP英语教材（3-6年级为三年级起点）',
            style: TextStyle(fontSize: 12, color: Color(0xff888888))),
        const SizedBox(height: 14),
        FormGroup(
          label: '作业类型（可多选，每种类型可单独设置数量）',
          child: Column(
            children: [
              for (final t in validTypes)
                TypeRow(
                  label: _labelFor(t),
                  checked: (_counts[t] ?? 0) > 0,
                  count: _counts[t] ?? 0,
                  onChecked: (v) {
                    setState(() {
                      if (v && (_counts[t] ?? 0) <= 0) _counts[t] = 8;
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
              Text('共 $total 题（每种类型可单独调整数量，0 表示不选）',
                  style: const TextStyle(fontSize: 12, color: Color(0xffaaaaaa))),
            ],
          ),
        ),
        FormGroup(
          label: '选项',
          child: Column(
            children: [
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
              CheckLabel(
                label: '连线题附答案',
                value: _showAnswer,
                onChanged: (v) {
                  setState(() {
                    _showAnswer = v;
                    _regenerate();
                  });
                },
              ),
            ],
          ),
        ),
        if ((_counts['listening'] ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _generateListeningAudio,
                icon: const Icon(Icons.audiotrack, size: 18),
                label: Text(_loading ? '⏳ 生成中…' : '生成听力音频（AI配音·下载MP3）'),
              ),
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
            child: Text('⏳ AI 正在生成英语阅读理解，请稍候…',
                style: TextStyle(fontSize: 14, color: Color(0xff2f6fd0))),
          ),
      ],
    );
  }

  String _labelFor(String id) {
    if (widget.grade == 1 && id == 'trace') return '单词描红';
    return ENG_TYPE_LABELS[id] ?? id;
  }
}
