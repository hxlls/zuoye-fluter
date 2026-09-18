// 守卫：英语题量超过该年级词表容量时不能崩溃。
//
// 历史 bug：totalN（各题型题量之和）大于词表实际长度时，
// english_worksheet 里的 allVocab.sublist(offset, offset + n) 越界，抛
//   RangeError (end): Not in inclusive range 30..38: 60
// 二~六年级把「单词描红」「中译英」都调到 30 题即可稳定触发，整份卷子生成失败。
import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/core/english_worksheet.dart';
import 'package:zuoye_fluter/data/app_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppData().load();
  });

  test('英语：各年级 x 题量组合是否崩溃', () async {
    final bad = <String>[];
    const types = ['alphabet', 'trace', 'cn2en'];
    for (final g in [1, 2, 3, 4, 5, 6]) {
      for (final n in [8, 16, 30]) {
        try {
          englishRenderPages(EnglishOptions(
              grade: g,
              version: 'renjiao',
              volume: '上',
              types: types,
              counts: {for (final t in types) t: n}));
        } catch (e) {
          bad.add('g=$g n=$n 崩溃: $e');
        }
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
