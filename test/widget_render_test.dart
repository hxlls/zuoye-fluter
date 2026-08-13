import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/data/app_data.dart';
import 'package:zuoye_fluter/core/math_worksheet.dart';
import 'package:zuoye_fluter/core/chinese_worksheet.dart';
import 'package:zuoye_fluter/core/english_worksheet.dart';
import 'package:zuoye_fluter/core/worksheet_model.dart';
import 'package:zuoye_fluter/ui/worksheet_view.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
  }

  Future<void> pumpPages(WidgetTester tester, List<WsPage> pages) async {
    final captured = <Object>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      captured.add(details.exception);
      // ignore: avoid_print
      print('=== 渲染异常（页面：${details.library}）===\n${details.exception}');
      // ignore: avoid_print
      print(details.informationCollector?.call().toString() ?? '');
    };
    for (final p in pages) {
      captured.clear();
      await tester.pumpWidget(wrap(WorksheetPageView(page: p)));
      await tester.pump();
      if (captured.isNotEmpty) {
        FlutterError.onError = oldOnError;
        fail('渲染 ${p.title?.main} 页面抛异常');
      }
    }
    FlutterError.onError = oldOnError;
  }

  testWidgets('数学页面可渲染', (tester) async {
    final pages = mathRenderPages(MathOptions(
      grade: 4,
      version: 'renjiao',
      volume: '上',
      count: 30,
      diff: 'mid',
      showAnswer: true,
      showTitle: true,
    ));
    expect(pages.isNotEmpty, true);
    await pumpPages(tester, pages);
  });

  testWidgets('语文页面可渲染', (tester) async {
    final pages = chineseRenderPages(ChineseOptions(
      grade: 3,
      version: 'renjiao',
      volume: '上',
      types: ['pinyin2char', 'char2pinyin', 'zuci', 'gushiFill', 'chengyuFill', 'chengyuGuess', 'mingjuFill'],
      counts: {
        'pinyin2char': 6,
        'char2pinyin': 6,
        'zuci': 6,
        'gushiFill': 2,
        'chengyuFill': 3,
        'chengyuGuess': 3,
        'mingjuFill': 2,
      },
      showAnswer: true,
      showTitle: true,
    ));
    expect(pages.isNotEmpty, true);
    await pumpPages(tester, pages);
  });

  testWidgets('英语页面可渲染（一年级）', (tester) async {
    final pages = englishRenderPages(EnglishOptions(
      grade: 1,
      version: 'renjiao',
      volume: '上',
      count: 8,
      showTitle: true,
      showAnswer: true,
    ));
    expect(pages.isNotEmpty, true);
    await pumpPages(tester, pages);
  });

  testWidgets('英语页面可渲染（三年级含连线）', (tester) async {
    final pages = englishRenderPages(EnglishOptions(
      grade: 3,
      version: 'renjiao',
      volume: '上',
      types: ['trace', 'match', 'cn2en', 'en2cn', 'spell'],
      counts: {'trace': 8, 'match': 6, 'cn2en': 6, 'en2cn': 6, 'spell': 6},
      showTitle: true,
      showAnswer: true,
    ));
    expect(pages.isNotEmpty, true);
    await pumpPages(tester, pages);
  });
}
