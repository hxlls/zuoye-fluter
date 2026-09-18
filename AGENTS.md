# AGENTS.md — Flutter 版项目指南

> 面向接手本项目的开发者 / AI 助手。**改动代码前请先读完「关键机制」一节**，
> 那里的约定大多是踩过坑之后固化下来的，违反它们会造成肉眼难查的回归。

## 项目概况

小学作业生成器（练字帖 / 语文 / 数学 / 英语 / AI 出题），**Flutter 重写版**。
技术栈 Dart/Flutter（`lib/`，约 13k 行），目标平台 **Windows 桌面 + Android APK + Web**。

- 原 JS 版（Electron + Capacitor）在 `/home/ling/xiaoxuezuoye`，本目录是其 Dart 移植。
- CI：`.github/workflows/build.yml`。**注意 build job 的触发条件是 `pubspec.yaml`
  版本号发生变化**（比较 `HEAD^` 与 `HEAD`）—— 只推代码不改版本号，
  只会跑 `check`（analyze + test），**不会编译、不会发 Release**。

## 架构

```
lib/
  main.dart
  data/
    app_data.dart            加载 assets/data.json；教材/词库/语料/版本支持的唯一入口
    type_count_store.dart    题量持久化（按 科目+题型id 全局记忆）
    work_context_store.dart  教材版本 / 学期 / 年级 持久化
    panel_pref_store.dart    各面板显示选项持久化（按面板一份）
    ai_pref_store.dart       AI 面板科目 / 题型勾选 / 参数 / 帮答对话
    corpus_store.dart        自定义语料（导入的课文）
  core/
    type_catalog.dart        ★ 题型可用性的**唯一事实来源**
    scope_guard.dart         ★ 超纲校验（生成后检查）
    rand_gen.dart            随机数工具（RandGen / shuffle / gcd / fracStr）
    math_gen.dart            数学题目生成（MATH_TYPE_DETAILS 的逻辑移植）
    math_worksheet.dart      数学分页 → WsPage
    chinese_worksheet.dart   语文分页 → WsPage
    english_worksheet.dart   英语分页 → WsPage
    calligraphy_worksheet.dart 练字帖分页
    worksheet_model.dart     WsPage / WsNode / WsCard 模型（预览与 PDF 共用）
    wav_merge.dart           听力音频拼接
  ai/
    ai_client.dart           AI 配置（安全存储）+ OpenAI 兼容请求
    ai_generator.dart        AI prompt / 解析 / 渲染
  ui/
    home_page.dart           主页（教材上下文 + 三标签 + 科目卡片）
    preview_panel.dart       预览容器（分页扫描 / 缩放 / PDF、打印入口）
    worksheet_view.dart      预览页 Widget（大题编号、得分栏、续页渲染）
    worksheet_cards.dart     各科题卡 Widget（含长除号手绘）
    panel_widgets.dart       通用控件（PanelLayout / SegButtons / TypeRow …）
    *_panel.dart             各科配置面板
  pdf/pdf_service.dart       PDF 导出（RepaintBoundary 截图 → pdf 包）
assets/data.json             全部教材数据（勿手改，见 docs/DATA_MODEL.md）
```

## 关键机制（改动前务必先读）

### 1. 题型可用性：唯一来源是 `TypeCatalog`

**不要再在面板里写「这个年级有哪些题型」的判断。** 历史上有三份实现
（math_panel / chinese_panel / english_panel 各自的 `_ensureCounts`），
加上渲染层又独立算一次，规则容易漂移。

```dart
TypeCatalog.of(subject, version, grade, volume, includeUnavailable: false)
```
- 数学：取 `CONTENT[版本][年级]['math'][册]` 列表本身（列表即真相）
- 语文：`CN_TYPE_GRADES` 区间
- 英语：`ENG_TYPE_GRADES` 区间 **加上** `engTypeAllowed(id, ver, grade)` 的版本业务规则

`english_worksheet.dart` 的 `engTypeAllowed` / `allowedEngTypes` 已改为**委托**给
TypeCatalog。新增题型时只改一处，并补 `test/type_catalog_test.dart` 的
**反漂移用例**（5 版本 × 6 年级逐一比对旧函数与新目录层结果一致）。

### 2. 持久化：状态必须落盘，且要分清「哪一维进键」

页面容器用的是 `IndexedStack`（见第 3 条），但**重开 App 仍会丢**，
所以面板状态一律持久化。现有存储与键：

| Store | 键 | 说明 |
|---|---|---|
| `work_context_store` | `ctx_version` / `ctx_volume` / `ctx_grade` | 读取时防御：版本不存在→回落人教版；年级不被支持→归一化 |
| `type_count_store` | `type_counts_<subject>` | 题量按「科目+题型id」记忆，**不按三维分档** |
| `panel_pref_store` | `panel_opts_<panel>` | 选项按面板一份（选项是「我怎么排版」，跨年级不变） |
| `ai_pref_store` | `ai_subject` / `ai_styles_<subject>` / `ai_opts` / `ai_help_subject` / `ai_help_messages` | |
| `corpus_store` | `customCorpora` / `activeCorpusId` / `captureTargetId` | |
| `english_panel` | `eng_settings_<grade>_<version>_<volume>` | 英语的**显示选项**仍按三维分档（历史遗留） |
| `ai_client` | `ai_api_key` | 系统级加密存储 |

取舍原则：**题量跟题型绑定 → 按题型记**；**选项是我的排版习惯 → 按面板记**。

⚠️ 加持久化会**改变测试的隐含前提**：原先「每个用例从默认值开始」自动成立，
加持久化后必须在每个用例前 `SharedPreferences.setMockInitialValues({})`，
否则上一个用例选的「外研三起点·3年级」会串进下一个用例。

### 3. 页面容器：`IndexedStack`，不是 `switch`

`home_page._tabBody()` 与 AI 页的「出题/帮答」都用 **IndexedStack**。
`switch` 会销毁整棵子树 —— 表现为「切走再回来，预览没了 / 勾选自己勾回来了 /
对话清空了」。切换标签后各面板状态**原地保留**是硬要求。

### 4. 科目面板是**独立路由**

科目面板通过 `Navigator.push(MaterialPageRoute(...))` 打开，不是主页内的状态切换。
原因是返回键层级：**预览页 → 配置页 → 首页 → 退出应用**。
如果只是改 `_subject` 换子树渲染，就没有路由可弹，返回键会直接退出应用。

⚠️ **嵌套 `PopScope` 会同时触发所有 handler**（不是内层优先）。
所以不要在多处注册返回拦截。

### 5. 试卷版式约定

预览的 Widget 就是试卷本身 —— **PDF 是对预览 Widget 截图后嵌进 A4 的**
（`PdfService` 对每个 `RepaintBoundary` 做 `toImage(pixelRatio: 3.1)`）。
**只改 Widget 渲染，PDF 与「所见即所得」自动跟着变**，不要维护两套。

- **大题序号**：中文（一、二、三…），跨页连续（预览层预扫描后传给各页）
- **得分栏**：`题序 | 一 | 二 | … | 总分`，列数 = 实际大题数
- **小题序号**：与题目**同一行**（`1. 2+5=____`），紧贴不居中留空
- **续页标题**：同一大题被拆到两页时，续页标题标「（续）」且
  **不参与编号、不计入得分栏**（`WsHeading.continuation`）
- **说明行**用 `WsNote`，**刻意不是 `WsSection`** —— 后者会被识别为「大题开始」而占编号
- **长除号「厂」形必须手绘**（`Border(left+top)`），**不要用 Unicode `⟌`(U+27CC)**：
  该字符字形随字体而异，横线方向会变，同一个 App 在 Android 与浏览器上表现不一致。
  `test/long_division_test.dart` 有源码级守卫锁住这一点。
- 题卡不套边框（靠留白分隔），只有书写格线（四线三格、田字格）例外

### 6. 分页约定

三科分页是**三份独立实现**（`math_worksheet` / `chinese_worksheet` / `english_worksheet`），
**修了一科不代表另两科没问题**，同类改动要三处都看。

- **不可分的内容不能被拆页**：中英连线题的左右两列是一个整体
  （拆开后学生无法跨页画线），整节放不下就整体挪到下一页
- **标题不能孤立在页尾**：判断「标题能否放下」时必须把第一行题目的高度一起算
  （`curH + 标题 + 第一行 > 可用高`）。数学与语文都犯过这个错，各修了一次
- 被拆的节，续页的序号要接着编号（英语 `_engNodeFor(startSeq:)`）
- 英语续页会重发标题并标「（续）」；**数学与语文的续页目前不带标题**
  （行为不一致，属已知待定项，改动前先与维护者确认）

### 7. 超纲校验 `ScopeGuard`

本地生成的题目有**硬约束**（题型列表由 `CONTENT` 决定、数值上限按题型 id 推导、
语料按年级分桶），不会超纲。AI 生成是**软约束**，所以加了生成后校验：

- `integerCeil()` 从题型 id 推导整数上限，**提示词侧与校验侧共用这一份推导**
  （避免「提示词说 20、校验按 100」）
- 数学只查 1–3 年级（四年级起数域交错，卡死会误伤）
- 语文只查 `pinyin2char` / `char2pinyin` / `zuci`（明确以本册写字表为语料的题型）
- **英语词汇不查** —— `ENG_505` 是 headword 形式（`'be (am, is, are)'`），
  功能词 is/the/my 都不在表内，逐词比对必然大量误报
- **宁可漏报不要误报**：误报比漏报更伤老师对工具的信任

## 数据

`assets/data.json` 的结构、维度、题型规则、语料分布、持久化键设计，
以及「哪些坑不能踩」，统一见 **[docs/DATA_MODEL.md](docs/DATA_MODEL.md)**。

## 校验与测试

```bash
bash scripts/validate.sh      # = flutter analyze + flutter test + 版本号一致性
```

提交前必须全绿（**0 error / 0 warning**，info 可接受）。

测试策略（`test/`，每一条都对应一次真实回归）：

- `core_test.dart` 数据加载与各科分页断言
- `type_catalog_test.dart` 含 30 个**反漂移**用例
- `scope_guard_test.dart` 含「提示词与校验器上限一致」的反漂移用例
- `panel_counts_test.dart` 面板 State 层（纯逻辑测试锁不住的部分）
- `persistence_test.dart` / `ai_panel_pref_test.dart` 持久化
- `layout_smoke_test.dart` 6 面板 × 8 种屏宽，靠 `takeException()` 扫布局溢出
- `section_number_test.dart` 跨科目：大题编号不重复（用渲染层同款口径）
- `eng_vocab_bounds_test.dart` 题量超过词表容量不崩溃
- `long_division_test.dart` 源码级守卫：禁止 U+27CC

**写回归测试的铁律**：写完必须**临时退回修复**跑一次，确认它**真的会失败**。
本项目已经出现过三个「永远通过」的假测试（含一个把 `Set` 比 `Set` 恒为真的断言）。

## 构建与发布

- Android：`flutter build apk --release`（需 `export JAVA_HOME=$HOME/jdk21`）
- Web：`flutter build web --release`
- Windows：本机 Linux 不能构建，须在 Windows 环境或依赖 CI 的 windows-latest job
- Release 构建用固定签名密钥（本地 `android/key.properties`，CI 从 Secrets 还原），
  保证版本间可覆盖安装；密钥文件不入库

### 版本号（唯一来源 `pubspec.yaml`）

只改 `pubspec.yaml` 的 `version`（格式 `3.1.0+30100`，`+` 后为 versionCode），
然后 `node scripts/sync-version.js` 同步 `lib/data/app_data.dart`。**不要手改 app_data.dart。**

## Web 预览部署（局域网演示用）

```bash
bash _deploy.sh     # 构建 + 部署 + 自测，一步到位
```

三件必须记住的事：

1. **必须带 `--base-href /app/`**。应用部署在 `/app/` 子路径下，而 Flutter 默认生成
   `<base href="/">`，会让 `main.dart.js` / `assets/` / `canvaskit/` 全部去请求根路径 →
   **整页空白**。`_deploy.sh` 里有断言，base href 不是 `/app/` 直接 `exit 1`。
2. **必须带 `--pwa-strategy=none`**，并放一个**自我注销**的 service worker。
   默认策略会把 `main.dart.js` 整个缓存进 CORE，用户会一直看到旧版本
   （表现为「你明明说改了，我这边没变化」）。
3. **给 `flutter_bootstrap.js` 加版本参数** + 注入 `no-store` meta。
   `python http.server` 不返回 `Cache-Control`，浏览器会用启发式缓存**不重新验证**，
   这是「部署了但用户看不到」的头号原因。

⚠️ `nohup python3 -m http.server &` 会被 SSH 会话结束连带杀掉，服务挂了就重跑 `_serve_up.sh`。

## 环境注意

- Flutter 在 `~/flutter/flutter`；JDK 21 在 `~/jdk21`（系统 Java 25 与 AGP 不兼容）
- pub 走镜像：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、
  `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
- Android SDK 在 `~/androidsdk`；模拟器 AVD 名 `zuoye`（1080×2340）
- 本机无 GTK dev 库且无 sudo → 不构建 Linux 桌面版

## 踩坑备忘

- **批量改源码必须显式 `newline="\n"`**：Python 默认会把 `\n` 翻成 CRLF，
  一个文件能因此显示 830 行变更。改完用
  `awk '/\r/{n++} END{print n+0}' 文件` 检查（**别用 `grep -c`**，
  计数为 0 时它返回退出码 1，会干扰脚本逻辑）
- **dart2js 会把中文转成 `\uXXXX`**：想在产物里验证某句中文是否编进去了，
  要搜转义串（如「续」→ `\u7eed`），直接搜中文一律 0 命中
- **看截图下结论前必须裁剪放大**：1080×2340 的截图在会话里被缩到 ~500px，
  中文字形极易看错，本项目已因此误判 3 次
- **「测试全绿」不等于「产品没问题」**：本项目的真 bug 全部是
  「把真实产物逐屏看一遍」发现的。自动断言只覆盖你想到了的那部分
- **`input swipe` 在 Flutter 预览面板里滚回顶部无效**（InteractiveViewer 拦截），
  可靠做法是点「调整参数」返回再重新生成
- **模拟器坐标换算用统一比例 2.16**（截图 1080×2340 对应显示 500px 宽），
  更稳的是用像素颜色直接定位控件
