import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/core/calligraphy_worksheet.dart';
import 'package:zuoye_fluter/core/chinese_worksheet.dart';
import 'package:zuoye_fluter/core/english_worksheet.dart';
import 'package:zuoye_fluter/core/math_worksheet.dart';
import 'package:zuoye_fluter/core/type_catalog.dart';
import 'package:zuoye_fluter/data/app_data.dart';

/// 全版本 × 年级 × 册 × 科目的出题矩阵冒烟测试。
///
/// 目的：把「某个版本/年级组合界面上能勾题型，但一点生成就抛异常或出空白页」
/// 这类问题一次性暴露出来 —— 新增教材版本（如上海五四学制）时最容易漏。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  test('矩阵冒烟：所有版本/年级/册/科目都能出题', () async {
    final data = AppData();
    final problems = <String>[];
    var covered = 0;

    for (final ver in data.textbooks.keys) {
      final support = data.versionSupport[ver];
      if (support == null) {
        problems.add('$ver: 缺 VERSION_SUPPORT');
        continue;
      }
      for (final subj in ['cally', 'math', 'eng']) {
        final r = support[subj];
        if (r == null) continue;
        for (var g = r[0]; g <= r[1]; g++) {
          for (final vol in ['上', '下']) {
            final tag = '$ver/$g$vol/$subj';
            try {
              if (subj == 'math') {
                final ids = TypeCatalog.idsOf(Subject.math,
                    version: ver, grade: g, volume: vol);
                if (ids.isEmpty) {
                  problems.add('$tag: 题型清单为空');
                  continue;
                }
                final pages = mathRenderPages(MathOptions(
                  grade: g,
                  version: ver,
                  volume: vol,
                  types: ids,
                  counts: {for (final id in ids) id: 2},
                ));
                if (pages.isEmpty) problems.add('$tag: 渲染出 0 页');
                for (final p in pages) {
                  if (p.nodes.isEmpty) {
                    problems.add('$tag: 有空白页');
                    break;
                  }
                }
              } else if (subj == 'cally') {
                final ids =
                    TypeCatalog.idsOf(Subject.chinese, version: ver, grade: g);
                final pages = chineseRenderPages(ChineseOptions(
                  grade: g,
                  version: ver,
                  volume: vol,
                  types: ids,
                  counts: {for (final id in ids) id: 1},
                ));
                if (pages.isEmpty) problems.add('$tag: 渲染出 0 页');
                final cp = calligraphyRenderPages(CalligraphyOptions(
                  grade: g,
                  version: ver,
                  volume: vol,
                  charCount: 16,
                ));
                if (cp.isEmpty) problems.add('$tag: 练字帖渲染出 0 页');
              } else {
                final ids =
                    TypeCatalog.idsOf(Subject.english, version: ver, grade: g);
                final pages = englishRenderPages(EnglishOptions(
                  grade: g,
                  version: ver,
                  volume: vol,
                  types: ids,
                  counts: {for (final id in ids) id: 2},
                ));
                if (pages.isEmpty) problems.add('$tag: 渲染出 0 页');
              }
              covered++;
            } catch (e, st) {
              problems.add('$tag: 抛异常 $e\n${st.toString().split('\n').take(3).join('\n')}');
            }
          }
        }
      }
    }

    // ignore: avoid_print
    print('=== 矩阵覆盖组合数: $covered，问题数: ${problems.length} ===');
    for (final p in problems) {
      // ignore: avoid_print
      print('  !! $p');
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
