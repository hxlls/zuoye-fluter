import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// AI 接口预设。
class AiProviderPreset {
  final String label;
  final String base;
  const AiProviderPreset({required this.label, required this.base});
}

/// AI 服务商预设。
class AiProviderInfo {
  final String label;
  final List<AiProviderPreset> presets;
  final String model;
  final String voice;
  final String ttsStyle;
  const AiProviderInfo({
    required this.label,
    required this.presets,
    required this.model,
    required this.voice,
    required this.ttsStyle,
  });
}

/// 各服务商的预设接口、默认模型与 TTS 风格。
///
/// 字段：
/// - `presets`：该服务商支持的接口地址候选（第一个为官方默认，最后一个通常是「自定义」）
/// - `model`：文本（及多模态）默认模型
/// - `voice`：**语音合成模型**，听力配音用。**空字符串 = 该服务商不提供 TTS**
/// - `ttsStyle`：TTS 接口风格，决定走哪个端点（见 AiTts.speech）
///   - `'audio'`：POST /audio/speech，响应即音频二进制（OpenAI / 通义 / 智谱）
///   - `'chat'` ：POST /chat/completions 带 audio 参数，音频在
///     choices[0].message.audio.data（MiMo 属此类）
///   - `'auto'` ：风格未知（自定义地址），由语音模型名前缀推断
const AI_PROVIDERS = <String, AiProviderInfo>{
  // DeepSeek：模型名以 `GET /models` 的返回为准 —— 2026-09 实测只有
  // `deepseek-flash` 与 `deepseek-v4-pro`（写成 deepseek-flash 会被拒）。
  // 两者**均支持多模态**（实测发 1x1 图片被正常接受）。
  // 但**该 endpoint 不提供 TTS**：/audio/speech 返回 404，chat 的 audio
  // 参数会被静默忽略（200 但无 audio 字段），故 voice 留空。
  // 若你的服务确实支持语音，把 voice 填上模型名、ttsStyle 按接口实际形态选即可。
  'deepseek': AiProviderInfo(
    label: 'DeepSeek',
    presets: [
      AiProviderPreset(label: '官方 API', base: 'https://api.deepseek.com'),
      AiProviderPreset(label: '自定义', base: ''),
    ],
    model: 'deepseek-flash',
    voice: '',
    ttsStyle: 'chat',
  ),
  'openai': AiProviderInfo(
    label: 'OpenAI',
    presets: [
      AiProviderPreset(label: '官方 API', base: 'https://api.openai.com/v1'),
      AiProviderPreset(label: '自定义', base: ''),
    ],
    model: 'gpt-4o-mini',
    voice: 'tts-1',
    ttsStyle: 'audio',
  ),
  'qwen': AiProviderInfo(
    label: '通义千问',
    presets: [
      AiProviderPreset(
          label: '官方兼容模式',
          base: 'https://dashscope.aliyuncs.com/compatible-mode/v1'),
      AiProviderPreset(label: '自定义', base: ''),
    ],
    model: 'qwen-plus',
    voice: 'cosyvoice-v1',
    ttsStyle: 'audio',
  ),
  'kimi': AiProviderInfo(
    label: 'Kimi',
    presets: [
      AiProviderPreset(label: '官方 API', base: 'https://api.moonshot.cn/v1'),
      AiProviderPreset(label: '自定义', base: ''),
    ],
    model: 'moonshot-v1-8k',
    voice: '',
    ttsStyle: 'audio',
  ),
  'glm': AiProviderInfo(
    label: '智谱 GLM',
    presets: [
      AiProviderPreset(
          label: '官方 API', base: 'https://open.bigmodel.cn/api/paas/v4'),
      AiProviderPreset(label: '自定义', base: ''),
    ],
    model: 'glm-4-flash',
    voice: 'glm-4v-voice',
    ttsStyle: 'audio',
  ),
  'mimo': AiProviderInfo(
    label: '小米 MiMo',
    presets: [
      AiProviderPreset(label: '官方 API', base: 'https://api.xiaomimimo.com/v1'),
      AiProviderPreset(label: '自定义', base: ''),
    ],
    model: 'mimo-v2.5',
    voice: 'mimo-v2.5-tts',
    ttsStyle: 'chat',
  ),
  'ollama': AiProviderInfo(
    label: 'Ollama 本地',
    presets: [
      AiProviderPreset(label: '本地默认', base: 'http://localhost:11434/v1'),
      AiProviderPreset(label: '自定义', base: ''),
    ],
    model: 'qwen2.5:7b',
    voice: '',
    ttsStyle: 'audio',
  ),
  // 自定义地址：接口风格未知，声明为 'auto'，由 AiEndpoint.ttsStyle
  // 按语音模型名前缀推断（mimo- 系走 chat，其余走 /audio/speech）
  'custom': AiProviderInfo(
    label: '自定义',
    presets: [
      AiProviderPreset(label: '自定义地址', base: ''),
    ],
    model: '',
    voice: '',
    ttsStyle: 'auto',
  ),
};

/// 模型能力表 —— **能力判断的单一来源**。
///
/// 只登记**已知**模型。表里查不到的按「未知即尝试」处理（见 [ModelCapability.of]）：
/// 直接把请求发出去、靠报错反推。这样模型迭代时不必改代码，
/// 只在**实测确认不支持**时补一条即可。
///
/// ⚠️ **使用纪律：只登记实测确认过的能力。** 未验证的模型宁可留空 ——
/// 查不到会走「未知即尝试」（安全），而**标错会直接误导**：
/// 把支持视觉的模型标成 false，它会在发图前被短路拦截，功能直接不可用。
/// 模型名同理：必须以 `GET /models` 的实际返回为准，不能照搬产品宣传里的名字。
///
/// 为什么能力按「模型名」而不是「服务商」登记：
/// 同一服务商的不同模型能力可以完全不同（通义 qwen-plus 不支持视觉，
/// qwen-vl-max 支持），所以能力属于模型，服务商那一层只管地址与默认值。
///
/// - `vision`：能否接受图片输入（多模态理解）
/// - `tts`：能否输出音频（语音合成）
const MODEL_CAPABILITIES = <String, ({bool vision, bool tts})>{
  // DeepSeek —— 以 GET /models 的实际返回为准（2026-09 实测）
  'deepseek-flash': (vision: true, tts: false),
  'deepseek-v4-pro': (vision: true, tts: false),
  // OpenAI
  'gpt-4o': (vision: true, tts: false),
  'gpt-4o-mini': (vision: true, tts: false),
  'tts-1': (vision: false, tts: true),
  // 通义
  'qwen-vl-max': (vision: true, tts: false),
  'qwen-plus': (vision: false, tts: false),
  'cosyvoice-v1': (vision: false, tts: true),
  // 智谱
  'glm-4v': (vision: true, tts: false),
  'glm-4v-voice': (vision: true, tts: true),
  'glm-4-flash': (vision: false, tts: false),
  // 小米 MiMo —— 下面的模型清单与能力**全部实测确认**（2026-09）
  'mimo-v2.5': (vision: true, tts: false), // 多模态可用：响应带 image_tokens
  'mimo-v2.5-pro': (vision: true, tts: false),
  'mimo-v2.5-asr': (vision: false, tts: false), // 语音识别，非 TTS
  'mimo-v2.5-tts': (vision: false, tts: true), // TTS 可用：响应带 message.audio.data
  'mimo-v2.5-tts-voiceclone': (vision: false, tts: true),
  'mimo-v2.5-tts-voicedesign': (vision: false, tts: true),
  // Kimi
  'moonshot-v1-8k': (vision: false, tts: false),
  // Ollama（本地；默认的 qwen2.5:7b 是纯文本模型。
  // 本机若换跑 llava 等多模态模型，在设置里改成对应模型名即可，
  // 未登记的模型会按「未知即尝试」处理，不会被误拦）
  'qwen2.5:7b': (vision: false, tts: false),
};

/// 单个模型的能力查询结果。
///
/// 字段为 `null` 表示**未知**（表里没登记）—— 未知不代表「不支持」，
/// 而是「去试试看」。调用方应使用 [tryVision] / [tryTts]，
/// 它们把「未知」视作「允许尝试」。
class ModelCapability {
  /// 能否接受图片输入。`null` = 未知
  final bool? vision;

  /// 能否输出音频。`null` = 未知
  final bool? tts;

  const ModelCapability(this.vision, this.tts);

  /// 按模型名查询（大小写与首尾空白不敏感）。
  static ModelCapability of(String model) {
    final hit = MODEL_CAPABILITIES[model.trim().toLowerCase()];
    if (hit != null) return ModelCapability(hit.vision, hit.tts);
    return const ModelCapability(null, null);
  }

  /// 是否应当按「支持图片」去尝试。未知 → true。
  bool get tryVision => vision ?? true;

  /// 是否应当按「支持音频输出」去尝试。未知 → true。
  bool get tryTts => tts ?? true;

  /// 是否已登记（false = 表里没有，结论未知）
  bool get isKnown => vision != null || tts != null;

  /// 是否**只会出声、不能对话**（纯 TTS 模型）。
  ///
  /// 这类模型与对话模型混在同一份 `/models` 清单里，很容易被选成主模型 ——
  /// 拿它去 /chat/completions 出题必然失败。设置界面据此标注「仅配音」。
  /// **未知模型一律不算**纯 TTS：不替用户下结论（未知即尝试）。
  bool get pureTts => tts == true && vision != true;

  /// 作为「语音模型」候选时的排序权重：
  /// 已知支持配音 → 0，未知 → 1，已知不支持配音 → 2。
  ///
  /// 这里只算权重、**不做过滤** —— 未知模型照样出现在候选里，只是排在后面。
  /// 能力表不认识的模型很可能正是该接口专属的配音模型（如 tts-1-hd），
  /// 提前滤掉等于替用户挡路。
  static int ttsRank(String model) {
    final t = of(model).tts;
    if (t == true) return 0;
    if (t == null) return 1;
    return 2;
  }

  /// 按配音能力给模型清单排序，返回**新列表**（不改动入参）。
  /// 同权重按名称升序 —— 保证下拉顺序稳定，不随接口返回顺序跳动。
  static List<String> sortForTts(List<String> models) {
    final out = [...models];
    out.sort((a, b) {
      final byRank = ttsRank(a).compareTo(ttsRank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
    return out;
  }
}

/// AI 配置
/// 一个 API 端点：一份独立的「地址 + Key + 模型」。
///
/// 为什么要支持多个：不同厂商能力不同 —— DeepSeek 支持多模态但不提供 TTS，
/// 小米 MiMo 提供 TTS。此前只有一套 base/key，语音只能与主模型同厂商，
/// 既无法分工，也无法为不同任务选不同模型。
class AiEndpoint {
  String id;

  /// 显示名（如「DeepSeek 主力」），仅用于界面
  String name;

  /// AI_PROVIDERS 的 key，用于取预设默认值与 TTS 接口风格
  String provider;

  String base;
  String model;

  /// 该端点的语音合成模型（听力配音用）。
  /// **空 = 这个端点不提供 TTS**（旧行为里 voiceModel 为空即是此意）。
  String voiceModel;

  /// 密钥。内存中为明文；落盘时写入系统安全存储（见 AiStore）。
  String key;
  bool encrypted;
  bool decryptFailed;

  AiEndpoint({
    String? id,
    this.name = '',
    this.provider = 'deepseek',
    this.base = '',
    this.model = '',
    this.voiceModel = '',
    this.key = '',
    this.encrypted = false,
    this.decryptFailed = false,
  }) : id = id ?? newEndpointId();

  /// TTS 接口风格。
  ///
  /// 优先级：服务商预设的**明确**声明（'chat' / 'audio'）→
  /// 否则（'auto' 或未登记的服务商）按语音模型名前缀推断 ——
  /// mimo- 系走 chat/completions + audio，其余走 /audio/speech。
  ///
  /// ⚠️ 早先写成 `AI_PROVIDERS[provider]?.ttsStyle ?? (前缀判断)`，
  /// 因为 custom 也在预设表里、且默认给了 'audio'，导致 `??` 右侧
  /// **永远不执行**，前缀推断成了死代码（自定义地址配上 MiMo 风格接口会错）。
  String get ttsStyle {
    final declared = AI_PROVIDERS[provider]?.ttsStyle;
    if (declared == 'chat' || declared == 'audio') return declared!;
    return voiceModel.startsWith('mimo-') ? 'chat' : 'audio';
  }

  /// 该端点是否具备语音合成能力
  bool get hasTts => voiceModel.trim().isNotEmpty;

  factory AiEndpoint.fromJson(Map<String, dynamic> j) => AiEndpoint(
        id: (j['id'] as String?) ?? newEndpointId(),
        name: (j['name'] as String?) ?? '',
        provider: (j['provider'] as String?) ?? 'deepseek',
        base: (j['base'] as String?) ?? '',
        model: (j['model'] as String?) ?? '',
        voiceModel: (j['voiceModel'] as String?) ?? '',
        key: (j['key'] as String?) ?? '',
        encrypted: (j['encrypted'] as bool?) ?? false,
        decryptFailed: (j['decryptFailed'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider,
        'base': base,
        'model': model,
        'voiceModel': voiceModel,
        'key': key,
        'encrypted': encrypted,
        'decryptFailed': decryptFailed,
      };
}

String newEndpointId() =>
    'ep_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond % 1000}';

/// AI 配置：若干**端点** + 「用途 → 端点」的绑定。
///
/// 分两层是为了让两件变化节奏不同的事各自独立：
/// - **端点列表**：可任意增删（换厂商、加备用、按能力分工）
/// - **用途绑定**：`main`（出题 / 帮答 / 看图）与 `voice`（听力配音）各用哪个端点
///
/// **兼容层**：保留了旧版的 provider / base / model / key / voiceModel 读写接口
/// （getter / setter 代理到 main 与 voice 端点），
/// 因此各面板与 ai_generator 里既有的 `cfg.base` 这类访问**无需任何改动**。
class AiConfig {
  List<AiEndpoint> endpoints;

  /// 主模型端点 id（出题 / 帮答 / 看图）
  String? mainId;

  /// 语音端点 id（听力配音）。为空时**回落到主端点**，保持旧行为。
  String? voiceId;

  AiConfig({
    List<AiEndpoint>? endpoints,
    this.mainId,
    this.voiceId,
    // ---- 以下为兼容旧构造用法：传任一项即自动生成/更新主端点 ----
    String? provider,
    String? base,
    String? model,
    String? key,
    String? voiceModel,
  }) : endpoints = endpoints ?? [] {
    final wantsLegacy = provider != null ||
        base != null ||
        model != null ||
        key != null ||
        voiceModel != null;
    if (this.endpoints.isEmpty && wantsLegacy) {
      final ep = AiEndpoint(
        id: 'ep_legacy',
        name: '默认端点',
        provider: provider ?? 'deepseek',
        base: base ?? '',
        model: model ?? '',
        voiceModel: voiceModel ?? '',
        key: key ?? '',
      );
      this.endpoints.add(ep);
      this.mainId = ep.id;
      this.voiceId = ep.id;
    }
  }

  AiEndpoint? _byId(String? id) {
    if (id == null) return null;
    for (final e in endpoints) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// 主端点。未指定或已被删除时回落到第一个端点。
  AiEndpoint? get main {
    final hit = _byId(mainId);
    if (hit != null) return hit;
    return endpoints.isEmpty ? null : endpoints.first;
  }

  /// 语音端点。未指定时回落到主端点（单端点配置也能配音）。
  AiEndpoint? get voice => _byId(voiceId) ?? main;

  /// 是否有端点已配置到「可用」程度
  bool get usable {
    final m = main;
    return m != null && m.base.trim().isNotEmpty && m.model.trim().isNotEmpty;
  }

  bool get hasVoice => voice?.hasTts ?? false;

  /// 语音是否**就绪**：语音端点的地址与语音模型都已配置。
  /// 注意不能只看 [base]（那是主端点的）—— 语音可能来自另一个厂商。
  bool get voiceReady {
    final v = voice;
    return v != null && v.base.trim().isNotEmpty && v.voiceModel.trim().isNotEmpty;
  }

  // ------------- 兼容旧接口 -------------
  String get provider => main?.provider ?? 'deepseek';
  set provider(String v) { main?.provider = v; }
  String get base => main?.base ?? '';
  set base(String v) { main?.base = v; }
  String get model => main?.model ?? '';
  set model(String v) { main?.model = v; }
  String get key => main?.key ?? '';
  set key(String v) { main?.key = v; }
  String get voiceModel => voice?.voiceModel ?? '';
  set voiceModel(String v) { voice?.voiceModel = v; }
  bool get encrypted => main?.encrypted ?? false;
  bool get decryptFailed => endpoints.any((e) => e.decryptFailed);

  factory AiConfig.fromJson(Map<String, dynamic> j) {
    // ---- 新格式：endpoints 列表 ----
    final rawEps = j['endpoints'];
    if (rawEps is List) {
      final eps = <AiEndpoint>[];
      for (final e in rawEps) {
        if (e is Map) {
          eps.add(AiEndpoint.fromJson(Map<String, dynamic>.from(e)));
        }
      }
      if (eps.isNotEmpty) {
        return AiConfig(
          endpoints: eps,
          mainId: j['mainId'] as String?,
          voiceId: j['voiceId'] as String?,
        );
      }
    }
    // ---- 旧格式迁移：单套 base/model/key/voiceModel → 1 个端点 ----
    final ep = AiEndpoint(
      id: 'ep_legacy',
      name: '默认端点',
      provider: (j['provider'] as String?) ?? 'deepseek',
      base: (j['base'] as String?) ?? '',
      model: (j['model'] as String?) ?? '',
      voiceModel: (j['voiceModel'] as String?) ?? '',
      key: (j['key'] as String?) ?? '',
      encrypted: (j['encrypted'] as bool?) ?? false,
      decryptFailed: (j['decryptFailed'] as bool?) ?? false,
    );
    return AiConfig(endpoints: [ep], mainId: ep.id, voiceId: ep.id);
  }

  Map<String, dynamic> toJson() => {
        'endpoints': [for (final e in endpoints) e.toJson()],
        'mainId': mainId,
        'voiceId': voiceId,
      };
}

/// AI 配置存储：共享参数存 SharedPreferences，Key 用系统级加密
class AiStore {
  static const _prefsKey = 'aiConfig';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// 旧版只有一个密钥槽位，迁移时作为兜底读取
  static const _legacySecKey = 'ai_api_key';

  /// 每个端点一个独立槽位（同一 App 内多厂商 Key 互不覆盖）
  static String _secKeyFor(String endpointId) => 'ai_api_key_$endpointId';

  static Future<AiConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final cfg = raw != null
        ? AiConfig.fromJson(json.decode(raw) as Map<String, dynamic>)
        : AiConfig();

    for (final e in cfg.endpoints) {
      if (!e.encrypted || e.key.isEmpty) continue;
      try {
        var plain = await _storage.read(key: _secKeyFor(e.id));
        // 旧版配置的密钥存在单一槽位里，迁移时兜底取一次
        plain ??= await _storage.read(key: _legacySecKey);
        if (plain != null) {
          e.key = plain;
          e.decryptFailed = false;
        } else {
          e.key = '';
          e.decryptFailed = true;
        }
      } catch (err) {
        e.key = '';
        e.decryptFailed = true;
      }
    }
    return cfg;
  }

  static Future<void> save(AiConfig cfg) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = cfg.toJson();
    final eps = stored['endpoints'] as List;

    for (var i = 0; i < cfg.endpoints.length; i++) {
      final e = cfg.endpoints[i];
      final m = eps[i] as Map<String, dynamic>;
      if (e.key.isEmpty) {
        m['encrypted'] = false;
        continue;
      }
      try {
        await _storage.write(key: _secKeyFor(e.id), value: e.key);
        m['key'] = 'encrypted';
        m['encrypted'] = true;
      } catch (err) {
        // 系统安全存储不可用时退化为明文，与旧版行为一致
        m['key'] = e.key;
        m['encrypted'] = false;
      }
      m['decryptFailed'] = false;
    }

    await prefs.setString(_prefsKey, json.encode(stored));
    // 迁移完成后清掉旧槽位（新槽位已写入）
    try {
      await _storage.delete(key: _legacySecKey);
    } catch (err) {
      // 忽略：清理旧密钥失败不影响使用
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    // 逐个端点清除各自的密钥槽位
    if (raw != null) {
      try {
        final cfg = AiConfig.fromJson(json.decode(raw) as Map<String, dynamic>);
        for (final e in cfg.endpoints) {
          try {
            await _storage.delete(key: _secKeyFor(e.id));
          } catch (err) {
            // 忽略单个端点清理失败
          }
        }
      } catch (err) {
        // 忽略：配置解析失败也要继续清空
      }
    }
    await prefs.remove(_prefsKey);
    try {
      await _storage.delete(key: _legacySecKey);
    } catch (err) {
      // 忽略：清除密钥失败不影响登出
    }
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
      // 已知不支持图片的模型：直接给出明确提示，不必发一个注定失败的请求
      // （表里查不到的按「未知即尝试」处理，不受此影响）
      // 用 cfg.model：此处作用域内还没有 model 局部变量
      if (ModelCapability.of(cfg.model).vision == false) {
        throw Exception(
            '当前模型 ${cfg.model} 不支持图片识别。请在「AI 智能出题设置」中改用支持视觉的模型（如 deepseek-flash）。');
      }
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

/// 模型列表（OpenAI 兼容 `GET {base}/models`）
///
/// 用途：让用户在设置里一键拉取「当前 Key 可用的模型」，免去手输模型名。
///
/// 实测（2026-09）DeepSeek / OpenAI / Kimi / 智谱 / 通义 / 小米 MiMo
/// 六家的该端点均可用；DeepSeek 的 `{base}` 不含 `/v1` 也能直接拼 `/models`。
/// 若某接口没有这个端点，调用方会收到 404 并被转成友好提示，
/// 用户仍可手动输入模型名 —— 所以这只是便利功能，不是必需路径。
///
/// ⚠️ 注意：该端点**只返回模型 id，不含能力信息**
/// （OpenAI 规范的字段只有 id / object / created / owned_by）。
/// 「能不能看图 / 能不能出声」要另查 [MODEL_CAPABILITIES] 或实际探测。
class AiModels {
  /// 拉取模型 id 列表。失败时抛异常（由调用方用 aiFriendlyError 转成提示）。
  static Future<List<String>> list(AiConfig cfg) async {
    final base = _trimSlash(cfg.base);
    if (base.isEmpty) {
      throw Exception('未配置 API 地址');
    }
    final headers = <String, String>{
      if (cfg.key.isNotEmpty) 'Authorization': 'Bearer ${cfg.key}',
    };
    final resp = await http
        .get(Uri.parse('$base/models'), headers: headers)
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = resp.body;
      throw Exception(
          'API 返回错误 ${resp.statusCode}：${body.length > 200 ? body.substring(0, 200) : body}');
    }
    return parse(resp.body);
  }

  /// 解析 `/models` 响应体。抽成纯函数便于单测。
  ///
  /// 容错：只取 `data[].id` 是字符串的项；`data` 不是数组时抛异常
  /// （说明这个接口不是 OpenAI 兼容格式，不该硬当成功处理）。
  static List<String> parse(String body) {
    final decoded = json.decode(body);
    if (decoded is! Map) {
      throw Exception('返回格式不是 OpenAI 兼容的 /models');
    }
    final data = decoded['data'];
    if (data is! List) {
      throw Exception('返回格式不是 OpenAI 兼容的 /models（缺少 data 数组）');
    }
    final out = <String>[];
    for (final e in data) {
      if (e is Map && e['id'] is String) {
        final id = (e['id'] as String).trim();
        if (id.isNotEmpty && !out.contains(id)) out.add(id);
      }
    }
    out.sort();
    return out;
  }

  static String _trimSlash(String s) {
    var v = s.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }
}

/// 语音合成（听力配音）
///
/// 两种接口风格，由 AI_PROVIDERS 的 `ttsStyle` **显式声明**，不再靠模型名前缀去猜：
/// 1) `'audio'`：POST /audio/speech，响应即音频二进制（OpenAI tts-1、通义 cosyvoice 等）
/// 2) `'chat'` ：POST /chat/completions，assistant 消息 content 为待合成文本，
///    响应 choices[0].message.audio.data 为 base64 音频（MiMo；DeepSeek V4.1 Flash 同属此类）
class AiTts {
  /// 生成音频字节（默认 mp3；wav 用于面板内拼接静音）
  /// 需在 AI 设置中配置 voiceModel（语音模型名），否则抛异常
  /// [speed] 语速控制（0.25-4.0，默认 1.0，听力场景建议 0.8）
  static Future<Uint8List> speech(AiConfig cfg, String text,
      {String voice = 'alloy', String format = 'mp3', double speed = 1.0}) async {
    // 语音走的是 **voice 端点**，可以与主模型不同厂商：
    // 例如主模型用 DeepSeek（支持看图但不出声）、语音用小米 MiMo（支持 TTS）。
    // voiceId 未设置时会回落到主端点，单端点配置的行为与旧版完全一致。
    final ep = cfg.voice;
    if (ep == null || ep.base.trim().isEmpty) {
      throw Exception('未配置 API 地址，请先填写 AI 设置');
    }
    final model = ep.voiceModel.trim();
    if (model.isEmpty) {
      throw Exception(
          '未配置语音模型。请在「AI 智能出题设置」中填写语音模型（如 OpenAI tts-1、通义 cosyvoice-v1、智谱 glm-4v-voice、小米 MiMo mimo-v2.5-tts）。');
    }
    // 风格由端点自身决定：服务商预设的显式声明优先，自定义服务商按前缀兜底
    return ep.ttsStyle == 'chat'
        ? await _speechChat(ep, text, model, format, voice, speed)
        : await _speechAudioEndpoint(ep, text, model, format, voice, speed);
  }

  /// MiMo 风格：chat/completions + assistant 消息指定合成文本
  static Future<Uint8List> _speechChat(AiEndpoint ep, String text, String model,
      String format, String voice, double speed) async {
    var base = ep.base.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final url = base.endsWith('/chat/completions')
        ? base
        : '$base/chat/completions';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (ep.key.isNotEmpty) 'Authorization': 'Bearer ${ep.key}',
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
  static Future<Uint8List> _speechAudioEndpoint(AiEndpoint ep, String text,
      String model, String format, String voice, double speed) async {
    var base = ep.base.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final url = base.endsWith('/audio/speech')
        ? base
        : '$base/audio/speech';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (ep.key.isNotEmpty) 'Authorization': 'Bearer ${ep.key}',
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
    return '当前模型/接口不支持图片识别（只接受文本）。请在顶部「AI 智能出题设置」中改用支持视觉的模型，例如 DeepSeek deepseek-flash、通义 qwen-vl-max、智谱 glm-4v、OpenAI gpt-4o。';
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
