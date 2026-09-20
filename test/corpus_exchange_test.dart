/// 语料交换文件（导出 / 导入）的往返契约。
///
/// 「导出的课文库要能在任意设备直接导入使用」这句话拆开就是下面这些断言：
///   ① 导出 ↔ 解析严格对称（元数据与条目一个都不丢，含已补的题目）
///   ② 手写的老格式（只有 items）仍能解析
///   ③ 格式不对时返回 null，而不是抛异常（调用方据此提示，别的导入不受影响）
///
/// 导出与导入必须同步演化，所以断言都压在这一处。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/data/corpus_store.dart';

void main() {
  Corpus sample() => Corpus(
        name: '语文 六年级下册',
        version: 'tongbiao',
        grade: 6,
        volume: '下',
        source: 'licensed',
        origin: 'imported-pdf',
        items: [
          {
            'unit': '第一单元',
            'title': '山那边的邮局',
            'text': '哨兵正文甲。',
            'questions': [
              {'q': '问题？', 'a': '答案'}
            ],
            'version': 'tongbiao',
            'grade': 6,
            'volume': '下',
            'source': 'licensed',
          },
          {
            'unit': '第一单元',
            'title': '会唱歌的石头',
            'text': '哨兵正文乙。',
            'questions': <dynamic>[],
          },
        ],
      );

  group('往返', () {
    test('导出 → 解析：元数据与条目一个不少', () {
      final c = sample();
      final back = CorpusFile.decode(CorpusFile.encode(c));
      expect(back, isNotNull);
      expect(back!.name, c.name);
      expect(back.version, c.version);
      expect(back.grade, c.grade);
      expect(back.volume, c.volume);
      expect(back.source, c.source);
      expect(back.schemaVersion, CorpusFile.schemaVersion);
      expect(back.items.length, c.items.length);
      for (var i = 0; i < c.items.length; i++) {
        expect(back.items[i]['title'], c.items[i]['title']);
        expect(back.items[i]['text'], c.items[i]['text']);
        expect(back.items[i]['unit'], c.items[i]['unit']);
      }
    });

    test('已补的题目跟着一起走（否则导过去还得重新花钱调 AI）', () {
      final back = CorpusFile.decode(CorpusFile.encode(sample()))!;
      final q = (back.items[0]['questions'] as List).first as Map;
      expect(q['q'], '问题？');
      expect(q['a'], '答案');
    });

    test('文件自带 schemaVersion / exportedAt（便于将来迁移）', () {
      final file = CorpusFile.encode(sample());
      expect(file[CorpusFile.schemaKey], CorpusFile.schemaVersion);
      expect(file['exportedAt'], isA<String>());
      expect(file['id'], isA<String>());
      expect(file['origin'], 'imported-pdf');
    });

    test('导出即快照：之后再改原库，不会影响已编好的对象', () {
      final c = sample();
      final file = CorpusFile.encode(c);
      final before = (file['items'] as List).length;
      c.items.add({'title': '导出之后才加的'});
      expect((file['items'] as List).length, before);
    });
  });

  group('兼容与容错', () {
    test('手写老格式（只有 items + name）仍可解析', () {
      final back = CorpusFile.decode({
        'name': '我的课文库',
        'items': [
          {'title': '甲', 'text': '乙'}
        ],
      });
      expect(back, isNotNull);
      expect(back!.name, '我的课文库');
      expect(back.version, '');
      expect(back.grade, isNull);
      expect(back.volume, isNull);
      expect(back.schemaVersion, 0, reason: '老文件没有 schemaVersion，记 0');
      expect(back.items.length, 1);
    });

    test('文件名里的「原创」仍能兜底识别来源（老格式没写 source）', () {
      final back = CorpusFile.decode({
        'name': '原创课文库',
        'items': [
          {'title': '甲', 'text': '乙'}
        ],
      });
      expect(back!.source, 'original');
    });

    test('显式 source 优先于文件名暗示', () {
      final back = CorpusFile.decode({
        'name': '原创课文库',
        'source': 'licensed',
        'items': [
          {'title': '甲', 'text': '乙'}
        ],
      });
      expect(back!.source, 'licensed');
    });

    test('缺 items / 不是对象 → 返回 null（调用方提示格式不对，不抛）', () {
      expect(CorpusFile.decode(null), isNull);
      expect(CorpusFile.decode('字符串'), isNull);
      expect(CorpusFile.decode(123), isNull);
      expect(CorpusFile.decode(<String, dynamic>{}), isNull);
      expect(CorpusFile.decode({'items': 'not-a-list'}), isNull);
    });

    test('items 为空数组是合法解析（有没有内容由调用方判断）', () {
      final back = CorpusFile.decode({'items': <dynamic>[]});
      expect(back, isNotNull);
      expect(back!.items, isEmpty);
      expect(back.name, isNotEmpty,
          reason: '没写 name 时给兜底名，别造出标题为空的语料库');
    });
  });
}
