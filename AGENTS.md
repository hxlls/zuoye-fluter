# AGENTS.md — Flutter 版项目指南

> 面向接手本项目的开发者 / AI 助手。**改动代码前请先读完「关键机制」一节**，
> 那里的约定大多是踩过坑之后固化下来的，违反它们会造成肉眼难查的回归。

## 项目概况

小学作业生成器（练字帖 / 语文 / 数学 / 英语 / AI 出题），**Flutter 重写版**。
技术栈 Dart/Flutter（`lib/`，约 13k 行），目标平台 **Windows 桌面 + Android APK + Web**。

- 原 JS 版（Electron + Capacitor 实现）是上一代实现，本目录是其 Dart 移植。
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
    pdf_page_cleaner.dart    ★ 教材 PDF 逐页清洗（剔注音 / 重拼行 / 去重复行）
    textbook_structurer.dart ★ 教材 PDF 结构识别（目录 → 单元/课/正文）
    pdf_textbook_import.dart 教材 PDF 提取 → 清洗 → 结构的接线（syncfusion 唯一入口）
  ai/
    ai_client.dart           AI 配置（安全存储）+ OpenAI 兼容请求
    ai_generator.dart        AI prompt / 解析 / 渲染
  ui/
    home_page.dart           主页（教材上下文 + 三标签 + 科目卡片）
    preview_panel.dart       预览容器（分页扫描 / 缩放 / PDF、打印入口）
    worksheet_view.dart      预览页 Widget（大题编号、得分栏、续页渲染）
    worksheet_cards.dart     各科题卡 Widget（含长除号手绘）
    panel_widgets.dart       通用控件（PanelLayout / SegButtons / TypeRow …）
    pdf_import_flow.dart     教材 PDF 导入流程（选文件 → 页码范围 → 预览勾选）
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

### 8. 扩展 AI 服务商 / 模型

AI 的可配置项收敛在 `lib/ai/ai_client.dart` 的**两张表**里：

| 要做的事 | 改哪里 | 必要性 |
|---|---|---|
| 让新厂商出现在服务商下拉里 | `AI_PROVIDERS` 加一项 | 可选 |
| 给厂商增加接口地址候选 | 该项的 `presets` 加一条 | 可选 |
| 登记模型能否看图 / 出声 / 出声还缺什么 | `MODEL_CAPABILITIES` 加一行 | 可选 |
| 设置界面 | —— | **无需改动**（下拉均由 `AI_PROVIDERS` 自动生成） |

`AI_PROVIDERS` 一项有五个字段，`presets` 是该厂商的**接口地址候选列表**：

```dart
'厂商key': AiProviderInfo(
  label: '显示名',                        // 下拉里给用户看的名字
  presets: [
    AiProviderPreset(label: '官方 API', base: 'https://api.example.com/v1'),
    AiProviderPreset(label: '自定义',   base: ''),
  ],
  model: 'model-name',                   // 默认模型
  voice: '',                             // 语音模型；空 = 该厂商不提供 TTS
  ttsStyle: 'audio',                     // 'audio' | 'chat' | 'auto'
),
```

设置弹层里「服务商 → 接口 → 模型」三者是**联动**的：

1. 选服务商 → 自动填入该厂商第一个预设接口、默认模型与语音模型
2. 选接口 → 填入对应地址；若 API Key 已填，**自动拉取 `GET /models`**
3. 模型 → 从拉回的列表里选，或继续手动输入（手动输入始终可用）
4. 语音模型 → 同样从拉回的列表里选；候选按「拿到模型名就能出声」排序
   （`ModelCapability.sortForTts`：可直接用 → 未知 → 不支持 / 需额外输入），
   **不过滤**，留空仍表示该端点不配音

因此**接口候选的 `label` 要写清来源**（如「官方 API」「自定义」），
`base` 为空串的项表示交给用户手填 —— 约定放在列表**最后一项**。

**多数情况不必改代码**：设置里选 `custom`，自行填地址与模型即可。
`custom` 的 `ttsStyle` 为 `'auto'`，会按语音模型名前缀推断接口风格
（`mimo-` 系走 chat/completions + audio，其余走 /audio/speech）。
只有当希望新厂商出现在**预设下拉**、或让它被自动填入默认值时，才需要加这一项。

**五条纪律**：

1. **模型名以该 API 的 `GET /models` 返回为准**，不要照搬产品宣传里的名字。
   曾把产品名 `deepseek-v4.1-flash` 写进代码，而 API 实际只认 `deepseek-flash`，
   直接导致该厂商不可用。
2. **`MODEL_CAPABILITIES` 只登记实测确认过的能力**。不登记会走「未知即尝试」（安全）；
   登记错了会**直接误导** —— 把支持视觉的模型标成 `false`，它会在发图前被短路拦截。
3. **纯 TTS 模型只标注、不隐藏**。`mimo-v2.5-tts` 这类模型与对话模型同在
   一份 `/models` 清单里，设置界面据 `pureTts` 标「仅配音」—— 它出现在
   **主模型**候选里，误选会让出题直接失败。
4. **「是 TTS 模型」不等于「在本应用里能用」**。`mimo-v2.5-tts-voiceclone`
   要参考音频的 DataURL、`mimo-v2.5-tts-voicedesign` 要音色描述，本应用都没有
   对应入口，实测直接 400。这类模型用 `voiceNeeds` 登记，界面标出缺什么、
   试听前拦下，并且**不进候选前排**（见 `ModelCapability.ttsRank`）。
5. **「可选」不等于「可用」，候选上架前先逐个真跑一次**。把模型做成一键可选
   之后，用户就不会再查文档了 —— 缺入口的模型若混在候选前排，等于把 400 甩给用户。
   `voiceNeeds` 就是这类模型缺什么的登记处。

### 9. 教材 PDF 导入：版面参数逐书不同，划界一律以**目录**为准

三步流水线：`pdf_page_cleaner`（逐页清洗）→ `textbook_structurer`（结构识别）
→ `pdf_import_flow`（界面）。**零 AI 成本**，走 PDF 自带文本层；
扫描图片版无效，那种要 OCR 或走「拍照导入」。

**第一原则：不要拿版面位置切课。** 曾经的做法是「扫页面上的标题带（`top` 在
若干 pt 之间）」，它在人教社《道德与法治》一年级上册上完美，换到
《语文》六年级下册**一节课都切不出来**（0 课 / 0 单元）。原因是每本书的
版面都不同：课题可能是 `第1课 开开心心上学去`，也可能是 `2腊八粥`（无「第」「课」）；
单元扉页的位置也不同。用目录划界则与版面无关。

- **目录解析要用 `extractText(layoutText: true)` 的版面文本，不要用词坐标。**
  实测《语文》六年级下册的目录页上，`syncfusion` 给出的词坐标不可信
  （同一个词与 PyMuPDF 相比 `y` 差一整行、`x` 差 134pt，部分词甚至
  `right < left`）。而版面文本的顺序**完全正确**：条目、点线、页码三行一组。
  该调用**只对目录页做**，不增加全量提取的成本。
- **偏移 = 页脚页码 − PDF 页序，取众数**。与目录无关，最稳，且能容忍个别页读错
  （实测有目录页的页码被读成 60，是明显离群值）。
- **三重自校验，全过才用目录**：切出了课 / 首课在目录页之后 / 课首页上确实印着
  课名（命中率 ≥ 50%）。③ 是关键 —— 它拿**页面内容**去核对目录页码，
  而不是只信算术。任一不过就退回标题带兜底，不会按错位置切出一堆空课。
- **目录里页码不增的连续条目按「父 + 子」合并**：《古诗三首》下挂着
  `寒食 / 迢迢牵牛星 / 十五夜望月`，四条书页都是 11；《文言文二则》下有
  `学弈 / 两小儿辩日`。拆开的话后者 `end < start`，会切出空课。
  「古诗词诵读」下十首诗页码依次递增，则照常各自成课。

清洗（`pdf_page_cleaner`）的三步**顺序不能换**，换一步就崩：

1. **按字体名剔注音** —— 拼音字体的字形被错映射成 ASCII（`第dK1课kF开kQi`），
   靠正则猜必然误伤正文；按字体名精确剔除则 100% 干净。
2. **按 y 聚类重拼行** —— 库的 `extractTextLines()` 在这本 PDF 上**每个词自成一行**，
   必须自己聚类。注音中心与汉字中心相差约 25pt，用「字高中位数 / 2」当容差正好分开。
3. **跨页重复行去水印** —— 版权水印出现 68/70 次。

⚠️ **不能整段切掉页脚区。** 曾以为「正文比页脚带口深 37pt」，后来发现那个
710pt 是**页码**的底边（不是正文）。真实数据是正文最深 685pt、带上沿 673pt ——
只伸进去 12pt，而且带内除水印页码外**确实还有零星正文**。所以页脚里那两样东西
各有更精确的去处：水印 → 重复行检测，页码 → 结构化阶段的 `digitsOnly` 过滤。

**分段导入**：教材动辄上百页，按「页码区间」分多次导，段与段之间自动把被切断的
那一课拼回去（后一段开头、第一个课题之前的正文续到前一段的最后一课）。
两条容易踩的：

- **本段的已知目录要优先于本段拼出的坐标目录**。段内正文里偶然出现的
  「省略号 + 数字」会被误判成目录页，拿它顶掉已知目录后，后半本整段切不出课
  （实测 1.7 万字全被算成「段首正文」）。
- 传入的目录推出课页范围后**必须与本段实际区间求交**，否则段 B 会多出
  「第 1 课（空）」这类空课，`cutOff` 也判错。

⚠️ **已知局限**：部分教材把数字做成了**图片**（`我一般〔9〕点睡觉`），
文本层里根本不存在，且注音音节数仍等于汉字数，评分抓不到 —— 只能靠视觉兜底 + 人工确认。

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
- `pdf_page_cleaner_test.dart` 教材 PDF 清洗（夹具抄自真实教材第 7 页的逐词坐标）
- `textbook_structurer_test.dart` 教材结构识别（合成小书：点线目录、子条目合并、
  「目录对不上正文时退回标题带」、分段续接逐字一致）

⚠️ 改教材 PDF 相关逻辑后，**只跑单元测试不够** —— 合成夹具的版面参数是我们
自己写进去的，必然会顺应实现。真实样本在 `~/samples/`（`_real_textbook.pdf`
《道德与法治》一年级上册、`_yuwen6x.pdf` 《语文》六年级下册），
改完务必用它们各跑一遍，并检查「分段导入与整本导入逐字一致」。

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

### 把 Web 版部署到子路径时

Release 里的 Web 包是让用户解压后直接打开 `index.html`，走相对路径、无需额外配置。
但若要把它挂到某个子路径（例如 `/app/`），有两点必须注意，否则会出现
「怎么都打不开」或「改完看不到」：

- **构建加 `--base-href /app/`**。Flutter 默认生成 `<base href="/">`，
  会让 `main.dart.js` / `assets/` / `canvaskit/` 全去请求根路径 → 404 → **整页空白**。
- **构建加 `--pwa-strategy=none`**。默认策略会把 `main.dart.js` 整个缓存进
  service worker 的 CORE 列表，用户会一直看到旧版本（表现为「你明明说改了，
  我这边没变化」）。若此前注册过离线 SW，还需用一个会 `skipWaiting` + 清缓存 +
  `unregister()` 的自我注销脚本来顶替它。

## 环境要求

- **Flutter 3.24.5**（CI 固定此版本，更高版本未验证）
- **JDK 21**：Android Gradle Plugin 与更新版本的 Java 不兼容
  （例如系统自带的 Java 25 会导致构建失败）
- 国内网络下建议 pub 走镜像：
  `PUB_HOSTED_URL=https://pub.flutter-io.cn`、
  `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
- Linux 桌面版需 GTK dev 库；官方分发的是 Windows / Android / Web 三端

## 两条经验

- **验证 Web 产物里的中文，要搜转义串**。dart2js 会把中文转成 `\uXXXX`，
  直接搜中文一律 0 命中（例如想确认「续」是否编进去了，应搜 `\u7eed`）。
- **「测试全绿」不等于「产品没问题」**。本项目的真 bug 基本都是
  「把真实产物完整看一遍」发现的 —— 自动断言只覆盖你想到了的那部分。
  改完与渲染相关的代码后，建议至少把生成结果逐页看一遍。
