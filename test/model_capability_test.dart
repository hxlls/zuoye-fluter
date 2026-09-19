import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/ai/ai_client.dart';

/// 模型能力表的守卫测试。
///
/// 这张表是「模型能不能看图 / 能不能出声」的**单一来源**，
/// 一旦被改错，会直接影响多模态请求与听力配音的走向，所以把行为锁住。
void main() {
  test('已知模型：能力查得到', () {
    final v41 = ModelCapability.of('deepseek-v4.1-flash');
    expect(v41.vision, true);
    expect(v41.tts, true);
    expect(v41.isKnown, true);

    final old = ModelCapability.of('deepseek-v4-flash');
    expect(old.vision, false);
    expect(old.tts, false);
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
    expect(ModelCapability.of('  DeepSeek-V4.1-Flash  ').vision, true);
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
