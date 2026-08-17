import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/core/math_worksheet.dart';
import 'package:zuoye_fluter/core/math_gen.dart';
import 'package:zuoye_fluter/core/worksheet_model.dart';
import 'package:zuoye_fluter/data/app_data.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  test('数学作业中题目操作数不包含之前题目的答案', () {
    final opts = MathOptions(
      grade: 1,
      types: ['add10'],
      count: 20,
      showAnswer: true,
    );
    final pages = mathRenderPages(opts);
    
    final allExprs = <String>[];
    final allNums = <num>[];
    
    for (final page in pages) {
      for (final node in page.nodes) {
        if (node is WsGrid) {
          for (final card in node.cards) {
            if (card.kind == 'math' && card.data is MathItemData) {
              final item = card.data as MathItemData;
              allExprs.add(item.prob.expr ?? '${item.prob.a} ${item.prob.op} ${item.prob.b}');
              if (item.ans is num) allNums.add(item.ans as num);
            }
          }
        }
      }
    }
    
    expect(allExprs.length, greaterThan(0), reason: '应生成题目');
    
    int violations = 0;
    for (int i = 1; i < allExprs.length; i++) {
      final currentExpr = allExprs[i];
      final prevAnswers = allNums.sublist(0, i);
      for (final ans in prevAnswers) {
        final ansStr = ans == ans.roundToDouble() ? ans.toInt().toString() : ans.toString();
        if (currentExpr.contains(ansStr)) {
          violations++;
          print('违规: 题目${i+1} "$currentExpr" 包含之前答案 $ansStr');
        }
      }
    }
    print('共 ${allExprs.length} 题，违规 $violations 次');
    expect(violations, 0, reason: '题目操作数不应包含之前题目的答案');
  });
}