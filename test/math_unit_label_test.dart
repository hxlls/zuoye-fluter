import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/data/app_data.dart';

/// 数学题型的 sub 标签（`MathType.unit`）必须与「本册单元（教材目录）」同版次。
///
/// 数学面板上方画 `MATH_UNITS`（人教版 **2024 新版**），下方每个题型画一行
/// `sub = unit`。两份表各写各的，一旦 `unit` 还停在旧版（「人教版四上 第4单元」），
/// 同一个面板里就会自相矛盾 —— 上面写着「三 多位数乘两位数」，下面却说第 4 单元；
/// 「除数是两位数的除法」在 2024 新版已挪到四下，旧版标签会让四年级上册的家长
/// 以为它是本册内容。
///
/// 约定：`unit` 里凡出现教材单元，必须写成
/// `人教版<年级><册> <序号> <单元名>`，单元名**逐字**取自 `MATH_UNITS`；
/// 多条用全角分号「；」连接。跨册也要照实写（如四上的「除数是两位数的除法」
/// 写成「人教版四下 一 除数是两位数的除法」），这样标签本身就是一处提示。
/// 课标/综合类题型（量感、统计与概率、综合与实践、数学文化、综合练习）
/// 不硬凑单元，沿用原标签。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  const cnDigits = '一二三四五六';
  final refRe = RegExp(r'^人教版([一二三四五六])([上下]) (.+)$');

  /// 遍历所有「声明与人教版对齐」的版本 × 6 年级 × 2 册 × 每个题型。
  void forEachMathType(
      void Function(String version, int grade, String volume, MathType t) fn) {
    final data = AppData();
    for (final v in data.mathUnitsAligned) {
      for (var g = 1; g <= 6; g++) {
        for (final vol in ['上', '下']) {
          final types = data.vol(v, g, vol, 'math')?.math ?? const <MathType>[];
          expect(types, isNotEmpty, reason: '$v $g$vol 没有数学题型数据');
          for (final t in types) {
            fn(v, g, vol, t);
          }
        }
      }
    }
  }

  test('unit 里的单元引用逐条能在 MATH_UNITS 里找到', () {
    final data = AppData();
    forEachMathType((v, g, vol, t) {
      for (final part in t.unit.split('；')) {
        final m = refRe.firstMatch(part);
        if (m == null) continue; // 课标/综合类标签，不参与单元校验
        final rg = cnDigits.indexOf(m.group(1)!) + 1;
        final rvol = m.group(2)!;
        final entry = m.group(3)!;
        expect(data.mathUnitsFor(v, rg, rvol), contains(entry),
            reason: '$v $g$vol 的题型 ${t.id} 写着「$part」，'
                '但 $v $rg$rvol 的单元清单里没有这一条');
      }
    });
  });

  test('不再残留旧版「第N单元」写法', () {
    forEachMathType((v, g, vol, t) {
      expect(t.unit, isNot(contains('单元')),
          reason: '$v $g$vol 的题型 ${t.id} 仍写着旧版单元号：${t.unit}');
    });
  });

  test('人教版四上：题型标签指向 2024 新版单元', () {
    final types = {
      for (final t in AppData().vol('renjiao', 4, '上', 'math')!.math!)
        t.id: t.unit
    };
    expect(types['mul3x2'], '人教版四上 三 多位数乘两位数');
    // 除数是两位数的除法在 2024 新版挪到四下，标签要说实话而不是跟着旧版写四上
    expect(types['div3x2'], '人教版四下 一 除数是两位数的除法');
  });

  test('课标/综合类题型沿用原标签，不硬凑单元', () {
    final types = {
      for (final t in AppData().vol('renjiao', 4, '上', 'math')!.math!)
        t.id: t.unit
    };
    expect(types['estMeasure'], '2022 量感');
    expect(types['probability'], '2022 统计与概率');
    expect(types['project'], '2022 综合与实践');
    expect(types['culture'], '2022 课标·数学文化');
    expect(types['word'], '四年级上册 综合练习');
  });
}
