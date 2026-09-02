import '../data/app_data.dart';
import 'rand_gen.dart';

/// 数学题目渲染数据（跨预览/PDF 复用）
class MathProblem {
  final String tid;
  /// 题面 HTML 风格结构由渲染层解释；这里存语义字段
  final String? expr;      // 表达式文本（含 = 或 : 或纯算式）
  final num a;
  final num b;
  final String op;         // + - × ÷ ÷r ? 〇
  final bool word;         // 应用题
  final bool keepExpr;     // 单位换算（保留原式）
  final dynamic ans;       // 答案
  final bool compare;      // 比较大小
  final bool longDiv;      // 长除法竖式
  final bool vertical;     // 竖式（普通加减乘）

  MathProblem({
    required this.tid,
    this.expr,
    this.a = 0,
    this.b = 0,
    this.op = "",
    this.word = false,
    this.keepExpr = false,
    this.ans,
    this.compare = false,
    this.longDiv = false,
    this.vertical = false,
  });
}

/// 生成一个数学题目（含答案计算），移植自 MATH_TYPE_DETAILS.gen
MathProblem genMathProblem(String tid, RandGen g) {
  switch (tid) {
    case 'add10':
      {
        final s = g.rand(2, 10);
        final aa = g.rand(1, s - 1);
        return _ab(tid, aa, s - aa, '+', aa + s - aa);
      }
    case 'sub10':
      {
        final aa = g.rand(2, 10);
        final b = g.rand(1, aa);
        return _ab(tid, aa, b, '-', aa - b);
      }
    case 'add20':
      {
        final aa = g.rand(g.hard(2, 3, 4), 9);
        final lower = 11 - aa;
        final b = g.rand(lower, 9);
        return _ab(tid, aa, b, '+', aa + b);
      }
    case 'sub20':
      {
        final aa = g.rand(g.hard(11, 12, 14), 18);
        final b = g.rand((aa % 10) + 1, 9);
        return _ab(tid, aa, b, '-', aa - b);
      }
    case 'compare':
      {
        // 一、二年级限 20 以内比大小（教材低学段）；三年级起限 100 以内
        final bound = g.grade <= 2 ? 20 : 100;
        final aa = g.rand(1, bound);
        final b = g.rand(1, bound);
        return MathProblem(tid: tid, a: aa, b: b, op: '?', compare: true);
      }
    case 'add100':
      {
        // 二年级上：两位数加/减两位数（笔算，结果不超 100）
        final op = g.rand(1, 2) == 1 ? '+' : '-';
        if (op == '+') {
          final aa = g.rand(g.hard(21, 41, 61), 89);
          final b = g.rand(10, 99 - aa);
          return _ab(tid, aa, b, '+', aa + b);
        }
        final aa = g.rand(g.hard(30, 50, 70), 99);
        final b = g.rand(g.hard(15, 20, 30), aa);
        return _ab(tid, aa, b, '-', aa - b);
      }
    case 'add100a':
      {
        // 一年级下：两位数加减一位数/整十数（100 以内加减法·一）
        final op = g.rand(1, 2) == 1 ? '+' : '-';
        final isTens = g.rand(0, 1) == 0;
        final b = isTens ? g.rand(1, 8) * 10 : g.rand(1, 9);
        if (op == '+') {
          final aa = g.rand(11, 99 - b);
          return _ab(tid, aa, b, '+', aa + b);
        }
        final aa = g.rand(max(11, b + 1), 99);
        return _ab(tid, aa, b, '-', aa - b);
      }
    case 'mul':
      {
        final aa = g.rand(g.hard(2, 2, 3), g.hard(5, 7, 9));
        final b = g.rand(g.hard(2, 3, 4), g.hard(5, 7, 9));
        return _ab(tid, aa, b, '×', aa * b);
      }
    case 'div':
      {
        final aa = g.rand(g.hard(2, 3, 4), 9);
        final b = g.rand(2, 9);
        return _ab(tid, aa * b, b, '÷', (aa * b) / b);
      }
    case 'mix20':
      {
        // 二年级下两步混合：先表内乘/除（结果≤81），再加减 1-5
        final b = g.rand(2, 9);
        final q = g.rand(2, 9);
        final aa = b * q;
        final useMul = g.rand(0, 1) == 0;
        final expr1 = useMul ? '$aa × $b' : '$aa ÷ $b';
        final op2 = g.rand(0, 1) == 0 ? '+' : '-';
        final c = g.rand(1, 5);
        var ans = op2 == '+' ? aa + c : aa - c;
        if (ans < 0) ans = aa + c;
        return MathProblem(
            tid: tid, expr: '$expr1 $op2 $c', ans: ans, a: aa, b: c, op: op2);
      }
    case 'add1000':
      {
        final op = g.rand(1, 2) == 1 ? '+' : '-';
        if (op == '+') {
          final aa = g.rand(100, 900);
          final b = g.rand(100, 999 - aa);
          return _ab(tid, aa, b, '+', aa + b);
        }
        final aa = g.rand(300, 999);
        final b = g.rand(100, aa);
        return _ab(tid, aa, b, '-', aa - b);
      }
    case 'mul2x1':
      {
        final aa = g.rand(11, 99);
        final b = g.rand(2, 9);
        return _ab(tid, aa, b, '×', aa * b);
      }
    case 'mul2x2':
      {
        final aa = g.rand(11, 99);
        final b = g.rand(11, 99);
        return _ab(tid, aa, b, '×', aa * b);
      }
    case 'divr':
      {
        final b = g.rand(g.hard(3, 4, 5), 9);
        final q = g.rand(g.hard(2, 3, 4), 9);
        final r = g.rand(1, b - 1);
        final aa = b * q + r;
        return MathProblem(
            tid: tid,
            a: aa,
            b: b,
            op: '÷r',
            ans: '$q…$r',
            longDiv: true);
      }
    case 'div2x1':
      {
        final b = g.rand(2, 9);
        final aa = b * g.rand(11, 19);
        return MathProblem(
            tid: tid, a: aa, b: b, op: '÷', ans: (aa / b), longDiv: true);
      }
    case 'mix':
      {
        final pick = g.rand(0, 3);
        late int v1;
        late String expr;
        if (pick == 0) {
          final aa = g.rand(10, 99);
          final b = g.rand(10, 99);
          expr = '$aa + $b';
          v1 = aa + b;
        } else if (pick == 1) {
          final aa = g.rand(20, 99);
          final b = g.rand(10, aa);
          expr = '$aa - $b';
          v1 = aa - b;
        } else if (pick == 2) {
          final aa = g.rand(11, 49);
          final b = g.rand(11, 49);
          expr = '$aa × $b';
          v1 = aa * b;
        } else {
          final b = g.rand(2, 9);
          final q = g.rand(11, 49);
          final aa = b * q;
          expr = '$aa ÷ $b';
          v1 = q;
        }
        final op2 = g.rand(0, 1) == 0 ? '+' : '-';
        final c = g.rand(1, max(1, v1 - 1));
        var ans = op2 == '+' ? v1 + c : v1 - c;
        if (ans < 0) ans = v1 + c;
        return MathProblem(tid: tid, expr: '$expr $op2 $c', ans: ans);
      }
    case 'mul3x2':
      {
        final aa = g.rand(100, 999);
        final b = g.rand(10, 99);
        return _ab(tid, aa, b, '×', aa * b);
      }
    case 'div3x2':
      {
        final b = g.rand(12, 49);
        final aa = b * g.rand(11, 49);
        return MathProblem(
            tid: tid, a: aa, b: b, op: '÷', ans: (aa / b), longDiv: true);
      }
    case 'decadd':
      {
        final d = g.rand(1, 2);
        final pv = d == 1 ? 10 : 100;
        final aa = g.rand(pv ~/ 10, pv * 5 - 1);
        final b = g.rand(1, pv * 5 - aa);
        return _ab(tid, (aa / pv), (b / pv), '+',
            _round2(aa / pv + b / pv),
            precision: d);
      }
    case 'simple':
      {
        final variants = <String Function(int, int, int), int Function(int, int, int)>{
          (a, b, c) => '$a + $b + $c': (a, b, c) => a + b + c,
          (a, b, c) => '$a × $b × $c': (a, b, c) => a * b * c,
          (a, b, c) => '($a + $b) × $c': (a, b, c) => (a + b) * c,
        };
        final keys = variants.keys.toList();
        final v = keys[g.rand(0, keys.length - 1)];
        final aa = g.rand(10, 99);
        final b = g.rand(10, 99);
        final c = g.rand(2, 9);
        return MathProblem(
            tid: tid, expr: v(aa, b, c), ans: variants[v]!(aa, b, c));
      }
    case 'decmul':
      {
        final aa = g.rand(11, 99) / 10;
        final b = g.rand(11, 99) / 10;
        return _ab(tid, aa, b, '×', _round2(aa * b), precision: 2);
      }
    case 'decdiv':
      {
        // 用整数先乘再缩放，避免浮点误差（如 2.2×1.3 → 2.8600000000000003）
        final ai = g.rand(11, 99);
        final bi = g.rand(11, 99);
        final prod = _round2((ai * bi) / 100); // 被除数（精确到 2 位）
        final b = bi / 10; // 除数（1 位小数）
        return _ab(tid, prod, b, '÷', _round2(ai / 10), precision: 2);
      }
    case 'fracadd':
      {
        final d1 = g.rand(2, 9);
        final n1 = g.rand(1, d1 - 1);
        final d2 = g.rand(2, 9);
        final n2 = g.rand(1, d2 - 1);
        final op = g.rand(0, 1) == 0 ? '+' : '-';
        final num = op == '+' ? n1 * d2 + n2 * d1 : n1 * d2 - n2 * d1;
        final ans =
            num < 0 ? '-' + fracStr(-num, d1 * d2) : fracStr(num, d1 * d2);
        return MathProblem(
            tid: tid, expr: '$n1/$d1 $op $n2/$d2', ans: ans);
      }
    case 'equation':
      {
        final k = g.rand(2, 9);
        final m = g.rand(1, 9);
        final types = <(String, int)>[
          ('x + $k = ${k + m}', m),
          ('x - $k = $m', k + m),
          ('${k}x = ${k * m}', m),
          ('x ÷ $k = $m', k * m),
        ];
        final p = types[g.rand(0, types.length - 1)];
        return MathProblem(tid: tid, expr: p.$1, ans: p.$2);
      }
    case 'fracmul':
      {
        final d1 = g.rand(2, 9);
        final n1 = g.rand(1, d1 - 1);
        final d2 = g.rand(2, 9);
        final n2 = g.rand(1, d2 - 1);
        return MathProblem(
            tid: tid,
            expr: '$n1/$d1 × $n2/$d2',
            ans: fracStr(n1 * n2, d1 * d2));
      }
    case 'fracdiv':
      {
        final d1 = g.rand(2, 9);
        final n1 = g.rand(1, d1 - 1);
        final d2 = g.rand(2, 9);
        final n2 = g.rand(1, d2 - 1);
        return MathProblem(
            tid: tid,
            expr: '$n1/$d1 ÷ $n2/$d2',
            ans: fracStr(n1 * d2, d1 * n2));
      }
    case 'percent':
      {
        final base = g.rand(2, 9) * 100;
        final p = g.rand(10, 50) / 100;
        return MathProblem(
            tid: tid,
            expr: '$base × ${(p * 100).round()}%',
            ans: (base * p * 100).round() / 100);
      }
    case 'proportion':
      {
        final aa = g.rand(2, 9);
        final c = g.rand(2, 9);
        final b = aa * c;
        final m = g.rand(2, 9);
        return MathProblem(
            tid: tid, expr: '$aa : $b = $m : x', ans: m * c);
      }
    case 'word':
      return genWord(tid, g);
    case 'tensComp':
      {
        // 一年级上：数的分与合（10 以内）
        final n = g.rand(3, 10);
        final a = g.rand(1, n - 1);
        return MathProblem(
            tid: tid,
            word: true,
            expr: '$n 可以分成（　　　）和（　　　）。',
            ans: '$a 和 ${n - a}');
      }
    case 'perimeter':
      {
        // 三年级上：长方形/正方形周长
        if (g.rand(0, 1) == 0) {
          final a = g.rand(3, 9) * 10;
          final b = g.rand(2, 9) * 10;
          return MathProblem(
              tid: tid,
              word: true,
              expr: '一个长方形的长是 $a 米，宽是 $b 米，它的周长是多少米？',
              ans: (a + b) * 2);
        }
        final a = g.rand(3, 9) * 10;
        return MathProblem(
            tid: tid,
            word: true,
            expr: '一个正方形的边长是 $a 米，它的周长是多少米？',
            ans: a * 4);
      }
    case 'areaRect':
      {
        // 三年级下：长方形/正方形面积
        if (g.rand(0, 1) == 0) {
          final a = g.rand(3, 9);
          final b = g.rand(2, 9);
          return MathProblem(
              tid: tid,
              word: true,
              expr: '一块长方形菜地，长 $a 米，宽 $b 米，它的面积是多少平方米？',
              ans: a * b);
        }
        final a = g.rand(3, 9);
        return MathProblem(
            tid: tid,
            word: true,
            expr: '一个正方形的边长是 $a 米，它的面积是多少平方米？',
            ans: a * a);
      }
    case 'timeCalc':
      {
        // 三年级上：经过时间
        final h1 = g.rand(8, 16);
        final h2 = g.rand(h1 + 1, 17);
        return MathProblem(
            tid: tid,
            word: true,
            expr: '一节课从上午 $h1:00 开始，到上午 $h2:00 结束，经过了（　　　）小时。',
            ans: h2 - h1);
      }
    case 'avg':
      {
        // 四年级下：平均数
        final n = g.rand(2, 4);
        final base = g.rand(60, 95);
        var total = 0;
        final nums = <int>[];
        for (var i = 0; i < n; i++) {
          final v = base + g.rand(0, 20);
          nums.add(v);
          total += v;
        }
        return MathProblem(
            tid: tid,
            word: true,
            expr: '${nums.join('、')} 的平均数是（　　　）。',
            ans: total / n);
      }
    case 'polyArea':
      {
        // 五年级上：三角形/平行四边形/梯形面积
        final kind = g.rand(0, 2);
        if (kind == 0) {
          final base = g.rand(4, 12);
          final h = g.rand(3, 8);
          return MathProblem(
              tid: tid,
              word: true,
              expr: '一个三角形的底是 $base 厘米，高是 $h 厘米，它的面积是多少平方厘米？',
              ans: base * h / 2);
        }
        if (kind == 1) {
          final base = g.rand(4, 12);
          final h = g.rand(3, 8);
          return MathProblem(
              tid: tid,
              word: true,
              expr: '一个平行四边形的底是 $base 厘米，高是 $h 厘米，它的面积是多少平方厘米？',
              ans: base * h);
        }
        final a = g.rand(4, 10);
        final b = g.rand(2, a - 1);
        final h = g.rand(3, 8);
        return MathProblem(
            tid: tid,
            word: true,
            expr: '一个梯形的上底是 $a 厘米，下底是 $b 厘米，高是 $h 厘米，它的面积是多少平方厘米？',
            ans: (a + b) * h / 2);
      }
    case 'surface':
      {
        // 五年级下：长方体表面积
        final a = g.rand(2, 5);
        final b = g.rand(2, 5);
        final h = g.rand(2, 5);
        return MathProblem(
            tid: tid,
            word: true,
            expr: '一个长方体长 $a 分米、宽 $b 分米、高 $h 分米，它的表面积是多少平方分米？',
            ans: 2 * (a * b + a * h + b * h));
      }
    case 'volume':
      {
        // 五年级下：长方体体积
        final a = g.rand(2, 6);
        final b = g.rand(2, 6);
        final h = g.rand(2, 6);
        return MathProblem(
            tid: tid,
            word: true,
            expr: '一个长方体长 $a 分米、宽 $b 分米、高 $h 分米，它的体积是多少立方分米？',
            ans: a * b * h);
      }
    case 'ratio':
      {
        // 六年级上：化简比/求比值
        final kind = g.rand(0, 1);
        if (kind == 0) {
          final a = g.rand(12, 48);
          final b = g.rand(6, a ~/ 2);
          final gcdv = _gcd(a, b);
          return MathProblem(
              tid: tid,
              word: true,
              expr: '$a : $b 化成最简单的整数比是（　　　）。',
              ans: '${a ~/ gcdv} : ${b ~/ gcdv}');
        }
        final a = g.rand(3, 9) * 10;
        final b = g.rand(3, 9) * 10;
        return MathProblem(
            tid: tid,
            word: true,
            expr: '$a : $b 的比值是（　　　）。',
            ans: a / b);
      }
    case 'circle':
      {
        // 六年级上：圆周长/面积
        final kind = g.rand(0, 1);
        final r = g.rand(2, 10);
        if (kind == 0) {
          return MathProblem(
              tid: tid,
              word: true,
              expr: '一个圆的半径是 $r 厘米，它的周长是多少厘米？（圆周率取 3.14）',
              ans: _round2(2 * 3.14 * r));
        }
        return MathProblem(
            tid: tid,
            word: true,
            expr: '一个圆的半径是 $r 厘米，它的面积是多少平方厘米？（圆周率取 3.14）',
            ans: _round2(3.14 * r * r));
      }
    case 'cylinder':
      {
        // 六年级下：圆柱体积
        final r = g.rand(2, 5);
        final h = g.rand(3, 9);
        return MathProblem(
            tid: tid,
            word: true,
            expr: '一个圆柱的底面半径是 $r 厘米，高是 $h 厘米，它的体积是多少立方厘米？（圆周率取 3.14）',
            ans: _round2(3.14 * r * r * h));
      }
    case 'discount':
      {
        // 六年级下：折扣/成数/利率
        final kind = g.rand(0, 2);
        final price = g.rand(2, 9) * 100;
        if (kind == 0) {
          final z = g.rand(5, 9);
          return MathProblem(
              tid: tid,
              word: true,
              expr: '一件商品原价 $price 元，打 $z 折出售，现价是多少元？',
              ans: price * z / 10);
        }
        if (kind == 1) {
          final pct = g.rand(2, 9);
          return MathProblem(
              tid: tid,
              word: true,
              expr: '一件商品原价 $price 元，降价 $pct 成出售，现价是多少元？',
              ans: price * (10 - pct) / 10);
        }
        final pct = g.rand(2, 5);
        final years = g.rand(1, 3);
        return MathProblem(
            tid: tid,
            word: true,
            expr: '存入银行 $price 元，年利率是 $pct%，存 $years 年，到期可得利息多少元？',
            ans: price * pct / 100 * years);
      }
    case 'unitconv':
      return genUnitConv(tid, g);
    // ---------- 2022 课标原生新题型：量感 / 统计与概率 ----------
    case 'estMeasure':
      return genEstMeasure(tid, g);
    case 'chooseUnit':
      return genChooseUnit(tid, g);
    case 'probability':
      return genProbability(tid, g);
    case 'bargraph':
      return genBargraph(tid, g);
    case 'project':
      return genProject(tid, g);
    case 'culture':
      return genMathCulture(tid, g);
    default:
      return MathProblem(tid: tid, a: 0, b: 0, op: '', ans: '');
  }
}

int max(int a, int b) => a > b ? a : b;

int _gcd(int a, int b) {
  a = a.abs();
  b = b.abs();
  while (b != 0) {
    final t = a % b;
    a = b;
    b = t;
  }
  return a == 0 ? 1 : a;
}

MathProblem _ab(String tid, num aa, num b, String op, num ans,
    {int precision = 0}) {
  return MathProblem(tid: tid, a: aa, b: b, op: op, ans: ans);
}

num _round2(num v) {
  var r = (v * 100).roundToDouble() / 100;
  if (r == r.roundToDouble()) r = r.roundToDouble();
  return r;
}

/// 应用题生成（移植 genWord）
MathProblem genWord(String tid, RandGen g) {
  final gr = g.grade;
  final verb = g.rand(0, 3);
  if (gr <= 2) {
    if (verb == 0) {
      final a = g.rand(2, 20);
      final b = g.rand(1, 20);
      return MathProblem(
          tid: tid,
          word: true,
          expr: '小明有 $a 个气球，又买了 $b 个，现在一共有多少个？',
          ans: a + b);
    }
    if (verb == 1) {
      final a = g.rand(6, 20);
      final b = g.rand(1, a - 1);
      return MathProblem(
          tid: tid,
          word: true,
          expr: '书包里有 $a 支铅笔，用去了 $b 支，还剩多少支？',
          ans: a - b);
    }
    if (verb == 2) {
      final a = g.rand(5, 20);
      final b = g.rand(1, 20);
      return MathProblem(
          tid: tid,
          word: true,
          expr: '甲有 $a 本书，乙有 $b 本书，甲比乙多几本？',
          ans: (a - b).abs());
    }
    final a = g.rand(10, 30);
    final b = g.rand(1, a - 1);
    return MathProblem(
        tid: tid,
        word: true,
        expr: '一袋米有 $a 千克，吃了 $b 千克，还剩多少千克？',
        ans: a - b);
  }
  if (gr <= 4) {
    if (verb == 0) {
      final a = g.rand(2, 12);
      final b = g.rand(2, 9);
      return MathProblem(
          tid: tid,
          word: true,
          expr: '每盒有 $a 个鸡蛋，$b 盒一共有多少个鸡蛋？',
          ans: a * b);
    }
    if (verb == 1) {
      final b = g.rand(2, 9);
      final a = b * g.rand(2, 9);
      return MathProblem(
          tid: tid,
          word: true,
          expr: '把 $a 个苹果平均分给 $b 个小朋友，每人分几个？',
          ans: a / b);
    }
    if (verb == 2) {
      final a = g.rand(2, 9);
      final b = g.rand(2, 9);
      final c = g.rand(2, 30);
      return MathProblem(
          tid: tid,
          word: true,
          expr: '每盒有 $a 个，买了 $b 盒，又添了 $c 个，一共多少个？',
          ans: a * b + c);
    }
    final b = g.rand(2, 9);
    final q = g.rand(11, 99);
    final a = b * q;
    return MathProblem(
        tid: tid,
        word: true,
        expr: '共有 $a 张邮票，平均分给 $b 个人，每人得多少张？',
        ans: q);
  }
  if (gr <= 5) {
    if (verb == 0) {
      final p = g.rand(2, 99) / 10;
      final n = g.rand(2, 12);
      return MathProblem(
          tid: tid,
          word: true,
          expr: '每支钢笔 ${p.toStringAsFixed(1)} 元，买 $n 支要付多少元？',
          ans: (p * n * 10).round() / 10);
    }
    if (verb == 1) {
      final b = g.rand(2, 9);
      final a = b * g.rand(20, 99);
      return MathProblem(
          tid: tid,
          word: true,
          expr: '学校把 $a 本书平均分给 $b 个班，每班分多少本？',
          ans: a / b);
    }
    final a = g.rand(100, 999);
    final b = g.rand(11, 99);
    return MathProblem(
        tid: tid,
        word: true,
        expr: '图书馆有 $a 本科技书，故事书比它多 $b 本，故事书有多少本？',
        ans: a + b);
  }
  if (verb == 0) {
    final den = g.rand(2, 9);
    final total = den * g.rand(2, 20);
    final num = g.rand(1, den - 1);
    return MathProblem(
        tid: tid,
        word: true,
        expr: '小明有 $total 颗糖，拿出了它的 $num/$den 给妹妹，给了妹妹多少颗？',
        ans: total * num / den);
  }
  if (verb == 1) {
    final base = g.rand(2, 9) * 10;
    final pct = g.rand(10, 90);
    return MathProblem(
        tid: tid,
        word: true,
        expr: '一件商品 $base 元，降价 $pct%，便宜了多少元？',
        ans: (base * pct / 100 * 10).round() / 10);
  }
  if (verb == 2) {
    final a = g.rand(2, 9);
    final b = g.rand(2, 9);
    return MathProblem(
        tid: tid,
        word: true,
        expr: '一列火车每小时行 ${a * 10} 千米，$b 小时行多少千米？',
        ans: a * 10 * b);
  }
  final den = g.rand(2, 9);
  final total = den * g.rand(2, 20);
  final num = g.rand(1, den - 1);
  return MathProblem(
      tid: tid,
      word: true,
      expr: '一本书有 $total 页，第一天读了它的 $num/$den，读了多少页？',
      ans: total * num / den);
}

/// 单位换算（移植 genUnitConv）
MathProblem genUnitConv(String tid, RandGen g) {
  final data = AppData();
  final cand = data.unitConv
      .where((u) => u.grades.contains(g.grade))
      .toList();
  final u = cand[g.rand(0, cand.length - 1)];
  final val = g.rand(2, 99);
  return MathProblem(
      tid: tid,
      keepExpr: true,
      expr: '$val ${u.from} ＝ （　　　　　　）${u.to}',
      ans: val * u.mul);
}

/// 选择题渲染：题目 + A/B/C 选项（选项乱序），答案返回正确字母
MathProblem _mc(String tid, String q, String correct, List<String> wrong, RandGen g) {
  final letters = ['A', 'B', 'C'];
  final opts = _shuffle([correct, ...wrong], g);
  final idx = opts.indexOf(correct);
  final sb = StringBuffer();
  sb.write(q);
  sb.write('\n');
  for (var i = 0; i < opts.length; i++) {
    sb.write('${letters[i]}. ${opts[i]}    ');
  }
  return MathProblem(
      tid: tid, word: true, expr: sb.toString().trimRight(), ans: letters[idx]);
}

/// Fisher-Yates 乱序（基于 RandGen，保证可复现）
List<T> _shuffle<T>(List<T> l, RandGen g) {
  final a = List<T>.from(l);
  for (var i = a.length - 1; i > 0; i--) {
    final j = g.rand(0, i);
    final t = a[i];
    a[i] = a[j];
    a[j] = t;
  }
  return a;
}

/// 估测与量感（2022 量感）：选择合适的估算值
MathProblem genEstMeasure(String tid, RandGen g) {
  final items = <Map<String, dynamic>>[
    {'q': '估一估，一支铅笔大约长（　　）。', 'a': '15 厘米', 'w': ['15 米', '15 毫米'], 'min': 1},
    {'q': '估一估，一个小朋友大约高（　　）。', 'a': '130 厘米', 'w': ['130 米', '13 厘米'], 'min': 1},
    {'q': '估一估，教室的门大约高（　　）。', 'a': '2 米', 'w': ['2 厘米', '20 米'], 'min': 1},
    {'q': '估一估，一袋食盐大约重（　　）。', 'a': '500 克', 'w': ['5 千克', '5 克'], 'min': 1},
    {'q': '估一估，一个苹果大约重（　　）。', 'a': '200 克', 'w': ['2 千克', '2 克'], 'min': 1},
    {'q': '估一估，从 1 数到 100 大约需要（　　）。', 'a': '1 分钟', 'w': ['1 秒', '1 小时'], 'min': 1},
    {'q': '估一估，一个西瓜大约重（　　）。', 'a': '5 千克', 'w': ['5 克', '50 千克'], 'min': 3},
    {'q': '估一估，步行 1 千米大约需要（　　）。', 'a': '15 分钟', 'w': ['15 秒', '15 小时'], 'min': 3},
    {'q': '估一估，一张课桌面的面积大约（　　）。', 'a': '40 平方分米', 'w': ['40 平方厘米', '40 平方米'], 'min': 3},
    {'q': '估一估，一瓶矿泉水大约有（　　）。', 'a': '500 毫升', 'w': ['5 升', '5 毫升'], 'min': 5},
    {'q': '估一估，标准操场跑道一圈约（　　）。', 'a': '400 米', 'w': ['40 米', '4 千米'], 'min': 3},
  ];
  final pool = items.where((it) => g.grade >= (it['min'] as int)).toList();
  final it = pool[g.rand(0, pool.length - 1)];
  return _mc(tid, it['q'] as String, it['a'] as String,
      List<String>.from(it['w']), g);
}

/// 选择合适的单位（2022 量感）
MathProblem genChooseUnit(String tid, RandGen g) {
  final items = <Map<String, dynamic>>[
    {'q': '一个鸡蛋重约 50（　　）。', 'a': '克', 'w': ['千克', '吨'], 'min': 1},
    {'q': '一棵大树高约 8（　　）。', 'a': '米', 'w': ['厘米', '毫米'], 'min': 1},
    {'q': '数学书厚约 7（　　）。', 'a': '毫米', 'w': ['厘米', '分米'], 'min': 1},
    {'q': '小明每天睡眠约 9（　　）。', 'a': '小时', 'w': ['分钟', '秒'], 'min': 1},
    {'q': '火车每小时行驶约 120（　　）。', 'a': '千米', 'w': ['米', '分米'], 'min': 3},
    {'q': '一间教室的面积约 50（　　）。', 'a': '平方米', 'w': ['平方厘米', '公顷'], 'min': 3},
    {'q': '一瓶眼药水的容量约 10（　　）。', 'a': '毫升', 'w': ['升', '立方米'], 'min': 5},
    {'q': '一个足球场的面积约 7000（　　）。', 'a': '平方米', 'w': ['平方千米', '平方厘米'], 'min': 5},
    {'q': '一瓶可乐的容量约 2（　　）。', 'a': '升', 'w': ['毫升', '立方米'], 'min': 3},
  ];
  final pool = items.where((it) => g.grade >= (it['min'] as int)).toList();
  final it = pool[g.rand(0, pool.length - 1)];
  return _mc(tid, it['q'] as String, it['a'] as String,
      List<String>.from(it['w']), g);
}

/// 可能性（2022 统计与概率）
MathProblem genProbability(String tid, RandGen g) {
  final items = <Map<String, String>>[
    {'q': '太阳从东方升起是（　　）发生的。', 'a': '一定', 'w1': '可能', 'w2': '不可能'},
    {'q': '从只装有红球的盒子里摸出一个球，摸到白球是（　　）的。', 'a': '不可能', 'w1': '一定', 'w2': '可能'},
    {'q': '明天会下雨是（　　）的。', 'a': '可能', 'w1': '一定', 'w2': '不可能'},
    {'q': '抛一枚硬币，正面朝上是（　　）的。', 'a': '可能', 'w1': '一定', 'w2': '不可能'},
    {'q': '在没有水的空杯子里倒出水流是（　　）的。', 'a': '不可能', 'w1': '一定', 'w2': '可能'},
    {'q': '人的心脏一直在跳动是（　　）的。', 'a': '一定', 'w1': '可能', 'w2': '不可能'},
    {'q': '鱼在天上飞是（　　）的。', 'a': '不可能', 'w1': '一定', 'w2': '可能'},
  ];
  final it = items[g.rand(0, items.length - 1)];
  return _mc(tid, it['q']!, it['a']!, [it['w1']!, it['w2']!], g);
}

/// 读统计图（2022 统计与概率）：生成分类数据 + 条形图 + 读图问题
MathProblem genBargraph(String tid, RandGen g) {
  final cands = <List<String>>[
    ['水果', '苹果', '香蕉', '橘子', '西瓜'],
    ['运动', '篮球', '足球', '乒乓球', '羽毛球'],
    ['颜色', '红色', '黄色', '蓝色', '绿色'],
    ['小动物', '猫', '狗', '兔', '鱼'],
    ['季节', '春', '夏', '秋', '冬'],
  ];
  final c = cands[g.rand(0, cands.length - 1)];
  final label = c[0];
  final names = c.sublist(1);
  final vals = <int>[for (var i = 0; i < 4; i++) g.rand(3, 12)];
  final total = vals.fold(0, (s, v) => s + v);
  final maxIdx = vals.indexOf(vals.reduce((a, b) => a > b ? a : b));
  final k = g.rand(0, 3); // 指定问某个类别的人数

  final sb = StringBuffer();
  sb.write('下面是某班同学最喜欢的$label情况统计图（单位：人）：\n');
  for (var i = 0; i < 4; i++) {
    sb.write('${names[i]}  ${'█' * vals[i]} ${vals[i]}\n');
  }
  sb.write('1. 最喜欢（　　）的人数最多。\n');
  sb.write('2. 最喜欢「${names[k]}」的有（　　）人。\n');
  sb.write('3. 一共调查了（　　）人。');

  final ans =
      '最多：${names[maxIdx]}；${names[k]}：${vals[k]}人；共：$total人';
  return MathProblem(tid: tid, word: true, expr: sb.toString(), ans: ans);
}

/// 综合与实践·项目式学习（2022 综合与实践）：从原生项目库取对应学段的项目
MathProblem genProject(String tid, RandGen g) {
  final data = AppData();
  final seg = g.grade <= 2 ? 'low' : g.grade <= 4 ? 'mid' : 'high';
  final pool = data.mathProjectsBySeg(seg);
  final list = pool.isNotEmpty ? pool : data.mathProjects;
  final p = list[g.rand(0, list.length - 1)];
  final expr = '【综合与实践】${p.t}\n${p.d}';
  const ans = '（开放题，按实际情况完成，可用图画、表格或简短文字记录）';
  return MathProblem(tid: tid, word: true, expr: expr, ans: ans);
}

/// 数学文化（2022 数学文化）：从原生题库取对应学段的数学文化条目
MathProblem genMathCulture(String tid, RandGen g) {
  final data = AppData();
  final seg = g.grade <= 2 ? 'low' : g.grade <= 4 ? 'mid' : 'high';
  final pool = data.mathCultureBySeg(seg);
  final list = pool.isNotEmpty ? pool : data.mathCulture;
  final p = list[g.rand(0, list.length - 1)];
  final expr = '【数学文化】${p.t}\n${p.c}\n思考题：${p.q}';
  return MathProblem(tid: tid, word: true, expr: expr, ans: p.a);
}

/// 题目去重 key（移植 problemKey）
String problemKey(String tid, MathProblem prob) {
  if (prob.expr != null) return 'e|$tid|${prob.expr}';
  return '$tid|${prob.a}${prob.op}${prob.b}';
}
