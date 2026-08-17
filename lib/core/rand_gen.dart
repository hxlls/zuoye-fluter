import 'dart:math';

/// 随机数生成器（移植自原项目 makeGen / rand / hard）
class RandGen {
  final String diff;
  final int scale;
  final int grade;
  final Random _r;

  RandGen({String diff = "easy", int grade = 1, int? seed})
      : diff = diff,
        scale = diff == "easy" ? 1 : (diff == "mid" ? 2 : 3),
        grade = grade,
        _r = seed != null ? Random(seed) : Random();

  int rand(int min, int max) {
    return min + _r.nextInt(max - min + 1);
  }

  /// 按难度取三档值 [a=简单, b=中等, c=较难]
  int hard(int a, int b, int c) {
    return [a, b, c][scale - 1];
  }

  /// 打乱列表
  List<T> shuffle<T>(List<T> list) {
    final a = List<T>.from(list);
    a.shuffle(_r);
    return a;
  }
}

/// 洗牌（原 shuffleCopy）
List<T> shuffleCopy<T>(List<T> arr, [Random? r]) {
  final a = List<T>.from(arr);
  final rnd = r ?? Random();
  for (int i = a.length - 1; i > 0; i--) {
    final j = rnd.nextInt(i + 1);
    final t = a[i];
    a[i] = a[j];
    a[j] = t;
  }
  return a;
}

/// gcd
int gcd(int a, int b) {
  a = a.abs();
  b = b.abs();
  while (b != 0) {
    final t = a % b;
    a = b;
    b = t;
  }
  return a == 0 ? 1 : a;
}

/// 分数化简成字符串
String fracStr(int n, int d) {
  if (n == 0) return "0";
  if (n == d) return "1";
  final g = gcd(n, d);
  n = n ~/ g;
  d = d ~/ g;
  return d == 1 ? '$n' : '$n/$d';
}

/// 数字显示：整数去掉小数点；浮点尾差（如 2.8600000000000003）规整到 2 位小数
String fmtNum(num v) {
  if (v is int) return v.toString();
  if (v == v.roundToDouble()) return v.toInt().toString();
  final s = v.toString();
  final dot = s.indexOf('.');
  if (dot > 0 && s.length - dot - 1 > 3) {
    return _trimZeros(v.toStringAsFixed(2));
  }
  return s;
}

String _trimZeros(String s) {
  if (!s.contains('.')) return s;
  var t = s.replaceAll(RegExp(r'0+$'), '');
  if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  return t;
}
