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
  });

  testWidgets('切换教材版本后年级下拉选项变化', (tester) async {
    await pumpHome(tester);

    // 打开教材版本下拉，选择外研·三起点（仅支持3-6年级）
    await tester.tap(find.text('人教版'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外研·三起点').last);
    await tester.pumpAndSettle();

    // 年级应重置为最小支持年级 3
    expect(find.text('3年级'), findsOneWidget);
  });

  testWidgets('切换学期下拉', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('上册'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下册').last);
    await tester.pumpAndSettle();
    expect(find.text('下册'), findsOneWidget);
  });
}
