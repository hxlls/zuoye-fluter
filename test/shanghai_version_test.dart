import 'package:flutter_test/flutter_test.dart';
import 'package:zuoye_fluter/core/type_catalog.dart';
import 'package:zuoye_fluter/data/app_data.dart';

/// 上海五四学制（shanghai）版本的数据与题型接线回归测试。
///
/// 该版本与其它版本不同：
/// - 数学是**沪教版**（不与人教版对齐，有自己的单元目录）；
/// - 语文复用**统编**课文库（五四制 1-5 年级课文与六三制同年级一致）；
/// - 英语是**沪教牛津版（一起点上海）**。
/// 任一处接线断了，用户看到的就是「选了上海版却出不了题」或「单元目录拿人教版顶替」。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData().load();
  });

  test('教材登记：语数英三科，1-5 年级上下册数据齐全', () {
    final data = AppData();
    final tb = data.textbooks['shanghai'];
    expect(tb, isNotNull);
    expect(tb!.name, contains('五四'));
    expect(tb.cally, contains('五四'));
    expect(tb.math, contains('沪教'));
    expect(tb.eng, contains('牛津'));

    for (var g = 1; g <= 5; g++) {
      for (final v in ['上', '下']) {
        expect(data.vol('shanghai', g, v, 'cally')?.cally, isNotEmpty,
            reason: 'shanghai $g$v 生字缺失');
        expect(data.vol('shanghai', g, v, 'math')?.math, isNotEmpty,
            reason: 'shanghai $g$v 数学题型缺失');
        expect(data.vol('shanghai', g, v, 'eng')?.eng, isNotEmpty,
            reason: 'shanghai $g$v 英语词汇缺失');
      }
    }
    // 6 年级不属于五四小学段
    expect(data.vol('shanghai', 6, '上', 'math'), isNull);
  });

  test('语文复用统编课文库：hasTextbook 为真（duanwen/aiyuedu 可用）', () {
    final data = AppData();
    for (var g = 1; g <= 5; g++) {
      for (final v in ['上', '下']) {
        expect(data.hasTextbook('shanghai', g, v), isTrue,
            reason: 'shanghai $g$v 应复用统编课文库');
      }
    }
    // 与统编同年级课文目录一致（五四制 1-5 年级与六三制同年级一致）
    for (var g = 1; g <= 5; g++) {
      for (final v in ['上', '下']) {
        expect(
          data.yuwenTextsFor('shanghai', g, v).length,
          data.yuwenTextsFor('tongbiao', g, v).length,
          reason: 'shanghai $g$v 与统编课文数不一致',
        );
      }
    }
  });

  test('数学是沪教版：单元清单取自版本自身，不拿人教版顶替', () {
    final data = AppData();
    final units = data.mathUnitsFor('shanghai', 1, '上');
    expect(units, isNotEmpty, reason: '沪教版一上应有单元目录');
    expect(units.any((u) => u.contains('10以内的数')), isTrue);
    // 人教版一上有「三 认识立体图形」，沪教版一上没有 —— 必须是沪教版自己的清单
    expect(units, isNot(contains('三 认识立体图形')));
    // 沪教版数学不与人教版对齐
    expect(data.mathUnitsAligned, isNot(contains('shanghai')));
  });

  test('数学题型标签指向沪教版单元', () {
    final types = AppData().vol('shanghai', 1, '上', 'math')!.math!;
    expect(types.any((t) => t.id == 'add10'), isTrue);
    final add10 = types.firstWhere((t) => t.id == 'add10');
    expect(add10.unit, contains('沪教版'));
  });

  test('英语词汇为沪教牛津版（[word, 中文] 结构）', () {
    final eng = AppData().vol('shanghai', 1, '上', 'eng')!.eng!;
    expect(eng, isNotEmpty);
    expect(eng.first.length, 2);
  });

  test('题型目录：三科 1-5 年级均可出题', () {
    for (var g = 1; g <= 5; g++) {
      expect(
        TypeCatalog.idsOf(Subject.math,
            version: 'shanghai', grade: g, volume: '上'),
        isNotEmpty,
        reason: 'shanghai $g 数学题型为空',
      );
      expect(
        TypeCatalog.idsOf(Subject.chinese, version: 'shanghai', grade: g),
        isNotEmpty,
        reason: 'shanghai $g 语文题型为空',
      );
      expect(
        TypeCatalog.idsOf(Subject.english, version: 'shanghai', grade: g),
        isNotEmpty,
        reason: 'shanghai $g 英语题型为空',
      );
    }
  });

  /// 沪教版该册没有对应内容的题型，不能为了「看起来全」而拿别的年级硬凑。
  /// 逐条依据见 haoduoyun.cc 沪教版电子课本目录（本轮逐册核对）。
  test('沪教版该册没有对应内容的题型不出现', () {
    final data = AppData();
    List<String> ids(int g, String vol) =>
        (data.vol('shanghai', g, vol, 'math')?.math ?? const <MathType>[])
            .map((t) => t.id)
            .toList();

    // 四上「二 数与量」是大数的认识（读写/比较/改写/近似数），不含加减法
    expect(ids(4, '上'), isNot(contains('add1000')));
    // 四上「五 几何小实践」是圆的初步认识（圆心/半径/直径），不含周长面积
    // （圆周长与面积是沪教版六年级内容，本版本只到五年级）
    expect(ids(4, '上'), isNot(contains('circle')));
    // 四上「四 整数的四则运算」里没有「文字计算题」这一节对应的题型时，
    // simple 应挂到「运算定律」而不是文字计算题
    // 四下「三 统计」是折线统计图，本地生成器只有条形统计图
    expect(ids(4, '下'), isNot(contains('bargraph')));
    // 平均数是沪教版五上「三 统计」的内容
    expect(ids(4, '下'), isNot(contains('avg')));
    // 沪教版五下没有分数单元（分数的初步认识在 3下 / 4上）
    expect(ids(5, '下'), isNot(contains('fracadd')));
    // 百分数是沪教版六年级内容
    expect(ids(5, '下'), isNot(contains('percent')));
    // 周长在沪教版三下「六 几何小实践」，三上没有
    expect(ids(3, '上'), isNot(contains('perimeter')));
  });

  test('label 如实描述题型，不沿用人数版说法', () {
    final data = AppData();
    // add1000 生成三位数加减法（不是人教版的「万以内加减法」）
    for (final vol in ['上', '下']) {
      for (final t
          in data.vol('shanghai', 2, vol, 'math')?.math ?? const <MathType>[]) {
        if (t.id == 'add1000') expect(t.label, isNot(contains('万以内')));
      }
    }
    // simple 生成连加/连乘/带括号的简便运算（不是「化简与求值」——
    // 那是沪教版五上「简易方程(一)」的内容）
    for (final vol in ['上', '下']) {
      for (final t
          in data.vol('shanghai', 4, vol, 'math')?.math ?? const <MathType>[]) {
        if (t.id == 'simple') expect(t.label, isNot(contains('化简与求值')));
      }
    }
    // 四上 equation 生成「求未知数 x」，对应沪教版四上「正推、逆推」而非「简易方程」
    final g4 = data.vol('shanghai', 4, '上', 'math')!.math!;
    expect(g4.firstWhere((t) => t.id == 'equation').label, contains('正推'));
  });
}
