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
bool engTypeAllowed(String id, String ver, int grade) {
  if (id == 'listening') return !(ver == 'waiyanSQ' && grade < 3);
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

  int nFor(String t) =>
      opts.counts[t] == null ? (opts.count > 0 ? opts.count : 8) : (opts.counts[t] ?? 0).clamp(0, 60);
  bool enabled(String t) =>
      types.contains(t) && (opts.counts[t] == null || (opts.counts[t] ?? 0) > 0);
  final maxN = [opts.count, ...types.map(nFor)].reduce((a, b) => a > b ? a : b);
  final vocab = pickVocab(data, grade, maxN, ver, vol);

  final pages = <WsPage>[];

  if (enabled('alphabet')) {
    final blocks = buildAlphabet();
    final pg = chunkBlocks(blocks, 17);
    for (final b in pg) {
      pages.add(WsPage(
        title: opts.showTitle ? engTitleBar(opts) : null,
        nodes: [
          WsHeading('字母书写练习（先描后写）', engStyle: true),
          WsGrid(
            [for (final x in b) WsCard('eng', x)],
            cols: 2,
            evenly: true,
          ),
        ],
      ));
    }
  }

  if (enabled('trace')) {
    final blocks = <EngGridCardData>[];
    final n = nFor('trace');
    for (final pair in vocab.take(n)) {
      blocks.add(EngGridCardData('trace', EngCardData(type: 'trace', en: pair[0], cn: pair[1])));
    }
    for (final b in chunkBlocks(blocks, 10)) {
      pages.add(WsPage(
        title: opts.showTitle ? engTitleBar(opts) : null,
        nodes: [
          WsHeading('单词抄写（先描红，再自己写两遍）', engStyle: true),
          WsGrid(
            [for (final x in b) WsCard('eng', x)],
            cols: 2,
            evenly: true,
          ),
        ],
      ));
    }
  }

  if (enabled('match')) {
    final mVocab = vocab.take(nFor('match')).toList();
    final built = buildMatchingRows(mVocab);
    final rows = built.rows;
    final ansLines =
        opts.showAnswer ? buildMatchAnswer(mVocab, built.rightCn) : <String>[];
    for (final pg in chunkBlocks(rows, 15)) {
      pages.add(WsPage(
        title: opts.showTitle ? engTitleBar(opts) : null,
        nodes: [
          WsHeading('中英连线（把英文单词与正确的中文意思连起来）', engStyle: true),
          WsBlock(WsGridData(rows: pg)),
        ],
      ));
    }
    if (ansLines.isNotEmpty) {
      pages.add(WsPage(
        title: WsPageTitle(main: '连线题参考答案'),
        nodes: [WsMatchAnswer(ansLines)],
        noSpread: true,
      ));
    }
  }

  if (enabled('listening')) {
    final n = nFor('listening');
    final items = buildListeningItems(vocab, n, grade: grade);
    final blocks = <EngGridCardData>[
      for (final it in items)
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
    ];
    for (final pg in chunkBlocks(blocks, 6)) {
      pages.add(WsPage(
        title: opts.showTitle ? engTitleBar(opts) : null,
        nodes: [
          WsHeading('听力练习（听录音，选出你听到的单词的中文意思）', engStyle: true),
          WsGrid(
            [for (final x in pg) WsCard('eng', x)],
            cols: 1,
            evenly: true,
          ),
        ],
      ));
    }
    if (opts.showAnswer) {
      final lines = <String>[];
      for (final it in items) {
        final letter = String.fromCharCode(65 + it.answerIdx);
        lines.add('第${it.num}题：${it.en} → $letter. ${it.correctCn}');
      }
      pages.add(WsPage(
        title: WsPageTitle(main: '听力参考答案'),
        nodes: [WsMatchAnswer(lines)],
        noSpread: true,
      ));
    }
  }

  final qTypes = ['cn2en', 'en2cn', 'spell'].where(enabled).toList();
  final allowedQ = allowedEngTypes(ver, grade, qTypes);
  if (allowedQ.isNotEmpty) {
    final answerList = <(String, String)>[]; // key, ans
    for (final t in allowedQ) {
      final blocks = <EngGridCardData>[];
      for (final pair in vocab.take(nFor(t))) {
        blocks.add(EngGridCardData('word', wordQuestionBlock(pair[0], pair[1], t, answerList)));
      }
      if (blocks.isEmpty) continue;
      final labels = {
        'cn2en': '中译英（看中文，写出英文单词）',
        'en2cn': '英译中（写出单词的中文意思）',
        'spell': '单词拼写（补全单词中缺少的字母）',
      };
      for (final pg in chunkBlocks(blocks, 10)) {
        pages.add(WsPage(
          title: opts.showTitle ? engTitleBar(opts) : null,
          nodes: [
            WsHeading(labels[t] ?? '', engStyle: true),
            WsGrid(
              [for (final x in pg) WsCard('eng', x)],
              cols: 2,
              evenly: true,
            ),
          ],
        ));
      }
    }
    if (opts.showAnswer && answerList.isNotEmpty) {
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
List<ListeningItem> buildListeningItems(List<List<String>> vocab, int count,
    {int grade = 1}) {
  final rng = RandGen(grade: grade);
  final items = <ListeningItem>[];
  var n = 1;
  for (final pair in vocab.take(count)) {
    final en = pair[0];
    final cn = pair[1];
    // 干扰项：其他词的中文（去重）
    final distractors = <String>[];
    final shuffled = shuffleCopy(vocab);
    for (final p in shuffled) {
      if (p[1] == cn) continue;
      if (distractors.contains(p[1])) continue;
      distractors.add(p[1]);
      if (distractors.length >= 3) break;
    }
    while (distractors.length < 3) {
      distractors.add('其他选项${distractors.length + 1}');
    }
    final options = <String>[cn, ...distractors];
    // 洗牌得到最终选项，记录正确答案位置
    final order = rng.shuffle(List<int>.generate(4, (i) => i));
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

List<List<T>> chunkBlocks<T>(List<T> blocks, int capacity) {
  final pages = <List<T>>[];
  for (var i = 0; i < blocks.length; i += capacity) {
    pages.add(blocks.sublist(i, i + capacity > blocks.length ? blocks.length : i + capacity));
  }
  return pages;
}
