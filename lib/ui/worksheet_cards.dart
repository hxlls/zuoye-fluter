import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../core/worksheet_model.dart';
import '../core/rand_gen.dart';
import '../core/math_worksheet.dart';
import '../core/chinese_worksheet.dart';
import '../core/english_worksheet.dart';
import '../ai/ai_generator.dart';

const _kaiTi = 'KaiTi';
// 数学数字用衬线体，跨平台回退：Windows 有 Times/Georgia，Android/Linux 有 DejaVu Serif
const _mathFamily = 'Times New Roman';
const _mathFallback = ['Georgia', 'DejaVu Serif', 'Liberation Serif', 'serif'];

TextStyle _mathStyle(double size, {FontWeight w = FontWeight.w600}) => TextStyle(
      fontSize: size,
      fontWeight: w,
      letterSpacing: 1,
      color: const Color(0xff222222),
      fontFamily: _mathFamily,
      fontFamilyFallback: _mathFallback,
    );

/// 公共入口：根据卡片类型构建 Widget
Widget buildWsCardWidget(WsCard card) {
  if (card.kind == 'pad' || card.data == null) return const SizedBox();
  // 占位补全卡（填充行末空格）不渲染内容
  if (card.data is CnCardData && (card.data as CnCardData).pad) {
    return const SizedBox();
  }
  if (card.kind == 'math') {
    return _MathCard(data: card.data as MathItemData, numLabel: card.num);
  }
  if (card.kind == 'cn') return _CnCard(data: card.data as CnCardData);
  if (card.kind == 'ai') {
    return _AiCard(data: card.data as AiCardData, num: card.num);
  }
  if (card.kind == 'eng') {
    final d = card.data as EngGridCardData;
    if (d.kind == 'letter') return _LetterCard(data: d.data);
    if (d.kind == 'trace') return _TraceCard(data: d.data);
    return _WordQuestionCard(data: d.data);
  }
  return const SizedBox();
}

/// 公共入口：独立块（阅读/连线）
Widget buildWsBlockWidget(dynamic data) {
  if (data is ReadingBlockData) return _ReadingBlock(data: data);
  if (data is WsGridData) return _MatchList(rows: data.rows);
  return const SizedBox();
}

/// 数学卡片
class _MathCard extends StatelessWidget {
  final MathItemData data;
  final int? numLabel;
  const _MathCard({required this.data, this.numLabel});

  @override
  Widget build(BuildContext context) {
    final prob = data.prob;
    final detail = AppData().mathDetails[data.tid];
    Widget body;
    if (prob.word) {
      body = _WordExpr(expr: prob.expr!);
    } else if (prob.keepExpr) {
      body = _MathText(prob.expr!, size: 22);
    } else if (prob.expr != null) {
      body = _ExprText(
        expr: prob.expr!,
        blank: true,
      );
    } else if (prob.compare) {
      body = _MathText(
        '${fmt(prob.a)} 〇 ${fmt(prob.b)}',
        size: 19,
        blank: false,
      );
    } else if (prob.op == '÷r') {
      body = _LongDiv(a: prob.a, b: prob.b);
    } else if (detail != null && detail.inline) {
      // 口算题：横式 a op b = ____
      body = FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${fmt(prob.a)} ${prob.op} ${fmt(prob.b)} =',
                style: _mathStyle(19)),
            Container(
              margin: const EdgeInsets.only(left: 4),
              width: 56,
              height: 1.5,
              color: const Color(0xff333333),
            ),
          ],
        ),
      );
    } else if (prob.op == '÷') {
      // 除法笔算：标准长除法竖式
      body = _LongDiv(a: prob.a, b: prob.b);
    } else {
      body = _vertical(prob.a, prob.b, prob.op);
    }

    // 序号与题目分离布局：序号固定占一行，题目在下方，避免重叠
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffe2ddd2)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${numLabel ?? ""}.',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xff999999), fontWeight: FontWeight.w700)),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(child: body),
          ),
        ],
      ),
    );
  }

  Widget _vertical(num a, num b, String op) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(fmt(a),
              style: _mathStyle(23)
                  .copyWith(height: 1.25, letterSpacing: 0)),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('$op ',
                  style: _mathStyle(23).copyWith(height: 1.25, letterSpacing: 0)),
              Text(fmt(b),
                  style: _mathStyle(23).copyWith(height: 1.25, letterSpacing: 0)),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 2,
            width: 90,
            color: const Color(0xff333333),
          ),
          // 横线下方留空，供学生写答案
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  String fmt(num v) => fmtNum(v);
}

class _ExprText extends StatelessWidget {
  final String expr;
  final bool blank;
  const _ExprText({required this.expr, this.blank = true});

  @override
  Widget build(BuildContext context) {
    // 若表达式已含 = ，在其后加下划线；否则末尾加 " = " + 下划线
    final idx = expr.indexOf('=');
    final eqText = idx >= 0 ? expr.substring(0, idx + 1) : '$expr =';
    final rest = idx >= 0 ? expr.substring(idx + 1).trim() : '';
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(eqText,
              style: _mathStyle(19)),
          if (rest.isNotEmpty)
            Text(rest,
                style: _mathStyle(19)),
          if (blank)
            Container(
              margin: const EdgeInsets.only(left: 4),
              width: 56,
              height: 1.5,
              color: const Color(0xff333333),
            ),
        ],
      ),
    );
  }
}

class _MathText extends StatelessWidget {
  final String text;
  final double size;
  final bool blank;
  final bool alignRight;
  const _MathText(this.text, {this.size = 19, this.blank = false, this.alignRight = false});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    final idx = text.indexOf('〇');
    if (idx >= 0) {
      children.add(Text(text.substring(0, idx),
          style: _style(size, FontWeight.w600, 1)));
      // 比较大小：圆内填符号 → 改为括号（预留足够写 > < = 的空位）
      children.add(Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('（',
              style: _style(size, FontWeight.w600, 1)),
          Container(
            width: size * 1.7,
          ),
          Text('）',
              style: _style(size, FontWeight.w600, 1)),
        ],
      ));
      children.add(Text(text.substring(idx + 1),
          style: _style(size, FontWeight.w600, 1)));
    } else {
      children.add(Text(text,
          style: _style(size, FontWeight.w600, 1)));
      if (blank) {
        children.add(Container(
          margin: const EdgeInsets.only(left: 2),
          width: 56,
          height: 1.5,
          color: const Color(0xff333333),
        ));
      }
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: children,
      ),
    );
  }

  TextStyle _style(double size, FontWeight w, double ls) => TextStyle(
        fontSize: size,
        fontWeight: w,
        letterSpacing: ls,
        color: const Color(0xff222222),
        fontFamily: _mathFamily,
        fontFamilyFallback: _mathFallback,
      );
}

class _WordExpr extends StatelessWidget {
  final String expr;
  const _WordExpr({required this.expr});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(expr,
            textAlign: TextAlign.left,
            style: const TextStyle(fontSize: 17, height: 1.8, color: Color(0xff222222))),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('答：',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xff333333))),
            Expanded(
              child: Container(
                height: 24,
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xff333333), width: 1.5)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LongDiv extends StatelessWidget {
  final num a;
  final num b;
  const _LongDiv({required this.a, required this.b});

  @override
  Widget build(BuildContext context) {
    // 动态宽度：被除数位数越多越宽
    final dw = (('$a').length * 14.0 + 12).clamp(48.0, 120.0);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${fmt(b)} ',
              style: _mathStyle(18).copyWith(letterSpacing: 0)),
          Text('⟌',
              style: const TextStyle(fontSize: 34, height: 0.8, color: Color(0xff333333))),
          Container(
            width: dw,
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(height: 26),
                Text('${fmt(a)}',
                    style: _mathStyle(20).copyWith(letterSpacing: 0)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String fmt(num v) => fmtNum(v);
}

/// 语文卡片
class _CnCard extends StatelessWidget {
  final CnCardData data;
  const _CnCard({required this.data});

  @override
  Widget build(BuildContext context) {
    switch (data.type) {
      case 'pinyin2char':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(data.py,
                style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: Color(0xff333333))),
            const SizedBox(height: 8),
            _bracketLine(width: 4),
          ],
        );
      case 'char2pinyin':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pinyinFourLine(),
            const SizedBox(height: 4),
            Text(data.ch,
                style: const TextStyle(
                    fontSize: 38, color: Color(0xff222222), fontFamily: _kaiTi)),
          ],
        );
      case 'zuci':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(data.ch,
                style: const TextStyle(
                    fontSize: 38, color: Color(0xff222222), fontFamily: _kaiTi)),
            const SizedBox(height: 4),
            _bracketLine(width: 4),
            _bracketLine(width: 4),
            _bracketLine(width: 4),
          ],
        );
      case 'gushiFill':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${data.gTitle} · ${data.gAuthor}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xff2f6fd0))),
            const SizedBox(height: 6),
            for (var i = 0; i < (data.segs?.length ?? 0); i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: i == data.blank
                    ? const Text('（　　　　　　）',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 26, color: Color(0xff777777)))
                    : Text(data.segs![i],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 26,
                            height: 1.6,
                            fontFamily: _kaiTi,
                            color: Color(0xff222222))),
              ),
          ],
        );
      case 'chengyuFill':
        final chars = data.idiom!.split('');
        final shown = chars.asMap().entries
            .map((e) => e.key == data.blankIdx ? '（　）' : e.value)
            .join('');
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(shown,
                style: const TextStyle(
                    fontSize: 38, color: Color(0xff222222), fontFamily: _kaiTi)),
            const SizedBox(height: 6),
            Text('释义：${data.meaning}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xff555555), height: 1.6)),
          ],
        );
      case 'chengyuGuess':
        // 看意思写成语：释义文字后面紧跟横线（从上到下每题一行），字体加深
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(data.meaning ?? '',
                  style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xff222222),
                      height: 1.6,
                      fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 26,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: const BoxDecoration(
                  border: Border(
                      bottom:
                          BorderSide(color: Color(0xff333333), width: 1.5)),
                ),
              ),
            ),
          ],
        );
      case 'mingjuFill':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < (data.segs?.length ?? 0); i++)
              Text(
                i == data.blank
                    ? '（　　　　　　　　）'
                    : data.segs![i],
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 22,
                    height: 1.6,
                    fontFamily: _kaiTi,
                    color: i == data.blank
                        ? const Color(0xff666666)
                        : const Color(0xff000000)),
              ),
            if (data.source != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('出处：${data.source}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Color(0xff666666))),
              ),
          ],
        );
      default:
        return const SizedBox();
    }
  }

  Widget _ansLine() {
    return Container(
      width: 140,
      height: 26,
      margin: const EdgeInsets.only(top: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xff333333), width: 1.5)),
      ),
    );
  }

  /// 括号式答题空位（全角括号内留空）
  Widget _bracketLine({int width = 4}) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '（${'　' * width}）',
        style: const TextStyle(
            fontSize: 26, color: Color(0xff777777), height: 1.4),
      ),
    );
  }

  /// 四线三格（拼音书写）
  Widget _pinyinFourLine() {
    return SizedBox(
      width: 140,
      height: 46,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < 4; i++)
            Positioned(
              left: 0,
              right: 0,
              top: [10.0, 21.0, 32.0, 43.0][i],
              child: Container(
                height: 0,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: i == 1
                          ? const Color(0xff888888)
                          : const Color(0xff999999),
                      width: i == 1 ? 1.5 : 1.0,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// AI 卡片
class _AiCard extends StatelessWidget {
  final AiCardData data;
  final int? num;
  const _AiCard({required this.data, this.num});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffe2ddd2)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '${num ?? ''}. ',
                style: const TextStyle(
                    fontSize: 13, color: Color(0xff999999), fontWeight: FontWeight.w700),
              ),
              TextSpan(
                  text: data.q,
                  style: const TextStyle(fontSize: 16, height: 1.7)),
            ]),
          ),
          if (data.needsAns)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('答：',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xff333333))),
                  Expanded(
                    child: Container(
                      height: 20,
                      decoration: BoxDecoration(
                        border: Border(
                            bottom:
                                BorderSide(color: Color(0xff333333), width: 1.5)),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              height: 20,
              margin: const EdgeInsets.only(top: 4),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: Color(0xff333333), width: 1.5)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 英语字母卡片
class _LetterCard extends StatelessWidget {
  final EngCardData data;
  const _LetterCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(data.en,
            style: const TextStyle(
                fontSize: 30,
                fontFamily: 'Times New Roman',
                height: 1.1,
                color: Color(0xffc9c9c9))),
        const _FourLine(),
      ],
    );
  }
}

/// 单词描红
class _TraceCard extends StatelessWidget {
  final EngCardData data;
  const _TraceCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FourLine(
          word: data.en,
          color: const Color(0xffa0a0a0),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(data.cn,
              style: const TextStyle(fontSize: 13, color: Color(0xff888888))),
        ),
        const _FourLine(),
      ],
    );
  }
}

/// 单词题（中译英/英译中/拼写）
class _WordQuestionCard extends StatelessWidget {
  final EngCardData data;
  const _WordQuestionCard({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.type == 'listening') {
      final letters = 'ABCD';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🔊 听录音',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff2f6fd0))),
              const SizedBox(width: 8),
              Text(data.readText ?? data.en,
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'Times New Roman',
                      color: Color(0xff888888))),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < (data.options?.length ?? 0); i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text('${letters[i]}. ',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xff333333))),
                  Expanded(
                    child: Text(data.options![i],
                        style: const TextStyle(
                            fontSize: 16, color: Color(0xff222222))),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    if (data.type == 'cn2en') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.cn,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Color(0xff333333))),
          const SizedBox(height: 6),
          _FourLine(),
        ],
      );
    }
    if (data.type == 'en2cn') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.en,
              style: const TextStyle(
                  fontSize: 26,
                  fontFamily: 'Times New Roman',
                  letterSpacing: 2)),
          const SizedBox(height: 4),
          Container(
            width: 180,
            height: 26,
            margin: const EdgeInsets.only(top: 4),
            decoration: const BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: Color(0xff333333), width: 1.5)),
            ),
          ),
        ],
      );
    }
    // spell
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(data.shown ?? '',
            style: const TextStyle(
                fontSize: 26, fontFamily: 'Times New Roman', letterSpacing: 2)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text('中文：${data.cn}',
              style: const TextStyle(fontSize: 12, color: Color(0xff888888))),
        ),
        Container(
          width: 180,
          height: 26,
          decoration: const BoxDecoration(
            border: Border(
                bottom: BorderSide(color: Color(0xff333333), width: 1.5)),
          ),
        ),
      ],
    );
  }
}

/// 四线三格
class _FourLine extends StatelessWidget {
  final String? word;
  final Color? color;
  const _FourLine({this.word, this.color});

  @override
  Widget build(BuildContext context) {
    const top = [12.0, 25.0, 38.0, 51.0];
    const colors = [
      Color(0xff999999),
      Color(0xff888888),
      Color(0xff999999),
      Color(0xff999999),
    ];
    const widths = [1.0, 1.5, 1.0, 1.0];
    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          for (var i = 0; i < 4; i++)
            Positioned(
              left: 0,
              right: 0,
              top: top[i],
              child: Container(
                height: 0,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: colors[i],
                      width: widths[i],
                    ),
                  ),
                ),
              ),
            ),
          if (word != null)
            Positioned(
              left: 6,
              top: 10,
              child: Text(word!,
                  style: TextStyle(
                      fontSize: 34,
                      height: 1,
                      fontFamily: 'Times New Roman',
                      letterSpacing: 4,
                      color: color ?? const Color(0xffa0a0a0))),
            ),
        ],
      ),
    );
  }
}

/// 连线列表
class _MatchList extends StatelessWidget {
  final List<EngGridCardData> rows;
  const _MatchList({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xffe2ddd2)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text('${i + 1}. ${rows[i].data.en}',
                      style: const TextStyle(fontSize: 18, fontFamily: 'Times New Roman')),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    height: 12,
                    decoration: const BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: Color(0xff888888), width: 1.5)),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${rows[i].data.matchNum}. ${rows[i].data.cn}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 阅读短文块
class _ReadingBlock extends StatelessWidget {
  final ReadingBlockData data;
  const _ReadingBlock({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffe2ddd2)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '《${data.title}》${data.author.isNotEmpty ? ' · ${data.author}' : ''}',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xff2f6fd0)),
          ),
          const SizedBox(height: 8),
          Text(
            data.text,
            style: TextStyle(
              fontSize: 15,
              height: 1.9,
              color: const Color(0xff333333),
              fontFamily: data.en ? 'Times New Roman' : null,
            ),
          ),
          const SizedBox(height: 10),
          for (final q in data.questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.q, style: const TextStyle(fontSize: 15, height: 1.7)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('答：',
                          style: TextStyle(fontSize: 15, color: Color(0xff333333))),
                      Expanded(
                        child: Container(
                          height: 24,
                          decoration: const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color: Color(0xff333333), width: 1.5)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
