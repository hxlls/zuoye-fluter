import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/ai/ai_client.dart';

/// 模型能力表的守卫测试。
///
/// 这张表是「模型能不能看图 / 能不能出声」的**单一来源**，
/// 一旦被改错，会直接影响多模态请求与听力配音的走向，所以把行为锁住。
void main() {
  test('已知模型：能力查得到', () {
    // 模型名以 GET /models 的实际返回为准（2026-09 实测只有这两个）
    final flash = ModelCapability.of('deepseek-flash');
    expect(flash.vision, true);   // 多模态实测可用
    expect(flash.tts, false);     // 该 endpoint 不提供 TTS
    expect(flash.isKnown, true);

    final pro = ModelCapability.of('deepseek-v4-pro');
    expect(pro.vision, true);
    expect(pro.tts, false);
  });

  test('小米 MiMo：实测结论已锁住（多模态可用，TTS 走独立模型）', () {
    final base = ModelCapability.of('mimo-v2.5');
    expect(base.vision, true); // 实测：响应带 image_tokens
    expect(base.tts, false);   // 语音要换 mimo-v2.5-tts

    final tts = ModelCapability.of('mimo-v2.5-tts');
    expect(tts.tts, true);
    expect(tts.vision, false);
  });

  test('未知模型：按「未知即尝试」处理，不预设为不支持', () {
    final c = ModelCapability.of('some-brand-new-model-9000');
    expect(c.vision, isNull);
    expect(c.tts, isNull);
    expect(c.isKnown, false);
    expect(c.tryVision, true);
    expect(c.tryTts, true);
  });

  test('查询对大小写与首尾空白不敏感', () {
    expect(ModelCapability.of('  DeepSeek-Flash  ').vision, true);
    expect(ModelCapability.of('QWEN-VL-MAX').vision, true);
  });

  group('AiModels.parse —— /models 响应解析', () {
    test('标准 OpenAI 格式', () {
      final ids = AiModels.parse(
          '{"object":"list","data":[{"id":"b-model"},{"id":"a-model"}]}');
      expect(ids, ['a-model', 'b-model']); // 已排序
    });

    test('忽略非 id 项与重复项', () {
      final ids = AiModels.parse(
          '{"data":[{"id":"x"},{"foo":1},{"id":"x"},{"id":"  "},{"id":"y"}]}');
      expect(ids, ['x', 'y']);
    });

    test('缺少 data 数组时抛异常（不硬当成功）', () {
      expect(() => AiModels.parse('{"object":"list"}'), throwsException);
      expect(() => AiModels.parse('[]'), throwsException);
    });

    test('空列表不报错', () {
      expect(AiModels.parse('{"data":[]}'), isEmpty);
    });
  });

  test('纯 TTS 模型可被识别（设置界面据此标「仅配音」）', () {
    expect(ModelCapability.of('mimo-v2.5-tts').pureTts, true);
    expect(ModelCapability.of('tts-1').pureTts, true);
    // 既能看图也能出声：不是纯 TTS，标「仅配音」会误伤
    expect(ModelCapability.of('glm-4v-voice').pureTts, false);
    // 对话模型
    expect(ModelCapability.of('mimo-v2.5').pureTts, false);
    // 未知模型不下结论
    expect(ModelCapability.of('brand-new-9000').pureTts, false);
  });

  group('语音模型候选排序 —— sortForTts', () {
    test('支持配音 → 未知 → 已知不支持', () {
      final out = ModelCapability.sortForTts([
        'mimo-v2.5',            // 已知不支持配音
        'mimo-v2.5-tts',        // 已知支持配音
        'brand-new-tts-model',  // 未知：不过滤，排在中间
      ]);
      expect(out, ['mimo-v2.5-tts', 'brand-new-tts-model', 'mimo-v2.5']);
    });

    test('同权重按名称升序，且不改动入参', () {
      final src = [
        'mimo-v2.5-tts-voicedesign',
        'mimo-v2.5-tts',
        'mimo-v2.5-tts-voiceclone',
      ];
      final out = ModelCapability.sortForTts(src);
      expect(out, [
        'mimo-v2.5-tts',
        'mimo-v2.5-tts-voiceclone',
        'mimo-v2.5-tts-voicedesign',
      ]);
      expect(src.first, 'mimo-v2.5-tts-voicedesign', reason: '入参不应被改动');
    });

    test('ttsRank 三档权重', () {
      expect(ModelCapability.ttsRank('mimo-v2.5-tts'), 0);
      expect(ModelCapability.ttsRank('whatever-9000'), 1);
      expect(ModelCapability.ttsRank('mimo-v2.5'), 2);
    });

    test('空列表与单元素不炸', () {
      expect(ModelCapability.sortForTts([]), isEmpty);
      expect(ModelCapability.sortForTts(['only-one']), ['only-one']);
    });
  });

  test('预设里的服务商默认模型都应能在能力表中找到（防止两张表漂移）', () {
    final missing = <String>[];
    for (final e in AI_PROVIDERS.entries) {
      if (e.key == 'custom') continue;
      if (!ModelCapability.of(e.value.model).isKnown) missing.add('${e.key}: ${e.value.model}');
    }
    expect(missing, isEmpty,
        reason: '以下服务商的默认模型没登记能力，请补 MODEL_CAPABILITIES：$missing');
  });
}
