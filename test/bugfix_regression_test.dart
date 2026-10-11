import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuoye_fluter/core/english_worksheet.dart';
import 'package:zuoye_fluter/core/scope_guard.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/data/corpus_store.dart';
import 'package:zuoye_fluter/ui/chinese_panel.dart';

/// 一轮 bug 排查后的回归测试（三组互不相关的问题，各自锁死）。
///
/// 1. 内置课文语料重复：shanghai 复用统编课文库（YUWEN_TEXTS），若按版本逐个
///    合成内置语料而不按「实际课文库」去重，下拉里会出现两条内容一模一样、
///    名字却不同的条目（统编版 / 上海·五四学制）。
/// 2. 整数上限：id `add1000` 在人教版三年级是「万以内加减法」（上限 10000），
///    在沪教版/冀教版二年级是「三位数的加减法」（上限 1000）。原先一律返回
///    10000，二年级的提示词会写成「整数运算限制在万以内」，生成后校验也放行四位数。
/// 3. 英语取词去重：连线题按「中文」定位答案、听力按中文给选项，同一份卷子里
///    出现两个英文相同的词（snow/took/drink…）或两个中文相同的词（hello/hi…）
///    都会导致答案歧义。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('内置课文语料去重', () {
    Future<List<String>> bundledNames(
        WidgetTester tester, String version) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChinesePanel(grade: 1, version: version, volume: '上'),
        ),
      ));
      await tester.pumpAndSettle();
      final dd = tester.widget<DropdownButton<Corpus>>(
          find.byType(DropdownButton<Corpus>));
      return dd.items!
          .map((i) => (i.child as Text).data ?? '')
          .where((s) => s.contains('内置课文'))
          .toList();
    }

    testWidgets('统编版：不出现复用同一课文库的上海条目', (tester) async {
      final names = await bundledNames(tester, 'tongbiao');
      expect(names.where((n) => n.contains('上海')).toList(), isEmpty,
          reason: 'shanghai 与 tongbiao 是同一批课文，不应重复出现: $names');
    });

    testWidgets('上海五四学制：内置课文只出现一条（当前版本那条）', (tester) async {
      final names = await bundledNames(tester, 'shanghai');
      expect(names.where((n) => n.contains('上海')).length, 1,
          reason: '应保留当前版本那条: $names');
      expect(names.where((n) => n.contains('统编')).toList(), isEmpty,
          reason: '同一课文库的另一版本应被去重: $names');
    });

    test('textLibKeyOf：复用统编的版本与 tongbiao 同键', () {
      final data = AppData();
      expect(data.textLibKeyOf('shanghai'), data.textLibKeyOf('tongbiao'));
      expect(data.textLibKeyOf('shanghai'), 'YUWEN_TEXTS');
      expect(data.textLibKeyOf('hebei'), isNot(data.textLibKeyOf('tongbiao')));
    });
  });

  group('integerCeil · add1000 按年级区分', () {
    test('二年级的「三位数加减法」上限是 1000，不是 10000', () {
      for (final v in ['shanghai', 'hebei']) {
        expect(ScopeGuard.integerCeil(version: v, grade: 2, volume: '下'), 1000,
            reason: '$v 二年级下含 add1000（三位数加减法），上限应为 1000');
      }
    });

    test('三年级的「万以内加减法」上限仍是 10000（不回归）', () {
      expect(ScopeGuard.integerCeil(version: 'renjiao', grade: 3, volume: '上'),
          10000);
      expect(ScopeGuard.integerCeil(version: 'shanghai', grade: 3, volume: '上'),
          10000);
    });

    test('二年级四位数会被判超纲', () {
      final note = ScopeGuard.inspect(
        [const ScopeItem('word', '学校有 1200 本图书。')],
        subject: 'math',
        version: 'shanghai',
        grade: 2,
        volume: '下',
      );
      expect(note, contains('1200'));
      expect(note, contains('1000'));
    });
  });

  group('英语取词去重', () {
    test('任一册取词结果里不出现重复英文或重复中文', () {
      final data = AppData();
      for (final ver in data.textbooks.keys) {
        final support = data.versionSupport[ver];
        final r = support?['eng'];
        if (r == null) continue;
        for (var g = r[0]; g <= r[1]; g++) {
          for (final vol in ['上', '下']) {
            final picked = pickVocab(data, g, 60, ver, vol);
            final ens = picked.map((w) => w[0]).toList();
            final cns = picked.map((w) => w[1]).toList();
            expect(ens.toSet().length, ens.length,
                reason: '$ver $g$vol 取词出现重复英文');
            expect(cns.toSet().length, cns.length,
                reason: '$ver $g$vol 取词出现重复中文');
          }
        }
      }
    });

    test('连线题答案标号不重复（同一中文只对应一个词）', () {
      final data = AppData();
      // shanghai 五上词表里 drink 同时是「喝」与「饮料」，去重后只应留一个
      final picked = pickVocab(data, 5, 60, 'shanghai', '上');
      final drinks = picked.where((w) => w[0] == 'drink').toList();
      expect(drinks.length, lessThanOrEqualTo(1),
          reason: 'drink 出现多次会让连线题左列出现两个同样的词');
    });
  });
}
