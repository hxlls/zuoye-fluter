# 数据模型设计（`assets/data.json` + 本地持久化）

> 本文档记录**数据的形状、维度、规则与坑**。改数据或改「怎么读数据」之前请先读完。
> 代码侧的对应实现见 `lib/data/app_data.dart` 与 `lib/core/type_catalog.dart`。

## 1. 总览

`assets/data.json` 有 22 个顶层键，按作用分四类：

| 类别 | 键 | 作用 |
|---|---|---|
| **基座** | `TEXTBOOKS` / `GRADE_NAMES` / `VERSION_SUPPORT` | 有哪些教材版本、年级怎么称呼、每个版本提供哪些科目 |
| **内容主表** | `CONTENT` | **四维**：版本 × 年级 × 科目 × 上册/下册 |
| **规则表** | `CN_TYPE_GRADES` / `ENG_TYPE_GRADES` / `ENG_TYPE_LABELS` / `MATH_TYPE_DETAILS` / `MATH_INSTRUCTION` | 题型可用区间、标签、作答格式指令 |
| **语料库** | `YUWEN_CORPUS` / `GUSHI_RECITATION` / `ENG_505` / `YUWEN_BOOKS` / `YUWEN_TEXTS` / `HEBEI_TEXTS` / `RENJIAO_OLD_TEXTS` / `WAIYAN_YQ_TEXTS` / `WAIYAN_SQ_TEXTS` / `YUWEN_PRACTICAL` / `MATH_PROJECTS` / `MATH_CULTURE` / `UNIT_CONV` | 题目素材来源 |

⚠️ **语言约定**：数据里的年级键是**字符串**（`'1'`…`'6'`），册是**中文**（`'上'` / `'下'`），
科目键是 `'cally'` / `'math'` / `'eng'`。Dart 侧转换时注意 `int.parse` / `toString()`。

## 2. 教材与版本

### `TEXTBOOKS`（5 个版本）

| 键 | 名称 |
|---|---|
| `renjiao` | 人教版（部编版语文 / 人教版数学 / 人教 PEP 英语） |
| `hebei` | 冀教版（数学 + 英语） |
| `waiyanYQ` | 外研版·一年级起点（英语） |
| `waiyanSQ` | 外研版·三年级起点（英语） |
| `tongbiao` | 统编版 |

### `VERSION_SUPPORT` —— **每个版本提供哪些科目**

```json
"renjiao":   {"cally": [1,6], "math": [1,6], "eng": [1,6]}
"hebei":     {"cally": null,  "math": [1,6], "eng": [1,6]}
"waiyanYQ":  {"cally": null,  "math": null,  "eng": [1,2]}
"waiyanSQ":  {"cally": null,  "math": null,  "eng": [3,6]}
"tongbiao":  {"cally": [1,6], "math": [1,6], "eng": [1,6]}
```

值 = `[最小年级, 最大年级]`，`null` = 该版本不提供此科目。

**关键语义**：

- `cally` 键同时代表**练字帖**和**语文作业** —— 两者都源自语文教科书。
  所以 `cally: null` 的版本（冀教、外研）**语文作业与练字帖一起置灰**。
- **外研三起点没有 1、2 年级**（`eng: [3,6]`）：切换过去时年级要自动归一化到 3 年级，
  否则会出现「选了外研却还是一年级」的错位。
- **外研版只有英语**：主页科目卡片、AI 面板的科目选择器都必须按此过滤。
  （历史 bug：AI 面板曾写死「数学/英语/语文」三项，选了外研仍能选语文数学。）

## 3. `CONTENT` —— 内容主表（四维）

```
CONTENT[版本][年级][科目][册] → 列表
```

**同一路径下，三个科目的「列表元素含义」不同**，这是最容易搞错的地方：

| 科目 | 元素形状 | 列表长度的含义 |
|---|---|---|
| `cally` | `['一', 'yī']` 形式的 `[字, 拼音]` | **生字个数**（如人教版 1 上 103 字） |
| `math` | `{id, label, unit}` | **题型个数**（如人教版 1 上 10 个题型） |
| `eng` | `['apple', '苹果']` 形式的 `[词, 中文]` | **词汇个数**（如人教版 1 上 36 词） |

⚠️ **数学的 `math` 列表本身就是「该年级册可用题型」的真相**，不是靠区间过滤出来的。
`TypeCatalog` 直接取这个列表，因此**列表随三维变化** —— 一年级拿不到 `mul`，
换版本也会变（如外研三起点的数学列表与其他版本不同）。

实测规模示例（人教版）：

```
1上 cally=103字  math=10题型  eng=36词
1下 cally=170字  math= 8题型  eng=35词
2上 cally=209字  math= 8题型  eng=38词
3下 cally=113字  math= ?      eng= ?
```

各版本册数并不对称：`WAIYAN_SQ_TEXTS` 只有 `3/4/5/6`（三起点自然没有一二年级）。

## 4. 题型可用性规则（三科各不相同）

### 语文：`CN_TYPE_GRADES`（区间，9 个题型）

```json
"pinyin2char": [1,6]   "char2pinyin": [1,6]   "zuci": [1,6]
"gushiFill":   [1,6]   "mingjuFill":  [1,6]   "duanwen": [1,6]   "aiyuedu": [1,6]
"chengyuFill": [2,6]   "chengyuGuess":[2,6]      ← 成语类要 2 年级起
```

### 英语：`ENG_TYPE_GRADES`（区间，8 个题型）**+ 版本业务规则**

```json
"alphabet": [1,1]   "trace": [1,6]   "match": [1,6]
"cn2en": [2,6]      "en2cn": [2,6]
"spell": [3,6]      "listening": [1,6]   "aiyuedu": [3,6]
```

**但区间不是全部** —— `english_worksheet.dart` 的 `engTypeAllowed(id, ver, grade)`
还有版本相关规则（现已委托给 `TypeCatalog`）：

| 题型 | 额外规则 |
|---|---|
| `listening` | 外研三起点要 **≥3 年级**，其余版本 1–6 |
| `ailistening` | **≥3 年级**（注意：它不在 `ENG_TYPE_GRADES` 里，只靠这条规则） |
| `spell` | 外研三起点要 **≥5 年级**（三会→四会），其余 ≥3 年级 |
| `alphabet` | 仅 1 年级 |
| `cn2en` / `en2cn` | 2 年级起 |
| `aiyuedu` | 3 年级起 |

各题型顺序以 `english_panel.dart` 的 `_typeIds` 为准（**9 项**）。

⚠️ 历史 bug：`ailistening` 在 `ENG_TYPE_LABELS` 里漏了一项，而 UI 的标签是
**从 `data.json` 读的**（`type_catalog` 里 `label: labels[id] ?? id`），
于是界面上直接显示出英文 id。**标签有两处定义时，一定会有一处漏更新。**

### 数学：没有区间表，直接用 `CONTENT[..]['math'][册]` 的列表

可用的数值约束由题型 id 推导（见 `ScopeGuard.integerCeil()`），
因为 **id 是自描述的**：`add10` / `add20` / `add100` / `add1000` / `mul2x1` / `div3x2` …
手写课程表容易错，从 id 推导更可靠。

## 5. 数学专项

| 键 | 规模 | 作用 |
|---|---|---|
| `MATH_TYPE_DETAILS` | 48 个题型 | 题型的展示细节（unit / 分组等） |
| `MATH_INSTRUCTION` | 46 条 | **作答格式指令**（如「用竖式计算。」）—— 只有格式，**没有数值范围** |
| `UNIT_CONV` | 13 组 | 单位换算：`{from, to, mul, grades:[...]}`，按年级取用 |
| `MATH_PROJECTS` | 18 条 | 「综合与实践」项目：`{t:标题, d:描述}` |
| `MATH_CULTURE` | 12 条 | 「数学文化」：`{t, seg:low/mid/high, c:正文}` |

除法类题型的**年级位置**（查过一次，记下来省得再查）：

| 题型 | 位置 |
|---|---|
| `div` 表内除法 | renjiao **2 下**、waiyanSQ 2 下 |
| `divr` 有余数除法 | renjiao **2 下**、tongbiao 2 下 |
| `div2x1` 两三位数除以一位数 | renjiao **3 下**、waiyanYQ/waiyanSQ/tongbiao 3 下 |
| `div3x2` 除数是两位数 | waiyanSQ/hebei/tongbiao 4 上 |
| `decdiv` 小数除法 | renjiao/hebei/tongbiao/waiyanYQ **5 上** |
| `fracdiv` 分数除法 | hebei 5 下、tongbiao/waiyanSQ 6 上 |

## 6. 语料库

### `YUWEN_CORPUS` —— 语文三大语料，**按年级分桶**

```
YUWEN_CORPUS: { "gushi": Map<int,List>, "chengyu": Map<int,List>, "mingju": Map<int,List> }
```

取用时形如 `data.corpusGushi[grade] ?? []` —— **年级是分桶键，不是过滤条件**。
这保证了语料天然不超纲（低年级拿不到高年级的诗）。

### 其他语料

| 键 | 规模 | 说明 |
|---|---|---|
| `GUSHI_RECITATION` | 75 首 | 背诵篇目：`{t:题目, a:作者, seg:low/mid/high}` |
| `YUWEN_BOOKS` | 3 段（low/mid/high） | 内置课文篇目 |
| `YUWEN_TEXTS` / `HEBEI_TEXTS` / `RENJIAO_OLD_TEXTS` / `WAIYAN_YQ_TEXTS` / `WAIYAN_SQ_TEXTS` | 各 4–6 个年级 | 课文原文（按版本 + 年级） |
| `YUWEN_PRACTICAL` | 5 条 | 实用性阅读与交流（通知、书信等格式范例） |

### `ENG_505`

501 个课标词。**三年级起才用**，一二年级用各册配套词。

⚠️ **词汇超纲校验刻意没做**：`ENG_505` 是 headword 形式
（`{'w': 'a/an'}`、`'be (am, is, are)'`），功能词 is/the/my 等**都不在表内**，
逐词比对必然大量误报。**误报比漏报更伤老师对工具的信任**，所以宁可放弃这条检查。

## 7. Dart 侧映射

```
AppData（单例，lib/data/app_data.dart）
  ├─ load()                 解析 assets/data.json，暴露各键的强类型访问器
  ├─ versionSupport         版本 → 科目可用性
  ├─ vol(ver, grade, vol, subj)  取 CONTENT 里的列表（cally/math/eng 共用入口）
  └─ corpusGushi / corpusChengyu / corpusMingju   按年级分桶的语料

TypeCatalog（lib/core/type_catalog.dart）★ 题型可用性唯一事实来源
  ├─ enum Subject { math, chinese, english }
  ├─ TypeSpec { id, label, defaultQty, ... }
  ├─ TypeCatalog.of(subject, version, grade, volume, includeUnavailable: false)
  └─ seedTypeCounts()       只对「未设置过」的题型填默认值
                            （修掉「用户取消勾选被复活」的 bug）
```

**`TypeCatalog.of` 是唯一入口。** 面板、渲染层都应经它取题型，
不要在别处重新实现「这个年级有哪些题型」的判断（历史上散在 5 处，规则会漂移）。

## 8. 本地持久化设计

| 存储（Dart） | 键（SharedPreferences） | 语义与取舍 |
|---|---|---|
| `work_context_store` | `ctx_version` / `ctx_volume` / `ctx_grade` | 全局上下文。读取时防御：版本已不存在→回落人教版；年级不被该版本支持→归一化 |
| `type_count_store` | `type_counts_<subject>` | **题量跟题型绑定** → 按科目+题型 id 记一份，不按三维分档 |
| `panel_pref_store` | `panel_opts_<panel>` | **选项是我的排版习惯** → 按面板记一份，跨年级不变 |
| `ai_pref_store` | `ai_subject` / `ai_styles_<subject>` / `ai_opts` / `ai_help_subject` / `ai_help_messages` | AI 出题勾选、AI 帮答对话 |
| `corpus_store` | `customCorpora` / `activeCorpusId` / `captureTargetId` | 用户导入的课文语料 |
| `english_panel` | `eng_settings_<grade>_<version>_<volume>` | 英语的**显示选项**仍按三维分档（历史遗留，题量已迁到全局 store） |
| `ai_client` | `ai_api_key` | 系统级加密（Windows DPAPI / Android Keystore），不落明文 |

### 两条设计原则

1. **「跟题型的」按题型记，「跟排版习惯的」按面板记。**
   题量换个年级该保留（同一题型的偏好），选项换个年级不该重置。
2. **必须能区分「未设置」与「设为 0」。**
   `type_count_store.load()` 只返回用户**显式设置过**的题型，
   调用方用 `containsKey` 判断。否则用户取消勾选（题量 0）会被当成「没设置」而复活。

### 平台差异

- Android：应用私有目录下的 `shared_prefs/FlutterSharedPreferences.xml`
  （键名带 `flutter.` 前缀）
- Web：浏览器 **localStorage**（与手机端**完全独立**，设置不会跨端同步）

## 9. 数据来源与同步

`assets/data.json` 由原 JS 版项目（Electron + Capacitor 实现）的
`js/data.js` + `js/yuwen-corpus.js` 经转换脚本生成，**正常情况下不要手改**
（例外：修 `ENG_TYPE_LABELS` 漏项这类「Dart 侧与 JSON 不一致」的问题时必须补 JSON）。

原项目数据结构变化后需重新转换并同步，之后**务必跑**：

```bash
bash scripts/validate.sh    # analyze + test + 版本一致性
```

生成逻辑（`math_gen.dart` / `chinese_worksheet.dart` / `english_worksheet.dart`）
需与原项目 `js/` 下对应文件**人工对齐**。

## 10. 已知约束与陷阱

1. **`math` 列表长度 = 题型数，不是题目数**，而 `cally` / `eng` 的长度是字数 / 词数。
   同一个 `CONTENT` 路径下三者含义不同 —— 写循环时最容易踩。
2. **题型 id 必须自描述**：数值上限、是否用竖式、是否消耗词汇都从 id 推。
   新题型应沿用这套命名（`add100` / `mul2x2` / `div3x2`）。
3. **同一个题型在不同版本下可能可用性不同**（`spell` 在外研三起点要 ≥5 年级），
   所以任何缓存「某年级的题型列表」的做法都必须把版本一起进缓存键。
4. **词表容量是硬约束**：低年级词表有限（二年级仅 38 词），
   各题型题量之和超过词表长度时，`takeVocab` 会「取完为止」，
   靠后的题型题量自然减少 —— 这是**有意为之**的降级，不是 bug
   （反面做法「循环重复取词」会让同一单词在一份卷子里出现两次）。
5. **`VERSION_SUPPORT` 的 `cally` 一个键管两件事**（练字帖 + 语文），
   改动它会影响两张卡片。
