import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// AI 提供商预设
const AI_PROVIDERS = {
  'deepseek': (base: 'https://api.deepseek.com', model: 'deepseek-chat'),
  'openai': (base: 'https://api.openai.com/v1', model: 'gpt-4o-mini'),
  'qwen': (
    base: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-plus'
  ),
  'kimi': (base: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8k'),
  'glm': (
    base: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4-flash'
  ),
  'mimo': (
    base: 'https://api.xiaomimimo.com/v1',
    model: 'mimo-v2.5'
  ),
  'ollama': (base: 'http://localhost:11434/v1', model: 'qwen2.5:7b'),
  'custom': (base: '', model: ''),
};

/// AI 配置
class AiConfig {
  String provider;
  String base;
  String model;
  String key;
  bool encrypted;
  bool decryptFailed;

  AiConfig({
    this.provider = 'deepseek',
    this.base = '',
    this.model = '',
    this.key = '',
    this.encrypted = false,
    this.decryptFailed = false,
  });

  factory AiConfig.fromJson(Map<String, dynamic> j) => AiConfig(
        provider: (j['provider'] as String?) ?? 'deepseek',
        base: (j['base'] as String?) ?? '',
        model: (j['model'] as String?) ?? '',
        key: (j['key'] as String?) ?? '',
        encrypted: (j['encrypted'] as bool?) ?? false,
        decryptFailed: (j['decryptFailed'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'base': base,
        'model': model,
        'key': key,
        'encrypted': encrypted,
        'decryptFailed': decryptFailed,
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
  static Future<String> chat(AiConfig cfg, List<AiChatMessage> messages,
      {double temperature = 0.8}) async {
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
    final body = json.encode({
      'model': cfg.model,
      'messages': [
        for (final m in messages) {'role': m.role, 'content': m.content},
      ],
      'temperature': temperature,
      'stream': false,
    });

    try {
      final resp = await httpPostJson(url, headers, body);
      final text = resp.$2;
      if (resp.$1 < 200 || resp.$1 >= 300) {
        throw Exception(
            'API 返回错误 ${resp.$1}：${text.length > 300 ? text.substring(0, 300) : text}');
      }
      final data = json.decode(text) as Map<String, dynamic>;
      final content = data['choices']?[0]?['message']?['content'];
      if (content == null) {
        throw Exception('API 返回格式异常（缺少 choices[0].message.content）');
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
      .timeout(const Duration(seconds: 90));
  return (resp.statusCode, resp.body);
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
  if (RegExp(r'网络请求失败|fetch failed|ENOTFOUND|ECONNREFUSED',
          caseSensitive: false)
      .hasMatch(msg)) {
    return '网络请求失败，请检查网络连接或 API 地址（本地 Ollama 需先启动）。';
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
