// 跨科目守卫：数学 / 语文 / 英语的「大题编号」都不能出现重复。
//
// 背景：英语曾出现「同一大题被拆到两页后，续页又拿了一个新编号」，
// 得分栏列数随之虚高（见 5628eb3）。三个科目的分页是**三份独立实现**，
// 修了英语不代表数学、语文没问题 —— 所以这里用统一口径逐个验证。
//
// 口径刻意复用渲染层的 WorksheetPageView.isSectionStart，
// 而不是自己写 n is WsHeading：后者容易与渲染层漂移，测出来的不代表用户看到的。
import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/core/chinese_worksheet.dart';
import 'package:zuoye_fluter/core/english_worksheet.dart';
import 'package:zuoye_fluter/core/math_worksheet.dart';
import 'package:zuoye_fluter/core/worksheet_model.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/ui/worksheet_view.dart';

/// 用与渲染层完全相同的口径（isSectionStart）收集「大题开始」标题。
///
/// 之所以不自己写 n is WsHeading 之类的判断：那样容易和渲染层漂移，
/// 测出来的结论就不代表用户真正看到的东西。
List<String> sectionTitles(List<WsPage> pages) {
  final out = <String>[];
  for (final p in pages) {
    for (final n in p.nodes) {
      if (!WorksheetPageView.isSectionStart(n)) continue;
      if (n is WsHeading) out.add('H:${n.title}');
      if (n is WsSection) out.add('S:${n.text}');
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppData().load();
  });

  test('探针：数学大题标题跨页不重复', () async {
    final bad = <String>[];
    for (final g in [1, 2, 3, 4, 5, 6]) {
      for (final n in [20, 40, 80, 120]) {
        final pages = mathRenderPages(MathOptions(
            grade: g, version: 'renjiao', volume: '上', count: n));
        final t = sectionTitles(pages);
        if (t.length != t.toSet().length) {
          final dup = <String>[];
          final seen = <String>{};
          for (final x in t) {
            if (!seen.add(x)) dup.add(x);
          }
          bad.add('$g年级/$n题 页数=${pages.length} 重复=$dup');
        }
      }
    }
    expect(bad, isEmpty, reason: '数学出现重复大题标题:\n${bad.join(chr10)}');
  });

  test('探针：语文大题标题跨页不重复', () async {
    final bad = <String>[];
    const types = ['pinyin2char', 'char2pinyin', 'zuci', 'gushiFill'];
    for (final g in [1, 2, 3, 4, 5, 6]) {
      for (final n in [6, 12, 20, 30]) {
        final pages = chineseRenderPages(ChineseOptions(
            grade: g,
            version: 'renjiao',
            volume: '上',
            types: types,
            counts: {for (final t in types) t: n}));
        final t = sectionTitles(pages);
        if (t.length != t.toSet().length) {
          final dup = <String>[];
          final seen = <String>{};
          for (final x in t) {
            if (!seen.add(x)) dup.add(x);
          }
          bad.add('$g年级/$n题 页数=${pages.length} 重复=$dup');
        }
      }
    }
    expect(bad, isEmpty, reason: '语文出现重复大题标题:\n${bad.join(chr10)}');
  });

  test('探针：英语大题标题跨页不重复', () async {
    final bad = <String>[];
    const types = ['alphabet', 'trace', 'cn2en'];
    for (final g in [1, 2, 3, 4, 5, 6]) {
      for (final n in [8, 16, 30]) {
        final pages = englishRenderPages(EnglishOptions(
            grade: g,
            version: 'renjiao',
            volume: '上',
            types: types,
            counts: {for (final t in types) t: n}));
        final t = sectionTitles(pages);
        if (t.length != t.toSet().length) {
          final dup = <String>[];
          final seen = <String>{};
          for (final x in t) {
            if (!seen.add(x)) dup.add(x);
          }
          bad.add('$g年级/$n题 页数=${pages.length} 重复=$dup');
        }
      }
    }
    expect(bad, isEmpty, reason: '英语出现重复大题标题:\n${bad.join(chr10)}');
  });
}

const chr10 = '\n';
