#!/usr/bin/env bash
# 全量校验脚本（Flutter 版小学作业生成器）
# 运行：bash scripts/validate.sh
set -e

echo "== 1. Dart 语法/静态分析 =="
# --no-fatal-infos/--no-fatal-warnings：只把 error 当失败
flutter analyze --no-fatal-infos --no-fatal-warnings
if [ $? -ne 0 ]; then
  echo "  ✘ flutter analyze 存在错误"
  exit 1
fi
echo "  ✔ flutter analyze 通过"

echo "== 2. 单元测试 =="
flutter test
echo "  ✔ flutter test 全部通过"

echo "== 3. 版本号同步检查 =="
PUBSPEC_VER=$(grep '^version:' pubspec.yaml | head -1 | sed -E 's/version: *([0-9.]+).*/\1/')
APP_DATA_VER=$(grep -o 'version = "[0-9.]*"' lib/data/app_data.dart | sed -E 's/version = "([0-9.]+)"/\1/')
if [ "$PUBSPEC_VER" != "$APP_DATA_VER" ]; then
  echo "  ✘ 版本号不一致：pubspec=$PUBSPEC_VER app_data=$APP_DATA_VER"
  echo "  请运行 npm run sync-version"
  exit 1
fi
echo "  ✔ 版本号一致：$PUBSPEC_VER"

echo "✔ 全部校验通过"
