import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuoye_fluter/data/ai_pref_store.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/ui/home_page.dart';
import 'package:zuoye_fluter/ui/panel_widgets.dart';

/// AI 出题面板的偏好持久化测试。
///
/// 对应用户反馈：「选择了人教 6 年级，但只有组词+造句可以选，勾选还不能取消」。
///
/// 根因：`home_page` 的 tab 容器是 `switch` 而不是 `IndexedStack`，
/// 离开 AI 标签会**销毁** `AiPanel`；而它的状态（科目 / 题型勾选 / 题量 / 选项）
/// 原先只在内存里，于是一旦去设置里改年级（必然要离开 AI 标签），
/// 回来就全部重置：取消的勾选又自己勾上、科目也悄悄变回数学。
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

  Future<void> gotoAi(WidgetTester tester) async {
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
  }

  Future<void> setGrade(WidgetTester tester, int g) async {
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$g年级'));
    await tester.pumpAndSettle();
  }

  List<TypeRow> rows(WidgetTester tester) =>
      tester.widgetList<TypeRow>(find.byType(TypeRow)).toList();

  TypeRow? rowOf(WidgetTester tester, String label) {
    final hit = rows(tester).where((r) => r.label == label);
    return hit.isEmpty ? null : hit.first;
  }

  testWidgets('6 年级语文：8 个题型全部出现（不再只显示两个）', (tester) async {
    await pumpHome(tester);
    await setGrade(tester, 6);
    await gotoAi(tester);
    await tester.tap(find.text('语文'));
    await tester.pumpAndSettle();

    final labels = rows(tester).map((r) => r.label).toList();
    expect(labels.length, 8, reason: '语文 6 年级应显示全部 8 个题型，实际 $labels');
    expect(labels, contains('生字组词'));
    expect(labels, contains('词语造句'));
    expect(labels, contains('近义词·反义词'));
    expect(labels, contains('阅读理解'));
    expect(labels, contains('跨学科学习'));
  });

  testWidgets('取消勾选后切走再回来，仍然是取消状态（旧实现会复活）',
      (tester) async {
    await pumpHome(tester);
    await gotoAi(tester);
    await tester.tap(find.text('语文'));
    await tester.pumpAndSettle();

    // 取消「生字组词」
    final idx = rows(tester).indexWhere((r) => r.label == '生字组词');
    expect(idx, greaterThanOrEqualTo(0));
    await tester.tap(find.byType(Checkbox).at(idx));
    await tester.pumpAndSettle();
    expect(rowOf(tester, '生字组词')!.checked, isFalse);

    // 切到「出题」再切回「AI」——这一步会销毁并重建 AiPanel
    await tester.tap(find.text('出题'));
    await tester.pumpAndSettle();
    await gotoAi(tester);

    expect(rowOf(tester, '生字组词'), isNotNull,
        reason: '切回来后科目应仍是语文，而不是变回数学');
    expect(rowOf(tester, '生字组词')!.checked, isFalse,
        reason: '旧实现会 clear 后整表重播种，把取消的勾选复活');
  });

  testWidgets('科目选择在切走再回来后保留（旧实现会变回数学）', (tester) async {
    await pumpHome(tester);
    await gotoAi(tester);
    await tester.tap(find.text('语文'));
    await tester.pumpAndSettle();
    expect(rowOf(tester, '生字组词'), isNotNull);

    await tester.tap(find.text('出题'));
    await tester.pumpAndSettle();
    await gotoAi(tester);

    // 语文的题型仍在 => 科目没被重置
    expect(rowOf(tester, '生字组词'), isNotNull, reason: '科目应保持语文');
    expect(rowOf(tester, '计算题'), isNull, reason: '不应变回数学');
  });

  testWidgets('题量设置在切走再回来后保留', (tester) async {
    await pumpHome(tester);
    await gotoAi(tester);
    await tester.tap(find.text('语文'));
    await tester.pumpAndSettle();

    rowOf(tester, '词语填空')!.onCount(9);
    await tester.pumpAndSettle();
    expect(rowOf(tester, '词语填空')!.count, 9);

    await tester.tap(find.text('出题'));
    await tester.pumpAndSettle();
    await gotoAi(tester);

    expect(rowOf(tester, '词语填空')!.count, 9, reason: '题量应被持久化');
  });

  testWidgets('年级升高后新可用的题型补上默认勾选，但已取消的仍保持取消',
      (tester) async {
    await pumpHome(tester);

    // 1 年级：语文只有 5 个题型可用（近义词/阅读/跨学科要 2、3 年级起）
    await gotoAi(tester);
    await tester.tap(find.text('语文'));
    await tester.pumpAndSettle();
    expect(rowOf(tester, '阅读理解'), isNull, reason: '1 年级不应有阅读理解');

    // 取消「生字组词」
    final idx = rows(tester).indexWhere((r) => r.label == '生字组词');
    await tester.tap(find.byType(Checkbox).at(idx));
    await tester.pumpAndSettle();
    expect(rowOf(tester, '生字组词')!.checked, isFalse);

    // 升到 6 年级（中途离开 AI 标签）
    await setGrade(tester, 6);
    await gotoAi(tester);

    // 新出现的题型应带默认勾选
    expect(rowOf(tester, '阅读理解')!.checked, isTrue,
        reason: '新年级才可用的题型应补上默认勾选');
    // 而用户主动取消的仍应保持取消
    expect(rowOf(tester, '生字组词')!.checked, isFalse,
        reason: '补默认值不应复活用户已取消的题型');
  });

  testWidgets('AI 帮答：科目选择被持久化，切走再回来仍是它', (tester) async {
    await pumpHome(tester);
    await gotoAi(tester);
    await tester.tap(find.textContaining('AI 帮答'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();
    expect(await AiPrefStore.loadHelpSubject(), 'other');

    await tester.tap(find.text('出题'));
    await tester.pumpAndSettle();
    await gotoAi(tester);
    await tester.tap(find.textContaining('AI 帮答'));
    await tester.pumpAndSettle();

    // 面板被销毁重建后，应从存储恢复
    expect(await AiPrefStore.loadHelpSubject(), 'other',
        reason: '旧实现 _subject 只在内存，切走一次就变回数学');
  });

  group('AiPrefStore · 序列化往返', () {
    test('题量偏好往返（含 0，用于区分「主动取消」）', () async {
      SharedPreferences.setMockInitialValues({});
      await AiPrefStore.saveStyles('chinese', {'zuci': 0, 'zaoju': 5});
      expect(await AiPrefStore.loadStyles('chinese'), {'zuci': 0, 'zaoju': 5});
    });

    test('题量偏好按科目隔离', () async {
      SharedPreferences.setMockInitialValues({});
      await AiPrefStore.saveStyles('math', {'calc': 3});
      expect(await AiPrefStore.loadStyles('chinese'), isEmpty);
      expect((await AiPrefStore.loadStyles('math'))['calc'], 3);
    });

    test('对话记录往返', () async {
      SharedPreferences.setMockInitialValues({});
      await AiPrefStore.saveHelpMessages([('ai', '你好'), ('user', '1+1=?')]);
      final back = await AiPrefStore.loadHelpMessages();
      expect(back.length, 2);
      expect(back[0].$1, 'ai');
      expect(back[1].$2, '1+1=?');
    });

    test('无记录时返回空值，不抛异常', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AiPrefStore.loadStyles('math'), isEmpty);
      expect(await AiPrefStore.loadHelpMessages(), isEmpty);
      expect(await AiPrefStore.loadSubject(), isNull);
      expect(await AiPrefStore.loadHelpSubject(), isNull);
    });
  });

  group('AI 面板的科目按教材版本过滤', () {
    // 读 AI 面板「科目」那个 SegButtons 的选项值。
    // 用选项值而不是文案断言，避免和别处的「语文」字样撞车。
    List<String> subjectOptions(WidgetTester tester) {
      for (final s in tester.widgetList<SegButtons>(find.byType(SegButtons))) {
        if (s.options.any((o) => o.$1 == 'chinese' || o.$1 == 'english')) {
          return s.options.map((o) => o.$1).toList();
        }
      }
      return <String>[];
    }

    // 读当前「选中」的科目值（SegButtons.value）
    String? selectedSubject(WidgetTester tester) {
      for (final s in tester.widgetList<SegButtons>(find.byType(SegButtons))) {
        if (s.options.any((o) => o.$1 == 'chinese' || o.$1 == 'english')) {
          return s.value;
        }
      }
      return null;
    }

    Future<void> setVersion(WidgetTester tester, String name) async {
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    testWidgets('人教版：显示顺序为 语文/数学/英语，且默认选中数学', (tester) async {
      await pumpHome(tester);
      await gotoAi(tester);
      // 显示顺序：按主页科目卡片的习惯排
      expect(subjectOptions(tester), ['chinese', 'math', 'english']);
      // 默认值：沿用历史行为，必须是数学。
      // 这一条**不能省**——曾经因为用 `options.first` 当默认值，
      // 调一次显示顺序就把默认科目悄悄从数学变成了语文。
      expect(selectedSubject(tester), 'math',
          reason: '默认科目必须与显示顺序解耦，保持为数学');
    });

    testWidgets('默认科目的题型清单确实是数学的', (tester) async {
      await pumpHome(tester);
      await gotoAi(tester);
      expect(selectedSubject(tester), 'math');
      final labels =
          tester.widgetList<TypeRow>(find.byType(TypeRow)).map((r) => r.label).toList();
      expect(labels, contains('计算题'));
      expect(labels, isNot(contains('生字组词')),
          reason: '默认是数学时不应显示语文题型');
    });

    testWidgets('该版本不提供数学时，才退到第一个可用科目', (tester) async {
      await pumpHome(tester);
      await setVersion(tester, '外研·三起点');
      await gotoAi(tester);
      expect(subjectOptions(tester), ['english']);
      expect(selectedSubject(tester), 'english',
          reason: '外研不提供数学，应退到唯一可用的英语');
    });

    testWidgets('冀教版：不提供语文（cally 为 null）', (tester) async {
      await pumpHome(tester);
      await setVersion(tester, '冀教版');
      await gotoAi(tester);
      expect(subjectOptions(tester), ['math', 'english']);
    });

    testWidgets('外研·三起点：只剩英语', (tester) async {
      await pumpHome(tester);
      await setVersion(tester, '外研·三起点');
      await gotoAi(tester);
      expect(subjectOptions(tester), ['english'],
          reason: '外研三起点只提供英语，原先这里写死了三项');
    });

    testWidgets('外研·一起点：也只剩英语', (tester) async {
      await pumpHome(tester);
      await setVersion(tester, '外研·一起点');
      await gotoAi(tester);
      expect(subjectOptions(tester), ['english']);
    });

    testWidgets('当前科目被版本淘汰时自动切到可用科目', (tester) async {
      await pumpHome(tester);
      await gotoAi(tester);
      // 选语文
      await tester.tap(find.text('语文'));
      await tester.pumpAndSettle();
      expect(subjectOptions(tester), contains('chinese'));

      // 切到外研三起点（不提供语文）——应自动落到英语，而不是停在一个不存在的科目上
      await setVersion(tester, '外研·三起点');
      await gotoAi(tester);
      expect(subjectOptions(tester), ['english']);
      // 题型列表应变成英语的题型
      final labels = tester
          .widgetList<TypeRow>(find.byType(TypeRow))
          .map((r) => r.label)
          .toList();
      expect(labels, isNot(contains('生字组词')),
          reason: '切到只提供英语的版本后，不应还显示语文题型');
    });
  });
}
