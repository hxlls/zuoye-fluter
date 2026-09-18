import '../data/app_data.dart';

/// 一条待检查的题目。
class ScopeItem {
  /// 题型 id（数学题型 id / 语文题型 id），决定这条题按什么规则检查。
  final String typeId;

  /// 题干（可含答案）
  final String text;

  const ScopeItem(this.typeId, this.text);
}

/// 生成后的超纲检查。
///
/// 为什么需要：出题有两条路径，防护强度差别很大。
/// - 本地生成是**硬约束**：题型由 CONTENT[版本][年级][册] 决定、语料按年级分桶、
///   数值按年级分档、词汇三年级起才用 505 课标词表。结构性防住，不需要额外检查。
/// - AI 生成是**软约束**：只能靠提示词，模型可能不听。这里是唯一能真正兜住它的机制。
///
/// 设计原则：**只检查能可靠判定的东西，宁可漏报不要误报**——
/// 误报会让老师对整套工具失去信任，比漏报更糟。
///
/// 因此**英语词汇不做检查**：ENG_505 是 headword 形式（`a/an`、`be (am, is, are)`），
/// 功能词 is / the / my 都不在表内，逐词比对会产生大量误报。
class ScopeGuard {
  ScopeGuard._();

  static final RegExp _num = RegExp(r'\d+');

  /// 数字前若是这些字，说明它是引用而非题目数值（第3单元 / 第5页 / 3年级）
  static final RegExp _refBefore = RegExp(r'[第册页题年级班次条项组]');

  static final RegExp _cjk = RegExp(r'[\u4e00-\u9fa5]');

  /// 语文里以「本册写字表」为语料的题型——只有这几种适合做生字检查。
  /// 古诗/成语/名言/阅读各有自己的语料来源（YUWEN_CORPUS / 课文 / 外置语料），不适用。
  static const Set<String> charBasedCnTypes = {
    'pinyin2char',
    'char2pinyin',
    'zuci',
  };

  /// 从题型 id 推导本年级的整数上限；返回 null 表示不设上限。
  ///
  /// 题型 id 本身自描述（add10 / add20 / add100 / add1000），所以从数据推导，
  /// 不手写课程表——手写的课程知识一旦有误反而更危险。
  /// 与提示词侧（ai_generator 的 _gradeMathScope）共用这一份推导，
  /// 避免出现「提示词说 20、校验按 100」这种自相矛盾。
  ///
  /// 四年级起大数、小数、分数交错，简单规则概括容易误伤，故不设上限。
  static int? integerCeil({
    required String version,
    required int grade,
    required String volume,
  }) {
    if (grade > 3) return null;
    final ids = (AppData().vol(version, grade, volume, 'math')?.math ?? [])
        .map((t) => t.id)
        .toSet();
    if (ids.isEmpty) return null;
    bool has(String s) => ids.any((i) => i.contains(s));
    if (has('1000') || has('10000')) return 10000;
    if (has('100')) return 100;
    if (has('20')) return 20;
    return 10;
  }

  /// 本册写字表
  static Set<String> writingTable({
    required String version,
    required int grade,
    required String volume,
  }) =>
      (AppData().vol(version, grade, volume, 'cally')?.cally ?? [])
          .map((c) => c[0])
          .toSet();

  /// 数学：找出题干中超出年级上限的数字。已排除题号、年份与引用。
  static List<String> mathNumbersOver(String text, int ceil) {
    final out = <String>[];
    for (final m in _num.allMatches(text)) {
      final lit = m.group(0)!;
      final v = int.tryParse(lit);
      if (v == null || v <= ceil) continue;
      if (m.start > 0 && _refBefore.hasMatch(text[m.start - 1])) continue;
      if (lit.length == 4 && v >= 1900 && v <= 2100) continue; // 年份
      out.add(lit);
    }
    return out;
  }

  /// 语文：统计文本中的汉字数，以及不在本册写字表内的那些。
  static ({int total, int outside, List<String> samples}) charScope(
    String text,
    Set<String> allowed,
  ) {
    var total = 0;
    final outside = <String>[];
    for (final r in text.runes) {
      final c = String.fromCharCode(r);
      if (!_cjk.hasMatch(c)) continue;
      total++;
      if (!allowed.contains(c)) outside.add(c);
    }
    return (total: total, outside: outside.length, samples: outside.toSet().toList());
  }

  /// 对一批题目做超纲检查，返回人类可读的提示；空串表示未发现问题。
  static String inspect(
    List<ScopeItem> items, {
    required String subject,
    required String version,
    required int grade,
    required String volume,
  }) {
    if (items.isEmpty) return '';
    final notes = <String>[];

    if (subject == 'math') {
      final ceil = integerCeil(version: version, grade: grade, volume: volume);
      if (ceil != null) {
        final bad = <String>{};
        for (final it in items) {
          bad.addAll(mathNumbersOver(it.text, ceil));
        }
        if (bad.isNotEmpty) {
          final list = bad.take(8).join('、');
          notes.add('$grade 年级数学不应超过 $ceil，但出现了 $list'
              '${bad.length > 8 ? ' 等' : ''}');
        }
      }
    }

    if (subject == 'chinese') {
      final allowed =
          writingTable(version: version, grade: grade, volume: volume);
      if (allowed.isNotEmpty) {
        var total = 0, outside = 0;
        final samples = <String>{};
        for (final it in items) {
          if (!charBasedCnTypes.contains(it.typeId)) continue;
          final r = charScope(it.text, allowed);
          total += r.total;
          outside += r.outside;
          samples.addAll(r.samples);
        }
        // 阈值 20%：字词题里混入少量表外字（如「照样子」「括号」等提示语）属正常
        if (total > 0 && outside / total > 0.2) {
          final pct = (outside / total * 100).round();
          final s = samples.take(10).join('、');
          notes.add('字词题有 $pct% 的字不在本册写字表内（$s'
              '${samples.length > 10 ? ' 等' : ''}）');
        }
      }
    }

    return notes.join('；');
  }
}
