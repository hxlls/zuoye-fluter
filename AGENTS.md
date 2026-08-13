# AGENTS.md — Flutter 版项目指南

## 项目概况
小学作业生成器（小学数学/语文/英语/练字帖/AI 出题作业 PDF），**Flutter 重写版**。
技术栈：Dart/Flutter（`lib/`），目标平台 **Windows 桌面版 + Android APK + Web**。`.github/workflows/build.yml` 在版本号变化时自动编译（Android/Web 在 ubuntu，Windows 在 windows-latest，因 Flutter 桌面版不能跨平台构建）并发布 GitHub Release。
原 JS 版（Electron+Capacitor）位于 `/home/ling/xiaoxuezuoye`，本目录是其 Dart 移植。

## 架构
```
lib/
  data/app_data.dart        数据层：加载 assets/data.json（教材/词库/语料，由原 data.js 转换）
  core/
    rand_gen.dart           随机数/工具（RandGen, shuffle, gcd, fracStr）
    math_gen.dart           数学题目生成（MATH_TYPE_DETAILS 逻辑移植）
    math_worksheet.dart     数学作业分页 → WsPage
    chinese_worksheet.dart  语文作业分页 → WsPage
    english_worksheet.dart  英语作业分页 → WsPage
    calligraphy_worksheet.dart 练字帖分页
    worksheet_model.dart    WsPage/WsNode/WsCard 模型（预览+PDF 共用）
  ai/
    ai_client.dart          AI 配置（安全存储）+ OpenAI 兼容请求
    ai_generator.dart       AI prompt/解析/渲染
  ui/
    home_page.dart          主页面（版本/学期/年级/标签页）
    *_panel.dart            各科配置面板
    worksheet_view.dart     预览页 Widget
    worksheet_cards.dart    各科题卡 Widget
    preview_panel.dart      预览容器 + PDF 导出按钮
    panel_widgets.dart      通用控件（SegButtons/TypeRow 等）
  pdf/
    pdf_service.dart        PDF 导出（RepaintBoundary 截图 → pdf 包）
assets/data.json            数据（勿手改，由 conv_data.js 从原项目生成）
```

## 数据同步（重要）
- `assets/data.json` 由 `/tmp/opencode/conv_data.js` 从原项目 `js/data.js` + `js/yuwen-corpus.js` 生成（vm 沙箱执行，输出 JSON）。
- 原项目数据结构变化后：`node /tmp/opencode/conv_data.js && cp /tmp/opencode/data.json assets/data.json`。
- 生成逻辑（math_gen/chinese_worksheet/english_worksheet 等）需与 `/home/ling/xiaoxuezuoye/js/` 对应文件人工对齐。

## 版本号（唯一来源 pubspec.yaml）
- 只改 `pubspec.yaml` 的 `version`（格式 `1.66.0+16600`，`+` 后为 versionCode）。
- 然后运行 `node scripts/sync-version.js` 同步 `lib/data/app_data.dart` 的 `AppData.version`。
- 不要手改 app_data.dart 的版本号。

## 校验
- 修改代码后必须运行：`bash scripts/validate.sh`（= flutter analyze + flutter test + 版本一致性检查）。
- 单测在 `test/core_test.dart`（数据加载/数学/语文/英语/练字帖断言）。

## 构建
- Android：`flutter build apk --release`（需 JDK 21，`export JAVA_HOME=$HOME/jdk21`；本机系统 Java 25 与 AGP 不兼容）。
- Web：`flutter build web --release`。
- Windows：本机 Linux 不能构建，须在 Windows 环境或依赖 CI 的 windows-latest job。
- CI（.github/workflows/build.yml）在 main 分支版本号变化时自动构建 APK + Web（ubuntu）+ Windows zip（windows-latest），汇总发布 Release。

## 环境注意
- 本机 Flutter 在 `~/flutter/flutter`，已加入 `~/.bashrc` PATH。
- pub 走镜像 `PUB_HOSTED_URL=https://pub.flutter-io.cn`，`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`。
- 系统无 GTK dev 库且无 sudo，本机不构建 Linux 桌面版。
- Android SDK 在 `/home/ling/androidsdk`，JDK 21 在 `~/jdk21`（Adoptium Temurin）。
- 布局规则（单列/网格/古诗字体等）继承自原项目 AGENTS.md，改动前先对照原项目行为。
