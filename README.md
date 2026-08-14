# 小学作业生成器（zuoye-fluter）

中国小学作业生成工具（Flutter 版）：一键生成可打印的小学 **练字帖 / 语文 / 数学 / 英语** 作业，支持 **AI 出题** 与 **AI 帮答题**，可导出 A4 PDF 或直接打印。

目标平台 **Windows 桌面版 + Android APK + Web**。

## 功能

- ✍️ **练字帖**：田字格描红，按所选教材各年级上下册生字生成，可自定义文字；练习次数 / 每行字数 / 每页行数可调
- 📖 **语文作业**：看拼音写汉字、汉字注拼音（四线三格）、生字组词、古诗名句 / 成语 / 名言填空等（公共领域语料）、课文阅读（外置语料导入）、阅读理解（AI 生成）
- 🔢 **数学作业**：各年级上下册题型（口算 / 竖式 / 长除法 / 应用题 / 单位换算 / 比较大小等），计算答案精确无浮点误差
- 🇬🇧 **英语作业**：字母书写、单词抄写、中英连线、中译英 / 英译中、单词拼写、阅读理解（AI 生成）
- 🤖 **AI 出题**：多科多题型混合作卷，每个题型可单独设题量，按年级过滤题型
- 💡 **AI 帮答题**：拍照或输入题目，AI 分步骤讲解并给出答案
- 📥 生成 A4 作业，一键导出 PDF（系统另存为对话框）或打印

## 教材依据

人教版（部编版语文 / 人教版数学 / 人教PEP英语）、冀教版（数学 + 英语）、外研版（英语·一年级起点 / 三年级起点），均按上、下册分离。

## 使用说明

- **AI 功能需自备大模型 API Key**：支持 OpenAI 兼容接口（DeepSeek、通义、Kimi、智谱、小米 MiMo、本地 Ollama 等），在应用内「AI 智能出题设置」填入 API 地址、模型与 Key 即可
- Key 以系统级加密保存（Windows DPAPI / 安卓系统密钥库 Keystore），仅存本机、不联网上传

## 开发

```bash
# 安装依赖
flutter pub get

# 校验（analyze + 测试 + 版本一致性）
bash scripts/validate.sh

# 构建
flutter build apk --release   # Android（需 JDK 21）
flutter build web --release   # Web
flutter build windows --release  # Windows（需 Windows 环境）
```

### 版本号（唯一来源 `pubspec.yaml`）

只改 `pubspec.yaml` 的 `version`（如 `1.73.1+17301`），然后运行 `node scripts/sync-version.js` 同步 `lib/data/app_data.dart`。

### 数据同步

`assets/data.json` 由 `/tmp/opencode/conv_data.js` 从原项目 `js/data.js` + `js/yuwen-corpus.js` 生成，勿手改。原项目数据结构变化后：

```bash
node /tmp/opencode/conv_data.js && cp /tmp/opencode/data.json assets/data.json
```

### Android 签名

Release 构建使用固定签名密钥（本地 `android/key.properties`；CI 从 GitHub Secrets 还原），保证版本间签名一致可覆盖安装。密钥文件不入库。

## 免责声明

AI 生成的题目与答案由大模型提供，可能存在错误，使用前建议人工核对。本地模板题目由程序生成，计算题答案准确可靠。受版权保护的课文内容请购买正版后自行整理导入并自行向版权方付费，本应用不提供也不代收任何受版权保护内容。

## 更新日志

版本更新记录见 GitHub Releases。
