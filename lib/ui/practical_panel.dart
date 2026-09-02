import 'package:flutter/material.dart';
import '../data/app_data.dart';

/// 2022 课标「实用性阅读与交流」应用文格式与例文页（原生数据，非 AI）
class PracticalPage extends StatelessWidget {
  const PracticalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AppData();
    return Scaffold(
      appBar: AppBar(
        title: const Text('✉️ 应用文格式与例文（2022 课标）'),
        backgroundColor: const Color(0xff2f6fd0),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '义务教育语文课程标准（2022 年版）· 实用性阅读与交流',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xff333333)),
          ),
          const SizedBox(height: 4),
          const Text(
            '常用应用文写作格式与例文，供语文学习与作业参考。',
            style: TextStyle(fontSize: 12, color: Color(0xff888888)),
          ),
          const SizedBox(height: 12),
          for (final p in data.practical) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xfff7faff),
                border: Border.all(color: const Color(0xffd6e4f7)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.edit_note, size: 20, color: Color(0xff2f6fd0)),
                      const SizedBox(width: 8),
                      Text(p.title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xff2f6fd0))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('格式要点',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xff333333))),
                  const SizedBox(height: 2),
                  Text(p.format, style: const TextStyle(fontSize: 13, height: 1.5)),
                  const SizedBox(height: 10),
                  const Text('例文',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xff333333))),
                  const SizedBox(height: 2),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xffe6e6e6)),
                    ),
                    child: Text(p.example,
                        style: const TextStyle(fontSize: 13, height: 1.6, fontFamily: 'monospace')),
                  ),
                  const SizedBox(height: 8),
                  Text('💡 ${p.tip}',
                      style: const TextStyle(fontSize: 12, color: Color(0xff888888), height: 1.5)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            '说明：本页为原生参考资料，非 AI 生成；AI 出题器的「实用性阅读与交流」题型可结合此类格式要求生成练习。',
            style: TextStyle(fontSize: 11, color: Color(0xffaaaaaa)),
          ),
        ],
      ),
    );
  }
}
