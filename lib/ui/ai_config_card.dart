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
  String _provider = 'deepseek';
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
    _provider = cfg.provider;
    _baseCtl.text = cfg.base;
    _modelCtl.text = cfg.model;
    _keyCtl.text = cfg.key;
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
                        });
                      },
                    ),
                  ],
                ),
                _field('API 地址', _baseCtl, 'https://api.deepseek.com'),
                _field('模型', _modelCtl, 'deepseek-chat'),
                _field('API Key', _keyCtl, 'sk-...', obscure: true),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton(onPressed: _save, child: const Text('保存设置')),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: _test, child: const Text('测试')),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: _clear, child: const Text('清除')),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(_status,
                          style: TextStyle(fontSize: 13, color: _statusColor)),
                    ),
                  ],
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
