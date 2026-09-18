import 'dart:convert';
import '../data/app_data.dart';
import '../core/scope_guard.dart';
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
  final readingNote = styleIds.contains('yuedu')
      ? '\n阅读理解题专项：每题必须同时给出问题(q)与答案(a)，答案(a)严禁留空且必须能从短文找到依据、直接回答该问题；问题须是通顺完整的疑问句，符合中文表达习惯，不可无厘头或牵强。'
      : '';
  final special = subject == 'chinese'
      ? '题目中的生字/词语**必须**限定在本册写字表范围内，不得使用范围外的生字（越界即为超纲，需重出）：\n本册生字表：${_gradeChineseChars(data, opts)}'
          '${styleIds.contains('zhengshu') ? '\n整本书阅读单：每题围绕下面推荐书目之一设计一份阅读探究单（含内容梳理、精彩语句赏析、主题/人物感悟等3-4个任务），题目(q)写书名与任务，答案(a)写简要指导。可参考书目：${_gradeBooks(data, opts)}' : ''}'
          '${styleIds.contains('kuaxueke') ? '\n跨学科学习：以语文为核心，融合科学、历史、艺术或生活实际设计综合任务，体现"在真实情境中运用语文"。' : ''}'
          '${styleIds.contains('practical') ? '\n实用性阅读与交流：设计贴近生活的应用文与实用交流任务，如写一则通知/留言条/请假条/书信/倡议书（注意格式：称呼、正文、署名、日期规范），或给一段说明书/图表/留言让学生提取关键信息并作答；培养"在生活中学语文、用语文"的能力，语言简明得体。' : ''}'
          : subject == 'english'
              ? '英文题目词汇**必须**限定在下面该年级词汇表内，不得使用表外单词（越界即为超纲，需重出）：\n本年级词汇表：${_gradeEnglishVocab(data, opts)}'
                  '${opts.theme.isNotEmpty ? '\n本题严格围绕 2022 课标主题语境「${opts.theme}」展开（人与自我：生活与学习、做人与做事；人与社会：社会服务与人际沟通、文学与文化；人与自然：自然生态、环境保护）。' : ''}'
                  '${opts.textType.isNotEmpty ? '\n语篇类型优先使用「${opts.textType}」（如歌谣、配图故事、说明文、应用文等），贴近该语篇的真实体裁。' : ''}'
                  '${styleIds.contains('culture') ? '\n文化意识：设计围绕中外节日、习俗、文明礼仪或文化对比的题目（如春节/中秋/生日习俗、问候礼仪、中西饮食习惯与餐具差异等），培养跨文化理解与文化自信，语言尽量简单地道。' : ''}'
                  '${styleIds.contains('think') ? '\n思维品质：设计培养逻辑思维与批判性思维的题，如根据线索推理、比较事物异同、判断正误并说明理由、就某个生活话题简单发表自己的看法；题目(q)给出情境与问题，答案(a)给出合理推理与你的理由。' : ''}'
                  '${styleIds.contains('learn') ? '\n学习能力：设计培养自主学习能力与学习策略的题，如制定单词背诵/朗读计划、用图片或词典辅助理解生词、读后自我检查与订正、记录并分享自己的学习方法；题目(q)给出学习情境与任务，答案(a)给出可操作的学习策略或计划示例。' : ''}'
          : '应用题要贴近生活，答案给出单位。\n'
              '本年级数学题型清单（**只能出这些类型，不得引入清单之外的题型或运算**）：${_gradeMathTopics(data, opts)}\n'
              '${_gradeMathScope(data, opts)}'
              '注重培养学生的"量感"（对数量、度量、单位的直观感知与合理估算）与"模型意识"（用数学语言描述现实、建立简单模型）；综合与实践题要结合真实情境。';

  return '你是中国$subjectCN教学出题专家。请为"${tb.name}$gname$volName"的学生出一套$diffText难度的作业，共$total题，题型分配如下：\n'
      '$styleLines\n\n'
      '要求：\n'
      '1. 题目必须新颖、灵活，注重"举一反三"，不得照搬教材例题、课本原题或常见题库里的固定题目；\n'
      '2. 难度要与$gname学生的水平匹配，严格贴合$gname的知识范围（生字/词汇/知识点不得超纲）；\n'
      '3. ${withAnswer ? "每题必须给出正确答案，计算与拼写必须准确。" : "只要题目，不要给出答案。"}\n'
      '4. $special$readingNote\n\n'
      '只输出一个 JSON 对象，格式严格如下，不要输出任何其他文字、不要用代码块包裹：\n'
      '${withAnswer ? '{"sections":[{"type":"题型名称","items":[{"q":"题目","a":"答案"}]}]}' : '{"sections":[{"type":"题型名称","items":[{"q":"题目"}]}]}'}';
}

/// 该年级语文写字表生字（用于约束 AI 生字/词语范围）
String _gradeChineseChars(AppData data, AiPromptOpts opts) {
  final list = data.vol(opts.version, opts.grade, opts.volume, 'cally')?.cally ?? [];
  // 不截断：范围给全，模型才有条件真正守住「不超纲」。旧实现只取 60 个字，
  // 范围外的生字反而被当成允许的。
  final chars = list.map((c) => c[0]).join('、');
  return chars.isEmpty ? '（无）' : chars;
}

/// 英语词汇范围文本（2022 课标对齐：三年级起使用 ENG_505 二级词表）
String _engVocabText(AppData data, AiPromptOpts opts) {
  if (opts.grade >= 3 && data.eng505.isNotEmpty) {
    return data.eng505.join('、');
  }
  final list = data.vol(opts.version, opts.grade, opts.volume, 'eng')?.eng ?? [];
  return list.map((w) => w[0]).join('、');
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

/// 从题型 id 推导「数值与运算范围」硬约束，用于防 AI 超纲。
///
/// 题型 id 本身是自描述的（add10 / add20 / add100 / add1000 / mul* / div* / dec* / frac*），
/// 所以可以从数据推导，不必手写一份课程表——手写的课程知识一旦有误反而更危险。
///
/// 只在 1-3 年级给出数值禁令：这三个年级的整数范围是教材明确划定的（20 / 100 / 万以内）
/// 且数域单一。四年级起大数、小数、分数交错，简单规则概括容易误伤，因此只依赖
/// 上面的「题型清单」约束，这里返回空串。
String _gradeMathScope(AppData data, AiPromptOpts opts) {
  if (opts.grade > 3) return '';
  final ids =
      (data.vol(opts.version, opts.grade, opts.volume, 'math')?.math ?? [])
          .map((t) => t.id)
          .toSet();
  if (ids.isEmpty) return '';
  bool has(String s) => ids.any((i) => i.contains(s));

  // 上限的推导与「生成后校验」共用 ScopeGuard.integerCeil，
  // 避免出现「提示词说 20、校验按 100」这种自相矛盾。
  final ceil = ScopeGuard.integerCeil(
    version: opts.version,
    grade: opts.grade,
    volume: opts.volume,
  );
  if (ceil == null) return '';

  final parts = <String>['整数运算限制在${_ceilText(ceil)}'];
  if (!has('mul') && !has('div')) {
    parts.add('不得出现乘法和除法');
  } else if (!has('div')) {
    parts.add('可含乘法，但不得出现除法');
  }
  if (!has('dec')) parts.add('不得出现小数');
  if (!has('frac')) parts.add('不得出现分数');
  return '数值与运算硬性约束（越界即为超纲，必须重出）：${parts.join('；')}。\n';
}

/// 上限的中文说法：10000 说成「万以内」，其余用数字
String _ceilText(int ceil) => ceil >= 10000 ? '万以内' : '$ceil 以内';

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
  const usableH = 860.0;
  var cur = <WsCard>[];
  var curH = 0.0;
  var curInstr = '';
  var curSid = '';
  var curSent = 0;
  var itemNo = 1;

  WsPageTitle pageTitle() => WsPageTitle(
        main: '$subjectCN作业 · AI 出题',
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
      '你是$subCN辅导老师。请用$gname学生能听懂的语言，分步骤讲解学生给出的题目（参考${tb.name}$gname$vol的知识水平）：\n'
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

/// 阅读题「问题/答案」硬性约束，拼接到各阅读 prompt 末尾，
/// 确保答案非空、且问题与答案严格对应、符合中文母语者表达习惯。
const String _kReadingQaRules = '''
【题目与答案的硬性要求（必须逐条遵守）】
1. 每道题必须同时给出「问题(q)」和「答案(a)」，二者缺一不可；答案(a)严禁为空。
2. 问题(q)必须是完整、通顺、符合中文母语者表达习惯的疑问句（以"？"结尾），考查点明确，不得无厘头、牵强或生造。
3. 答案(a)必须能从所给短文/课文中找到明确依据，是"直接回答该问题"的简短准确内容（词语、短语或一两句短句）；不要把问题原样抄进答案，不要在答案里复述整道题。
4. 问题与答案严格分离：问题里不要再写出答案；答案里只写答案本身。
5. 输出前逐项自检：①每道题的问题都能在短文中找到明确答案吗？②答案是直接、准确、符合中文表达习惯的吗？③有没有把答案混进问题里？''';

/// 解析单道阅读题：模型偶尔会把答案写进问题（"……？答案：xxx"），
/// 这里在 a 为空时尝试把答案从问题文本中拆出，避免答案整页缺失。
ReadingQuestion _parseReadingQuestion(Map q) {
  final rawQ = '${q['q'] ?? ''}'.trim();
  var answer = '${q['a'] ?? ''}'.trim();
  var question = rawQ;
  if (answer.isEmpty) {
    final m = RegExp(r'[？?]\s*(?:答案|答)\s*[：:]\s*(.+)$', dotAll: true)
        .firstMatch(rawQ);
    if (m != null) {
      answer = m.group(1)!.trim();
      final qMark = rawQ.lastIndexOf(RegExp(r'[？?]'));
      question = qMark >= 0 ? rawQ.substring(0, qMark + 1).trim() : rawQ;
    }
  }
  return ReadingQuestion(question, answer);
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

  // 取该版本·年级/册的课文目录（课文模式用其正文补全，原创模式忽略）
  final texts = data.yuwenTextsFor(opts.version, opts.grade, opts.volume);
  final sel = texts.take(count).toList();

  String prompt;
  if (opts.useTextbook) {
    final isEnglish = opts.version.startsWith('waiyan');
    final hasText = sel.any((t) => t.text.trim().isNotEmpty);
    if (!isEnglish) {
      if (hasText) {
        // 统编版：本地有完整正文，直接基于真实课文出题
        final passages = sel
            .map((t) => '【课文】${t.title}（${t.unit}）\n${t.text}')
            .join('\n\n');
        prompt = '你是中国小学语文出题专家。下面是从"${tb.name}$gname$volName"课本中选取的${sel.length}篇真实课文：\n\n'
            '$passages\n\n'
            '请基于上面提供的课文，为$gname学生生成阅读理解练习（每篇课文出 3-5 道理解题）：\n'
            '1. 题目必须紧扣所给课文内容，考查：按原文提取信息、概括主要内容、理解关键词句的意思与作用、体会文章表达的思想感情或道理；\n'
            '2. 适当加入"思维能力/思辨性阅读"类题目（如推断原因、评价人物做法、联系生活实际谈看法）；\n'
            '3. 每题给出准确答案；难度贴合$gname。\n'
            '$_kReadingQaRules\n'
            '只输出一个 JSON 对象，不要输出任何其他文字：\n'
            '{"items":[{"title":"课文标题","author":"作者/出处","text":"课文正文（可原样或略写）","questions":[{"q":"问题","a":"答案"}]}]}';
      } else {
        // A档目录（冀教/旧人教版等）：仅有篇目、无正文——要求 AI 据标题原创适龄短文（不内嵌版权文本）
        final titles = sel
            .map((t) => '【篇目】${t.title}（${t.unit}）')
            .join('\n');
        prompt = '你是中国小学语文出题专家。下面列出的是"${tb.name}$gname$volName"课本中的课文篇目（仅标题，不含原文）：\n\n'
            '$titles\n\n'
            '请为$gname学生生成阅读理解练习（每篇课文出 3-5 道理解题），要求：\n'
            '1. 必须原创、贴合该年级：请以每篇【篇目】标题/所属单元为主题，自主创作一篇 100-300 字、适龄、积极健康的原创短文作为阅读素材；严禁照搬、复述或引用任何教材原文、网络现有课文或受版权保护的具体文本；\n'
            '2. 题目紧扣你创作的短文内容，考查：按原文提取信息、概括主要内容、理解关键词句的意思与作用、体会文章表达的思想感情或道理；并适当加入"思维能力/思辨性阅读"类题目（如推断原因、评价人物做法、联系生活实际谈看法）；\n'
            '3. 每题给出准确答案；难度贴合$gname。\n'
            '$_kReadingQaRules\n'
            '只输出一个 JSON 对象，不要输出任何其他文字：\n'
            '{"items":[{"title":"课文标题","author":"作者/出处（如不知可留空）","text":"你创作的原创短文正文","questions":[{"q":"问题","a":"答案"}]}]}';
      }
    } else {
      // 外研（英语）A档：依据 Module/Unit 篇目，由 AI 原创适龄英文短文出题（不内嵌版权文本）
      final topics = hasText
          ? sel.map((t) => '【Lesson】${t.title}（${t.unit}）\n${t.text}').join('\n\n')
          : sel.map((t) => '【Lesson】${t.title}（${t.unit}）').join('\n');
      prompt = 'You are an English reading-comprehension expert for Chinese primary school students using the "$tb.name" textbook series. '
          'Below are lesson topics from "$tb.name $gname$volName" (${sel.length} lessons)${hasText ? ", with their text" : " (titles only, no original text)"}:\n\n'
          '$topics\n\n'
          'Generate English reading-comprehension exercises (3-5 questions per lesson):\n'
          '1. For each lesson, write an ORIGINAL, age-appropriate English passage (60-150 words) themed on that lesson title/unit. '
          '${hasText ? "You may adapt the provided text." : "Create original content."} Do NOT reproduce any copyrighted textbook text verbatim.\n'
          '2. Questions must test: literal comprehension, main idea, vocabulary/key expressions, and inference; include some thinking-skills questions (e.g. why / infer / give an opinion).\n'
          '3. Provide accurate answers; difficulty suited to $gname.\n'
          '[Strict q/a rules: every item MUST include both "q" and "a"; "a" must never be empty and must directly, accurately answer "q" using the passage; do NOT embed the answer inside "q"; use natural, age-appropriate English.]\n'
          'Output ONLY one JSON object, no other text:\n'
          '{"items":[{"title":"lesson title","author":"","text":"your original English passage","questions":[{"q":"question","a":"answer"}]}]}';
    }
  } else {
    prompt = '你是中国小学语文出题专家。请为"${tb.name}$gname$volName"的学生生成$count篇原创阅读理解练习：\n'
        '1. 每篇给一篇适合该年级的原创短文（100-300字，主题贴近儿童生活、科普或传统美德等），短文用字尽量控制在下面该年级生字范围（生字可作参考，允许少量延伸）：\n生字：${chars.isEmpty ? '（无）' : chars}\n'
        '2. 每篇配3-5道理解题，题型兼顾：按原文找信息、概括主要内容、体会关键语句的意思与作用、明白文章道理；并适当加入"思维能力/思辨性阅读"类题目（如推断原因、评价人物做法、联系生活谈看法），难度贴合$gname；\n'
        '3. 题目必须原创、新颖，不得照搬教材课文或常见题库原题；答案要准确。\n'
        '$_kReadingQaRules\n'
        '只输出一个 JSON 对象，不要输出任何其他文字：\n'
        '{"items":[{"title":"标题","author":"作者","text":"短文正文","questions":[{"q":"问题","a":"答案"}]}]}';
  }
  final content = await AiClient.chat(cfg, [AiChatMessage('user', prompt)],
      jsonMode: true);
  final data2 = aiExtractJson(content);
  final items = data2['items'] is List ? data2['items'] as List : [];
  // 课文模式下，若 AI 未回显正文（text 为空），用本地课文正文按标题补全，
  // 避免题块因 text 为空被整块丢弃（保持原 ReadingBlockData 形状与下游不变）。
  final srcByTitle = <String, String>{for (final t in sel) t.title: t.text};
  final out = <ReadingBlockData>[];
  for (final it in items) {
    if (it is! Map) continue;
    final aiText = '${it['text'] ?? ''}'.trim();
    final src = srcByTitle['${it['title'] ?? ''}'];
    final text = aiText.isNotEmpty
        ? aiText
        : (src?.trim().isNotEmpty == true ? src! : '');
    if (text.isEmpty) continue; // 既无 AI 正文也无本地课文，跳过（与原行为一致）
    out.add(ReadingBlockData(
      title: '${it['title'] ?? '短文'}',
      author: '${it['author'] ?? ''}',
      text: text,
      questions: [
        for (final q in (it['questions'] as List? ?? []))
          if (q is Map) _parseReadingQuestion(q)
      ],
    ));
  }
  return out;
}

/// 基于单篇语料正文生成阅读理解题（语料/课文阅读路径用）。
/// 关键约束：严格基于所给【原文】出题，不得改写、缩写、扩写或替换原文；
/// 答案必须能从给定原文中找到明确依据。用于为没有预置题目的语料条目（含内置课文摘要）补题。
Future<List<ReadingQuestion>> aiGenerateQuestionsForPassage({
  required String title,
  required String text,
  required int grade,
  int count = 3,
}) async {
  final cfg = await AiStore.load();
  if (cfg.base.isEmpty || cfg.model.isEmpty) {
    throw Exception('请先在顶部「AI 智能出题设置」中填写 API 地址和模型并保存。');
  }
  final data = AppData();
  final gname = data.gradeNames[grade] ?? '小学';
  final n = count.clamp(2, 5);
  final prompt = '你是中国小学语文出题专家。下面是一篇课文/短文原文（已完整给出，'
      '请勿改写、缩写、扩写或用你自己的话替换它）：\n\n'
      '【篇名】$title\n【原文】\n$text\n\n'
      '请严格基于上面的【原文】为$gname学生出$n道阅读理解题，要求：\n'
      '1. 题目必须能从给定原文中找到明确、唯一的答案；严禁凭空编造原文中没有的信息或事实；\n'
      '2. 考查角度覆盖：按原文提取信息、理解关键词句的意思与作用、概括主要内容或体会文章表达的意思/道理；\n'
      '3. 每题给出准确、简短的答案（词语、短语或一两句短句即可）。\n'
      '$_kReadingQaRules\n'
      '只输出一个 JSON 对象，不要输出任何其他文字：\n'
      '{"questions":[{"q":"问题","a":"答案"}]}';
  final content = await AiClient.chat(cfg, [AiChatMessage('user', prompt)],
      jsonMode: true);
  final j = aiExtractJson(content);
  final qs = j['questions'] is List ? j['questions'] as List : [];
  final out = <ReadingQuestion>[];
  for (final q in qs) {
    if (q is! Map) continue;
    final rq = _parseReadingQuestion(q);
    if (rq.q.isNotEmpty && rq.a.isNotEmpty) out.add(rq);
  }
  return out;
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
  final prompt = '你是中国小学英语出题专家。请为"${tb.name}$gname$volName"的学生生成$count篇英语阅读理解：\n'
      '1. 每篇给一篇适合该年级的原创英文短文（40-120词），用词尽量控制在下面该年级词汇范围内（词汇可作参考，允许少量延伸）：\n词汇：${words.isEmpty ? '（无）' : words}\n'
      '$enThemeTip$enTextTypeTip'
      '2. 每篇配3-5道理解题（用英文提问，如根据原文回答问题、判断正误等，可附中文提示），难度贴合$gname；\n'
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
  final prompt = '你是中国小学英语听力出题专家。请为"${tb.name}$gname$volName"的学生生成$count篇英语听力材料：\n'
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
