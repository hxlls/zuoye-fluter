import 'dart:convert';
import '../data/app_data.dart';
import '../core/worksheet_model.dart';
import 'ai_client.dart';

/// AI 题型选项
class AiStyleOption {
  final String id;
  final String label;
  final List<int> grades;
  AiStyleOption(this.id, this.label, this.grades);
}

final AI_STYLE_OPTIONS = {
  'math': [
    AiStyleOption('calc', '计算题', [1, 6]),
    AiStyleOption('word', '应用题', [1, 6]),
    AiStyleOption('mix', '混合（含易错、推理）', [3, 6]),
  ],
  'english': [
    AiStyleOption('vocab', '词汇练习', [1, 6]),
    AiStyleOption('sent', '句子填空', [3, 6]),
    AiStyleOption('trans', '中英互译', [2, 6]),
    AiStyleOption('yuedu', '阅读理解', [3, 6]),
  ],
  'chinese': [
    AiStyleOption('zuci', '生字组词', [1, 6]),
    AiStyleOption('zaoju', '词语造句', [2, 6]),
    AiStyleOption('ktian', '词语填空', [2, 6]),
    AiStyleOption('jinyi', '近义词·反义词', [2, 6]),
    AiStyleOption('yuedu', '阅读理解', [3, 6]),
  ],
};

final AI_STYLE_DESC = {
  'calc': '计算题（含口算、竖式、简便运算等，难度与年级匹配）',
  'word': '应用题（结合生活情境，注重理解与举一反三，避免照搬教材例题）',
  'mix': '混合题型（计算+应用+易错/拓展推理，多样化）',
  'vocab': '词汇练习（单词拼写、英汉互译、选词填空等）',
  'sent': '句子填空（根据上下文填入合适的词或短语）',
  'trans': '中英互译（英译中、中译英各占一部分）',
  'zuci': '生字组词（给出生字，组两三个词语并选一个造句）',
  'zaoju': '词语造句（给出生词，用其写通顺的句子）',
  'ktian': '词语填空（选词填空、补充词语、按课文内容填空）',
  'jinyi': '近义词与反义词（给出生词，写出近义词和反义词）',
  'yuedu': '阅读理解（给出一篇适合该年级的短文，再围绕短文出几道理解题）',
};

final AI_STYLE_INSTRUCTION = {
  'calc': '计算下面各题。',
  'word': '列式解答下面的应用题。',
  'mix': '计算并解答下面各题。',
  'vocab': '完成下面的词汇练习。',
  'sent': '根据句意填入合适的词或短语。',
  'trans': '把下面的句子翻译成中文或英文。',
  'zuci': '照样子组词，并用一个词语造句。',
  'zaoju': '用下面的词语造句。',
  'ktian': '选词填空或补充句子。',
  'jinyi': '写出下面词语的近义词和反义词。',
  'yuedu': '阅读短文，回答问题。',
};

class AiStyleSpec {
  final String id;
  final int count;
  AiStyleSpec(this.id, this.count);
}

class AiSection {
  final String type;
  final String instruction;
  final List<AiItem> items;
  AiSection({
    required this.type,
    required this.instruction,
    required this.items,
  });
}

class AiItem {
  final String q;
  final String a;
  AiItem(this.q, this.a);
}

/// 构建 AI 出题 prompt
String aiBuildPrompt(String subject, List<AiStyleSpec> typeSpecs, AiPromptOpts opts) {
  final data = AppData();
  final tb = data.textbooks[opts.version] ?? data.textbooks['renjiao']!;
  final gname = data.gradeNames[opts.grade] ?? '小学';
  final volName = opts.volume == '下' ? '下册' : '上册';
  final diffText = opts.diff == 'hard'
      ? '较难'
      : opts.diff == 'mid'
          ? '中等'
          : '基础';
  final withAnswer = opts.showAnswer;
  final total = typeSpecs.fold<int>(0, (s, t) => s + t.count);

  final subjectCN = subject == 'math'
      ? '数学'
      : subject == 'english'
          ? '英语'
          : '语文';
  final styleLines = typeSpecs
      .map((t) => '- ${AI_STYLE_DESC[t.id] ?? '题目'}：${t.count}题')
      .join('\n');

  final special = subject == 'chinese'
      ? '题目中的生字/词语要适合该年级，最好从下面该年级生字范围中选取（括号内为该册生字，供参考）：\n生字：${_gradeChineseChars(data, opts)}'
      : subject == 'english'
          ? '英文题目词汇要属于该年级常用范围，可参考下面该年级词汇表（供参考）：\n词汇：${_gradeEnglishVocab(data, opts)}'
          : '应用题要贴近生活，答案给出单位。参考该年级数学知识范围：${_gradeMathTopics(data, opts)}';

  return '你是中国${subjectCN}教学出题专家。请为"${tb.name}${gname}${volName}"的学生出一套${diffText}难度的作业，共$total题，题型分配如下：\n'
      '$styleLines\n\n'
      '要求：\n'
      '1. 题目必须新颖、灵活，注重"举一反三"，不得照搬教材例题、课本原题或常见题库里的固定题目；\n'
      '2. 难度要与${gname}学生的水平匹配，严格贴合${gname}的知识范围（生字/词汇/知识点不得超纲）；\n'
      '3. ${withAnswer ? "每题必须给出正确答案，计算与拼写必须准确。" : "只要题目，不要给出答案。"}\n'
      '4. $special\n\n'
      '只输出一个 JSON 对象，格式严格如下，不要输出任何其他文字、不要用代码块包裹：\n'
      '${withAnswer ? '{"sections":[{"type":"题型名称","items":[{"q":"题目","a":"答案"}]}]}' : '{"sections":[{"type":"题型名称","items":[{"q":"题目"}]}]}'}';
}

/// 该年级语文写字表生字（用于约束 AI 生字/词语范围）
String _gradeChineseChars(AppData data, AiPromptOpts opts) {
  final list = data.vol(opts.version, opts.grade, opts.volume, 'cally')?.cally ?? [];
  final chars = list.take(60).map((c) => c[0]).join('、');
  return chars.isEmpty ? '（无）' : chars;
}

/// 该年级英语词汇表（用于约束 AI 词汇范围）
String _gradeEnglishVocab(AppData data, AiPromptOpts opts) {
  final list = data.vol(opts.version, opts.grade, opts.volume, 'eng')?.eng ?? [];
  final words = list.take(50).map((w) => w[0]).join('、');
  return words.isEmpty ? '（无）' : words;
}

/// 该年级数学题型/知识范围
String _gradeMathTopics(AppData data, AiPromptOpts opts) {
  final cfg = data.vol(opts.version, opts.grade, opts.volume, 'math')?.math ?? [];
  final topics = cfg.map((t) => t.label).join('、');
  return topics.isEmpty ? '（无）' : topics;
}

class AiPromptOpts {
  final String version;
  final String volume;
  final int grade;
  final String diff;
  final bool showAnswer;
  final int readingCount;
  AiPromptOpts({
    required this.version,
    required this.volume,
    required this.grade,
    required this.diff,
    required this.showAnswer,
    this.readingCount = 2,
  });
}

/// 提取 JSON
Map<String, dynamic> aiExtractJson(String text) {
  final t = text.trim();
  final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
  var candidate = fenced != null ? fenced.group(1)! : t;
  final start = candidate.indexOf('{');
  final end = candidate.lastIndexOf('}');
  if (start == -1 || end == -1 || end <= start) {
    throw Exception('AI 返回内容中未找到 JSON：${t.length > 200 ? t.substring(0, 200) : t}');
  }
  return json.decode(candidate.substring(start, end + 1)) as Map<String, dynamic>;
}

/// 生成 AI 作业 sections
Future<List<AiSection>> aiGenerateWorksheet(
  String subject,
  List<AiStyleSpec> specs,
  AiPromptOpts opts,
) async {
  final cfg = await AiStore.load();
  if (cfg.base.isEmpty || cfg.model.isEmpty) {
    throw Exception('请先在顶部「AI 智能出题设置」中填写 API 地址和模型并保存。');
  }
  final validSpecs = specs.where((t) => t.count > 0).toList();
  if (validSpecs.isEmpty) throw Exception('请至少选择一种题型并设置题量。');
  final content = await AiClient.chat(cfg, [
    AiChatMessage('user', aiBuildPrompt(subject, validSpecs, opts)),
  ], jsonMode: true);
  final data = aiExtractJson(content);
  final rawSections = data['sections'] is List
      ? (data['sections'] as List).cast<Map<String, dynamic>>()
      : (data['items'] is List
          ? [
              {'type': '题目', 'items': data['items'] as List}
            ]
          : <Map<String, dynamic>>[]);
  if (rawSections.isEmpty) throw Exception('AI 未返回题目，请重试。');
  return rawSections.map((s) {
    final label = '${s['type'] ?? ''}'.trim();
    return AiSection(
      type: label,
      instruction: AI_STYLE_INSTRUCTION[styleIdByLabel(subject, label)] ?? '',
      items: [
        for (final it in (s['items'] as List? ?? []))
          if (it is Map && '${it['q']}'.trim().isNotEmpty)
            AiItem(
              '${it['q']}'.trim(),
              opts.showAnswer ? '${it['a'] ?? ''}'.trim() : '',
            )
      ],
    );
  }).where((s) => s.items.isNotEmpty).toList();
}

/// 判断 AI 题目是否为「一句话 / 一段话」
bool isSentenceLikeQ(String q) {
  final s = q.trim();
  if (s.isEmpty) return false;
  if (RegExp(r'[。？！，；：,.?!;:]').hasMatch(s)) return true;
  if (s.split(RegExp(r'\s+')).length >= 4) return true;
  return s.length >= 15;
}

/// 题型 ID 识别
String styleIdByLabel(String subject, String label) {
  final opts = AI_STYLE_OPTIONS[subject] ?? [];
  for (final o in opts) {
    if (label.contains(o.label) || o.label.contains(label)) return o.id;
  }
  if (subject == 'english' && RegExp(r'(互译|翻译|英译中|中译英)').hasMatch(label)) {
    return 'trans';
  }
  return '';
}

/// 渲染 AI 作业为页面列表
List<WsPage> aiRenderPages(List<AiSection> sections, AiRenderOpts opts) {
  final data = AppData();
  final subject = opts.subject;
  final subjectCN = subject == 'math'
      ? '数学'
      : subject == 'english'
          ? '英语'
          : '语文';
  final tb = data.textbooks[opts.version] ?? data.textbooks['renjiao']!;
  final gname = data.gradeNames[opts.grade] ?? '第${opts.grade}年级';
  final volName = opts.volume == '下' ? '下册' : '上册';

  final pages = <WsPage>[];
  final usableH = 860.0;
  var cur = <WsCard>[];
  var curH = 0.0;
  var curInstr = '';
  var curSid = '';
  var curSent = 0;
  var itemNo = 1;

  WsPageTitle pageTitle() => WsPageTitle(
        main: '${subjectCN}作业 · AI 出题',
        sub: '${tb.name}$gname$volName · 大模型随机生成（答案建议核对）',
        meta1: '姓名：____________',
        meta2: '班级：____________',
        meta3: '日期：____________',
      );

  void flush() {
    if (cur.isNotEmpty) {
      final forcedCol = ['sent', 'yuedu', 'word'].contains(curSid);
      final colFlow = forcedCol || curSent > 0;
      final nodes = <WsNode>[];
      if (curInstr.isNotEmpty) nodes.add(WsSection(curInstr));
      nodes.add(WsGrid(cur, cols: colFlow ? 1 : 3, evenly: true));
      pages.add(WsPage(title: pageTitle(), nodes: nodes));
      cur = [];
      curH = 0;
      curSent = 0;
    }
  }

  for (final sec in sections) {
    final instr = sec.instruction.isNotEmpty ? sec.instruction : sec.type;
    final sid = styleIdByLabel(subject, sec.type);
    final isTrans = sid == 'trans';
    final needsAns = ['word', 'yuedu', 'trans', 'zaoju'].contains(sid);
    curInstr = instr;
    curSid = sid;
    for (final it in sec.items) {
      const h = 86.0;
      if (cur.isNotEmpty && curH + h > usableH) flush();
      final hasBlank = RegExp(r'[（(]').hasMatch(it.q) && RegExp(r'[)）]').hasMatch(it.q);
      final qText = isTrans && !hasBlank ? '${it.q}（　　　　　　　　　　　　）' : it.q;
      final needsAnswerLine = isTrans && !hasBlank ? false : needsAns;
      if (isSentenceLikeQ(it.q)) curSent++;
      cur.add(WsCard('ai', AiCardData(
        q: qText,
        needsAns: needsAnswerLine,
        showAnsLabel: needsAns,
      ), num: itemNo));
      curH += h;
      itemNo++;
    }
  }
  flush();

  if (opts.showAnswer) {
    final nodes = <WsNode>[];
    nodes.add(WsHeading('参考答案'));
    var n = 1;
    for (final sec in sections) {
      nodes.add(WsAnswerGroup(sec.instruction.isNotEmpty ? sec.instruction : sec.type));
      for (final it in sec.items) {
        nodes.add(WsAnswerLine(n++, it.q, '答：${it.a.isEmpty ? "—" : it.a}'));
      }
    }
    pages.add(WsPage(
      title: WsPageTitle(
          main: '参考答案', meta1: '$subjectCN · ${tb.name}$gname$volName'),
      nodes: nodes,
      noSpread: true,
    ));
  }

  return pages;
}

class AiCardData {
  final String q;
  final bool needsAns;
  final bool showAnsLabel;
  AiCardData({
    required this.q,
    this.needsAns = false,
    this.showAnsLabel = false,
  });
}

class AiRenderOpts {
  final String subject;
  final String version;
  final String volume;
  final int grade;
  final bool showAnswer;
  AiRenderOpts({
    required this.subject,
    required this.version,
    required this.volume,
    required this.grade,
    required this.showAnswer,
  });
}

/// AI 帮答 system prompt
AiChatMessage aiHelpSystemPrompt(String subject, AiHelpOpts opts) {
  final data = AppData();
  final tb = data.textbooks[opts.version] ?? data.textbooks['renjiao']!;
  final gname = data.gradeNames[opts.grade] ?? '小学';
  final vol = opts.volume == '下' ? '下册' : '上册';
  final subCN = subject == 'math'
      ? '数学'
      : subject == 'english'
          ? '英语'
          : subject == 'chinese'
              ? '语文'
              : '各学科';
  final imgRule = opts.withImage
      ? '如果用户上传了图片，请先仔细识别图片中的题目内容（文字、数字、算式、图形、表格等），确认无误后再解答；若图片不清晰导致无法辨认，请说明并请用户补充或重拍。'
      : '';
  return AiChatMessage(
      'system',
      '你是${subCN}辅导老师。请用${gname}学生能听懂的语言，分步骤讲解学生给出的题目（参考${tb.name}${gname}${vol}的知识水平）：\n'
      '1. 先简要说明思路；\n'
      '2. 再逐步列式计算或分析（步骤清晰、每步简短）；\n'
      '3. 最后一行用"答案："给出最终结果。\n'
      '$imgRule\n'
      '语言简洁易懂，不要照抄题目原文以外的多余内容。如果题目信息不完整或模糊，请先礼貌说明并请学生补充。');
}

class AiHelpOpts {
  final String version;
  final String volume;
  final int grade;
  final bool withImage;
  AiHelpOpts({
    required this.version,
    required this.volume,
    required this.grade,
    this.withImage = false,
  });
}

/// AI 阅读生成（语文）
Future<List<ReadingBlockData>> aiGenerateReading(AiPromptOpts opts) async {
  final cfg = await AiStore.load();
  if (cfg.base.isEmpty || cfg.model.isEmpty) {
    throw Exception('请先在顶部「AI 智能出题设置」中填写 API 地址和模型并保存。');
  }
  final data = AppData();
  final tb = data.textbooks[opts.version] ?? data.textbooks['renjiao']!;
  final gname = data.gradeNames[opts.grade] ?? '小学';
  final volName = opts.volume == '下' ? '下册' : '上册';
  final count = opts.readingCount;
  final chars = (data.vol(opts.version, opts.grade, opts.volume, 'cally')?.cally ?? [])
      .take(80)
      .map((c) => c[0])
      .join('、');
  final prompt = '你是中国小学语文出题专家。请为"${tb.name}${gname}${volName}"的学生生成$count篇原创阅读理解练习：\n'
      '1. 每篇给一篇适合该年级的原创短文（100-300字，主题贴近儿童生活、科普或传统美德等），短文用字尽量控制在下面该年级生字范围（生字可作参考，允许少量延伸）：\n生字：${chars.isEmpty ? '（无）' : chars}\n'
      '2. 每篇配3-5道理解题（按原文找信息、概括内容、体会句子意思、明白道理等），难度贴合${gname}；\n'
      '3. 题目必须原创、新颖，不得照搬教材课文或常见题库原题；答案要准确。\n'
      '只输出一个 JSON 对象，不要输出任何其他文字：\n'
      '{"items":[{"title":"标题","author":"作者","text":"短文正文","questions":[{"q":"问题","a":"答案"}]}]}';
  final content = await AiClient.chat(cfg, [AiChatMessage('user', prompt)],
      jsonMode: true);
  final data2 = aiExtractJson(content);
  final items = data2['items'] is List ? data2['items'] as List : [];
  return [
    for (final it in items)
      if (it is Map && '${it['text'] ?? ''}'.trim().isNotEmpty)
        ReadingBlockData(
          title: '${it['title'] ?? '短文'}',
          author: '${it['author'] ?? ''}',
          text: '${it['text'] ?? ''}',
          questions: [
            for (final q in (it['questions'] as List? ?? []))
              if (q is Map)
                ReadingQuestion('${q['q'] ?? ''}', '${q['a'] ?? ''}')
          ],
        )
  ];
}

/// AI 阅读生成（英语）
Future<List<ReadingBlockData>> aiGenerateReadingEN(AiPromptOpts opts) async {
  final cfg = await AiStore.load();
  if (cfg.base.isEmpty || cfg.model.isEmpty) {
    throw Exception('请先在顶部「AI 智能出题设置」中填写 API 地址和模型并保存。');
  }
  final data = AppData();
  final tb = data.textbooks[opts.version] ?? data.textbooks['renjiao']!;
  final gname = data.gradeNames[opts.grade] ?? '小学';
  final volName = opts.volume == '下' ? '下册' : '上册';
  final count = opts.readingCount;
  final words = (data.vol(opts.version, opts.grade, opts.volume, 'eng')?.eng ?? [])
      .take(50)
      .map((w) => w[0])
      .join('、');
  final prompt = '你是中国小学英语出题专家。请为"${tb.name}${gname}${volName}"的学生生成$count篇英语阅读理解：\n'
      '1. 每篇给一篇适合该年级的原创英文短文（40-120词），用词尽量控制在下面该年级词汇范围内（词汇可作参考，允许少量延伸）：\n词汇：${words.isEmpty ? '（无）' : words}\n'
      '2. 每篇配3-5道理解题（用英文提问，如根据原文回答问题、判断正误等，可附中文提示），难度贴合${gname}；\n'
      '3. 短文与题目必须原创，不得照搬教材课文或常见题库原题；答案要准确。\n'
      '只输出一个 JSON 对象，不要输出任何其他文字：\n'
      '{"items":[{"title":"标题","text":"英文短文正文","questions":[{"q":"问题","a":"答案"}]}]}';
  final content = await AiClient.chat(cfg, [AiChatMessage('user', prompt)],
      jsonMode: true);
  final data2 = aiExtractJson(content);
  final items = data2['items'] is List ? data2['items'] as List : [];
  return [
    for (final it in items)
      if (it is Map && '${it['text'] ?? ''}'.trim().isNotEmpty)
        ReadingBlockData(
          title: '${it['title'] ?? 'Passage'}',
          text: '${it['text'] ?? ''}',
          en: true,
          questions: [
            for (final q in (it['questions'] as List? ?? []))
              if (q is Map)
                ReadingQuestion('${q['q'] ?? ''}', '${q['a'] ?? ''}')
          ],
        )
  ];
}
