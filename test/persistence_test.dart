import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/data/panel_pref_store.dart';
import 'package:zuoye_fluter/data/work_context_store.dart';
import 'package:zuoye_fluter/ui/ai_help_panel.dart';
import 'package:zuoye_fluter/ui/ai_panel.dart';
import 'package:zuoye_fluter/ui/home_page.dart';
import 'package:zuoye_fluter/ui/math_panel.dart';
import 'package:zuoye_fluter/ui/panel_widgets.dart';

/// 「切走 / 重启后状态是否还在」的回归测试。
///
/// 这一族 bug 的共同成因：页面在离开时会被销毁——
/// 科目面板是从主页 push 出来的全屏页，`home_page` 的 tab 容器又是 `switch`
/// 而不是 `IndexedStack`。状态只要留在内存里就一定会丢。
///
/// 审计发现的缺口（本次一并补上）：
/// - `home_page`：教材版本/学期/年级 —— 每次重开 App 都回到「人教版·上册·1年级」
/// - `math_panel`：难度/附答案/显示标题栏
/// - `chinese_panel`：附答案/显示标题栏/课文模式
/// - `calligraphy_panel`：字数/每行格数/练习遍数/拼音/标题栏…
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  /// 模拟 App 重启：先换掉整棵树销毁 State，再重建
  Future<void> restartHome(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  group('WorkContextStore · 序列化往返', () {
    test('保存后可读回', () async {
      SharedPreferences.setMockInitialValues({});
      await WorkContextStore.save(version: 'hebei', volume: '下', grade: 6);
      final c = await WorkContextStore.load();
      expect(c, isNotNull);
      expect(c!.version, 'hebei');
      expect(c.volume, '下');
      expect(c.grade, 6);
    });

    test('无记录返回 null，不抛异常', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await WorkContextStore.load(), isNull);
    });
  });

  group('PanelPrefStore · 序列化往返', () {
    test('保存后可读回', () async {
      SharedPreferences.setMockInitialValues({});
      await PanelPrefStore.save('math', {'diff': 'hard', 'showAnswer': false});
      expect(await PanelPrefStore.load('math'),
          {'diff': 'hard', 'showAnswer': false});
    });

    test('按面板隔离', () async {
      SharedPreferences.setMockInitialValues({});
      await PanelPrefStore.save('math', {'diff': 'hard'});
      expect(await PanelPrefStore.load('chinese'), isEmpty);
      expect(await PanelPrefStore.load('calligraphy'), isEmpty);
    });
  });

  testWidgets('教材版本/学期/年级在重启后恢复（旧实现每次回到人教版·上册·1年级）',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('冀教版'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下册'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6年级'));
    await tester.pumpAndSettle();

    await restartHome(tester);

    expect(find.text('冀教版 · 下册 · 6年级'), findsOneWidget,
        reason: '重启后应恢复上次的教材版本/学期/年级');
  });

  testWidgets('重启后若年级不被该版本支持，会被归一化而不是崩掉', (tester) async {
    // 预置一份「外研三起点 + 1 年级」——该版本只有 3-6 年级
    SharedPreferences.setMockInitialValues({
      'ctx_version': 'waiyanSQ',
      'ctx_volume': '上',
      'ctx_grade': 1,
    });
    await pumpHome(tester);

    // 应被归一化到 3 年级，而不是显示 1 年级
    expect(find.textContaining('3年级'), findsWidgets);
    expect(find.text('外研·三起点 · 上册 · 1年级'), findsNothing);
  });

  testWidgets('数学面板的难度在重进后恢复', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<void> pumpMath() async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MathPanel(grade: 1, version: 'renjiao', volume: '上'),
        ),
      ));
      await tester.pumpAndSettle();
    }

    String? diffOf() {
      for (final s in tester.widgetList<SegButtons>(find.byType(SegButtons))) {
        if (s.options.any((o) => o.$1 == 'easy')) return s.value;
      }
      return null;
    }

    await pumpMath();
    expect(diffOf(), 'easy');

    await tester.tap(find.text('较难'));
    await tester.pumpAndSettle();
    expect(diffOf(), 'hard');

    // 模拟返回主页再重进：销毁再重建
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await pumpMath();

    expect(diffOf(), 'hard', reason: '难度选择应被持久化，而不是每次回到「简单」');
  });

  group('IndexedStack · 切 Tab 不销毁子树', () {
    // 用「面板是否还在 widget 树里」区分两种实现：
    // - IndexedStack：未显示的子树仍在树中（offstage），状态得以保留
    // - 原先的 switch：直接返回另一个子树，离开的那个被销毁
    testWidgets('切到「设置」后 AI 出题 / 帮答仍在树中', (tester) async {
      await pumpHome(tester);
      expect(find.byType(AiPanel, skipOffstage: false), findsOneWidget);

      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();

      expect(find.byType(AiPanel, skipOffstage: false), findsOneWidget,
          reason: '切 Tab 不应销毁 AI 出题面板');
      expect(find.byType(AiHelpPanel, skipOffstage: false), findsOneWidget,
          reason: '切 Tab 不应销毁 AI 帮答面板');
    });

    testWidgets('「出题 / 帮答」互相切换时不销毁对方', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();

      // 默认在「出题」，帮答也应已在树中
      expect(find.byType(AiHelpPanel, skipOffstage: false), findsOneWidget);

      await tester.tap(find.textContaining('AI 帮答'));
      await tester.pumpAndSettle();

      expect(find.byType(AiPanel, skipOffstage: false), findsOneWidget,
          reason: '切到帮答不应销毁出题面板（已生成的题目应留在原地）');
    });

    testWidgets('切回「出题」时题型勾选仍是上次的样子', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();

      // 取消第一行题型
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      final before = tester
          .widgetList<TypeRow>(find.byType(TypeRow))
          .first
          .checked;
      expect(before, isFalse);

      await tester.tap(find.textContaining('AI 帮答'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('AI 出题'));
      await tester.pumpAndSettle();

      expect(
        tester.widgetList<TypeRow>(find.byType(TypeRow)).first.checked,
        isFalse,
        reason: '不销毁子树时，勾选状态应原地保留',
      );
    });
  });
}
