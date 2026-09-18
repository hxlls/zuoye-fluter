import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/ui/home_page.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  setUp(() {
    // 每个用例前重置存储，避免教材版本/年级在用例之间串味
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpMobile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844); // iPhone 14 尺寸
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  testWidgets('手机端底部导航固定三项', (tester) async {
    await pumpMobile(tester);

    final nav = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    expect(nav.items.length, 3);
    for (final label in ['出题', 'AI', '设置']) {
      expect(find.text(label), findsWidgets, reason: '缺少导航项 $label');
    }
  });

  testWidgets('手机端首页以卡片形式列出科目', (tester) async {
    await pumpMobile(tester);
    for (final name in ['练字帖', '语文作业', '数学作业', '英语作业']) {
      expect(find.text(name), findsOneWidget, reason: '缺少科目卡片 $name');
    }
  });

  testWidgets('手机端进入科目后配置页全屏，底部常驻生成按钮', (tester) async {
    await pumpMobile(tester);
    await tester.tap(find.text('数学作业'));
    await tester.pumpAndSettle();

    // 进入面板后不再显示底部导航
    expect(find.byType(BottomNavigationBar), findsNothing);
    // 配置内容全屏可见
    expect(find.text('数学作业设置'), findsOneWidget);
    // 底部常驻生成按钮
    expect(find.text('生成预览'), findsOneWidget);
  });

  testWidgets('手机端点生成切到全屏预览，可返回调整参数', (tester) async {
    await pumpMobile(tester);
    await tester.tap(find.text('数学作业'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成预览'));
    await tester.pumpAndSettle();

    // 预览页有返回入口与导出按钮
    expect(find.text('调整参数'), findsOneWidget);
    expect(find.textContaining('下载 PDF'), findsOneWidget);

    await tester.tap(find.text('调整参数'));
    await tester.pumpAndSettle();
    expect(find.text('数学作业设置'), findsOneWidget);
    expect(find.text('生成预览'), findsOneWidget);
  });

  testWidgets('手机端设置页可选教材与年级', (tester) async {
    await pumpMobile(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('教材版本'), findsOneWidget);
    expect(find.text('外研·一起点'), findsOneWidget);
    expect(find.text('年级'), findsOneWidget);
  });
}
