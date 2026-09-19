import 'package:flutter/material.dart';
import '../ai/ai_client.dart';

/// AI 设置卡片（顶部）
///
/// 支持**多个 API 端点**：每个端点是一份独立的「地址 + Key + 模型」，
/// 再由「用途绑定」决定出题 / 帮答 / 看图 用哪个、听力配音用哪个。
/// 这样才能做「DeepSeek 出题（支持看图）+ MiMo 配音（支持 TTS）」这类分工 ——
/// 此前语音模型与主模型共用一套 base/key，无法跨厂商。
class AiConfigCard extends StatefulWidget {
  const AiConfigCard({super.key});

  @override
  State<AiConfigCard> createState() => _AiConfigCardState();
}

class _AiConfigCardState extends State<AiConfigCard> {
  AiConfig _cfg = AiConfig();
  String _status = '';
  Color _statusColor = const Color(0xff888888);
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await AiStore.load();
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      if (cfg.decryptFailed) {
        _status = '有端点的密钥无法解密，请重新输入后再保存';
        _statusColor = const Color(0xffd8433b);
      }
    });
  }

  /// 统一落盘入口：任何改动都立即保存，避免「改完忘了点保存」。
  Future<void> _persist(String okMessage) async {
    await AiStore.save(_cfg);
    if (!mounted) return;
    setState(() {
      _status = okMessage;
      _statusColor = const Color(0xff2f7d32);
    });
  }

  // ---------------- 端点增 / 改 / 删 ----------------

  Future<void> _addEndpoint() async {
    final created = AiEndpoint(name: '端点 ${_cfg.endpoints.length + 1}');
    final result = await _editEndpointDialog(created, isNew: true);
    if (result == null) return;
    _cfg.endpoints.add(result);
    // 第一个端点自动承担两个用途，省得再选一次
    _cfg.mainId ??= result.id;
    _cfg.voiceId ??= result.id;
    await _persist('已新增端点「${result.name}」');
  }

  Future<void> _editEndpoint(AiEndpoint ep) async {
    final result = await _editEndpointDialog(ep);
    if (result == null) return;
    final i = _cfg.endpoints.indexWhere((e) => e.id == ep.id);
    if (i < 0) return;
    _cfg.endpoints[i] = result;
    await _persist('已保存「${result.name}」');
  }

  Future<void> _deleteEndpoint(AiEndpoint ep) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除端点'),
        content: Text('确定删除「${ep.name}」？该端点保存的 API Key 会一并清除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (yes != true) return;
    _cfg.endpoints.removeWhere((e) => e.id == ep.id);
    // 修掉悬空绑定：main 指向被删的 → 落到第一个；
    // voice 指向被删的 → 置空，读取时回落到主端点
    if (_cfg.mainId == ep.id) {
      _cfg.mainId = _cfg.endpoints.isEmpty ? null : _cfg.endpoints.first.id;
    }
    if (_cfg.voiceId == ep.id) _cfg.voiceId = null;
    await _persist('已删除「${ep.name}」');
  }

  Future<void> _clearAll() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部 AI 设置'),
        content: const Text('将删除所有端点及其 API Key，确定吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清除')),
        ],
      ),
    );
    if (yes != true) return;
    await AiStore.clear();
    if (!mounted) return;
    setState(() {
      _cfg = AiConfig();
      _status = '已清除全部 AI 设置';
      _statusColor = const Color(0xff888888);
    });
  }

  // ---------------- 编辑弹层 ----------------

  /// 编辑一个端点。弹层内的「测试 / 试听 / 获取模型」都只作用于**弹层里的草稿**，
  /// 只有点「确定」才写回卡片 —— 中途取消不会留下半截修改。
  Future<AiEndpoint?> _editEndpointDialog(AiEndpoint src,
      {bool isNew = false}) async {
    final nameCtl = TextEditingController(text: src.name);
    final baseCtl = TextEditingController(text: src.base);
    final modelCtl = TextEditingController(text: src.model);
    final keyCtl = TextEditingController(text: src.key);
    final voiceCtl = TextEditingController(text: src.voiceModel);
    var provider = src.provider;
    var status = '';
    var statusColor = const Color(0xff888888);
    var busy = false;

    int presetIndexFor(String provider, String base) {
      final info = AI_PROVIDERS[provider] ?? AI_PROVIDERS['custom']!;
      final trimmed = base.trim();
      if (trimmed.isEmpty) {
        for (int i = 0; i < info.presets.length; i++) {
          if (info.presets[i].base.isNotEmpty) return i;
        }
        return 0;
      }
      for (int i = 0; i < info.presets.length; i++) {
        if (info.presets[i].base == trimmed) return i;
      }
      return info.presets.length - 1;
    }

    var presetIndex = presetIndexFor(provider, src.base);
    var fetchedModels = <String>[];

    AiEndpoint draft() => AiEndpoint(
          id: src.id,
          name: nameCtl.text.trim().isEmpty ? '未命名端点' : nameCtl.text.trim(),
          provider: provider,
          base: baseCtl.text.trim(),
          model: modelCtl.text.trim(),
          voiceModel: voiceCtl.text.trim(),
          key: keyCtl.text.trim(),
        );

    return showDialog<AiEndpoint>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          void say(String m, {bool bad = false}) => setDlg(() {
                status = m;
                statusColor =
                    bad ? const Color(0xffd8433b) : const Color(0xff2f7d32);
              });

          // 语音模型候选：把「已知支持配音」的排在前面（见 sortForTts）。
          // 仍然**不过滤** —— 未知模型可能是该接口专属的配音模型，滤掉等于挡路。
          final voiceCandidates = ModelCapability.sortForTts(fetchedModels);

          Future<void> getModels() async {
            final ep = draft();
            if (ep.base.isEmpty) {
              say('请先填写 API 地址', bad: true);
              return;
            }
            setDlg(() {
              busy = true;
              status = '正在获取模型列表…';
              statusColor = const Color(0xff2f6fd0);
            });
            try {
              final models = await AiModels.list(
                  AiConfig(endpoints: [ep], mainId: ep.id));
              if (!ctx.mounted) return;
              if (models.isEmpty) {
                setDlg(() {
                  busy = false;
                  fetchedModels = [];
                });
                say('该接口未返回任何模型（可手动填写模型名）', bad: true);
                return;
              }
              setDlg(() {
                busy = false;
                fetchedModels = models;
              });
              say('已获取 ${models.length} 个模型，可在模型 / 语音模型下拉框中选择');
            } catch (e) {
              setDlg(() {
                busy = false;
                fetchedModels = [];
              });
              say(aiFriendlyError(e), bad: true);
            }
          }

          Future<void> testText() async {
            final ep = draft();
            if (ep.base.isEmpty || ep.model.isEmpty || ep.key.isEmpty) {
              say('请先填写 API 地址、模型与 Key', bad: true);
              return;
            }
            setDlg(() {
              busy = true;
              status = '测试中…';
              statusColor = const Color(0xff2f6fd0);
            });
            try {
              final reply = await AiClient.chat(
                  AiConfig(endpoints: [ep], mainId: ep.id),
                  [AiChatMessage('user', '请回复"连接正常"四个字。')],
                  temperature: 0);
              setDlg(() => busy = false);
              say('连接正常（返回：${reply.length > 30 ? reply.substring(0, 30) : reply}）');
            } catch (e) {
              setDlg(() => busy = false);
              say('连接失败：${aiFriendlyError(e)}', bad: true);
            }
          }

          Future<void> testVoice() async {
            final ep = draft();
            if (ep.base.isEmpty || ep.voiceModel.isEmpty) {
              say('请先填写 API 地址与语音模型', bad: true);
              return;
            }
            // 需要参考音频 / 音色描述的模型：本应用没有这些输入入口，
            // 发出去必然 400（已实测），提前说清楚，别让用户对着接口报错猜。
            final need = ModelCapability.of(ep.voiceModel).voiceNeeds;
            if (need.isNotEmpty) {
              say('${ep.voiceModel} 需要额外提供$need，本应用未支持，请改用可直接合成'
                  '的语音模型（如 mimo-v2.5-tts、tts-1、cosyvoice-v1）', bad: true);
              return;
            }
            setDlg(() {
              busy = true;
              status = '语音测试中…';
              statusColor = const Color(0xff2f6fd0);
            });
            try {
              final cfg =
                  AiConfig(endpoints: [ep], mainId: ep.id, voiceId: ep.id);
              final bytes = await AiTts.speech(cfg, 'Hello, how are you?');
              setDlg(() => busy = false);
              say('语音接口正常（生成 ${bytes.length ~/ 1024} KB 音频）');
            } catch (e) {
              setDlg(() => busy = false);
              say('语音失败：${aiFriendlyError(e)}', bad: true);
            }
          }

          return AlertDialog(
            title: Text(isNew ? '新增端点' : '编辑端点'),
            content: SizedBox(
              width: MediaQuery.of(ctx).size.width * 0.9,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const SizedBox(
                          width: 96,
                          child: Text('服务商', style: TextStyle(fontSize: 13))),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: AI_PROVIDERS.containsKey(provider)
                            ? provider
                            : 'custom',
                        items: [
                          for (final e in AI_PROVIDERS.entries)
                            DropdownMenuItem(
                            value: e.key, child: Text(e.value.label)),
                        ],
                        onChanged: (v) => setDlg(() {
                          provider = v ?? 'custom';
                          final p = AI_PROVIDERS[provider]!;
                          presetIndex = presetIndexFor(provider, '');
                          baseCtl.text = p.presets[presetIndex].base;
                          modelCtl.text = p.model;
                          voiceCtl.text = p.voice;
                          fetchedModels = [];
                        }),
                      ),
                    ]),
                    Row(children: [
                      const SizedBox(
                          width: 96,
                          child: Text('接口', style: TextStyle(fontSize: 13))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<int>(
                          value: presetIndex,
                          isExpanded: true,
                          items: [
                            for (int i = 0;
                                i < AI_PROVIDERS[provider]!.presets.length;
                                i++)
                              DropdownMenuItem(
                                  value: i,
                                  child: Text(
                                      AI_PROVIDERS[provider]!.presets[i].label,
                                      style: const TextStyle(fontSize: 13))),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setDlg(() {
                              presetIndex = v;
                              final preset = AI_PROVIDERS[provider]!.presets[v];
                              if (preset.base.isNotEmpty) {
                                baseCtl.text = preset.base;
                              }
                              fetchedModels = [];
                            });
                            if (keyCtl.text.trim().isNotEmpty) getModels();
                          },
                        ),
                      ),
                    ]),
                    _dlgField('名称', nameCtl, '用于区分多个端点，如「DeepSeek 主力」'),
                    _dlgField('API 地址', baseCtl, 'https://api.deepseek.com'),
                    _dlgField('模型', modelCtl, '如 deepseek-flash'),
                    if (fetchedModels.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: DropdownButtonFormField<String>(
                          value: fetchedModels.contains(modelCtl.text.trim())
                              ? modelCtl.text.trim()
                              : null,
                          hint: const Text('从接口获取的模型列表中选择',
                              style: TextStyle(fontSize: 13)),
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final m in fetchedModels)
                              DropdownMenuItem(value: m, child: _modelItem(m)),
                          ],
                          onChanged: (v) {
                            if (v != null) setDlg(() => modelCtl.text = v);
                          },
                        ),
                      ),
                    _dlgField('API Key', keyCtl, 'sk-...', obscure: true),
                    _dlgField('语音模型(可选)', voiceCtl,
                        '留空 = 该端点不提供配音，如 mimo-v2.5-tts'),
                    if (fetchedModels.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: DropdownButtonFormField<String>(
                          value: voiceCandidates.contains(voiceCtl.text.trim())
                              ? voiceCtl.text.trim()
                              : null,
                          hint: const Text('从上方模型清单中选择（支持配音的排在前面）',
                              style: TextStyle(fontSize: 13)),
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final m in voiceCandidates)
                              DropdownMenuItem(value: m, child: _voiceItem(m)),
                          ],
                          onChanged: (v) {
                            if (v != null) setDlg(() => voiceCtl.text = v);
                          },
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: busy ? null : getModels,
                        icon: const Icon(Icons.list_alt, size: 18),
                        label: const Text('从接口获取模型列表'),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                            onPressed: busy ? null : testText,
                            child: const Text('测试连接')),
                        OutlinedButton(
                            onPressed: busy ? null : testVoice,
                            child: const Text('试听语音')),
                      ],
                    ),
                    if (status.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(status,
                            style:
                                TextStyle(fontSize: 12, color: statusColor)),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, draft()),
                  child: const Text('确定')),
            ],
          );
        },
      ),
    );
  }

  /// 模型下拉项：已知能力的模型右侧带上能力徽章（看图 / 配音）。
  Widget _modelItem(String id) {
    final badge = _capBadge(id);
    if (badge == null) {
      return Text(id, style: const TextStyle(fontSize: 13));
    }
    return Row(
      children: [
        Expanded(
          child: Text(id,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 6),
        Text(badge,
            style: TextStyle(fontSize: 10.5, color: _badgeColor(badge))),
      ],
    );
  }

  /// 已知能力的模型给个小提示；**未知的不显示**（不误导）。
  ///
  /// 纯 TTS 模型单独标「仅配音」：它就在**主模型**候选里，选错会让出题直接
  /// 失败（拿 TTS 模型去 /chat/completions 生成题目）。
  String? _capBadge(String model) {
    final cap = ModelCapability.of(model);
    if (cap.pureTts) return '仅配音';
    final parts = <String>[
      if (cap.vision == true) '支持看图',
      if (cap.tts == true) '支持配音',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// 徽章配色：能力信息用绿色，警示信息（仅配音）用琥珀色。
  Color _badgeColor(String badge) =>
      badge == '仅配音' ? const Color(0xffb26a00) : const Color(0xff2f7d32);

  /// **语音模型**下拉项：只提示与「能不能配音」有关的信息。
  /// 灰色「不支持配音」是明确结论，值得写出来；未知的留空（不误导）。
  Widget _voiceItem(String id) {
    final cap = ModelCapability.of(id);
    if (cap.needsExtraInput) {
      return _voiceRow(id, '需${cap.voiceNeeds}，未支持', const Color(0xffb26a00));
    }
    if (cap.tts == null) return Text(id, style: const TextStyle(fontSize: 13));
    return _voiceRow(id, cap.tts! ? '支持配音' : '不支持配音',
        cap.tts! ? const Color(0xff2f7d32) : const Color(0xff9a9a9a));
  }

  Widget _voiceRow(String id, String note, Color color) {
    return Row(
      children: [
        Expanded(
          child: Text(id,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 6),
        Text(note, style: TextStyle(fontSize: 10.5, color: color)),
      ],
    );
  }

  // ---------------- 主界面 ----------------

  @override
  Widget build(BuildContext context) {
    final eps = _cfg.endpoints;
    final title = eps.isEmpty
        ? '🤖 AI 智能出题设置（未配置：填入大模型 API 后即可 AI 生成题目）'
        : '🤖 AI 智能出题设置（已配置 ${eps.length} 个端点）';
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: _expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        title: Text(title,
            style: const TextStyle(fontSize: 14, color: Color(0xff2f6fd0))),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('API 端点', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                if (eps.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('还没有端点。新增一个并填入地址与 Key 即可启用 AI 功能。',
                        style: TextStyle(fontSize: 12, color: Color(0xff888888))),
                  )
                else
                  for (final ep in eps) _endpointTile(ep),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addEndpoint,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新增端点'),
                  ),
                ),
                const Divider(),
                const Text('用途绑定', style: TextStyle(fontSize: 13)),
                _bindingRow('主模型', '出题 / 帮答 / 看图', _cfg.mainId, (v) {
                  setState(() => _cfg.mainId = v);
                }),
                _bindingRow('听力配音', '留空则用主模型', _cfg.voiceId, (v) {
                  setState(() => _cfg.voiceId = v);
                }),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: () => _persist('已保存用途绑定'),
                      child: const Text('保存绑定'),
                    ),
                    OutlinedButton(
                        onPressed: _clearAll, child: const Text('清除全部')),
                  ],
                ),
                if (_status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_status,
                        style: TextStyle(fontSize: 13, color: _statusColor)),
                  ),
                const SizedBox(height: 8),
                const Text(
                    'API Key 使用系统级加密保存：Windows（DPAPI）/ macOS（钥匙串）/ 安卓（系统密钥库 Keystore），仅存本机、不联网上传；每次请求只发给该端点对应的服务商。',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xffaaaaaa), height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 端点一行：名称 + 用途标签 + 摘要 + 编辑 / 删除
  Widget _endpointTile(AiEndpoint ep) {
    final isMain = _cfg.main?.id == ep.id;
    final isVoice = _cfg.voice?.id == ep.id && ep.hasTts;
    final summary = StringBuffer();
    summary.write(ep.base.isEmpty ? '未填地址' : ep.base);
    summary.write('   ·   模型：${ep.model.isEmpty ? '未填' : ep.model}');
    if (ep.hasTts) summary.write('   ·   语音：${ep.voiceModel}');
    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: ListTile(
        dense: true,
        onTap: () => _editEndpoint(ep),
        title: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(ep.name,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            if (isMain) _tag('主模型', const Color(0xff2f6fd0)),
            if (isVoice) _tag('配音', const Color(0xff2f7d32)),
            if (ep.decryptFailed) _tag('密钥待重填', const Color(0xffd8433b)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(summary.toString(),
              style:
                  const TextStyle(fontSize: 11.5, color: Color(0xff777777))),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 19),
              tooltip: '编辑',
              onPressed: () => _editEndpoint(ep),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 19),
              tooltip: '删除',
              onPressed: () => _deleteEndpoint(ep),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.35), width: 0.5),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color)),
      );

  /// 用途绑定一行：左侧用途名，右侧端点下拉
  Widget _bindingRow(String label, String note, String? value,
      ValueChanged<String?> onChanged) {
    final ids = [for (final e in _cfg.endpoints) e.id];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13)),
                Text(note,
                    style: const TextStyle(
                        fontSize: 10.5, color: Color(0xff999999))),
              ],
            ),
          ),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: ids.contains(value) ? value : null,
              hint: const Text('未设置（用主模型）',
                  style: TextStyle(fontSize: 13)),
              items: [
                for (final e in _cfg.endpoints)
                  DropdownMenuItem(
                      value: e.id,
                      child:
                          Text(e.name, style: const TextStyle(fontSize: 13))),
              ],
              onChanged: _cfg.endpoints.isEmpty ? null : onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dlgField(String label, TextEditingController ctl, String hint,
      {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
              width: 96,
              child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: TextField(
              controller: ctl,
              obscureText: obscure,
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
