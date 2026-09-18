import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/ui/math_panel.dart';
import 'package:zuoye_fluter/ui/panel_widgets.dart';

/// 面板层的题量行为测试。
///
/// 为什么单独测这一层：type_catalog_test.dart 覆盖的是纯逻辑，
/// 而「取消勾选被复活」「题量切年级丢失」这两个真实 bug 都发生在**面板 State** 里
/// （_ensureCounts 的判断条件、是否持久化）。纯逻辑测试锁不住它们。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  setUp(() {
    // TypeCountStore 走 SharedPreferences，必须 mock，否则抛 MissingPluginException
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpMath(
    WidgetTester tester, {
    int grade = 1,
    String volume = '上',
  }) async {
    // 注意：PanelLayout 在宽屏下用 Row 左右分栏并撑满高度，
    // 外面**不能**再套 SingleChildScrollView（会给到无限高约束而崩）。
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MathPanel(grade: grade, version: 'renjiao', volume: volume),
      ),
    ));
    await tester.pumpAndSettle();
  }

  List<TypeRow> rows(WidgetTester tester) =>
      tester.widgetList<TypeRow>(find.byType(TypeRow)).toList();

  TypeRow rowOf(WidgetTester tester, String label) =>
      rows(tester).firstWhere((r) => r.label == label);

  int indexOf(WidgetTester tester, String label) =>
      rows(tester).indexWhere((r) => r.label == label);

  testWidgets('题型清单来自 TypeCatalog：一年级有「10以内加法」、无「表内乘法」',
      (tester) async {
    await pumpMath(tester, grade: 1);
    final labels = rows(tester).map((r) => r.label).toList();

    expect(labels, contains('10以内加法'));
    expect(labels, isNot(contains('表内乘法')));
  });

  testWidgets('切到二年级后题型换成二年级的', (tester) async {
    await pumpMath(tester, grade: 1);
    await pumpMath(tester, grade: 2);
    final labels = rows(tester).map((r) => r.label).toList();

    expect(labels, contains('表内乘法'));
    expect(labels, isNot(contains('10以内加法')));
  });

  testWidgets('同年级切「下」册题型随之变化', (tester) async {
    await pumpMath(tester, grade: 1, volume: '上');
    final up = rows(tester).map((r) => r.label).toList();
    await pumpMath(tester, grade: 1, volume: '下');
    final down = rows(tester).map((r) => r.label).toList();

    expect(down, isNot(equals(up)));
  });

  testWidgets('取消勾选后切年级再切回，仍保持未勾选（旧实现会复活）',
      (tester) async {
    await pumpMath(tester, grade: 1);
    const target = '10以内加法';
    expect(rowOf(tester, target).checked, isTrue);

    // 真实点击复选框取消勾选
    await tester.tap(find.byType(Checkbox).at(indexOf(tester, target)));
    await tester.pumpAndSettle();
    expect(rowOf(tester, target).checked, isFalse);
    expect(rowOf(tester, target).count, 0);

    // 切走再切回
    await pumpMath(tester, grade: 2);
    await pumpMath(tester, grade: 1);

    expect(rowOf(tester, target).checked, isFalse,
        reason: '旧实现用 count < 1 判断「没设置过」，会把主动取消的题型填回默认题量');
    expect(rowOf(tester, target).count, 0);
  });

  testWidgets('题量设置在切换年级后保留（全局按题型记忆）', (tester) async {
    await pumpMath(tester, grade: 2);
    const target = '表内乘法';

    // 通过 TypeRow 的回调设置题量，等价于用户在下拉里选 7
    rowOf(tester, target).onCount(7);
    await tester.pumpAndSettle();
    expect(rowOf(tester, target).count, 7);

    await pumpMath(tester, grade: 1);
    await pumpMath(tester, grade: 2);

    expect(rowOf(tester, target).count, 7, reason: '题量应跨年级保留');
    expect(rowOf(tester, target).checked, isTrue);
  });

  testWidgets('题量设置为 0 后再设回非零，能正常恢复', (tester) async {
    await pumpMath(tester, grade: 1);
    const target = '10以内加法';

    rowOf(tester, target).onCount(0);
    await tester.pumpAndSettle();
    expect(rowOf(tester, target).count, 0);

    rowOf(tester, target).onChecked(true);
    await tester.pumpAndSettle();
    // 恢复时用该题型的 defaultQty（数学为 10），不是硬编码数字
    expect(rowOf(tester, target).count, 10);
    expect(rowOf(tester, target).checked, isTrue);
  });
}
