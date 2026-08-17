import '../data/app_data.dart';
import 'rand_gen.dart';
import 'worksheet_model.dart';

/// 语文作业选项
class ChineseOptions {
  final int grade;
  final String version;
  final String volume;
  final List<String> types;
  final Map<String, int> counts;
  final int count;
  final bool showAnswer;
  final bool showTitle;
  final List<ReadingBlockData>? aiReadingItems;

  ChineseOptions({
    this.grade = 1,
    this.version = 'renjiao',
    this.volume = '上',
    List<String>? types,
    Map<String, int>? counts,
    this.count = 12,
    this.showAnswer = true,
    this.showTitle = true,
    this.aiReadingItems,
  })  : types = types ?? [],
        counts = counts ?? {};
}

/// 语文题型指令
const CHINESE_INSTRUCTION = {
  'pinyin2char': '看拼音，在括号里写出相应的汉字。',
  'char2pinyin': '给下列汉字注上拼音。',
  'zuci': '照样子给生字组词，每个字组2-3个词语。',
  'gushiFill': '在下面空白处填入诗句，把古诗补充完整。',
  'chengyuFill': '在下面空白处填上正确的字，把成语补充完整。',
  'chengyuGuess': '根据给出的意思，写出相应的成语。',
  'mingjuFill': '在下面空白处填入句子，把名言名句补充完整。',
  'duanwen': '阅读下面的短文，回答问题。',
  'aiyuedu': '阅读下面的短文，回答问题。',
};

const CHINESE_TYPES_LABELS = {
  'pinyin2char': '看拼音写汉字',
  'char2pinyin': '汉字注拼音',
  'zuci': '生字组词',
  'gushiFill': '古诗名句填空',
  'chengyuFill': '成语填空',
  'chengyuGuess': '看意思写成语',
  'mingjuFill': '名言名句填空',
  'duanwen': '课文·阅读（外置语料）',
  'aiyuedu': '阅读理解（AI生成）',
};

/// 语文网格卡片数据
class CnCardData {
  final String type;
  // pinyin2char / char2pinyin / zuci
  final String ch;
  final String py;
  // gushiFill
  final String? gTitle;
  final String? gAuthor;
  final List<String>? segs;
  final int? blank;
  final String? answer;
  // chengyuFill / chengyuGuess
  final String? idiom;
  final String? meaning;
  final int? blankIdx;
  // mingjuFill
  final String? source;
  final bool pad;

  CnCardData({
    required this.type,
    this.ch = '',
    this.py = '',
    this.gTitle,
    this.gAuthor,
    this.segs,
    this.blank,
    this.answer,
    this.idiom,
    this.meaning,
    this.blankIdx,
    this.source,
    this.pad = false,
  });

  CnCardData.pad(this.type)
      : pad = true,
        ch = '',
        py = '',
        gTitle = null,
        gAuthor = null,
        segs = null,
        blank = null,
        answer = null,
        idiom = null,
        meaning = null,
        blankIdx = null,
        source = null;
}

/// 生成语文作业
List<WsPage> chineseRenderPages(ChineseOptions opts, {List<ReadingBlockData>? customCorpus}) {
  final data = AppData();
  final ver = opts.version;
  final vol = opts.volume;
  final grade = opts.grade;

  final types = opts.types.isNotEmpty ? opts.types : ['pinyin2char'];
  bool enabled(String t) =>
      types.contains(t) && (opts.counts[t] == null || (opts.counts[t] ?? 0) > 0);
  final wantReading = enabled('duanwen');
  final wantAIReading = enabled('aiyuedu');
  final gridTypes = types
      .where((t) => t != 'duanwen' && t != 'aiyuedu' && enabled(t))
      .toList();

  final rng = RandGen(grade: grade);
  final charPool =
      rng.shuffle(data.vol(ver, grade, vol, 'cally')?.cally ?? []);
  final gushiPool = rng.shuffle(data.corpusGushi[grade] ?? []);
  final chengyuPool = rng.shuffle(data.corpusChengyu[grade] ?? []);
  final mingjuPool = rng.shuffle(data.corpusMingju[grade] ?? []);

  final usedGlobal = <String>{};
  final usedGushiFull = <String>[];
  final usedMingjuText = <String>[];

  CnCardData? genOne(String t) {
    if (t == 'pinyin2char' || t == 'char2pinyin' || t == 'zuci') {
      for (final c in charPool) {
        if (c.isEmpty || c[0].isEmpty) continue;
        if (usedGlobal.contains('ch|${c[0]}')) continue;
        usedGlobal.add('ch|${c[0]}');
        return CnCardData(type: t, ch: c[0], py: c.length > 1 ? c[1] : '');
      }
      return null;
    }
    if (t == 'gushiFill') {
      for (final p in gushiPool) {
        if (usedGlobal.contains('gushi|${p.t}')) continue;
        if (usedMingjuText.any((txt) => p.full.contains(txt))) continue;
        usedGlobal.add('gushi|${p.t}');
        usedGushiFull.add(p.full);
        final segs = splitSegments(p.full);
        if (segs.isEmpty) return null;
        final idx = segs.length <= 1
            ? 0
            : 1 + rng.rand(0, segs.length - 2);
        return CnCardData(
          type: t,
          gTitle: p.t,
          gAuthor: p.a,
          segs: segs,
          blank: idx,
          answer: segs[idx],
        );
      }
      return null;
    }
    if (t == 'chengyuFill' || t == 'chengyuGuess') {
      for (final cy in chengyuPool) {
        if (usedGlobal.contains('cy|${cy.w}')) continue;
        usedGlobal.add('cy|${cy.w}');
        if (t == 'chengyuFill') {
          final bIdx = rng.rand(0, cy.w.length - 1);
          return CnCardData(
            type: t,
            idiom: cy.w,
            meaning: cy.m,
            blankIdx: bIdx,
            answer: cy.w[bIdx],
          );
        }
        return CnCardData(type: t, idiom: cy.w, meaning: cy.m, answer: cy.w);
      }
      return null;
    }
    if (t == 'mingjuFill') {
      for (final mj in mingjuPool) {
        if (usedGlobal.contains('mj|${mj.t}')) continue;
        if (usedGushiFull.any((full) => full.contains(mj.t))) continue;
        usedGlobal.add('mj|${mj.t}');
        usedMingjuText.add(mj.t);
        final segs = splitSegments(mj.t);
        if (segs.isEmpty) return null;
        return CnCardData(
          type: t,
          segs: segs,
          source: mj.s,
          blank: segs.length - 1,
          answer: segs[segs.length - 1],
        );
      }
      return null;
    }
    return null;
  }

  final fallbackPerType =
      gridTypes.isEmpty ? 0 : (opts.count / gridTypes.length).ceil();
  final sections = <(String, List<CnCardData>)>[];
  for (final t in gridTypes) {
    final perType = opts.counts[t] == null
        ? fallbackPerType
        : (opts.counts[t] ?? 0).clamp(0, 60);
    final items = <CnCardData>[];
    var guard = 0;
    while (items.length < perType && guard++ < 600) {
      final it = genOne(t);
      if (it != null) {
        items.add(it);
      } else {
        break;
      }
    }
    if (items.isNotEmpty) sections.add((t, items));
  }

  final pages = <WsPage>[];
  final usableH = 950.0;
  var curContent = <WsNode>[];
  var curH = 0.0;

  WsPageTitle cnTitle({required String main}) {
    final tb = data.textbooks[ver] ?? data.textbooks['renjiao']!;
    final gname = data.gradeNames[grade] ?? '第$grade年级';
    final volName = vol == '下' ? '下册' : '上册';
    return WsPageTitle(
      main: '$main · $gname · $volName',
      sub: '参考教材：${tb.cally}$gname$volName',
      meta1: '姓名：____________',
      meta2: '班级：____________',
      meta3: '日期：____________',
    );
  }

  void flush() {
    if (curContent.isNotEmpty) {
      pages.add(WsPage(
        title: opts.showTitle ? cnTitle(main: '语文作业') : null,
        nodes: curContent,
      ));
      curContent = [];
      curH = 0;
    }
  }

  for (final (type, items) in sections) {
    final instrH = 38.0;
    if (curContent.isNotEmpty && curH + instrH > usableH) flush();
    curContent.add(WsSection(CHINESE_INSTRUCTION[type] ?? '按要求做题。'));
    curH += instrH;

    final colFlow = type == 'chengyuGuess' || type == 'chengyuFill';
    final twoCol = type == 'gushiFill' || type == 'mingjuFill';
    final perRow = colFlow ? 1 : (twoCol ? 2 : 3);

    double rowH(String t) {
      if (t == 'gushiFill') return 156;
      if (t == 'mingjuFill') return 100;
      if (t == 'chengyuFill') return 132;
      if (t == 'zuci') return 146;
      if (t == 'chengyuGuess') return 116;
      return 132;
    }

    double colH(String t) {
      if (t == 'mingjuFill') return 100;
      if (t == 'chengyuFill') return 76;
      if (t == 'chengyuGuess') return 76;
      return 80;
    }

    final rh = (colFlow ? colH(type) : rowH(type)) + 10;
    var row = <CnCardData>[];
    for (final it in items) {
      if (row.isEmpty && curH + rh > usableH) flush();
      row.add(it);
      if (row.length == perRow) {
        curContent.add(WsGrid(
          [for (final c in row) WsCard('cn', c)],
          cols: perRow,
          evenly: false,
          itemHeight: rh,
        ));
        curH += rh;
        row = [];
      }
    }
    if (row.isNotEmpty) {
      while (row.length < perRow) row.add(CnCardData.pad(type));
      curContent.add(WsGrid(
        [for (final c in row) WsCard('cn', c)],
        cols: perRow,
        evenly: false,
        itemHeight: rh,
      ));
      curH += rh;
    }
  }
  flush();

  // 外置语料阅读
  if (wantReading) {
    final corpus = customCorpus ?? [];
    final readingItems = corpus
        .where((it) =>
            (it.grade == null || it.grade == grade) &&
            (it.volume == null || it.volume == vol))
        .toList();
    if (readingItems.isNotEmpty) {
      pages.addAll(renderReadingPages(readingItems, opts));
    } else {
      pages.add(WsPage(
        title: opts.showTitle ? cnTitle(main: '语文作业') : null,
        nodes: [
          WsPlaceholder('📂', '该年级暂无外置语料',
              '请先在「语文作业设置」中导入您拥有合法使用权的课文/阅读材料（格式见"查看示例格式"），并自行向版权方支付相应费用。'),
        ],
      ));
    }
  }

  // AI 阅读理解页
  if (wantAIReading) {
    final aiItems = opts.aiReadingItems;
    if (aiItems != null && aiItems.isNotEmpty) {
      pages.addAll(renderReadingPages(aiItems, opts));
      if (opts.showAnswer) {
        pages.addAll(renderReadingAnswerPage(aiItems, opts));
      }
    } else {
      pages.add(WsPage(
        title: opts.showTitle ? cnTitle(main: '语文作业') : null,
        nodes: [
          WsPlaceholder('🤖', '阅读理解 · AI 生成',
              '点击「生成预览」按钮，AI 将实时生成短文与理解题（需先在顶部「AI 智能出题设置」配置 API 并保存）。'),
        ],
      ));
    }
  }

  // 参考答案页
  if (opts.showAnswer && (sections.isNotEmpty || wantReading || wantAIReading)) {
    final nodes = <WsNode>[];
    nodes.add(WsHeading('参考答案'));
    var n = 1;
    for (final (type, items) in sections) {
      nodes.add(WsAnswerGroup(CHINESE_INSTRUCTION[type] ?? ''));
      for (final it in items) {
        nodes.add(WsAnswerLine(n++, qShort(it), '答：${ansText(it)}'));
      }
    }
    if (wantReading) {
      final corpus = customCorpus ?? [];
      final ri = corpus
          .where((it) =>
              (it.grade == null || it.grade == grade) &&
              (it.volume == null || it.volume == vol))
          .toList();
      for (final it in ri) {
        for (final q in it.questions) {
          nodes.add(WsAnswerLine(
              n++, '《${it.title}》 ${q.q}', '答：${q.a.isEmpty ? "—" : q.a}'));
        }
      }
    }
    if (wantAIReading && opts.aiReadingItems != null) {
      for (final it in opts.aiReadingItems!) {
        for (final q in it.questions) {
          nodes.add(WsAnswerLine(
              n++, '《${it.title}》 ${q.q}', '答：${q.a.isEmpty ? "—" : q.a}'));
        }
      }
    }
    pages.add(WsPage(
      title: WsPageTitle(main: '参考答案', meta1: '语文'),
      nodes: nodes,
      noSpread: true,
    ));
  }

  return pages;
}

/// 阅读题分页渲染
List<WsPage> renderReadingPages(List<ReadingBlockData> items, ChineseOptions opts) {
  final pages = <WsPage>[];
  var cur = <WsNode>[];
  var curH = 0.0;

  for (final it in items) {
    final h = 210 + (it.questions.length * 52).toDouble();
    if (cur.isNotEmpty && curH + h > 880) {
      pages.add(_readingPage(opts, cur));
      cur = [];
      curH = 0;
    }
    cur.add(WsBlock(it));
    curH += h;
  }
  if (cur.isNotEmpty) pages.add(_readingPage(opts, cur));
  return pages;
}

WsPage _readingPage(ChineseOptions opts, List<WsNode> nodes) {
  final data = AppData();
  final grade = opts.grade;
  final vol = opts.volume;
  final tb = data.textbooks[opts.version] ?? data.textbooks['renjiao']!;
  final gname = data.gradeNames[grade] ?? '第$grade年级';
  final volName = vol == '下' ? '下册' : '上册';
  final head = <WsNode>[
    WsSection('阅读下面的短文，回答问题。'),
    ...nodes,
  ];
  return WsPage(
    title: opts.showTitle
        ? WsPageTitle(
            main: '阅读理解 · $gname · $volName',
            sub: '参考教材：${tb.cally}$gname$volName',
            meta1: '姓名：____________',
            meta2: '班级：____________',
            meta3: '日期：____________',
          )
        : null,
    nodes: head,
  );
}

/// AI 阅读理解参考答案页
List<WsPage> renderReadingAnswerPage(
    List<ReadingBlockData> items, ChineseOptions opts) {
  final data = AppData();
  final grade = opts.grade;
  final vol = opts.volume;
  final gname = data.gradeNames[grade] ?? '第$grade年级';
  final nodes = <WsNode>[];
  nodes.add(WsHeading('参考答案'));
  var n = 1;
  for (final it in items) {
    for (final q in it.questions) {
      nodes.add(WsAnswerLine(
          n++, '《${it.title}》 ${q.q}', '答：${q.a.isEmpty ? "—" : q.a}'));
    }
  }
  return [
    WsPage(
      title: WsPageTitle(
          main: '参考答案',
          meta1: '阅读理解 · $gname · ${vol == '下' ? '下册' : '上册'}'),
      nodes: nodes,
      noSpread: true,
    ),
  ];
}

/// 按句切分（保留标点）
List<String> splitSegments(String text) {
  final reg = RegExp(r'[^，。；？！、]+[，。；？！、]?');
  final segs = reg
      .allMatches(text)
      .map((m) => m.group(0)!.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  return segs;
}

String ansText(CnCardData it) {
  switch (it.type) {
    case 'pinyin2char':
      return it.ch;
    case 'char2pinyin':
      return it.py;
    case 'zuci':
      return '开放题（写出2-3个词语）';
    case 'gushiFill':
      return it.answer ?? '';
    case 'chengyuFill':
      return it.answer ?? '';
    case 'chengyuGuess':
      return it.idiom ?? '';
    case 'mingjuFill':
      return it.answer ?? '';
    default:
      return '';
  }
}

String qShort(CnCardData it) {
  switch (it.type) {
    case 'pinyin2char':
      return it.py;
    case 'char2pinyin':
      return it.ch;
    case 'zuci':
      return it.ch;
    case 'gushiFill':
      return '${it.gTitle}（${it.gAuthor}）';
    case 'chengyuFill':
      return '${it.idiom}（填字）';
    case 'chengyuGuess':
      return '看意思写成语';
    case 'mingjuFill':
      return it.source ?? '';
    default:
      return '';
  }
}
