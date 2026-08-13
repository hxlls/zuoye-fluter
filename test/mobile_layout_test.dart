import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/ui/home_page.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  Future<void> pumpMobile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844); // iPhone 14 尺寸
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();
  }

  testWidgets('手机端底部导航栏存在', (tester) async {
    await pumpMobile(tester);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    // 底部导航 7 个标签
    for (final label in ['练字帖', '语文', '数学', '英语', 'AI', '帮答', '关于']) {
      expect(find.text(label), findsWidgets, reason: '缺少导航项 $label');
    }
  });

  testWidgets('手机端有设置抽屉按钮', (tester) async {
    await pumpMobile(tester);
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('手机端切换底部导航到数学', (tester) async {
    await pumpMobile(tester);
    await tester.tap(find.text('数学'));
    await tester.pumpAndSettle();
    // 数学面板预览区出现（窄屏配置在抽屉里，预览区显示下载按钮）
    expect(find.text('下载 PDF（数学作业）'), findsOneWidget);
  });

  testWidgets('手机端打开设置抽屉', (tester) async {
    await pumpMobile(tester);
    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    // 抽屉出现，包含练字帖设置
    expect(find.text('练字帖设置'), findsOneWidget);
    // 抽屉里应能打开
    expect(find.byType(Drawer), findsOneWidget);
  });
}
