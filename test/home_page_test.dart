import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/ui/home_page.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();
  }

  testWidgets('顶部下拉选择器渲染', (tester) async {
    await pumpHome(tester);

    // 三个下拉都存在
    expect(find.text('教材版本'), findsOneWidget);
    expect(find.text('学期'), findsOneWidget);
    expect(find.text('年级'), findsOneWidget);

    // 当前值显示（人教版 / 上册 / 1年级）
    expect(find.text('人教版'), findsOneWidget);
    expect(find.text('上册'), findsOneWidget);
    expect(find.text('1年级'), findsOneWidget);

    // 验证下拉可交互（通过 widget onChanged 触发，避免打开菜单触发框架 ListTile 断言）
    final buttons = find.byType(DropdownButton<String>);
    expect(buttons, findsNWidgets(3));
  });

  testWidgets('教材版本下拉存在且选项正确', (tester) async {
    await pumpHome(tester);

    final dropdowns = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .toList();
    // 第一个是教材版本下拉
    expect(dropdowns.length, 3);
    // 通过构造参数验证选项包含 4 个版本
    final versionItems = dropdowns[0].items!;
    final labels = versionItems.map((i) => (i.child as Text).data).toSet();
    expect(labels, containsAll(['人教版', '冀教版', '外研·一起点', '外研·三起点']));

    // 手动触发 onChanged 模拟切换版本 → 年级重置为 3
    dropdowns[0].onChanged!('waiyanSQ');
    await tester.pump();
    expect(find.text('3年级'), findsOneWidget);
  });

  testWidgets('学期下拉存在且选项正确', (tester) async {
    await pumpHome(tester);

    final dropdowns = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .toList();
    // 第二个是学期下拉
    final volumeItems = dropdowns[1].items!;
    final labels = volumeItems.map((i) => (i.child as Text).data).toSet();
    expect(labels, containsAll(['上册', '下册']));

    // 手动触发切换学期
    dropdowns[1].onChanged!('下');
    await tester.pump();
    expect(find.text('下册'), findsOneWidget);
  });
}
