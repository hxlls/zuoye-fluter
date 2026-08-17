import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// AI 提供商预设（含语音模型：听力配音用，可能因账号/模型而异，可在设置中修改）
const AI_PROVIDERS = {
  'deepseek': (
    base: 'https://api.deepseek.com',
    model: 'deepseek-v4-flash',
    voice: ''
  ),
  'openai': (
    base: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    voice: 'tts-1'
  ),
  'qwen': (
    base: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-plus',
    voice: 'cosyvoice-v1'
  ),
  'kimi': (
    base: 'https://api.moonshot.cn/v1',
    model: 'moonshot-v1-8k',
    voice: ''
  ),
  'glm': (
    base: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4-flash',
    voice: 'glm-4v-voice'
  ),
  'mimo': (
    base: 'https://api.xiaomimimo.com/v1',
    model: 'mimo-v2.5',
    voice: 'mimo-v2.5-tts'
  ),
  'ollama': (
    base: 'http://localhost:11434/v1',
    model: 'qwen2.5:7b',
    voice: ''
  ),
  'custom': (base: '', model: '', voice: ''),
};

/// AI 配置
class AiConfig {
  String provider;
  String base;
  String model;
  String key;
  bool encrypted;
  bool decryptFailed;
  /// 语音合成模型（听力配音用，如 OpenAI tts-1 / 通义 cosyvoice-v1 / 智谱 glm-4v-voice）
  String voiceModel;

  AiConfig({
    this.provider = 'deepseek',
    this.base = '',
    this.model = '',
    this.key = '',
    this.encrypted = false,
    this.decryptFailed = false,
    this.voiceModel = '',
  });

  factory AiConfig.fromJson(Map<String, dynamic> j) => AiConfig(
        provider: (j['provider'] as String?) ?? 'deepseek',
        base: (j['base'] as String?) ?? '',
        model: (j['model'] as String?) ?? '',
        key: (j['key'] as String?) ?? '',
        encrypted: (j['encrypted'] as bool?) ?? false,
        decryptFailed: (j['decryptFailed'] as bool?) ?? false,
        voiceModel: (j['voiceModel'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'base': base,
        'model': model,
        'key': key,
        'encrypted': encrypted,
        'decryptFailed': decryptFailed,
        'voiceModel': voiceModel,
      };
}

/// AI 配置存储：共享参数存 SharedPreferences，Key 用系统级加密
class AiStore {
  static const _prefsKey = 'aiConfig';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _secKey = 'ai_api_key';

  static Future<AiConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final cfg = raw != null
        ? AiConfig.fromJson(json.decode(raw) as Map<String, dynamic>)
        : AiConfig();
    if (cfg.encrypted && cfg.key.isNotEmpty) {
      try {
        final plain = await _storage.read(key: _secKey);
        if (plain != null) {
          cfg.key = plain;
          cfg.decryptFailed = false;
        } else {
          cfg.key = '';
          cfg.decryptFailed = true;
        }
      } catch (e) {
        cfg.key = '';
        cfg.decryptFailed = true;
      }
    }
    return cfg;
  }

  static Future<void> save(AiConfig cfg) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = cfg.toJson();
    if (cfg.key.isNotEmpty) {
      try {
        await _storage.write(key: _secKey, value: cfg.key);
        stored['key'] = 'encrypted';
        stored['encrypted'] = true;
      } catch (e) {
        stored['key'] = cfg.key;
        stored['encrypted'] = false;
      }
    }
    stored['decryptFailed'] = false;
    await prefs.setString(_prefsKey, json.encode(stored));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    try {
      await _storage.delete(key: _secKey);
    } catch (e) {}
  }
}

/// AI 请求结果
class AiChatMessage {
  final String role; // user / assistant / system
  final String content;
  AiChatMessage(this.role, this.content);
}

/// OpenAI 兼容请求
class AiClient {
  /// 发送消息并返回文本内容（原生 http，无 CORS）
  /// [imageBase64] 传入 `data:image/...;base64,...` 时按多模态发送（OpenAI 兼容 image_url）
  /// [jsonMode] 出题等需解析 JSON 的场景：DeepSeek V4 默认 thinking 模式会导致长 JSON 输出
  ///   不稳定/空 content，启用后自动关闭 thinking 并请求 json_object
  static Future<String> chat(AiConfig cfg, List<AiChatMessage> messages,
      {double temperature = 0.8, String? imageBase64, bool jsonMode = false}) async {
    if (cfg.base.trim().isEmpty) {
      throw Exception('未配置 API 地址，请先填写 AI 设置');
    }
    if (cfg.model.trim().isEmpty) {
      throw Exception('未配置模型名称');
    }
    var base = cfg.base.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final url = base.endsWith('/chat/completions')
        ? base
        : '$base/chat/completions';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (cfg.key.isNotEmpty) 'Authorization': 'Bearer ${cfg.key}',
    };
    final msgs = <Map<String, dynamic>>[
      for (final m in messages) {'role': m.role, 'content': m.content},
    ];
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      // 最后一条 user 消息改为多模态：文本 + 图片
      final last = msgs.last;
      last['content'] = [
        {'type': 'text', 'text': '${last['content'] ?? ''}'},
        {
          'type': 'image_url',
          'image_url': {'url': imageBase64},
        },
      ];
    }
    final model = cfg.model.trim();
    final isDeepseekV4 = model.startsWith('deepseek-v4');
    final isMimo = model.startsWith('mimo-');
    final body = json.encode({
      'model': model,
      'messages': msgs,
      'temperature': temperature,
      'stream': false,
      // 出题需输出整页 JSON，给足输出长度避免截断
      // 参数名因提供商而异：DeepSeek 用 max_tokens，MiMo 用 max_completion_tokens
      if (jsonMode)
        if (isMimo)
          'max_completion_tokens': 8192
        else
          'max_tokens': 8192,
      if (jsonMode)
        'response_format': {
          'type': 'json_object',
        },
      // DeepSeek V4 / MiMo 默认 thinking 模式：出题时关闭，避免思维链干扰 JSON 输出
      if (jsonMode && (isDeepseekV4 || isMimo)) 'thinking': {'type': 'disabled'},
    });

    try {
      final resp = await httpPostJson(url, headers, body);
      final text = resp.$2;
      if (resp.$1 < 200 || resp.$1 >= 300) {
        throw Exception(
            'API 返回错误 ${resp.$1}：${text.length > 300 ? text.substring(0, 300) : text}');
      }
      final data = json.decode(text) as Map<String, dynamic>;
      final msg = data['choices']?[0]?['message'];
      var content = msg?['content'];
      // 部分推理模型 content 为 null，答案可能在 reasoning_content 或最后一段
      if (content == null) {
        final reasoning = msg?['reasoning_content'];
        content = (reasoning is String && reasoning.trim().isNotEmpty)
            ? reasoning
            : null;
      }
      if (content == null) {
        throw Exception(
            'API 返回格式异常（缺少 choices[0].message.content）：${text.length > 200 ? text.substring(0, 200) : text}');
      }
      return content as String;
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('网络请求失败：$e');
    }
  }
}

/// 辅助：POST JSON，返回 (statusCode, body)
Future<(int, String)> httpPostJson(String url, Map<String, String> headers, String body) async {
  final resp = await http
      .post(Uri.parse(url), headers: headers, body: body)
      .timeout(const Duration(seconds: 180));
  return (resp.statusCode, resp.body);
}

/// 语音合成（听力配音）
/// 两种接口：
/// 1) OpenAI 风格：POST /audio/speech（OpenAI tts-1、通义 cosyvoice 等）
/// 2) MiMo 风格：POST /chat/completions，assistant 消息 content 为要合成的文本，
///    响应 choices[0].message.audio.data 为 base64 音频（模型名以 mimo- 开头）
class AiTts {
  /// 生成音频字节（默认 mp3；wav 用于面板内拼接静音）
  /// 需在 AI 设置中配置 voiceModel（语音模型名），否则抛异常
  /// [speed] 语速控制（0.25-4.0，默认 1.0，听力场景建议 0.8）
  static Future<Uint8List> speech(AiConfig cfg, String text,
      {String voice = 'alloy', String format = 'mp3', double speed = 1.0}) async {
    if (cfg.base.trim().isEmpty) {
      throw Exception('未配置 API 地址，请先填写 AI 设置');
    }
    if (cfg.voiceModel.trim().isEmpty) {
      throw Exception(
          '未配置语音模型。请在「AI 智能出题设置」中填写 voiceModel（如 OpenAI tts-1、通义 cosyvoice-v1、智谱 glm-4v-voice、小米 MiMo mimo-v2.5-tts）。');
    }
    final model = cfg.voiceModel.trim();
    return model.startsWith('mimo-')
        ? await _speechChat(cfg, text, model, format, voice, speed)
        : await _speechAudioEndpoint(cfg, text, model, format, voice, speed);
  }

  /// MiMo 风格：chat/completions + assistant 消息指定合成文本
  static Future<Uint8List> _speechChat(
      AiConfig cfg, String text, String model, String format, String voice, double speed) async {
    var base = cfg.base.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final url = base.endsWith('/chat/completions')
        ? base
        : '$base/chat/completions';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (cfg.key.isNotEmpty) 'Authorization': 'Bearer ${cfg.key}',
    };
    // MiMo 内置音色：mimo_default / 冰糖 / 茉莉 / 苏打 / 白桦 / Mia / Chloe / Milo / Dean
    final v = voice == 'alloy' ? 'mimo_default' : voice;
    final body = json.encode({
      'model': model,
      'messages': [
        {'role': 'assistant', 'content': text},
      ],
      'audio': {
        'format': format == 'mp3' ? 'mp3' : 'wav',
        'voice': v,
        if (speed != 1.0) 'speed': speed,
      },
      'stream': false,
    });
    try {
      final resp = await httpPostJson(url, headers, body);
      if (resp.$1 < 200 || resp.$1 >= 300) {
        throw Exception(
            '语音接口返回错误 ${resp.$1}：${resp.$2.length > 300 ? resp.$2.substring(0, 300) : resp.$2}');
      }
      final data = json.decode(resp.$2) as Map<String, dynamic>;
      final audio = data['choices']?[0]?['message']?['audio'];
      final b64 = audio?['data'];
      if (b64 is! String || b64.isEmpty) {
        throw Exception(
            '语音接口未返回音频数据（message.audio.data）。请核对语音模型名称。返回：${resp.$2.length > 200 ? resp.$2.substring(0, 200) : resp.$2}');
      }
      return base64.decode(b64);
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('语音合成网络请求失败：$e');
    }
  }

  /// OpenAI 风格：/audio/speech 返回二进制
  static Future<Uint8List> _speechAudioEndpoint(AiConfig cfg, String text,
      String model, String format, String voice, double speed) async {
    var base = cfg.base.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final url = base.endsWith('/audio/speech')
        ? base
        : '$base/audio/speech';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (cfg.key.isNotEmpty) 'Authorization': 'Bearer ${cfg.key}',
    };
    final body = json.encode({
      'model': model,
      'input': text,
      'voice': voice,
      'response_format': format,
      if (speed != 1.0) 'speed': speed,
    });
    try {
      final resp = await httpPostBytes(url, headers, body);
      if (resp.$1 < 200 || resp.$1 >= 300) {
        final msg = utf8.decode(resp.$2, allowMalformed: true);
        throw Exception(
            '语音接口返回错误 ${resp.$1}：${msg.length > 300 ? msg.substring(0, 300) : msg}');
      }
      final bytes = resp.$2;
      if (bytes.isEmpty) {
        throw Exception('语音接口返回空音频，请重试或核对语音模型名称。');
      }
      return bytes;
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('语音合成网络请求失败：$e');
    }
  }
}

/// 辅助：POST JSON 返回二进制（用于 audio/speech）
Future<(int, Uint8List)> httpPostBytes(
    String url, Map<String, String> headers, String body) async {
  final resp = await http
      .post(Uri.parse(url), headers: headers, body: body)
      .timeout(const Duration(seconds: 180));
  return (resp.statusCode, resp.bodyBytes);
}

/// 错误友好化
String aiFriendlyError(Object e) {
  final msg = '$e';
  if (RegExp(
          r'image_url|unknown variant|does not support image|image.*not (support|supported)|not.*vision|只接受文本|only.*text',
          caseSensitive: false)
      .hasMatch(msg)) {
    return '当前模型/接口不支持图片识别（只接受文本）。请在顶部「AI 智能出题设置」中改用支持视觉的模型，例如：通义 qwen-vl-max、智谱 glm-4v、OpenAI gpt-4o；DeepSeek 建议先用文字输入。';
  }
  if (RegExp(
          r'API 返回错误 401|Unauthorized|invalid api key|authentication',
          caseSensitive: false)
      .hasMatch(msg)) {
    return 'API Key 无效或未授权，请在「AI 智能出题设置」中检查 API Key。';
  }
  if (RegExp(r'API 返回错误 404|not found', caseSensitive: false)
      .hasMatch(msg)) {
    return '模型名称或接口地址有误（404）。请核对「AI 智能出题设置」中的 API 地址和模型名。';
  }
  if (RegExp(
          r'网络请求失败|fetch failed|ENOTFOUND|ECONNREFUSED|Failed host lookup|No address associated with hostname',
          caseSensitive: false)
      .hasMatch(msg)) {
    return '网络/DNS 解析失败，无法连接到 API 服务器。请检查网络连接或更换网络（部分网络/地区可能无法访问该 API 域名）；本地 Ollama 需先启动。';
  }
  return msg;
}

/// 调试辅助（避免未使用警告）
// ignore: unused_element
bool _debugEnabled = false;
// ignore: unused_element
void _log(String s) {
  if (_debugEnabled) debugPrint(s);
}
