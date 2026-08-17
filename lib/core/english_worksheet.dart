import '../data/app_data.dart';
import 'rand_gen.dart';
import 'worksheet_model.dart';

/// 英语作业选项
class EnglishOptions {
  final int grade;
  final String version;
  final String volume;
  final List<String> types;
  final Map<String, int> counts;
  final int count;
  final bool showAnswer;
  final bool showTitle;
  final List<ReadingBlockData>? aiReadingItems;
  final List<ReadingBlockData>? aiListeningItems;

  EnglishOptions({
    this.grade = 1,
    this.version = 'renjiao',
    this.volume = '上',
    List<String>? types,
    Map<String, int>? counts,
    this.count = 8,
    this.showAnswer = true,
    this.showTitle = true,
    this.aiReadingItems,
    this.aiListeningItems,
  })  : types = types ?? [],
        counts = counts ?? {};
}

const ENG_TYPE_LABELS = {
  'alphabet': '字母书写练习',
  'trace': '单词抄写',
  'match': '中英连线',
  'cn2en': '中译英',
  'en2cn': '英译中',
  'spell': '单词拼写',
  'listening': '听力练习（AI配音）',
  'aiyuedu': '阅读理解（AI生成）',
  'ailistening': '听力短文（AI生成）',
};

/// 英语卡片数据
class EngCardData {
  final String type;
  final String en;
  final String cn;
  // match 连线
  final String? matchNum; // 右列字母编号
  final int? rightIdx;
  // spell
  final String? shown; // 带空白的单词
  final String? missing;
  // listening 听力
  final List<String>? options; // 中文选项
  final int? answerIdx; // 正确选项下标
  final String? readText; // 朗读文本（按年级分级）
  // alphabet
  final bool alphabet;

  EngCardData({
    required this.type,
    this.en = '',
    this.cn = '',
    this.matchNum,
    this.rightIdx,
    this.shown,
    this.missing,
    this.options,
    this.answerIdx,
    this.readText,
    this.alphabet = false,
  });
}

/// 英语网格卡片（letter / trace / wordQuestion）
class EngGridCardData {
  final String kind; // letter / trace / word
  final EngCardData data;
  EngGridCardData(this.kind, this.data);
}

List<String> defaultEngTypes(int grade) {
  if (grade == 1) return ['alphabet', 'trace'];
  return ['trace', 'match'];
}

/// 题型是否对当前版本+年级可用
/// spell（单词拼写）需要学生已具备拼写能力：
/// - 外研三起点：3-4 年级黑体词为「三会」（听、说、读），5-6 年级才要求「四会」（听写拼写）；
/// - 其余版本（人教/冀教/一起点）：三年级起要求拼写（低年级以字母、描红、抄写为主）。
/// listening（听力）：外研三起点三年级才学英语，仅 3-6 年级开放；其余版本 1-6 年级均可。
/// ailistening（听力短文）：需要一定听力理解能力，3-6 年级开放。
bool engTypeAllowed(String id, String ver, int grade) {
  if (id == 'listening') return !(ver == 'waiyanSQ' && grade < 3);
  if (id == 'ailistening') return grade >= 3;
  if (id != 'spell') return true;
  if (ver == 'waiyanSQ') return grade >= 5;
  return grade >= 3;
}

/// 过滤出对当前版本+年级可用的题型（与面板一致）
List<String> allowedEngTypes(String ver, int grade, List<String> ids) {
  final data = AppData();
  return ids.where((id) {
    final r = data.engTypeGrades[id];
    final inRange = r == null || (grade >= r[0] && grade <= r[1]);
    return inRange && engTypeAllowed(id, ver, grade);
  }).toList();
}

List<WsPage> englishRenderPages(EnglishOptions opts) {
  final data = AppData();
  final grade = opts.grade;
  final ver = opts.version;
  final vol = opts.volume;
  final types = opts.types.isNotEmpty ? opts.types : defaultEngTypes(grade);
  // 未显式传题型（如单测/外部调用）→ 使用默认题型并按默认题量输出
  final defaulted = opts.types.isEmpty;
  // 题型可用性必须同时满足：当前版本+年级允许（教材要求）、且已勾选（显式题量>0）
  final allowed = allowedEngTypes(ver, grade, types).toSet();

  int nFor(String t) =>
      opts.counts[t] == null ? (opts.count > 0 ? opts.count : 8) : (opts.counts[t] ?? 0).clamp(0, 60);
  bool enabled(String t) =>
      allowed.contains(t) && (defaulted || (opts.counts[t] ?? 0) > 0);

  // 计算各题型需要的单词数量，确保不同题型使用不同单词
  final traceN = enabled('trace') ? nFor('trace') : 0;
  final matchN = enabled('match') ? nFor('match') : 0;
  final listeningN = enabled('listening') ? nFor('listening') : 0;
  final qTypes = ['cn2en', 'en2cn', 'spell'].where(enabled).toList();
  final qN = qTypes.isNotEmpty ? nFor(qTypes.first) : 0;
  final totalN = traceN + matchN + listeningN + qN;
  final allVocab = pickVocab(data, grade, totalN, ver, vol);

  // 为每个题型分配不同的单词子集，避免答案泄露
  var offset = 0;
  final traceVocab = traceN > 0 ? allVocab.sublist(offset, offset + traceN) : <List<String>>[];
  offset += traceN;
  final matchVocabList = matchN > 0 ? allVocab.sublist(offset, offset + matchN) : <List<String>>[];
  offset += matchN;
  final listeningVocab = listeningN > 0 ? allVocab.sublist(offset, offset + listeningN) : <List<String>>[];
  offset += listeningN;
  final questionVocab = qN > 0 ? allVocab.sublist(offset, offset + qN) : <List<String>>[];

  // 各题型排版分节（多题型同页紧凑排布，避免每题型独占一页浪费纸张）
  final sections = <_EngSection>[];
  List<List<String>>? matchVocab;
  List<List<String>>? matchRightCn;
  List<ListeningItem>? listeningItems;
  final answerList = <(String, String)>[]; // key, ans

  if (enabled('alphabet')) {
    sections.add(_EngSection(
      heading: '字母书写练习（先描后写）',
      rows: _pairRows(buildAlphabet(), 2),
      cols: 2,
      rowH: _engRowH('letter'),
    ));
  }

  if (enabled('trace')) {
    final cards = <EngGridCardData>[
      for (final pair in traceVocab)
        EngGridCardData('trace', EngCardData(type: 'trace', en: pair[0], cn: pair[1])),
    ];
    sections.add(_EngSection(
      heading: '单词抄写（先描红，再自己写两遍）',
      rows: _pairRows(cards, 2),
      cols: 2,
      rowH: _engRowH('trace'),
    ));
  }

  if (enabled('match') && matchVocabList.isNotEmpty) {
    matchVocab = matchVocabList;
    final built = buildMatchingRows(matchVocab!);
    matchRightCn = built.rightCn;
    sections.add(_EngSection(
      heading: '中英连线（把英文单词与正确的中文意思连起来）',
      rows: [for (final r in built.rows) [r]],
      block: true,
      rowH: _engRowH('match'),
    ));
  }

  if (enabled('listening') && listeningVocab.isNotEmpty) {
    // 获取整个年级的词汇库（包括上册和下册），用于补充干扰项
    final allGradeVocab = <List<String>>[];
    for (final v in ['上', '下']) {
      final volData = data.vol(ver, grade, v, 'eng');
      if (volData?.eng != null) {
        allGradeVocab.addAll(volData!.eng!);
      }
    }
    final items = buildListeningItems(listeningVocab, nFor('listening'),
        grade: grade, allGradeVocab: allGradeVocab);
    listeningItems = items;
    sections.add(_EngSection(
      heading: '听力练习（听录音，选出你听到的单词的中文意思）',
      rows: [
        for (final it in items)
          [
            EngGridCardData(
              'word',
              EngCardData(
                type: 'listening',
                en: it.en,
                cn: it.correctCn,
                options: it.options,
                answerIdx: it.answerIdx,
                readText: it.readText,
              ),
            ),
          ],
      ],
      cols: 1,
      rowH: _engRowH('listening'),
    ));
  }

  const qLabels = {
    'cn2en': '中译英（看中文，写出英文单词）',
    'en2cn': '英译中（写出单词的中文意思）',
    'spell': '单词拼写（补全单词中缺少的字母）',
  };
  final allowedQ = allowedEngTypes(
      ver, grade, qTypes);
  for (final t in allowedQ) {
    final cards = <EngGridCardData>[];
    for (final pair in questionVocab) {
      cards.add(EngGridCardData('word', wordQuestionBlock(pair[0], pair[1], t, answerList)));
    }
    if (cards.isEmpty) continue;
    sections.add(_EngSection(
      heading: qLabels[t] ?? '',
      rows: _pairRows(cards, 2),
      cols: 2,
      rowH: _engRowH(t),
    ));
  }

  final pages = _packEngSections(sections, opts);

  if (opts.showAnswer) {
    if (matchVocab != null && matchRightCn != null) {
      final ansLines = buildMatchAnswer(matchVocab, matchRightCn);
      if (ansLines.isNotEmpty) {
        pages.add(WsPage(
          title: WsPageTitle(main: '连线题参考答案'),
          nodes: [WsMatchAnswer(ansLines)],
          noSpread: true,
        ));
      }
    }
    if (listeningItems != null) {
      final lines = <String>[];
      for (final it in listeningItems) {
        final letter = String.fromCharCode(65 + it.answerIdx);
        lines.add('第${it.num}题：${it.en} → $letter. ${it.correctCn}');
      }
      pages.add(WsPage(
        title: WsPageTitle(main: '听力参考答案'),
        nodes: [WsMatchAnswer(lines)],
        noSpread: true,
      ));
    }
    if (answerList.isNotEmpty) {
      final lines = <String>[];
      for (var i = 0; i < answerList.length; i++) {
        lines.add('${i + 1}. ${answerList[i].$1} → ${answerList[i].$2}');
      }
      pages.add(WsPage(
        title: WsPageTitle(main: '参考答案'),
        nodes: [WsMatchAnswer(lines)],
        noSpread: true,
      ));
    }
  }

  // AI 阅读理解
  if (enabled('aiyuedu')) {
    final aiItems = opts.aiReadingItems;
    if (aiItems != null && aiItems.isNotEmpty) {
      pages.addAll(renderENReadingPages(aiItems, opts));
      if (opts.showAnswer) pages.addAll(renderENReadingAnswer(aiItems, opts));
    } else {
      pages.add(WsPage(
        title: opts.showTitle ? engTitleBar(opts) : null,
        nodes: [
          WsPlaceholder('🤖', '阅读理解 · AI 生成（英文）',
              '点击「生成预览」按钮，AI 将实时生成英文短文与理解题（需先在顶部「AI 智能出题设置」配置 API 并保存）。'),
        ],
      ));
    }
  }

  // AI 听力短文
  if (enabled('ailistening')) {
    final aiListeningItems = opts.aiListeningItems;
    if (aiListeningItems != null && aiListeningItems.isNotEmpty) {
      pages.addAll(renderENListeningPages(aiListeningItems, opts));
      if (opts.showAnswer) pages.addAll(renderENListeningAnswer(aiListeningItems, opts));
    } else {
      pages.add(WsPage(
        title: opts.showTitle ? engTitleBar(opts) : null,
        nodes: [
          WsPlaceholder('🎧', '听力短文 · AI 生成（英文）',
              '点击「生成预览」按钮，AI 将实时生成英文听力材料与理解题（需先在顶部「AI 智能出题设置」配置 API 并保存）。'),
        ],
      ));
    }
  }

  return pages;
}

List<WsPage> renderENReadingPages(List<ReadingBlockData> items, EnglishOptions opts) {
  final pages = <WsPage>[];
  var cur = <WsNode>[];
  var curH = 0.0;
  for (final it in items) {
    final en = ReadingBlockData(
      title: it.title,
      text: it.text,
      en: true,
      questions: it.questions,
    );
    final h = 200 + (it.questions.length * 52).toDouble();
    if (cur.isNotEmpty && curH + h > 880) {
      pages.add(_enReadingPage(opts, cur));
      cur = [];
      curH = 0;
    }
    cur.add(WsBlock(en));
    curH += h;
  }
  if (cur.isNotEmpty) pages.add(_enReadingPage(opts, cur));
  return pages;
}

WsPage _enReadingPage(EnglishOptions opts, List<WsNode> nodes) {
  return WsPage(
    title: opts.showTitle ? engTitleBar(opts) : null,
    nodes: [
      WsSection('Read the passage and answer the questions.（阅读短文，回答问题。）'),
      ...nodes,
    ],
  );
}

List<WsPage> renderENReadingAnswer(List<ReadingBlockData> items, EnglishOptions opts) {
  final nodes = <WsNode>[];
  nodes.add(WsHeading('参考答案'));
  var n = 1;
  for (final it in items) {
    for (final q in it.questions) {
      nodes.add(WsAnswerLine(n++, '${it.title} · ${q.q}', '答：${q.a.isEmpty ? "—" : q.a}'));
    }
  }
  return [
    WsPage(title: WsPageTitle(main: '参考答案'), nodes: nodes, noSpread: true),
  ];
}

List<WsPage> renderENListeningPages(List<ReadingBlockData> items, EnglishOptions opts) {
  final pages = <WsPage>[];
  var cur = <WsNode>[];
  var curH = 0.0;
  for (final it in items) {
    final en = ReadingBlockData(
      title: it.title,
      text: it.text,
      en: true,
      isListening: true,
      questions: it.questions,
    );
    final h = 200 + (it.questions.length * 52).toDouble();
    if (cur.isNotEmpty && curH + h > 880) {
      pages.add(_enListeningPage(opts, cur));
      cur = [];
      curH = 0;
    }
    cur.add(WsBlock(en));
    curH += h;
  }
  if (cur.isNotEmpty) pages.add(_enListeningPage(opts, cur));
  return pages;
}

WsPage _enListeningPage(EnglishOptions opts, List<WsNode> nodes) {
  return WsPage(
    title: opts.showTitle ? engTitleBar(opts) : null,
    nodes: [
      WsSection('Listen to the passage and answer the questions.（听录音，回答问题。）'),
      ...nodes,
    ],
  );
}

List<WsPage> renderENListeningAnswer(List<ReadingBlockData> items, EnglishOptions opts) {
  final nodes = <WsNode>[];
  nodes.add(WsHeading('听力参考答案'));
  var n = 1;
  for (final it in items) {
    for (final q in it.questions) {
      nodes.add(WsAnswerLine(n++, '${it.title} · ${q.q}', '答：${q.a.isEmpty ? "—" : q.a}'));
    }
  }
  return [
    WsPage(title: WsPageTitle(main: '听力参考答案'), nodes: nodes, noSpread: true),
  ];
}

/// 空白单词（spell）
({String shown, String missing}) blankWord(String word, RandGen rng) {
  final chars = word.split('');
  final n = (chars.length / 4).floor().clamp(1, 2);
  final idxs = <int>{};
  var guard = 0;
  while (idxs.length < n && guard++ < 50) {
    final i = rng.rand(1, chars.length - 1);
    idxs.add(i);
  }
  final sorted = idxs.toList()..sort((a, b) => b - a);
  final shown = List<String>.from(chars);
  for (final i in sorted) {
    shown[i] = '＿';
  }
  final missing = sorted.map((i) => chars[i]).join();
  return (shown: shown.join(), missing: missing);
}

EngCardData wordQuestionBlock(String en, String cn, String type, List<(String, String)> answerList) {
  final rng = RandGen();
  if (type == 'cn2en') {
    answerList.add(('中译英：$cn', en));
    return EngCardData(type: type, en: en, cn: cn);
  } else if (type == 'en2cn') {
    answerList.add(('英译中：$en', cn));
    return EngCardData(type: type, en: en, cn: cn);
  } else {
    final b = blankWord(en, rng);
    answerList.add(('拼写：$cn', b.missing));
    return EngCardData(type: type, en: en, cn: cn, shown: b.shown, missing: b.missing);
  }
}

List<EngGridCardData> buildAlphabet() {
  final blocks = <EngGridCardData>[];
  for (var i = 0; i < 26; i++) {
    final upper = String.fromCharCode(65 + i);
    final lower = String.fromCharCode(97 + i);
    blocks.add(EngGridCardData('letter', EngCardData(type: 'alphabet', alphabet: true, en: '$upper$lower')));
  }
  return blocks;
}

class WsGridData {
  final List<EngGridCardData> rows;
  WsGridData({required this.rows});
}

/// 连线题结果：rows 为渲染行，rightCn 为右列中文选项顺序（答案须基于同一顺序）
class MatchBuildResult {
  final List<EngGridCardData> rows;
  final List<List<String>> rightCn;
  MatchBuildResult(this.rows, this.rightCn);
}

MatchBuildResult buildMatchingRows(List<List<String>> vocab) {
  final rightCn = shuffleCopy(vocab);
  final letters = 'abcdefghijklmnopqrstuvwxyz';
  final rows = <EngGridCardData>[];
  for (var i = 0; i < vocab.length; i++) {
    rows.add(EngGridCardData(
      'match',
      EngCardData(
        type: 'match',
        en: vocab[i][0],
        cn: rightCn[i][1],
        matchNum: letters[i],
        rightIdx: i,
      ),
    ));
  }
  return MatchBuildResult(rows, rightCn);
}

/// 连线题答案：基于与题目相同的 rightCn 顺序生成
List<String> buildMatchAnswer(List<List<String>> vocab, List<List<String>> rightCn) {
  final letters = 'abcdefghijklmnopqrstuvwxyz';
  final lines = <String>[];
  for (var i = 0; i < vocab.length; i++) {
    // 左列第 i 行英文 vocab[i]，其释义 vocab[i][1] 在右列中的位置 → 标号
    final idx = rightCn.indexWhere((p) => p[1] == vocab[i][1]);
    final letter = idx >= 0 ? letters[idx] : '?';
    lines.add('${i + 1}. ${vocab[i][0]} → $letter. ${vocab[i][1]}');
  }
  return lines;
}

List<List<String>> pickVocab(AppData data, int grade, int count, String ver, String vol) {
  final list = data.vol(ver, grade, vol, 'eng')?.eng ?? [];
  final shuffled = shuffleCopy(list);
  return shuffled.take(count < shuffled.length ? count : shuffled.length).toList();
}

/// 听力题：听英文，选中文意思
class ListeningItem {
  final int num;
  final String en; // 录音文本（朗读的英文）
  final String readText; // 实际朗读内容（按年级分级）
  final String correctCn; // 正确答案中文
  final List<String> options; // 4 个中文选项（含正确）
  final int answerIdx; // 正确选项下标（0-3）
  ListeningItem({
    required this.num,
    required this.en,
    required this.readText,
    required this.correctCn,
    required this.options,
    required this.answerIdx,
  });
}

/// 生成听力题：每词 1 题，4 个中文选项（正确 + 3 干扰项）
/// 朗读内容按年级分级：
/// - 1-2 年级：直接朗读单词（听音选义）
/// - 3-4 年级：朗读 "It's a/an ..." 短句（听句辨词）
/// - 5-6 年级：朗读 "Number N. I have a ..." 情景句（听情景选词）
/// [allGradeVocab] 为整个年级的词汇库（用于补充干扰项）
List<ListeningItem> buildListeningItems(List<List<String>> vocab, int count,
    {int grade = 1, List<List<String>>? allGradeVocab}) {
  final rng = RandGen(grade: grade);
  final items = <ListeningItem>[];
  var n = 1;
  for (final pair in vocab.take(count)) {
    final en = pair[0];
    final cn = pair[1];
    // 干扰项：优先从当前题目词汇中选取，不足时从整个年级词汇库中补充
    final distractors = <String>[];
    final shuffled = shuffleCopy(vocab);
    for (final p in shuffled) {
      if (p[1] == cn) continue;
      if (distractors.contains(p[1])) continue;
      distractors.add(p[1]);
      if (distractors.length >= 3) break;
    }
    // 如果当前题目词汇不足，从整个年级词汇库中补充干扰项
    if (distractors.length < 3 && allGradeVocab != null) {
      final allShuffled = shuffleCopy(allGradeVocab);
      for (final p in allShuffled) {
        if (p[1] == cn) continue;
        if (distractors.contains(p[1])) continue;
        distractors.add(p[1]);
        if (distractors.length >= 3) break;
      }
    }
    // 如果仍然不足，动态调整选项数量
    final optionCount = 1 + distractors.length;
    final options = <String>[cn, ...distractors];
    // 洗牌得到最终选项，记录正确答案位置
    final order = rng.shuffle(List<int>.generate(optionCount, (i) => i));
    final finalOpts = <String>[for (final i in order) options[i]];
    final correctPos = order.indexOf(0);
    // 朗读文本按年级分级
    final readText = _readTextFor(grade, n, en);
    items.add(ListeningItem(
      num: n++,
      en: en,
      readText: readText,
      correctCn: cn,
      options: finalOpts,
      answerIdx: correctPos,
    ));
  }
  return items;
}

String _readTextFor(int grade, int num, String en) {
  if (grade <= 2) return 'Number $num. $en.';
  if (grade <= 4) {
    final a = _startsWithVowel(en) ? 'an' : 'a';
    return 'Number $num. It is $a $en.';
  }
  return 'Number $num. I can see $en in the picture.';
}

bool _startsWithVowel(String s) {
  if (s.isEmpty) return false;
  final c = s.toLowerCase().substring(0, 1);
  return 'aeiou'.contains(c);
}

/// 听力配音文本：返回「第n题：en. 选项A...」逐行文本（用于 TTS 生成音频）
String listeningNarration(List<ListeningItem> items) {
  final buf = StringBuffer();
  for (final it in items) {
    buf.writeln('Number ${it.num}. ${it.en}.');
  }
  return buf.toString();
}

WsPageTitle? engTitleBar(EnglishOptions opts) {
  final data = AppData();
  final tb = data.textbooks[opts.version] ?? data.textbooks['renjiao']!;
  final gname = data.gradeNames[opts.grade] ?? '第${opts.grade}年级';
  final volName = opts.volume == '下' ? '下册' : '上册';
  return WsPageTitle(
    main: '英语练习 · $gname · $volName',
    sub: '参考教材：${tb.eng} $gname$volName',
    meta1: '姓名：____________',
    meta2: '班级：____________',
    meta3: '日期：____________',
  );
}

/// 英语排版分节：一个题型（含标题 + 若干行卡片）
class _EngSection {
  final String heading;
  final List<List<EngGridCardData>> rows; // 每元素 = 一行（cols 个卡片，或 block 一整行）
  final int cols;
  final bool block; // 连线题：整行块（WsBlock/WsGridData）
  final double rowH; // 预估行高（px）
  _EngSection({
    required this.heading,
    required this.rows,
    this.cols = 2,
    this.block = false,
    required this.rowH,
  });
}

/// 按预估行高取各题型单行高度（估高偏保守，避免内容超 A4 被裁剪）
double _engRowH(String t) {
  switch (t) {
    case 'letter':
      return 90;
    case 'trace':
      return 134;
    case 'cn2en':
      return 94;
    case 'en2cn':
      return 70;
    case 'spell':
      return 86;
    case 'listening':
      return 140;
    case 'match':
      return 62;
  }
  return 100;
}

/// 把卡片按列数两两成行
List<List<EngGridCardData>> _pairRows(List<EngGridCardData> cards, int cols) {
  final rows = <List<EngGridCardData>>[];
  for (var i = 0; i < cards.length; i += cols) {
    rows.add(cards.sublist(i, i + cols > cards.length ? cards.length : i + cols));
  }
  return rows;
}

WsNode _engNodeFor(_EngSection sec, List<List<EngGridCardData>> subRows) {
  if (sec.block) {
    return WsBlock(WsGridData(rows: [for (final r in subRows) r.first]));
  }
  return WsGrid(
    [for (final r in subRows) for (final c in r) WsCard('eng', c)],
    cols: sec.cols,
    evenly: true,
  );
}

// A4 (1123px) 减去上下留白与标题栏后的可用内容高度；行高与间距均为保守预估
const _engPageContent = 920.0;
const _engHeadingH = 36.0;
const _engRowGap = 8.0;

/// 把多个题型按预估高度紧凑排进 A4 页面（同页可混排多个题型，节省纸张）
List<WsPage> _packEngSections(List<_EngSection> sections, EnglishOptions opts) {
  final pages = <WsPage>[];
  var nodes = <WsNode>[];
  var used = 0.0;
  String? curHeading;

  void flush() {
    if (nodes.isEmpty) return;
    pages.add(WsPage(
      title: opts.showTitle ? engTitleBar(opts) : null,
      nodes: nodes,
    ));
    nodes = [];
    used = 0;
    curHeading = null;
  }

  for (final sec in sections) {
    var gridRows = <List<EngGridCardData>>[];
    for (final row in sec.rows) {
      final rh = sec.rowH + _engRowGap;
      final needHeading = curHeading != sec.heading;
      if (nodes.isNotEmpty &&
          used + (needHeading ? _engHeadingH : 0) + rh > _engPageContent) {
        // 当前页放不下：先收拢本节的格子，再另起一页
        if (gridRows.isNotEmpty) {
          nodes.add(_engNodeFor(sec, gridRows));
          gridRows = [];
        }
        flush();
      }
      if (curHeading != sec.heading) {
        nodes.add(WsHeading(sec.heading, engStyle: true));
        used += _engHeadingH;
        curHeading = sec.heading;
      }
      gridRows.add(row);
      used += rh;
    }
    if (gridRows.isNotEmpty) {
      nodes.add(_engNodeFor(sec, gridRows));
      gridRows = [];
      curHeading = null;
    }
  }
  flush();
  return pages;
}
