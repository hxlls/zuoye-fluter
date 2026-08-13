import '../data/app_data.dart';
import 'rand_gen.dart';
import 'worksheet_model.dart';
import 'math_gen.dart';

/// 数学作业生成选项
class MathOptions {
  final int grade;
  final String version;
  final String volume;
  final List<String> types;
  final Map<String, int> counts;
  final int count; // 默认总题量（当 counts 无某题型值时使用）
  final String diff;
  final bool showAnswer;
  final bool showTitle;

  MathOptions({
    this.grade = 1,
    this.version = 'renjiao',
    this.volume = '上',
    List<String>? types,
    Map<String, int>? counts,
    this.count = 30,
    this.diff = 'easy',
    this.showAnswer = true,
    this.showTitle = true,
  })  : types = types ?? [],
        counts = counts ?? {};
}

/// 数学题目渲染信息
class MathItemData {
  final String tid;
  final MathProblem prob;
  final String key;
  final dynamic ans;

  MathItemData({
    required this.tid,
    required this.prob,
    required this.key,
    required this.ans,
  });
}

/// 数学题型节
class MathSection {
  final String tid;
  final String title;
  final String unit;
  final List<MathItemData> items;
  final bool vertical;
  final int? cols;
  final int? itemH;

  MathSection({
    required this.tid,
    required this.title,
    required this.unit,
    required this.items,
    required this.vertical,
    this.cols,
    this.itemH,
  });
}

/// 生成数学作业 → 页面列表
List<WsPage> mathRenderPages(MathOptions opts) {
  final data = AppData();
  final grade = opts.grade;
  final ver = opts.version;
  final vol = opts.volume;

  // 配置与题型
  final cfg = data.vol(ver, grade, vol, 'math')?.math ?? [];
  final types = opts.types.isNotEmpty
      ? opts.types
      : cfg.map((t) => t.id).toList();
  final g = RandGen(diff: opts.diff, grade: grade);

  final sections = <MathSection>[];
  final answerGroups = <(String, String, List<dynamic>)>[]; // title, unit, answers
  final _fallback =
      (opts.count / types.length).ceil().clamp(1, 30); // 与 JS fallbackPerType 一致

  for (final tid in types) {
    final detail = data.mathDetails[tid];
    if (detail == null) continue;
    final meta = cfg.where((t) => t.id == tid).firstOrNull;
    final unit = meta?.unit ?? "";
    final perType = opts.counts.containsKey(tid)
        ? (opts.counts[tid] ?? 0).clamp(0, 30)
        : _fallback;
    if (perType <= 0) continue;

    final items = <MathItemData>[];
    final answers = <dynamic>[];
    final used = <String>{};
    int attempts = 0;
    while (items.length < perType && attempts < 1000) {
      attempts++;
      final prob = genMathProblem(tid, g);
      final key = problemKey(tid, prob);
      if (used.contains(key)) continue;
      used.add(key);
      final ans = _computeAns(tid, prob);
      items.add(MathItemData(tid: tid, prob: prob, key: key, ans: ans));
      answers.add(ans);
    }
    if (items.isNotEmpty) {
      sections.add(MathSection(
        tid: tid,
        title: detail.desc,
        unit: unit,
        items: items,
        vertical: detail.vertical,
        cols: detail.cols,
        itemH: detail.itemH,
      ));
      answerGroups.add((detail.desc, unit, answers));
    }
  }

  final pages = <WsPage>[];
  final usableH = 860.0;
  final pageNo = <int>[1];

  WsPageTitle mathTitle(int pageNo) {
    final tb = data.textbooks[ver] ?? data.textbooks['renjiao']!;
    final gname = data.gradeNames[grade] ?? '第$grade年级';
    final volName = vol == '下' ? '下册' : '上册';
    return WsPageTitle(
      main: '数学练习 · $gname · $volName',
      sub: '参考教材：${tb.math}$gname$volName',
      meta1: '姓名：____________',
      meta2: '班级：____________',
      meta3: '日期：____________',
    );
  }

  // 手动分页（对齐 paginateMath 逻辑）
  var curH = 0.0;
  var curNodes = <WsNode>[];
  var curTitle = opts.showTitle ? mathTitle(pageNo[0]) : null;

  void flushPage() {
    if (curNodes.isNotEmpty) {
      pages.add(WsPage(
        title: curTitle,
        nodes: curNodes,
      ));
      pageNo[0]++;
    }
    curNodes = [];
    curH = 0;
  }

  for (final sec in sections) {
    final secH = 60.0;
    if (curH + secH > usableH && curNodes.isNotEmpty) {
      flushPage();
      curTitle = opts.showTitle ? mathTitle(pageNo[0]) : null;
    }
    curH += secH;
    curNodes.add(WsHeading(sec.title, unit: sec.unit));
    final instr = data.mathInstruction[sec.tid] ?? '计算下面各题。';
    curNodes.add(WsSection(instr, mathStyle: true));

    final perRow = sec.cols ?? (sec.vertical ? 4 : 3);
    final itemH = (sec.itemH ?? (sec.vertical ? 138 : 74)).toDouble();
    var row = <WsCard>[];
    for (var i = 0; i < sec.items.length; i++) {
      if (row.isEmpty) {
        if (curH + itemH > usableH) {
          flushPage();
          curTitle = opts.showTitle ? mathTitle(pageNo[0]) : null;
        }
      }
      row.add(WsCard('math', sec.items[i], num: i + 1));
      if (row.length == perRow) {
        curNodes.add(WsGrid(row,
            cols: sec.cols ?? (sec.vertical ? 4 : 3),
            evenly: true,
            itemHeight: itemH + 10));
        curH += itemH + 10;
        row = [];
      }
    }
    if (row.isNotEmpty) {
      // 补齐
      while (row.length < perRow) {
        row.add(WsCard('pad', null));
      }
      curNodes.add(WsGrid(row,
          cols: sec.cols ?? (sec.vertical ? 4 : 3),
          evenly: true,
          itemHeight: itemH + 10));
      curH += itemH + 10;
    }
  }
  if (curNodes.isNotEmpty) flushPage();

  // 答案页
  if (opts.showAnswer && answerGroups.isNotEmpty) {
    final nodes = <WsNode>[];
    nodes.add(WsHeading('参考答案'));
    for (final (title, unit, answers) in answerGroups) {
      nodes.add(WsAnswerGroup(title, unit: unit));
      var line = '';
      final lines = <String>[];
      for (var i = 0; i < answers.length; i++) {
        line += '${i + 1}. ${_ansStr(answers[i])}　';
        if ((i + 1) % 10 == 0) {
          lines.add(line);
          line = '';
        }
      }
      if (line.isNotEmpty) lines.add(line);
      for (final l in lines) {
        nodes.add(WsAnswerLine(0, l, ''));
      }
    }
    pages.add(WsPage(
      title: opts.showTitle
          ? mathTitle(pageNo[0])
          : WsPageTitle(main: '参考答案', meta1: '数学'),
      nodes: nodes,
      noSpread: true,
    ));
  }

  return pages;
}

dynamic _computeAns(String tid, MathProblem prob) {
  if (prob.ans != null) return prob.ans;
  if (prob.compare) {
    if (prob.a > prob.b) return '>';
    if (prob.a < prob.b) return '<';
    return '=';
  }
  final a = prob.a;
  final b = prob.b;
  dynamic ans;
  switch (prob.op) {
    case '+':
      ans = a + b;
      break;
    case '-':
      ans = a - b;
      break;
    case '×':
      ans = a * b;
      break;
    case '÷':
      ans = a / b;
      break;
  }
  // 小数精度处理
  if (prob.op == '+' || prob.op == '-') {
    if ('$a'.contains('.') || '$b'.contains('.')) {
      final r = (ans * 100).roundToDouble() / 100;
      ans = r == r.roundToDouble() ? r.roundToDouble() : r;
    }
  }
  return ans;
}

String _ansStr(dynamic a) {
  if (a == null) return '';
  if (a is double) {
    if (a == a.roundToDouble()) return a.round().toString();
    return a.toString();
  }
  return '$a';
}
