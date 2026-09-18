import 'package:flutter/material.dart';
import '../core/worksheet_model.dart';
import 'worksheet_cards.dart';


/// 大题序号转中文：0->一、1->二 …（试卷惯例）
String cnNumber(int i) {
  const digits = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];
  final n = i + 1;
  if (n <= 9) return digits[n - 1];
  if (n == 10) return '十';
  if (n < 20) return '十${digits[n - 11]}';
  return '$n';
}

/// 试卷顶部的「题号 / 得分」表——试卷的标志性元素，老师在此打分
class _ScoreTable extends StatelessWidget {
  final List<String> columns;
  const _ScoreTable({required this.columns});

  @override
  Widget build(BuildContext context) {
    const line = Color(0xff4a4a4a);
    Widget cell(String t, {bool head = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
            child: Text(
              t,
              style: TextStyle(
                fontSize: 12.5,
                color: head ? const Color(0xff111111) : const Color(0xff333333),
                fontWeight: head ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );

    // 末尾加「总分」列——真实试卷的标准卷头就是
    // 「题序 | 一 | 二 | … | 九 | 总分」，老师最后合计总分用。
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 52.0 + columns.length * 46.0 + 56.0,
          child: Table(
            border: TableBorder.all(color: line, width: 0.8),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(children: [
                cell('题号', head: true),
                for (final c in columns) cell(c),
                cell('总分', head: true),
              ]),
              TableRow(children: [
                cell('得分', head: true),
                for (final _ in columns) cell(''),
                cell(''),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// A4 预览页（试卷版式）
class WorksheetPageView extends StatelessWidget {
  final WsPage page;

  /// 本页第一个大题在全卷中的序号（从 0 起）。
  /// 试卷的大题序号「一、二、三」要跨页连续，而页面是独立渲染的，
  /// 所以由预览层预扫描各页后把起始序号传进来。
  final int sectionOffset;

  /// 全卷大题的中文序号（如 ['一','二','三']）。
  /// 非空时在**第一页**顶部渲染「题号 / 得分」表——试卷的标志性元素。
  final List<String> scoreColumns;

  const WorksheetPageView({
    super.key,
    required this.page,
    this.sectionOffset = 0,
    this.scoreColumns = const [],
  });

  /// 判断某个节点是否开启一个新大题。
  ///
  /// 各科目用的节点类型不一致：数学/英语用 WsHeading 当大题标题，
  /// 语文直接拿 WsSection（题型说明）当大题标题。
  /// 而数学的 WsSection 是「直接写出得数。」这种**小题说明**（mathStyle=true），
  /// 不算新大题。
  static bool isSectionStart(WsNode n) =>
      (n is WsHeading && !n.continuation) ||
      (n is WsSection && !n.mathStyle);

  /// 给本页节点逐一标出所属大题序号（非大题节点为 null）
  List<int?> _sectionNumbers() {
    // 参考答案页不做大题编号（它的 WsHeading('参考答案') 不是题目）
    if (page.noSpread) return List<int?>.filled(page.nodes.length, null);
    final out = <int?>[];
    var n = sectionOffset;
    for (final node in page.nodes) {
      if (isSectionStart(node)) {
        out.add(n);
        n++;
      } else {
        out.add(null);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final nums = _sectionNumbers();
    // 普通页 min-height A4，内容超高时自然增高（对应 CSS min-height:1123 + flex:1），
    // 避免内容溢出纸张；参考答案等 noSpread 页同样允许自然增高
    return Container(
      width: 794,
      constraints: const BoxConstraints(minHeight: 1123),
      padding: const EdgeInsets.fromLTRB(56, 44, 56, 44),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(color: Color(0x26000000), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: page.noSpread
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (page.title != null) _TitleBar(title: page.title!),
                if (scoreColumns.isNotEmpty) _ScoreTable(columns: scoreColumns),
                for (var i = 0; i < page.nodes.length; i++)
                  _buildNode(context, page.nodes[i], nums[i]),
              ],
            )
          : IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (page.title != null) _TitleBar(title: page.title!),
                  if (scoreColumns.isNotEmpty) _ScoreTable(columns: scoreColumns),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: page.packed
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.spaceEvenly,
                      children: [
                        for (var i = 0; i < page.nodes.length; i++)
                          _buildNode(context, page.nodes[i], nums[i]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildNode(BuildContext context, WsNode node, int? sectionNo) {
    if (node is WsSection) {
      return _SectionLabel(
        text: node.text,
        mathStyle: node.mathStyle,
        number: sectionNo == null ? null : cnNumber(sectionNo),
      );
    }
    if (node is WsNote) {
      // 与「小题说明」同款缩进灰字，紧跟所属大题标题
      return Padding(
        padding: const EdgeInsets.only(left: 24, bottom: 8),
        child: Text(node.text,
            style: const TextStyle(fontSize: 13.5, color: Color(0xff666666))),
      );
    }
    if (node is WsHeading) {
      return _Heading(
        title: node.title,
        unit: node.unit,
        engStyle: node.engStyle,
        number: sectionNo == null ? null : cnNumber(sectionNo),
        continuation: node.continuation,
      );
    }
    if (node is WsGrid) {
      return _buildGrid(node);
    }
    if (node is WsBlock) {
      return buildWsBlockWidget(node.data);
    }
    if (node is WsPlaceholder) {
      return _Placeholder(p: node);
    }
    if (node is WsAnswerLine) {
      return _AnswerLine(node: node);
    }
    if (node is WsAnswerGroup) {
      return _AnswerGroup(node: node);
    }
    if (node is WsMatchAnswer) {
      return _MatchAnswer(node: node);
    }
    return const SizedBox();
  }

  Widget _buildGrid(WsGrid grid) {
    // 网格保持自然高度（对应 CSS 中 grid 项的 min-height），由页面级 spaceEvenly 分布间距
    // 行间加最小间距（对应 CSS gap），避免题目挤在一起
    final rows = <Widget>[];
    for (var i = 0; i < grid.cards.length; i += grid.cols) {
      final end = i + grid.cols > grid.cards.length
          ? grid.cards.length
          : i + grid.cols;
      final cards = grid.cards.sublist(i, end);
      // 有 itemHeight 时按最小行高约束（自然更高时仍可增高，避免裁剪），
      // 使稀疏内容页（如单位换算）不会留下大片空白
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var c = 0; c < grid.cols; c++)
            Expanded(
              child: c < cards.length
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _buildCard(cards[c]),
                    )
                  : const SizedBox(),
            ),
        ],
      );
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: grid.itemHeight == null
            ? row
            : ConstrainedBox(
                constraints: BoxConstraints(minHeight: grid.itemHeight!),
                child: row,
              ),
      ));
    }
    return Column(
      mainAxisAlignment:
          grid.evenly ? MainAxisAlignment.spaceEvenly : MainAxisAlignment.start,
      children: rows,
    );
  }

  Widget _buildCard(WsCard card) {
    return buildWsCardWidget(card);
  }
}

class _TitleBar extends StatelessWidget {
  final WsPageTitle title;
  const _TitleBar({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        children: [
          Text(
            title.main,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              color: Color(0xff222222),
            ),
          ),
          if (title.sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                title.sub!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xff999999)),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(bottom: 6),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xff999999))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title.meta1 ?? '', style: const TextStyle(fontSize: 14, color: Color(0xff444444))),
                Text(title.meta2 ?? '', style: const TextStyle(fontSize: 14, color: Color(0xff444444))),
                Text(title.meta3 ?? '', style: const TextStyle(fontSize: 14, color: Color(0xff444444))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool mathStyle;

  /// 大题中文序号（如「一」）。null 表示这只是小题说明、不是大题标题。
  final String? number;

  const _SectionLabel({required this.text, this.mathStyle = false, this.number});

  @override
  Widget build(BuildContext context) {
    // 小题说明（如数学的「直接写出得数。」）：缩进灰字，跟在所属大题标题下
    if (mathStyle) {
      return Padding(
        padding: const EdgeInsets.only(left: 24, bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 13.5, color: Color(0xff666666))),
      );
    }
    // 试卷大题标题：中文序号 + 黑色加粗，不用原来的蓝色竖条
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 12),
      child: Text(
        number == null ? text : '$number、$text',
        style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: Color(0xff111111),
            height: 1.4),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String title;
  final String? unit;
  final bool engStyle;

  /// 大题中文序号（如「一」）
  final String? number;

  /// 续页标题：不编号，标成「（续）」
  final bool continuation;

  const _Heading({
    required this.title,
    this.unit,
    this.engStyle = false,
    this.number,
    this.continuation = false,
  });

  @override
  Widget build(BuildContext context) {
    // 试卷大题标题：中文序号 + 黑色加粗；右侧浅灰注明教材单元（给家长看的参考）
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              continuation
                  ? '$title（续）'
                  : (number == null ? title : '$number、$title'),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xff111111),
                  height: 1.4),
            ),
          ),
          if (unit != null && unit!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(unit!,
                  style:
                      const TextStyle(fontSize: 11.5, color: Color(0xffaaaaaa))),
            ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final WsPlaceholder p;
  const _Placeholder({required this.p});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(p.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 12),
          Text(p.title,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(p.desc,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xff888888))),
          ),
        ],
      ),
    );
  }
}

class _AnswerLine extends StatelessWidget {
  final WsAnswerLine node;
  const _AnswerLine({required this.node});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(
        TextSpan(children: [
          if (node.num > 0)
            TextSpan(
              text: '${node.num}. ',
              style: const TextStyle(
                  fontSize: 14, color: Color(0xff999999), fontWeight: FontWeight.w700),
            ),
          TextSpan(
              text: node.key,
              style: const TextStyle(fontSize: 14, height: 1.7)),
          TextSpan(
            text: ' ${node.ans}',
            style: const TextStyle(fontSize: 14, height: 1.7, color: Color(0xff2f6fd0)),
          ),
        ]),
      ),
    );
  }
}

class _AnswerGroup extends StatelessWidget {
  final WsAnswerGroup node;
  const _AnswerGroup({required this.node});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(
        children: [
          Text(node.title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          if (node.unit != null && node.unit!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(node.unit!,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xff999999))),
            ),
        ],
      ),
    );
  }
}

class _MatchAnswer extends StatelessWidget {
  final WsMatchAnswer node;
  const _MatchAnswer({required this.node});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 40,
      runSpacing: 4,
      children: [
        for (final l in node.lines)
          SizedBox(
            width: 330,
            child: Text(l,
                style:
                    const TextStyle(fontSize: 15, height: 1.9, color: Color(0xff555555))),
          ),
      ],
    );
  }
}
