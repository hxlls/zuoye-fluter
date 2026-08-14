import 'package:flutter/material.dart';
import '../core/worksheet_model.dart';
import 'worksheet_cards.dart';

/// A4 预览页
class WorksheetPageView extends StatelessWidget {
  final WsPage page;
  const WorksheetPageView({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    // 普通页固定 A4 高度；参考答案等 noSpread 页允许自然增高（对应 CSS min-height）
    final height = page.noSpread ? null : 1123.0;
    return Container(
      width: 794,
      height: height,
      constraints: page.noSpread
          ? const BoxConstraints(minHeight: 1123)
          : null,
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
                for (final n in page.nodes) _buildNode(context, n),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (page.title != null) _TitleBar(title: page.title!),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: page.packed
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final n in page.nodes) _buildNode(context, n),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildNode(BuildContext context, WsNode node) {
    if (node is WsSection) {
      return _SectionLabel(text: node.text, mathStyle: node.mathStyle);
    }
    if (node is WsHeading) {
      return _Heading(title: node.title, unit: node.unit, engStyle: node.engStyle);
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
  const _SectionLabel({required this.text, this.mathStyle = false});

  @override
  Widget build(BuildContext context) {
    if (mathStyle) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 14, color: Color(0xff666666))),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 10, top: 4),
      child: Container(
        padding: const EdgeInsets.only(left: 8),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xff2f6fd0), width: 4)),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xff2f6fd0))),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String title;
  final String? unit;
  final bool engStyle;
  const _Heading({required this.title, this.unit, this.engStyle = false});

  @override
  Widget build(BuildContext context) {
    final color = engStyle ? const Color(0xff2f6fd0) : const Color(0xff222222);
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Container(
        padding: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          border: Border(
              left: BorderSide(color: engStyle ? const Color(0xff2f6fd0) : const Color(0xff2f6fd0), width: 4)),
        ),
        child: Row(
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: color)),
            if (unit != null && unit!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(unit!,
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xff999999))),
              ),
          ],
        ),
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
