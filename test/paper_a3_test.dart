import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuoye_fluter/core/paper.dart';
import 'package:zuoye_fluter/core/worksheet_model.dart';
import 'package:zuoye_fluter/ui/preview_panel.dart';
import 'package:zuoye_fluter/core/paper.dart' show PaperPref;
import 'package:zuoye_fluter/ui/worksheet_view.dart';

void main() {
  group('PaperSize 栏位拼排', () {
    test('A4 每页独占一张纸', () {
      final sheets = PaperSize.a4.sheetSlots(3);
      expect(sheets.length, 3);
      expect(sheets[0], (0, null));
      expect(sheets[1], (1, null));
      expect(sheets[2], (2, null));
    });

    test('A3 两页一纸，奇数页右栏留空', () {
      final sheets = PaperSize.a3.sheetSlots(5);
      expect(sheets.length, 3);
      expect(sheets[0], (0, 1));
      expect(sheets[1], (2, 3));
      expect(sheets[2], (4, null));
      expect(PaperSize.a3.sheetSlots(4).length, 2);
    });

    test('A3 纸面宽为 A4 的两倍（双栏各 794）', () {
      expect(PaperSize.a3.pageWidth, PaperSize.a4.pageWidth * 2);
      expect(PaperSize.a3.pageHeight, PaperSize.a4.pageHeight);
      expect(PaperSize.a3.columnWidth, 794.0);
    });
  });

  group('A3 试卷版页眉规则', () {
    final repeated = WsPage(
      title: WsPageTitle(main: '语文作业 · 六年级 · 上册', meta1: '姓名：____________'),
      repeatedHeader: true,
      nodes: [WsSection('一、看拼音写词语'), WsNote('栏内内容')],
    );
    final answer = WsPage(
      title: WsPageTitle(main: '参考答案', meta1: '语文'),
      noSpread: true,
      nodes: [WsNote('答案内容')],
    );

    testWidgets('A4 模式页眉逐页重复（与旧行为一致）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorksheetPageView(page: repeated),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('语文作业 · 六年级 · 上册'), findsOneWidget);
    });

    testWidgets('A3 模式：重复主标题只在第一栏，语义标题（参考答案）保留',
        (tester) async {
      Widget col(WorksheetPageView view) => MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: view),
            ),
          );

      // 第一栏：chrome 渲染
      await tester.pumpWidget(col(WorksheetPageView(page: repeated)));
      await tester.pump();
      expect(find.text('语文作业 · 六年级 · 上册'), findsOneWidget);

      // 非第一栏：repeatedHeader 主标题被省略
      await tester.pumpWidget(col(WorksheetPageView(
        page: repeated,
        showChrome: false,
      )));
      await tester.pump();
      expect(find.text('语文作业 · 六年级 · 上册'), findsNothing);

      // 非第一栏的参考答案页：语义标题仍保留
      await tester.pumpWidget(col(WorksheetPageView(
        page: answer,
        showChrome: false,
      )));
      await tester.pump();
      expect(find.text('参考答案'), findsOneWidget);
    });

    testWidgets('预览面板切到 A3：主标题只出现一次、得分栏只在第一栏',
        (tester) async {
      final pages = [
        for (var i = 0; i < 3; i++)
          WsPage(
            title: WsPageTitle(
                main: '数学作业 · 四年级 · 上册', meta1: '姓名：____________'),
            repeatedHeader: true,
            nodes: [WsNote('第${i + 1}页内容')],
          ),
      ];
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: WorksheetPreviewPanel()),
      ));
      await tester.pump();
      // 空面板提示
      expect(find.text('点击「生成预览」查看作业'), findsOneWidget);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WorksheetPreviewPanel(pages: pages)),
      ));
      await tester.pump();
      // 默认 A4：三页各自带标题
      expect(find.text('数学作业 · 四年级 · 上册'), findsNWidgets(3));

      await tester.tap(find.text('A3 试卷版'));
      await tester.pump();
      // A3：两张纸（3 页 = 2+1），主标题只剩第一栏一处
      expect(find.text('数学作业 · 四年级 · 上册'), findsOneWidget);
      expect(find.text('第2页内容'), findsOneWidget);
      expect(find.text('第3页内容'), findsOneWidget);
    });

    testWidgets('纸张选择持久化：点选后写入偏好，新面板恢复', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final pages = [
        for (var i = 0; i < 2; i++)
          WsPage(
            title: WsPageTitle(
                main: '语文作业 · 六年级 · 上册', meta1: '姓名：____________'),
            repeatedHeader: true,
            nodes: [WsNote('第${i + 1}页内容')],
          ),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WorksheetPreviewPanel(pages: pages)),
      ));
      await tester.pump(); // initState 异步读偏好（此时为空 → A4）
      await tester.pump();
      expect(find.text('语文作业 · 六年级 · 上册'), findsNWidgets(2)); // A4 逐页页头

      await tester.tap(find.text('A3 试卷版'));
      await tester.pump(); // setState + PaperPref.save
      await tester.pump();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('paperSize'), 'a3');
      expect(await PaperPref.load(), PaperSize.a3);

      // 新面板实例（模拟重启）：恢复 A3
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WorksheetPreviewPanel(pages: pages)),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('语文作业 · 六年级 · 上册'), findsOneWidget); // A3 只在首栏
    });
  });
}
