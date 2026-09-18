import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/core/english_worksheet.dart';
import 'package:zuoye_fluter/core/type_catalog.dart';
import 'package:zuoye_fluter/data/app_data.dart';

/// 题型可用性（科目 × 年级 × 册）的回归测试。
///
/// 最后一段「反漂移」是重点：渲染层（english_worksheet）与目录层（TypeCatalog）
/// 必须给出完全一致的结果，否则会出现「界面能勾但出不了题」。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  group('TypeCatalog · 数学随版本/年级/册变化', () {
    test('题型随年级变化', () {
      final g1 = TypeCatalog.idsOf(Subject.math,
          version: 'renjiao', grade: 1, volume: '上');
      final g2 = TypeCatalog.idsOf(Subject.math,
          version: 'renjiao', grade: 2, volume: '上');

      expect(g1, contains('add10'));
      expect(g1, isNot(contains('mul')));
      expect(g2, contains('mul'));
      expect(g2, isNot(contains('add10')));
    });

    test('同年级切册题型不同', () {
      final up = TypeCatalog.idsOf(Subject.math,
          version: 'renjiao', grade: 1, volume: '上');
      final down = TypeCatalog.idsOf(Subject.math,
          version: 'renjiao', grade: 1, volume: '下');
      expect(up, isNot(equals(down)));
    });

    test('单元提示随年级变化', () {
      final s = TypeCatalog.of(Subject.math,
          version: 'renjiao', grade: 1, volume: '上');
      expect(s.first.unit, contains('一上'));
    });
  });

  group('TypeCatalog · 语文按年级区间', () {
    test('成语题 2 年级起才可用', () {
      final g1 =
          TypeCatalog.idsOf(Subject.chinese, version: 'renjiao', grade: 1);
      final g2 =
          TypeCatalog.idsOf(Subject.chinese, version: 'renjiao', grade: 2);

      expect(g1, isNot(contains('chengyuFill')));
      expect(g1, isNot(contains('chengyuGuess')));
      expect(g2, contains('chengyuFill'));
      expect(g2, contains('chengyuGuess'));
      expect(g2.length, g1.length + 2);
    });

    test('includeUnavailable 会保留不可用项并标注', () {
      final all = TypeCatalog.of(Subject.chinese,
          version: 'renjiao', grade: 1, includeUnavailable: true);
      expect(all.length, TypeCatalog.cnOrder.length);
      expect(all.firstWhere((t) => t.id == 'chengyuFill').available, isFalse);
    });

    test('标签取自 CHINESE_TYPES_LABELS', () {
      final s =
          TypeCatalog.of(Subject.chinese, version: 'renjiao', grade: 1);
      expect(s.firstWhere((t) => t.id == 'pinyin2char').label, '看拼音写汉字');
    });
  });

  group('TypeCatalog · 英语年级区间 + 版本规则', () {
    test('一年级不含拼写/AI 阅读/听力短文', () {
      final ids =
          TypeCatalog.idsOf(Subject.english, version: 'renjiao', grade: 1);
      expect(ids, contains('alphabet'));
      expect(ids, isNot(contains('spell')));
      expect(ids, isNot(contains('aiyuedu')));
      expect(ids, isNot(contains('ailistening')));
    });

    test('alphabet 仅一年级', () {
      expect(TypeCatalog.idsOf(Subject.english, version: 'renjiao', grade: 1),
          contains('alphabet'));
      expect(TypeCatalog.idsOf(Subject.english, version: 'renjiao', grade: 2),
          isNot(contains('alphabet')));
    });

    test('spell：普通版本三年级起，外研三起点要五年级', () {
      expect(TypeCatalog.idsOf(Subject.english, version: 'renjiao', grade: 3),
          contains('spell'));
      expect(TypeCatalog.idsOf(Subject.english, version: 'waiyanSQ', grade: 3),
          isNot(contains('spell')));
      expect(TypeCatalog.idsOf(Subject.english, version: 'waiyanSQ', grade: 4),
          isNot(contains('spell')));
      expect(TypeCatalog.idsOf(Subject.english, version: 'waiyanSQ', grade: 5),
          contains('spell'));
    });

    test('listening：外研三起点三年级起，其余版本一年级起', () {
      expect(TypeCatalog.idsOf(Subject.english, version: 'waiyanSQ', grade: 1),
          isNot(contains('listening')));
      expect(TypeCatalog.idsOf(Subject.english, version: 'waiyanSQ', grade: 3),
          contains('listening'));
      expect(TypeCatalog.idsOf(Subject.english, version: 'renjiao', grade: 1),
          contains('listening'));
    });

    test('ailistening 不在年级表里，只由版本规则决定（3 年级起）', () {
      expect(TypeCatalog.idsOf(Subject.english, version: 'renjiao', grade: 2),
          isNot(contains('ailistening')));
      expect(TypeCatalog.idsOf(Subject.english, version: 'renjiao', grade: 3),
          contains('ailistening'));
    });

    test('默认勾选题型：一年级字母+描红，三年级描红+连线', () {
      final g1 = TypeCatalog.of(Subject.english,
          version: 'renjiao', grade: 1);
      final g3 = TypeCatalog.of(Subject.english,
          version: 'renjiao', grade: 3);
      expect(g1.firstWhere((t) => t.id == 'alphabet').defaultOn, isTrue);
      expect(g1.firstWhere((t) => t.id == 'match').defaultOn, isFalse);
      expect(g3.firstWhere((t) => t.id == 'trace').defaultOn, isTrue);
      expect(g3.firstWhere((t) => t.id == 'match').defaultOn, isTrue);
      expect(g3.firstWhere((t) => t.id == 'spell').defaultOn, isFalse);
    });

    test('一年级把 trace 显示为「单词描红」（原 _labelFor 的特例）', () {
      final g1 = TypeCatalog.of(Subject.english,
          version: 'renjiao', grade: 1);
      final g3 = TypeCatalog.of(Subject.english,
          version: 'renjiao', grade: 3);
      expect(g1.firstWhere((t) => t.id == 'trace').label, '单词描红');
      expect(g3.firstWhere((t) => t.id == 'trace').label, '单词抄写');
    });
  });

  group('seedTypeCounts · 不复活用户主动取消的题型', () {
    const specs = <TypeSpec>[
      TypeSpec(id: 'a', label: 'A', available: true, defaultOn: true, defaultQty: 10),
      TypeSpec(id: 'b', label: 'B', available: true, defaultOn: true, defaultQty: 10),
      TypeSpec(id: 'c', label: 'C', available: false, defaultOn: true, defaultQty: 10),
    ];

    test('从未设置过 -> 填默认值', () {
      final m = seedTypeCounts(specs, <String, int>{});
      expect(m['a'], 10);
      expect(m['b'], 10);
    });

    test('已设为 0（用户主动取消）-> 保持 0', () {
      final m = seedTypeCounts(specs, <String, int>{'a': 0});
      expect(m['a'], 0, reason: '旧实现用 count < 1 判断，会把它复活成 10');
      expect(m['b'], 10);
    });

    test('已设为非零 -> 保持原值', () {
      expect(seedTypeCounts(specs, <String, int>{'a': 7})['a'], 7);
    });

    test('不可用题型不填默认值', () {
      expect(seedTypeCounts(specs, <String, int>{}).containsKey('c'), isFalse);
    });
  });

  group('反漂移 · 渲染层与目录层必须一致', () {
    const versions = ['renjiao', 'tongbiao', 'hebei', 'waiyanYQ', 'waiyanSQ'];

    for (final ver in versions) {
      for (var grade = 1; grade <= 6; grade++) {
        test('allowedEngTypes($ver, $grade) == TypeCatalog', () {
          final viaRender = allowedEngTypes(ver, grade, TypeCatalog.engOrder);
          final viaCatalog =
              TypeCatalog.idsOf(Subject.english, version: ver, grade: grade);
          expect(viaRender, viaCatalog);
        });
      }
    }
  });
}
