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
}
