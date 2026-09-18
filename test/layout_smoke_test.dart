import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/ui/ai_help_panel.dart';
import 'package:zuoye_fluter/ui/ai_panel.dart';
import 'package:zuoye_fluter/ui/calligraphy_panel.dart';
import 'package:zuoye_fluter/ui/chinese_panel.dart';
import 'package:zuoye_fluter/ui/english_panel.dart';
import 'package:zuoye_fluter/ui/home_page.dart';
import 'package:zuoye_fluter/ui/math_panel.dart';

/// 多尺寸布局冒烟测试。
///
/// 用户报过的 UI 缺陷里有一类就是「某个宽度下控件溢出 / 够不着」
/// （例如 AI 配置卡的四个按钮在 390px 宽度溢出）。
/// widget 测试里 RenderFlex 溢出会变成异常，所以可以用 `takeException()`
/// 系统性地把所有面板 × 常见屏宽扫一遍，而不是等用户踩到。
///
/// 覆盖宽度：320（小屏 iPhone SE）→ 1440（桌面），含 760px 这个
/// 「手机 / 桌面」布局分界的两侧。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const widths = <double>[320, 360, 390, 414, 600, 768, 1024, 1440];

  Future<void> pumpPanel(WidgetTester tester, double w, Widget child) async {
    tester.view.physicalSize = Size(w, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  /// 取出并断言没有异常（溢出会被记成异常）
  void expectNoException(WidgetTester tester, String label) {
    final e = tester.takeException();
    expect(e, isNull, reason: '$label 出现布局异常：$e');
  }

  final panels = <String, Widget Function()>{
    '练字帖': () => const CalligraphyPanel(grade: 1, version: 'renjiao', volume: '上'),
    '数学': () => const MathPanel(grade: 1, version: 'renjiao', volume: '上'),
    '语文': () => const ChinesePanel(grade: 1, version: 'renjiao', volume: '上'),
    '英语': () => const EnglishPanel(grade: 1, version: 'renjiao', volume: '上'),
    // AI 出题用 6 年级：题型最多，最容易挤出布局问题
    'AI出题': () => const AiPanel(grade: 6, version: 'renjiao', volume: '上'),
    'AI帮答': () => const AiHelpPanel(grade: 1, version: 'renjiao', volume: '上'),
  };

  for (final entry in panels.entries) {
    for (final w in widths) {
      testWidgets('${entry.key} @ ${w.toInt()}px 无布局异常', (tester) async {
        await pumpPanel(tester, w, entry.value());
        expectNoException(tester, '${entry.key} @ ${w.toInt()}px');
      });
    }
  }

  for (final w in widths) {
    testWidgets('主页三个标签 @ ${w.toInt()}px 无布局异常', (tester) async {
      tester.view.physicalSize = Size(w, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      expectNoException(tester, '主页-出题 @ ${w.toInt()}px');

      for (final tab in ['AI', '设置']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expectNoException(tester, '主页-$tab @ ${w.toInt()}px');
      }
    });
  }

  group('窄屏关键控件可达性', () {
    testWidgets('320px 下科目面板的生成按钮存在且可点', (tester) async {
      await pumpPanel(tester, 320,
          const MathPanel(grade: 1, version: 'renjiao', volume: '上'));

      final btn = find.text('生成预览');
      expect(btn, findsOneWidget, reason: '窄屏下应仍有常驻生成按钮');

      // 点一下，确认没有异常且能切到预览
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expectNoException(tester, '320px 点生成');
    });

    testWidgets('320px 下 AI 出题的题型行可达', (tester) async {
      await pumpPanel(tester, 320,
          const AiPanel(grade: 6, version: 'renjiao', volume: '上'));

      // 默认科目是数学（与显示顺序解耦），所以这里应当能查到数学题型。
      // 不改成「只断言有 TypeRow 就行」——那样等于什么都没验证。
      expect(find.text('计算题'), findsWidgets,
          reason: '默认科目为数学，窄屏下应能看到数学题型行');
      expectNoException(tester, '320px AI 出题');
    });
  });
}
