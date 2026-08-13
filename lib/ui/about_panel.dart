import 'package:flutter/material.dart';
import '../data/app_data.dart';

/// 关于面板
class AboutPanel extends StatelessWidget {
  const AboutPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    const Text('📖', style: TextStyle(fontSize: 48)),
                    const Text('小学作业生成器',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('版本 v${AppData.version}',
                        style: const TextStyle(fontSize: 14, color: Color(0xff888888))),
                    const SizedBox(height: 6),
                    const Text('中国小学作业生成工具 · 练字帖 / 语文 / 数学 / 英语 + AI 出题与帮答题',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Color(0xff666666))),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _block('📌 功能', [
                '✍️ 练字帖：田字格描红，按所选教材各年级上下册生字生成，可自定义文字',
                '📖 语文作业：看拼音写汉字 / 注音 / 组词、古诗名句 / 成语 / 名言填空等理解题（公共领域语料）、课文阅读（外置语料导入）、阅读理解（AI 生成）',
                '🔢 数学作业：各年级上下册题型（口算 / 竖式 / 长除法 / 应用题 / 单位换算等），答案精确无浮点误差',
                '🇬🇧 英语作业：字母书写、单词抄写、中英连线、中译英 / 英译中、单词拼写、阅读理解（AI 生成）',
                '🤖 AI 出题：多科多题型混合作卷，每个题型可单独设题量，按年级过滤题型',
                '💡 AI 帮答题：拍照或输入题目，AI 分步骤讲解并给出答案',
                '📥 生成 A4 作业，一键导出 PDF 或打印（逐页精确合成）',
              ]),
              _block('📚 教材依据',
                  ['人教版（部编版语文 / 人教版数学 / 人教PEP英语）、冀教版（数学 + 英语）、外研版（英语·一年级起点 / 三年级起点），均按上、下册分离。']),
              _block('⚠️ 免责声明', [
                'AI 生成的题目与答案由大模型提供，可能存在错误，使用前建议人工核对。本地模板题目由程序生成，计算题答案准确可靠。受版权保护的课文内容请购买正版后自行整理导入并自行向版权方付费，本应用不提供也不代收任何受版权保护内容。'
              ]),
              _block('🔧 技术说明', [
                'Flutter 跨平台应用（Windows / Android）。AI 功能需自备大模型 API Key，支持 OpenAI 兼容接口（DeepSeek、通义、Kimi、智谱、本地 Ollama 等）；Key 以系统级加密保存（Windows DPAPI / 安卓 Keystore），数据仅存本机。'
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _block(String title, List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $it',
                  style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xff444444))),
            ),
        ],
      ),
    );
  }
}
