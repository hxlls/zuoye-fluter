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
    // 每个用例前重置存储。home_page 现在会持久化教材版本/学期/年级，
    // 不重置的话上一个用例选过的「外研三起点 · 3年级」会串进下一个用例
    // （表现为「1年级」找不到）——这是持久化生效后的必然结果，测试必须隔离。
    // 同时设置页会渲染 AiConfigCard，其 AiStore.load() 也走 SharedPreferences。
    SharedPreferences.setMockInitialValues({});
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

  testWidgets('外研三起点只提供 3-6 年级，且科目仅英语', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    // 人教版：1-6 年级齐全
    expect(find.text('1年级'), findsOneWidget);

    await tester.tap(find.text('外研·三起点'));
    await tester.pumpAndSettle();

    // 外研三起点在数据里是 {cally:null, math:null, eng:[3,6]}，
    // 年级选项不应出现 1、2 年级
    expect(find.text('1年级'), findsNothing);
    expect(find.text('2年级'), findsNothing);
    for (final g in [3, 4, 5, 6]) {
      expect(find.text('$g年级'), findsOneWidget, reason: '缺少 $g 年级');
    }

    // 该版本只提供英语，其余科目卡片应标注不提供
    await tester.tap(find.text('出题'));
    await tester.pumpAndSettle();
    expect(find.text('当前版本不提供'), findsNWidgets(3)); // 练字帖/语文/数学
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

  testWidgets('五个教材版本的年级与科目裁剪全部符合 VERSION_SUPPORT', (tester) async {
    // 独立断言表：刻意不引用 VERSION_SUPPORT，避免「用被测数据自证」。
    // 数据源 assets/data.json 的 VERSION_SUPPORT：
    //   renjiao  {cally:[1,6], math:[1,6], eng:[1,6]}
    //   tongbiao {cally:[1,6], math:[1,6], eng:[1,6]}
    //   hebei    {cally:null,  math:[1,6], eng:[1,6]}
    //   waiyanYQ {cally:null,  math:null,  eng:[1,2]}
    //   waiyanSQ {cally:null,  math:null,  eng:[3,6]}
    // 注意：语文作业与练字帖共用 cally 支持键（都源自语文教科书），
    //       所以 cally 为 null 时这两张卡片一起变成「不提供」。
    const expectTable = <String, (List<int>, int)>{
      '人教版':      ([1, 2, 3, 4, 5, 6], 0),
      '统编版':      ([1, 2, 3, 4, 5, 6], 0),
      '冀教版':      ([1, 2, 3, 4, 5, 6], 2), // 练字帖 / 语文作业
      '外研·一起点': ([1, 2],             3), // 练字帖 / 语文作业 / 数学作业
      '外研·三起点': ([3, 4, 5, 6],       3),
    };

    for (final entry in expectTable.entries) {
      final ver = entry.key;
      final (grades, unavailable) = entry.value;

      await pumpHome(tester);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ver));
      await tester.pumpAndSettle();

      for (final g in [1, 2, 3, 4, 5, 6]) {
        final f = find.text('$g年级');
        if (grades.contains(g)) {
          expect(f, findsOneWidget, reason: '$ver 应提供 $g 年级');
        } else {
          expect(f, findsNothing, reason: '$ver 不应出现 $g 年级');
        }
      }

      await tester.tap(find.text('出题'));
      await tester.pumpAndSettle();
      expect(
        find.text('当前版本不提供'),
        findsNWidgets(unavailable),
        reason: '$ver 的「不提供」科目数不符',
      );
    }
  });
}
