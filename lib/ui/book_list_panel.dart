import 'package:flutter/material.dart';
import '../data/app_data.dart';

/// 2022 课标「整本书阅读」推荐书目页（原生数据，非 AI）
class BookListPage extends StatelessWidget {
  final int grade;
  const BookListPage({super.key, required this.grade});

  @override
  Widget build(BuildContext context) {
    final data = AppData();
    final curSeg = grade <= 2 ? 'low' : grade <= 4 ? 'mid' : 'high';
    const segs = [
      ('low', '第一学段（1–2 年级）'),
      ('mid', '第二学段（3–4 年级）'),
      ('high', '第三学段（5–6 年级）'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('📚 整本书阅读书目（2022 课标）'),
        backgroundColor: const Color(0xff2f6fd0),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '义务教育语文课程标准（2022 年版）· 整本书阅读推荐书目',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xff333333)),
          ),
          const SizedBox(height: 4),
          Text(
            '当前年级对应：${curSeg == 'low' ? '第一学段（1–2 年级）' : curSeg == 'mid' ? '第二学段（3–4 年级）' : '第三学段（5–6 年级）'}（高亮）',
            style: const TextStyle(fontSize: 12, color: Color(0xff888888)),
          ),
          const SizedBox(height: 12),
          for (final (seg, label) in segs) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6, top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: seg == curSeg
                    ? const Color(0xff2f6fd0)
                    : const Color(0xfff0f0f0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.bookmark,
                      size: 18,
                      color: seg == curSeg ? Colors.white : const Color(0xff2f6fd0)),
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: seg == curSeg
                              ? Colors.white
                              : const Color(0xff333333))),
                  const Spacer(),
                  Text('${data.corpusBooks[seg]?.length ?? 0} 本',
                      style: TextStyle(
                          fontSize: 12,
                          color: seg == curSeg
                              ? Colors.white70
                              : const Color(0xff999999))),
                ],
              ),
            ),
            for (final b in data.corpusBooks[seg] ?? [])
              ListTile(
                dense: true,
                leading: const Icon(Icons.auto_stories, size: 18, color: Color(0xff2f6fd0)),
                title: Text('《${b.t}》',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: b.a.isNotEmpty ? Text(b.a, style: const TextStyle(fontSize: 12)) : null,
              ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          const Text(
            '说明：书目按学段分段为推荐性归类，供整本书阅读规划参考；AI「整本书阅读单」题型将围绕本清单书目设计探究任务。',
            style: TextStyle(fontSize: 11, color: Color(0xffaaaaaa)),
          ),
        ],
      ),
    );
  }
}
