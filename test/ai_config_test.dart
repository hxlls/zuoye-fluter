import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/ai/ai_client.dart';

/// 多端点配置（方案 C：端点列表 + 用途绑定）的结构与迁移守卫。
void main() {
  group('旧配置迁移', () {
    test('旧格式（单套 base/model/key）自动迁移成 1 个端点', () {
      final cfg = AiConfig.fromJson({
        'provider': 'deepseek',
        'base': 'https://api.deepseek.com',
        'model': 'deepseek-flash',
        'voiceModel': '',
        'key': 'sk-x',
        'encrypted': true,
        'decryptFailed': false,
      });
      expect(cfg.endpoints.length, 1);
      expect(cfg.main!.model, 'deepseek-flash');
      // voiceId 指向同一点端（旧版语音与主模型同厂商）
      expect(cfg.voice!.id, cfg.main!.id);
      // 兼容层仍然读得到旧字段
      expect(cfg.base, 'https://api.deepseek.com');
      expect(cfg.provider, 'deepseek');
    });

    test('兼容旧构造用法：传旧命名参数即生成主端点', () {
      final cfg = AiConfig(provider: 'mimo', base: 'B', model: 'M', voiceModel: 'V');
      expect(cfg.endpoints.length, 1);
      expect(cfg.base, 'B');
      expect(cfg.model, 'M');
      expect(cfg.voiceModel, 'V');
    });

    test('无参构造不生成端点（用户尚未配置）', () {
      final cfg = AiConfig();
      expect(cfg.endpoints, isEmpty);
      expect(cfg.main, isNull);
      expect(cfg.voice, isNull);
      expect(cfg.usable, false);
    });
  });

  group('多端点 + 用途绑定', () {
    final ds = AiEndpoint(
        id: 'a', provider: 'deepseek', base: 'B1', model: 'deepseek-flash');
    final mm = AiEndpoint(
        id: 'b',
        provider: 'mimo',
        base: 'B2',
        model: 'mimo-v2.5',
        voiceModel: 'mimo-v2.5-tts');

    test('main 与 voice 可指向不同端点（DeepSeek 出题 + MiMo 配音）', () {
      final cfg = AiConfig(endpoints: [ds, mm], mainId: 'a', voiceId: 'b');
      expect(cfg.main!.id, 'a');
      expect(cfg.voice!.id, 'b');
      // 兼容层：base 取主端点，voiceModel 取语音端点
      expect(cfg.base, 'B1');
      expect(cfg.voiceModel, 'mimo-v2.5-tts');
      expect(cfg.voiceReady, true);
    });

    test('voiceId 未设置时回落到主端点（单端点也能配音）', () {
      final cfg = AiConfig(endpoints: [mm], mainId: 'b');
      expect(cfg.voice!.id, 'b');
      expect(cfg.voiceModel, 'mimo-v2.5-tts');
    });

    test('mainId 指向已删除的端点时回落到第一个', () {
      final cfg = AiConfig(endpoints: [ds, mm], mainId: '已不存在');
      expect(cfg.main!.id, 'a');
    });

    test('voiceReady：地址或语音模型缺失时为 false', () {
      final cfg = AiConfig(
          endpoints: [AiEndpoint(id: 'x', base: '', model: 'm', voiceModel: 'v')],
          mainId: 'x');
      expect(cfg.voiceReady, false); // 地址为空
    });

    test('序列化往返不丢结构', () {
      final cfg = AiConfig(endpoints: [ds, mm], mainId: 'a', voiceId: 'b');
      final back = AiConfig.fromJson(
          json.decode(json.encode(cfg.toJson())) as Map<String, dynamic>);
      expect(back.endpoints.length, 2);
      expect(back.main!.id, 'a');
      expect(back.voice!.id, 'b');
      expect(back.voiceModel, 'mimo-v2.5-tts');
    });
  });

  group('端点的 TTS 接口风格', () {
    test('优先取服务商预设声明', () {
      expect(
          AiEndpoint(provider: 'mimo', voiceModel: 'mimo-v2.5-tts').ttsStyle, 'chat');
      expect(AiEndpoint(provider: 'openai', voiceModel: 'tts-1').ttsStyle, 'audio');
      expect(
          AiEndpoint(provider: 'qwen', voiceModel: 'cosyvoice-v1').ttsStyle, 'audio');
    });

    test('自定义服务商（预设声明为 auto）按前缀推断', () {
      // 回归守卫：早先 custom 在预设里被写成 'audio'，
      // 导致这里的 chat 推断永远走不到（死代码）
      expect(AiEndpoint(provider: 'custom', voiceModel: 'mimo-x').ttsStyle, 'chat');
      expect(AiEndpoint(provider: 'custom', voiceModel: 'other-tts').ttsStyle, 'audio');
      expect(AiEndpoint(provider: 'unknown-vendor', voiceModel: 'mimo-y').ttsStyle,
          'chat');
    });

    test('预设的明确声明优先于前缀推断', () {
      // openai 声明 audio，即便模型名带 mimo- 前缀也按声明走
      expect(AiEndpoint(provider: 'openai', voiceModel: 'mimo-weird').ttsStyle,
          'audio');
    });

    test('hasTts 由 voiceModel 是否为空决定', () {
      expect(AiEndpoint(voiceModel: 'tts-1').hasTts, true);
      expect(AiEndpoint(voiceModel: '').hasTts, false);
      expect(AiEndpoint(voiceModel: '   ').hasTts, false);
    });
  });
}
