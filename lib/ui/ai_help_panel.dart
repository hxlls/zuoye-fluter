import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/app_data.dart';
import '../ai/ai_generator.dart';
import '../ai/ai_client.dart';
import 'panel_widgets.dart';

/// AI 帮答题面板
class AiHelpPanel extends StatefulWidget {
  final int grade;
  final String version;
  final String volume;
  const AiHelpPanel({
    super.key,
    required this.grade,
    required this.version,
    required this.volume,
  });

  @override
  State<AiHelpPanel> createState() => _AiHelpPanelState();
}

class _AiHelpPanelState extends State<AiHelpPanel> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _subject = 'math';
  final _inputCtl = TextEditingController();
  final List<(String, String)> _messages = []; // (role, content)
  bool _sending = false;
  String _pendingImage = '';

  @override
  void initState() {
    super.initState();
    _messages.add(('ai',
        '你好！我是 AI 作业帮手。把你不会的题目写在下方输入框，我会分步骤讲解并给出答案。也可以点「📷」上传题目照片，AI 会自动识别题目再讲解。'));
  }

  Future<void> _send() async {
    final q = _inputCtl.text.trim();
    if (q.isEmpty && _pendingImage.isEmpty) return;
    final cfg = await AiStore.load();
    if (cfg.base.isEmpty || cfg.model.isEmpty) {
      _showSnack('请先在顶部「AI 智能出题设置」中填写 API 地址和模型并保存。');
      return;
    }
    final withImage = _pendingImage.isNotEmpty;
    final imgData = withImage ? _pendingImage : null;
    final userMsg = withImage
        ? '（请识别图片中的题目并解答）$q'
        : q;
    setState(() {
      _messages.add(('user', userMsg));
      _inputCtl.clear();
      _pendingImage = '';
      _sending = true;
    });
    try {
      final sys = aiHelpSystemPrompt(_subject, AiHelpOpts(
        version: widget.version,
        volume: widget.volume,
        grade: widget.grade,
        withImage: withImage,
      ));
      final content = await AiClient.chat(cfg, [
        sys,
        AiChatMessage('user', userMsg),
      ], imageBase64: imgData);
      setState(() {
        _messages.add(('ai', content.isEmpty ? '（AI 未返回内容，请重试）' : content));
      });
    } catch (e) {
      setState(() {
        _messages.add(('ai', '（出错了：${aiFriendlyError(e)}）'));
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 拍摄照片（直接调用手机相机）
  Future<void> _takePhoto() async {
    try {
      final f = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (bytes.length > 15 * 1024 * 1024) {
        _showSnack('图片太大（超过15MB）');
        return;
      }
      setState(() => _pendingImage = 'data:image/jpeg;base64,${base64Encode(bytes)}');
    } catch (e) {
      _showSnack('拍照失败：$e');
    }
  }

  /// 从相册选择图片
  Future<void> _pickImage() async {
    try {
      final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (bytes.length > 15 * 1024 * 1024) {
        _showSnack('图片太大（超过15MB）');
        return;
      }
      setState(() => _pendingImage = 'data:image/jpeg;base64,${base64Encode(bytes)}');
    } catch (e) {
      _showSnack('选择图片失败：$e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final data = AppData();
    final wide = MediaQuery.of(context).size.width >= 760;
    final chat = _buildChat(data, wide: wide);
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSidebar(data),
          Expanded(child: chat),
        ],
      );
    }
    // 手机：设置收进抽屉，主区全屏问答
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
        backgroundColor: const Color(0xfffaf8f2),
        title: const Text('💡 AI 帮答题',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            child: _buildSidebar(data),
          ),
        ),
      ),
      body: chat,
    );
  }

  Widget _buildSidebar(AppData data) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(14),
      color: const Color(0xfffaf8f2),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI 帮答题',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('💡 输入或拍照上传题目，AI 识别并分步骤讲解',
                style: TextStyle(fontSize: 12, color: Color(0xff888888))),
            const SizedBox(height: 14),
            FormGroup(
              label: '科目',
              child: SegButtons(
                options: [
                  ('math', '数学'),
                  ('english', '英语'),
                  ('chinese', '语文'),
                  ('other', '其他'),
                ],
                value: _subject,
                onChanged: (v) => setState(() => _subject = v),
              ),
            ),
            FormGroup(
              label: '讲解对象年级',
              child: Text(
                '使用顶部选择的 ${data.textbooks[widget.version]?.name ?? '人教版'} ${data.gradeNames[widget.grade] ?? ''} ${widget.volume == '下' ? '下册' : '上册'}',
                style: const TextStyle(fontSize: 14, color: Color(0xff555555)),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => setState(() => _messages.clear()),
                child: const Text('🔄 新对话（清空记录）'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChat(AppData data, {required bool wide}) {
    return Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xffe9e6df),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xfff2efe8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: ListView(
                      children: [
                        for (final (role, content) in _messages)
                          _chatBubble(role, content),
                      ],
                    ),
                  ),
                ),
                if (_pendingImage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.image, size: 16),
                        const SizedBox(width: 4),
                        const Text('已添加题目图片', style: TextStyle(fontSize: 13)),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _pendingImage = ''),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.photo_camera),
                        onPressed: _takePhoto,
                        tooltip: '拍照上传题目',
                      ),
                      IconButton(
                        icon: const Icon(Icons.photo_library_outlined),
                        onPressed: _pickImage,
                        tooltip: '从相册选择图片',
                      ),
                      Expanded(
                        child: TextField(
                          controller: _inputCtl,
                          maxLines: 2,
                          minLines: 1,
                          decoration: const InputDecoration(
                            hintText: '输入题目，例如：小明有12块糖，平均分给3个小朋友，每人分几块？',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      wide
                          ? FilledButton(
                              onPressed: _sending ? null : _send,
                              child: Text(_sending ? '⏳ 讲解中…' : '🤖 AI 解答'),
                            )
                          : FilledButton(
                              onPressed: _sending ? null : _send,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              child: Text(_sending ? '⏳' : '解答'),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          );
  }

  Widget _chatBubble(String role, String content) {
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.5,
        ),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xffd8433b) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isUser ? 12 : 4),
            topRight: Radius.circular(isUser ? 4 : 12),
            bottomLeft: const Radius.circular(12),
            bottomRight: const Radius.circular(12),
          ),
          border: isUser ? null : Border.all(color: const Color(0xffd0cdc4)),
        ),
        child: Text(
          content,
          style: TextStyle(
            fontSize: 15,
            height: 1.6,
            color: isUser ? Colors.white : const Color(0xff222222),
          ),
        ),
      ),
    );
  }
}
