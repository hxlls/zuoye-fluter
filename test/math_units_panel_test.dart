import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/ui/math_panel.dart';
import 'package:zuoye_fluter/ui/panel_widgets.dart';

/// 数学面板「本册单元（教材目录）」的渲染测试。
///
/// 为什么必须在面板层测：ai_prompt_scope_test 锁的是 MATH_UNITS 数据与提示词，
/// 而这次改动的本体是 **UI 文案**——教材名有没有真的取自数据、单元目录有没有
/// 真的画出来、没有数据的版本会不会拿人教版顶替，只有 pump 出来才看得见。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  setUp(() {
    // TypeCountStore / PanelPrefStore 走 SharedPreferences，必须 mock，
    // 否则抛 MissingPluginException。
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpMath(
    WidgetTester tester, {
    int grade = 4,
    String version = 'renjiao',
    String volume = '上',
  }) async {
    // PanelLayout 宽屏下用 Row 分栏并撑满高度，外层不能再套滚动容器。
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MathPanel(grade: grade, version: version, volume: volume),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// 面板内所有 Text 的文字连成一串，方便 contains 断言。
  String allText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((s) => s.isNotEmpty)
      .join('\n');

  /// 只取「本册单元（教材目录）」那一组的文字。
  ///
  /// 「上/下册不串页」要锁的是**目录那一组**，不能拿整个面板的文字来断言：
  /// 题型的 sub 标签会照实写出内容的真实归属册（四上的「除数是两位数的除法」
  /// 在 2024 新版属于四下，标成「人教版四下 一 除数是两位数的除法」），
  /// 那是有意给出的提示，不是目录串页。
  String tocText(WidgetTester tester) {
    final group = find.ancestor(
      of: find.text('本册单元（教材目录）'),
      matching: find.byType(FormGroup),
    );
    return tester
        .widgetList<Text>(
            find.descendant(of: group, matching: find.byType(Text)))
        .map((t) => t.data ?? '')
        .where((s) => s.isNotEmpty)
        .join('\n');
  }

  testWidgets('四年级上画出人教版本册目录，且顺序与数据一致', (tester) async {
    await pumpMath(tester, grade: 4, volume: '上');
    final s = tocText(tester);
    final units = AppData().mathUnitsFor('renjiao', 4, '上');

    expect(units.isNotEmpty, true);
    expect(s, contains('本册单元（教材目录）'));
    // 直接拿数据拼接后的整串比对，等于同时锁住「内容」与「顺序」。
    expect(s, contains(units.join('　·　')));
    expect(s, isNot(contains('这个版本的单元清单暂未收录')));
  });

  testWidgets('四年级上只出现上册单元，下册单元不串页', (tester) async {
    await pumpMath(tester, grade: 4, volume: '上');
    final s = tocText(tester);

    expect(s, contains('一 万以上数的认识'));
    expect(s, isNot(contains('一 除数是两位数的除法')));
  });

  testWidgets('切到下册目录跟着换', (tester) async {
    await pumpMath(tester, grade: 4, volume: '下');
    final s = tocText(tester);

    expect(s, contains('一 除数是两位数的除法'));
    expect(s, isNot(contains('一 万以上数的认识')));
  });

  testWidgets('教材名取自数据，不是硬编码「人教版」', (tester) async {
    await pumpMath(tester, grade: 4);
    final book = AppData().textbooks['renjiao']?.math ?? '数学教材';

    expect(book.isNotEmpty, true);
    expect(allText(tester), contains('📚 $book'));
  });

  testWidgets('未收录单元清单的版本如实说明，不拿人教版顶替', (tester) async {
    // 冀教版数学用的是冀教版教材，MATH_UNITS._meta.alignment 里没有 hebei。
    await pumpMath(tester, grade: 4, version: 'hebei');
    final s = tocText(tester);

    expect(s, contains('这个版本的单元清单暂未收录'));
    expect(s, isNot(contains('一 万以上数的认识')));
  });
}
