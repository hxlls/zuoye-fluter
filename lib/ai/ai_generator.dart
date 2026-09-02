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
    AiStyleOption('practice', '综合与实践（量感·统计·项目式）', [1, 6]),
  ],
  'english': [
    AiStyleOption('vocab', '词汇练习', [1, 6]),
    AiStyleOption('sent', '句子填空', [2, 6]),
    AiStyleOption('trans', '中英互译', [4, 6]),
    AiStyleOption('yuedu', '阅读理解', [3, 6]),
    AiStyleOption('culture', '文化意识（节日·习俗·文化对比）', [3, 6]),
    AiStyleOption('think', '思维品质（推理·比较·判断·表达观点）', [3, 6]),
    AiStyleOption('learn', '学习能力（策略·计划·自主学习）', [3, 6]),
  ],
  'chinese': [
    AiStyleOption('zuci', '生字组词', [1, 6]),
    AiStyleOption('zaoju', '词语造句', [1, 6]),
    AiStyleOption('ktian', '词语填空', [1, 6]),
    AiStyleOption('jinyi', '近义词·反义词', [2, 6]),
    AiStyleOption('yuedu', '阅读理解', [3, 6]),
    AiStyleOption('zhengshu', '整本书阅读单', [1, 6]),
    AiStyleOption('kuaxueke', '跨学科学习', [3, 6]),
    AiStyleOption('practical', '实用性阅读与交流（应用文·情境）', [1, 6]),
  ],
};

final AI_STYLE_DESC = {
  'calc': '计算题（含口算、竖式、简便运算等，难度与年级匹配）',
  'word': '应用题（结合生活情境，注重理解与举一反三，避免照搬教材例题）',
  'mix': '混合题型（计算+应用+易错/拓展推理，多样化）',
  'practice': '综合与实践（围绕量感、数据意识、项目式/主题式学习设计真实情境题，如估测、选择单位、读统计图、简单调查）',
  'vocab': '词汇练习（单词拼写、英汉互译、选词填空等）',
  'sent': '句子填空（根据上下文填入合适的词或短语）',
  'trans': '中英互译（英译中、中译英各占一部分）',
  'culture': '文化意识（围绕中外节日、习俗、文明礼仪、文化对比设计题目，培养跨文化理解与文化自信，如春节/中秋/生日习俗、问候礼仪、中西饮食习惯差异等）',
  'think': '思维品质（围绕短文或主题设计推理、比较、判断、表达观点类题目，培养逻辑与批判性思维，如根据线索推断、比较异同、判断正误并说出理由、就话题简单发表自己的看法）',
  'learn': '学习能力（围绕学习策略、学习计划、自主探究、资源利用、自我反思设计题目，培养良好的英语学习习惯与自主学习能力，如制定每周单词背诵计划、用词典/图片辅助理解、做完题后自我检查与订正、分享自己的学习方法）',
  'zuci': '生字组词（给出生字，组两三个词语并选一个造句）',
  'zaoju': '词语造句（给出生词，用其写通顺的句子）',
  'ktian': '词语填空（选词填空、补充词语、按课文内容填空）',
  'jinyi': '近义词与反义词（给出生词，写出近义词和反义词）',
  'yuedu': '阅读理解（给出一篇适合该年级的短文，再围绕短文出几道理解题）',
  'zhengshu': '整本书阅读单（围绕一本推荐书目设计阅读探究任务，含内容梳理、语句赏析、主题感悟等）',
  'kuaxueke': '跨学科学习（以语文为核心，融合科学、历史、艺术、生活等设计综合任务）',
  'practical': '实用性阅读与交流（围绕真实生活情境设计应用文与实用交流任务，如写通知、留言条、请假条、书信、倡议书，或读图表/说明书提取信息并作答，培养在生活中学语文、用语文）',
};

final AI_STYLE_INSTRUCTION = {
  'calc': '计算下面各题。',
  'word': '列式解答下面的应用题。',
  'mix': '计算并解答下面各题。',
  'practice': '完成下面的综合与实践题（注意联系生活、写明单位与思路）。',
  'vocab': '完成下面的词汇练习。',
  'sent': '根据句意填入合适的词或短语。',
  'trans': '把下面的句子翻译成中文或英文。',
  'culture': '完成下面的文化意识题（围绕节日、习俗或文化对比，语言简单地道）。',
  'think': '完成下面的思维品质训练题（推理、比较、判断或表达观点，注意写出你的理由）。',
  'learn': '完成下面的学习能力训练题（围绕学习策略与自主计划，写出你的做法）。',
  'zuci': '照样子组词，并用一个词语造句。',
  'zaoju': '用下面的词语造句。',
  'ktian': '选词填空或补充句子。',
  'jinyi': '写出下面词语的近义词和反义词。',
  'yuedu': '阅读短文，回答问题。',
  'zhengshu': '完成下面的整本书阅读单。',
  'kuaxueke': '完成下面的跨学科学习任务。',
  'practical': '完成下面的实用性阅读与交流题（注意格式规范与情境得体）。',
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

  final styleIds = typeSpecs.map((t) => t.id).toSet();
  final special = subject == 'chinese'
      ? '题目中的生字/词语要适合该年级，最好从下面该年级生字范围中选取（括号内为该册生字，供参考）：\n生字：${_gradeChineseChars(data, opts)}'
          '${styleIds.contains('zhengshu') ? '\n整本书阅读单：每题围绕下面推荐书目之一设计一份阅读探究单（含内容梳理、精彩语句赏析、主题/人物感悟等3-4个任务），题目(q)写书名与任务，答案(a)写简要指导。可参考书目：' + _gradeBooks(data, opts) : ''}'
          '${styleIds.contains('kuaxueke') ? '\n跨学科学习：以语文为核心，融合科学、历史、艺术或生活实际设计综合任务，体现"在真实情境中运用语文"。' : ''}'
          '${styleIds.contains('practical') ? '\n实用性阅读与交流：设计贴近生活的应用文与实用交流任务，如写一则通知/留言条/请假条/书信/倡议书（注意格式：称呼、正文、署名、日期规范），或给一段说明书/图表/留言让学生提取关键信息并作答；培养"在生活中学语文、用语文"的能力，语言简明得体。' : ''}'
          : subject == 'english'
              ? '英文题目词汇要属于该年级常用范围，可参考下面该年级词汇表（供参考）：\n词汇：${_gradeEnglishVocab(data, opts)}'
                  '${opts.theme.isNotEmpty ? '\n本题严格围绕 2022 课标主题语境「${opts.theme}」展开（人与自我：生活与学习、做人与做事；人与社会：社会服务与人际沟通、文学与文化；人与自然：自然生态、环境保护）。' : ''}'
                  '${opts.textType.isNotEmpty ? '\n语篇类型优先使用「${opts.textType}」（如歌谣、配图故事、说明文、应用文等），贴近该语篇的真实体裁。' : ''}'
                  '${styleIds.contains('culture') ? '\n文化意识：设计围绕中外节日、习俗、文明礼仪或文化对比的题目（如春节/中秋/生日习俗、问候礼仪、中西饮食习惯与餐具差异等），培养跨文化理解与文化自信，语言尽量简单地道。' : ''}'
                  '${styleIds.contains('think') ? '\n思维品质：设计培养逻辑思维与批判性思维的题，如根据线索推理、比较事物异同、判断正误并说明理由、就某个生活话题简单发表自己的看法；题目(q)给出情境与问题，答案(a)给出合理推理与你的理由。' : ''}'
                  '${styleIds.contains('learn') ? '\n学习能力：设计培养自主学习能力与学习策略的题，如制定单词背诵/朗读计划、用图片或词典辅助理解生词、读后自我检查与订正、记录并分享自己的学习方法；题目(q)给出学习情境与任务，答案(a)给出可操作的学习策略或计划示例。' : ''}'
          : '应用题要贴近生活，答案给出单位。参考该年级数学知识范围：${_gradeMathTopics(data, opts)}'
              '\n注重培养学生的"量感"（对数量、度量、单位的直观感知与合理估算）与"模型意识"（用数学语言描述现实、建立简单模型）；综合与实践题要结合真实情境。';

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

/// 英语词汇范围文本（2022 课标对齐：三年级起使用 ENG_505 二级词表）
String _engVocabText(AppData data, AiPromptOpts opts) {
  if (opts.grade >= 3 && data.eng505.isNotEmpty) {
    return data.eng505.join('、');
  }
  final list = data.vol(opts.version, opts.grade, opts.volume, 'eng')?.eng ?? [];
  return list.take(50).map((w) => w[0]).join('、');
}

/// 该年级英语词汇表（用于约束 AI 词汇范围）
String _gradeEnglishVocab(AppData data, AiPromptOpts opts) {
  final w = _engVocabText(data, opts);
  return w.isEmpty ? '（无）' : w;
}

/// 该年级数学题型/知识范围
String _gradeMathTopics(AppData data, AiPromptOpts opts) {
  final cfg = data.vol(opts.version, opts.grade, opts.volume, 'math')?.math ?? [];
  final topics = cfg.map((t) => t.label).join('、');
  return topics.isEmpty ? '（无）' : topics;
}

/// 该年级整本书阅读推荐书目（用于约束 AI 整本书阅读单选题）
String _gradeBooks(AppData data, AiPromptOpts opts) {
  final books = data.bookList(opts.grade);
  final names = books.map((b) => '《${b.t}》').join('、');
  return names.isEmpty ? '（无）' : names;
}

class AiPromptOpts {
  final String version;
  final String volume;
  final int grade;
  final String diff;
  final bool showAnswer;
  final int readingCount;
  /// 英语：2022 课标三大主题语境（人与自我/人与社会/人与自然），留空表示不限定
  final String theme;
  /// 英语：语篇类型（歌谣/配图故事/说明文/应用文 等），留空表示不限定
  final String textType;
  /// 语文：是否「基于统编版课文」生成阅读理解（true 时从 YUWEN_TEXTS 取真实课文出题）
  final bool useTextbook;
  AiPromptOpts({
    required this.version,
    required this.volume,
    required this.grade,
    required this.diff,
    required this.showAnswer,
    this.readingCount = 2,
    this.theme = '',
    this.textType = '',
    this.useTextbook = false,
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

  String prompt;
  if (opts.useTextbook) {
    // 基于统编版课文模式：从 YUWEN_TEXTS 取真实课文出题
    final texts = data.yuwenTextsFor(opts.grade, opts.volume);
    final sel = texts.take(count).toList();
    final passages = sel
        .map((t) => '【课文】${t.title}（${t.unit}）\n${t.text}')
        .join('\n\n');
    prompt = '你是中国小学语文出题专家。下面是从"统编版语文${gname}${volName}"课本中选取的${sel.length}篇真实课文：\n\n'
        '$passages\n\n'
        '请基于上面提供的课文，为${gname}学生生成阅读理解练习（每篇课文出 3-5 道理解题）：\n'
        '1. 题目必须紧扣所给课文内容，考查：按原文提取信息、概括主要内容、理解关键词句的意思与作用、体会文章表达的思想感情或道理；\n'
        '2. 适当加入"思维能力/思辨性阅读"类题目（如推断原因、评价人物做法、联系生活实际谈看法）；\n'
        '3. 每题给出准确答案；难度贴合${gname}。\n'
        '只输出一个 JSON 对象，不要输出任何其他文字：\n'
        '{"items":[{"title":"课文标题","author":"作者/出处","text":"课文正文（可原样或略写）","questions":[{"q":"问题","a":"答案"}]}]}';
  } else {
    prompt = '你是中国小学语文出题专家。请为"${tb.name}${gname}${volName}"的学生生成$count篇原创阅读理解练习：\n'
        '1. 每篇给一篇适合该年级的原创短文（100-300字，主题贴近儿童生活、科普或传统美德等），短文用字尽量控制在下面该年级生字范围（生字可作参考，允许少量延伸）：\n生字：${chars.isEmpty ? '（无）' : chars}\n'
        '2. 每篇配3-5道理解题，题型兼顾：按原文找信息、概括主要内容、体会关键语句的意思与作用、明白文章道理；并适当加入"思维能力/思辨性阅读"类题目（如推断原因、评价人物做法、联系生活谈看法），难度贴合${gname}；\n'
        '3. 题目必须原创、新颖，不得照搬教材课文或常见题库原题；答案要准确。\n'
        '只输出一个 JSON 对象，不要输出任何其他文字：\n'
        '{"items":[{"title":"标题","author":"作者","text":"短文正文","questions":[{"q":"问题","a":"答案"}]}]}';
  }
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
  final words = _engVocabText(data, opts);
  final enThemeTip = opts.theme.isNotEmpty
      ? '【主题语境】短文与题目严格围绕 2022 课标主题语境「${opts.theme}」展开（人与自我：生活与学习、做人与做事；人与社会：社会服务与人际沟通、文学与文化；人与自然：自然生态、环境保护）。\n'
      : '';
  final enTextTypeTip = opts.textType.isNotEmpty
      ? '【语篇类型】优先使用「${opts.textType}」（如歌谣、配图故事、说明文、应用文等），贴近该语篇的真实体裁。\n'
      : '';
  final prompt = '你是中国小学英语出题专家。请为"${tb.name}${gname}${volName}"的学生生成$count篇英语阅读理解：\n'
      '1. 每篇给一篇适合该年级的原创英文短文（40-120词），用词尽量控制在下面该年级词汇范围内（词汇可作参考，允许少量延伸）：\n词汇：${words.isEmpty ? '（无）' : words}\n'
      '$enThemeTip$enTextTypeTip'
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

/// AI 听力短文生成（英语）
/// [narrationOnly] 为 true 时强制使用叙述形式（单人配音适用），false 时允许对话形式
Future<List<ReadingBlockData>> aiGenerateListeningEN(AiPromptOpts opts, {bool narrationOnly = true}) async {
  final cfg = await AiStore.load();
  if (cfg.base.isEmpty || cfg.model.isEmpty) {
    throw Exception('请先在顶部「AI 智能出题设置」中填写 API 地址和模型并保存。');
  }
  final data = AppData();
  final tb = data.textbooks[opts.version] ?? data.textbooks['renjiao']!;
  final gname = data.gradeNames[opts.grade] ?? '小学';
  final volName = opts.volume == '下' ? '下册' : '上册';
  final count = opts.readingCount;
  final words = _engVocabText(data, opts);

  // 根据年级确定听力材料难度
  String lengthDesc;
  String questionDesc;
  if (opts.grade <= 2) {
    lengthDesc = '20-40词，简单句子，日常用语';
    questionDesc = '2-3道选择题（每题3个选项）';
  } else if (opts.grade <= 4) {
    lengthDesc = '40-80词，简短对话或小故事';
    questionDesc = '3-4道选择题或判断题';
  } else {
    lengthDesc = '60-120词，稍长对话或短文';
    questionDesc = '4-5道选择题、判断题或填空题';
  }

  // 根据 narrationOnly 决定对话限制
  final dialogRule = narrationOnly
      ? '- 【重要】听力材料必须用第三人称叙述（如"Tom goes to school. He likes math."），绝对不要出现对话（禁止使用 says/asks/replies/answers 等对话动词，禁止冒号引号等对话格式）；\n'
        '- 【重要】不要出现任何人物之间的直接对话或间接对话，全程用叙述描述事件和场景。'
      : '- 听力材料可以用对话形式（如 "Hello!" "How are you?"）或叙述形式，贴近真实生活场景；\n'
        '- 如果使用对话，注意节奏感，让朗读时有自然停顿。';

  final enThemeTip = opts.theme.isNotEmpty
      ? '【主题语境】听力材料严格围绕 2022 课标主题语境「${opts.theme}」展开（人与自我/人与社会/人与自然）。\n'
      : '';
  final enTextTypeTip = opts.textType.isNotEmpty
      ? '【语篇类型】优先使用「${opts.textType}」（如歌谣、配图故事、说明文、应用文等）。\n'
      : '';
  final prompt = '你是中国小学英语听力出题专家。请为"${tb.name}${gname}${volName}"的学生生成$count篇英语听力材料：\n'
      '1. 每篇给出一段适合该年级的原创英文听力材料（$lengthDesc），用词尽量控制在下面该年级词汇范围内（词汇可作参考，允许少量延伸）：\n词汇：${words.isEmpty ? '（无）' : words}\n'
      '2. 听力材料类型：小故事、简单通知、描述性短文等，贴近学生生活；\n'
      '3. 每篇配$questionDesc（选择题给出A/B/C选项，判断题给出T/F），问题用中文提问；\n'
      '4. 听力材料与题目必须原创，不得照搬教材课文或常见题库原题；答案要准确。\n'
      '$enThemeTip$enTextTypeTip'
      '只输出一个 JSON 对象，不要输出任何其他文字：\n'
      '{"items":[{"title":"标题","text":"英文听力材料正文","questions":[{"q":"问题","options":["选项内容","选项内容","选项内容"],"a":"正确答案"}]}]}\n'
      '注意：\n'
      '- options字段只放纯选项内容（如"博物馆"），不要加"A."/"B."等字母前缀；\n'
      '- a字段为正确答案内容（如"A"或选项内容）；\n'
      '- 判断题不需要options字段，a字段为"T"或"F"；\n'
      '$dialogRule';
  final content = await AiClient.chat(cfg, [AiChatMessage('user', prompt)],
      jsonMode: true);
  final data2 = aiExtractJson(content);
  final items = data2['items'] is List ? data2['items'] as List : [];
  return [
    for (final it in items)
      if (it is Map && '${it['text'] ?? ''}'.trim().isNotEmpty)
        ReadingBlockData(
          title: '${it['title'] ?? '听力材料'}',
          text: '${it['text'] ?? ''}',
          en: true,
          isListening: true,
          questions: [
            for (final q in (it['questions'] as List? ?? []))
              if (q is Map)
                ReadingQuestion(
                  '${q['q'] ?? ''}',
                  '${q['a'] ?? ''}',
                  options: (q['options'] as List?)?.map((o) => '$o').toList(),
                )
          ],
        )
  ];
}
