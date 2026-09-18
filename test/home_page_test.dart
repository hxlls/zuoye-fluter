import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/ui/home_page.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 设置页会渲染 AI 配置卡，其 AiStore.load() 走 SharedPreferences
    SharedPreferences.setMockInitialValues({});
    await AppData().load();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  testWidgets('底部导航固定三项，不随教材版本增减', (tester) async {
    await pumpHome(tester);

    final nav = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    expect(nav.items.length, 3);
    expect(nav.items.map((i) => i.label).toList(), ['出题', 'AI', '设置']);
  });

  testWidgets('首页以卡片列出四个科目，并显示当前教材上下文', (tester) async {
    await pumpHome(tester);

    for (final name in ['练字帖', '语文作业', '数学作业', '英语作业']) {
      expect(find.text(name), findsOneWidget, reason: '缺少科目卡片 $name');
    }
    expect(find.text('人教版 · 上册 · 1年级'), findsOneWidget);
  });

  testWidgets('设置页提供教材版本 / 学期 / 年级选择', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('教材版本'), findsOneWidget);
    expect(find.text('学期'), findsOneWidget);
    expect(find.text('年级'), findsOneWidget);

    for (final v in ['人教版', '统编版', '冀教版', '外研·一起点', '外研·三起点']) {
      expect(find.text(v), findsOneWidget, reason: '缺少教材版本 $v');
    }
  });

  testWidgets('切到外研三起点时年级自动归一化并给出提示', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    // 外研三起点仅 3-6 年级，当前 1 年级应被归一化到 3 年级
    await tester.tap(find.text('外研·三起点'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已切到 3 年级'), findsOneWidget);
  });

  testWidgets('外研版不提供语文，对应卡片置灰并标注', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外研·三起点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('出题'));
    await tester.pumpAndSettle();

    // 语文卡片仍在原位（导航项不会消失），但标注为不提供
    expect(find.text('语文作业'), findsOneWidget);
    expect(find.text('当前版本不提供'), findsWidgets);
  });
}
