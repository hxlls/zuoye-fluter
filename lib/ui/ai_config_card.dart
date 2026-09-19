import 'package:flutter/material.dart';
import '../ai/ai_client.dart';

/// AI 设置卡片（顶部）
class AiConfigCard extends StatefulWidget {
  const AiConfigCard({super.key});

  @override
  State<AiConfigCard> createState() => _AiConfigCardState();
}

class _AiConfigCardState extends State<AiConfigCard> {
  final _baseCtl = TextEditingController();
  final _modelCtl = TextEditingController();
  final _keyCtl = TextEditingController();
  final _voiceCtl = TextEditingController();
  String _provider = 'deepseek';
  String _status = '';
  Color _statusColor = const Color(0xff888888);
  /// 正在拉取模型列表（期间禁用按钮，避免重复请求）
  bool _loadingModels = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await AiStore.load();
    _provider = cfg.provider;
    _baseCtl.text = cfg.base;
    _modelCtl.text = cfg.model;
    _keyCtl.text = cfg.key;
    _voiceCtl.text = cfg.voiceModel;
    if (cfg.decryptFailed) {
      _status = '上次保存的密钥无法解密，请重新输入';
      _statusColor = const Color(0xffd8433b);
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final cfg = AiConfig(
      provider: _provider,
      base: _baseCtl.text.trim(),
      model: _modelCtl.text.trim(),
      key: _keyCtl.text.trim(),
      voiceModel: _voiceCtl.text.trim(),
    );
    if (cfg.base.isEmpty || cfg.model.isEmpty) {
      setState(() {
        _status = '请填写 API 地址与模型';
        _statusColor = const Color(0xffd8433b);
      });
      return;
    }
    await AiStore.save(cfg);
    setState(() {
      _status = '已保存（系统加密）✓';
      _statusColor = const Color(0xff2f7d32);
    });
  }

  Future<void> _clear() async {
    await AiStore.clear();
    _keyCtl.text = '';
    setState(() {
      _status = '已清除';
      _statusColor = const Color(0xff888888);
    });
  }

  Future<void> _test() async {
    final cfg = AiConfig(
      provider: _provider,
      base: _baseCtl.text.trim(),
      model: _modelCtl.text.trim(),
      key: _keyCtl.text.trim(),
    );
    if (cfg.base.isEmpty || cfg.model.isEmpty || cfg.key.isEmpty) {
      setState(() {
        _status = '请先填写 API 地址、模型与 Key';
        _statusColor = const Color(0xffd8433b);
      });
      return;
    }
    setState(() {
      _status = '测试中…';
      _statusColor = const Color(0xff2f6fd0);
    });
    try {
      final reply = await AiClient.chat(cfg, [
        AiChatMessage('user', '请回复"连接正常"四个字。'),
      ], temperature: 0);
      setState(() {
        _status = '连接正常 ✓（返回：${reply.length > 30 ? reply.substring(0, 30) : reply}）';
        _statusColor = const Color(0xff2f7d32);
      });
    } catch (e) {
      setState(() {
        _status = '连接失败：${aiFriendlyError(e)}';
        _statusColor = const Color(0xffd8433b);
      });
    }
  }

  /// 从 `{base}/models` 拉取可用模型，选中后填入模型输入框。
  ///
  /// 这只是便利功能：拉不到（接口不支持该端点 / 网络问题）时会给出提示，
  /// 用户仍可手动输入模型名，不影响原有流程。
  Future<void> _loadModels() async {
    final base = _baseCtl.text.trim();
    if (base.isEmpty) {
      setState(() {
        _status = '请先填写 API 地址';
        _statusColor = const Color(0xffd8433b);
      });
      return;
    }
    setState(() {
      _loadingModels = true;
      _status = '正在获取模型列表…';
      _statusColor = const Color(0xff2f6fd0);
    });
    try {
      final models = await AiModels.list(AiConfig(
        provider: _provider,
        base: base,
        model: _modelCtl.text.trim(),
        key: _keyCtl.text.trim(),
        voiceModel: _voiceCtl.text.trim(),
      ));
      if (!mounted) return;
      if (models.isEmpty) {
        setState(() {
          _loadingModels = false;
          _status = '该接口未返回任何模型（可手动填写模型名）';
          _statusColor = const Color(0xffd8433b);
        });
        return;
      }
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('选择模型（共 ${models.length} 个）'),
          children: [
            SizedBox(
              width: MediaQuery.of(ctx).size.width * 0.8,
              height: 360,
              child: ListView.builder(
                itemCount: models.length,
                itemBuilder: (c, i) {
                  final id = models[i];
                  final badge = _capBadge(id);
                  return ListTile(
                    dense: true,
                    title: Text(id, style: const TextStyle(fontSize: 14)),
                    subtitle: badge == null ? null : Text(badge,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xff2f7d32))),
                    onTap: () => Navigator.pop(ctx, id),
                  );
                },
              ),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        if (picked != null) {
          _modelCtl.text = picked;
          _status = '已选择模型：$picked';
          _statusColor = const Color(0xff2f7d32);
        } else {
          _status = '已取消选择';
          _statusColor = const Color(0xff888888);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        _status = aiFriendlyError(e);
        _statusColor = const Color(0xffd8433b);
      });
    }
  }

  /// 已知能力的模型，在列表里给个小提示；**未知的不显示**（不误导）。
  String? _capBadge(String model) {
    final cap = ModelCapability.of(model);
    final parts = <String>[
      if (cap.vision == true) '支持看图',
      if (cap.tts == true) '支持配音',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _testVoice() async {
    final cfg = AiConfig(
      provider: _provider,
      base: _baseCtl.text.trim(),
      model: _modelCtl.text.trim(),
      key: _keyCtl.text.trim(),
      voiceModel: _voiceCtl.text.trim(),
    );
    if (cfg.base.isEmpty || cfg.voiceModel.isEmpty) {
      setState(() {
        _status = '请填写 API 地址与语音模型';
        _statusColor = const Color(0xffd8433b);
      });
      return;
    }
    setState(() {
      _status = '语音测试中…';
      _statusColor = const Color(0xff2f6fd0);
    });
    try {
      final bytes = await AiTts.speech(cfg, 'Hello, how are you?');
      setState(() {
        _status = '语音接口正常 ✓（生成 ${bytes.length ~/ 1024} KB 音频）';
        _statusColor = const Color(0xff2f7d32);
      });
    } catch (e) {
      setState(() {
        _status = '语音失败：${aiFriendlyError(e)}';
        _statusColor = const Color(0xffd8433b);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: _expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        title: const Text('🤖 AI 智能出题设置（可选：填入大模型 API 后即可 AI 生成题目）',
            style: TextStyle(fontSize: 14, color: Color(0xff2f6fd0))),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('服务商', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _provider,
                      items: [
                        for (final e in AI_PROVIDERS.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.key)),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _provider = v ?? 'deepseek';
                          final p = AI_PROVIDERS[_provider]!;
                          _baseCtl.text = p.base;
                          _modelCtl.text = p.model;
                          _voiceCtl.text = p.voice;
                        });
                      },
                    ),
                  ],
                ),
                _field('API 地址', _baseCtl, 'https://api.deepseek.com'),
                _field('模型', _modelCtl, '如 deepseek-v4.1-flash / gpt-4o-mini'),
                _field('API Key', _keyCtl, 'sk-...', obscure: true),
                _field('语音模型(可选)', _voiceCtl,
                    '听力配音用，如 deepseek-v4.1-flash / tts-1 / cosyvoice-v1'),
                const SizedBox(height: 4),
                // 从接口拉取可用模型：填好地址与 Key 后点一下，免去手输模型名。
                // 各家的 /models 端点实测均可用；不支持时仍可手动输入。
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _loadingModels ? null : _loadModels,
                    icon: const Icon(Icons.list_alt, size: 18),
                    label: Text(_loadingModels ? '获取中…' : '从接口获取模型列表'),
                  ),
                ),
                const SizedBox(height: 6),
                // 按钮在手机窄屏上横排会溢出，改用 Wrap 自动换行；
                // 状态文字另起一行，避免被挤成竖条
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton(onPressed: _save, child: const Text('保存设置')),
                    OutlinedButton(onPressed: _test, child: const Text('测试')),
                    OutlinedButton(onPressed: _testVoice, child: const Text('试听语音')),
                    OutlinedButton(onPressed: _clear, child: const Text('清除')),
                  ],
                ),
                if (_status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_status,
                        style: TextStyle(fontSize: 13, color: _statusColor)),
                  ),
                const SizedBox(height: 8),
                const Text('API Key 使用系统级加密保存：Windows（DPAPI）/ macOS（钥匙串）/ 安卓（系统密钥库 Keystore），仅存本机、不联网上传；每次请求只发给设置里填写的那家服务商。',
                    style: TextStyle(fontSize: 12, color: Color(0xffaaaaaa), height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctl, String hint,
      {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 13))),
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
