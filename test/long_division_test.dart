import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 守卫：长除号必须**手绘**，不得使用 Unicode 的 '\u27cc'。
///
/// U+27CC (MATHEMATICAL LONG DIVISION) 的字形随字体而异：
/// 多数西文字体把横线画在**左侧**（Linux 长除法的习惯），
/// 于是本该压在被除数上方的横线会跑到除数头上，中文教材的写法变成「3 \u2310 48」。
/// 同一份代码在 Android 与浏览器上渲染结果还会不一致 —— 曾因此被用户发现。
void main() {
  test('lib 下不得再出现字形不稳定的 U+27CC 长除号', () {
    final offenders = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.readAsStringSync().contains('\u27cc')) offenders.add(e.path);
    }
    expect(offenders, isEmpty,
        reason: 'U+27CC 的横线方向随字体而变，应改用自绘「厂」形（Border 左+上）：\$offenders');
  });
}
