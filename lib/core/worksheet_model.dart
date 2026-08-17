/// 作业文档模型：与渲染层解耦，预览(Widget)与 PDF 共用同一份数据
library;

/// 一页内容
class WsPage {
  /// 页头（hw-title）
  WsPageTitle? title;
  /// 内容节点（fill-col 内）
  List<WsNode> nodes;
  /// 是否不拉伸（参考答案等，top 对齐）
  bool noSpread;
  /// 内容是否紧凑排布（unitconv 等稀疏页：行从顶部开始，避免大片留白）
  bool packed;

  WsPage({this.title, List<WsNode>? nodes, this.noSpread = false, this.packed = false})
      : nodes = nodes ?? [];
}

/// 页头标题栏
class WsPageTitle {
  final String main;      // t1
  final String? sub;      // 参考教材行
  final String? meta1;    // 姓名/班级/日期 或 说明
  final String? meta2;
  final String? meta3;

  WsPageTitle({
    required this.main,
    this.sub,
    this.meta1,
    this.meta2,
    this.meta3,
  });
}

/// 内容节点抽象
sealed class WsNode {}

/// 题型说明（cn-section-title / math-instr）
class WsSection extends WsNode {
  final String text;
  final bool mathStyle; // math-instr 灰字样式
  WsSection(this.text, {this.mathStyle = false});
}

/// 数学/英语大标题（math-title / eng-title）
class WsHeading extends WsNode {
  final String title;
  final String? unit; // math 单元说明（灰色小字）
  final bool engStyle; // eng-title 蓝色
  WsHeading(this.title, {this.unit, this.engStyle = false});
}

/// 卡片网格
class WsGrid extends WsNode {
  /// 列数（1=单列 2/3/4=多列）
  final int cols;
  /// 内容是否均匀拉伸填满（align-content: space-evenly）
  final bool evenly;
  final List<WsCard> cards;
  final double? itemHeight; // 单卡固定高（可空=自然高度）
  WsGrid(this.cards, {this.cols = 3, this.evenly = true, this.itemHeight});
}

/// 单张卡片
class WsCard {
  final String kind; // cn / math / ai / eng
  final dynamic data;
  final int? num; // 序号（ai 题号 / 数学 idx）
  WsCard(this.kind, this.data, {this.num});
}

/// 独立块（阅读短文块、连线行等，占整行）
class WsBlock extends WsNode {
  final dynamic data;
  WsBlock(this.data);
}

/// 阅读短文块
class ReadingBlockData {
  final String title;
  final String author;
  final String text;
  final bool en; // 英文短文
  final bool isListening; // 听力短文（不显示原文）
  final int? grade;
  final String? volume;
  final List<ReadingQuestion> questions;
  ReadingBlockData({
    required this.title,
    this.author = "",
    required this.text,
    this.en = false,
    this.isListening = false,
    this.grade,
    this.volume,
    List<ReadingQuestion>? questions,
  }) : questions = questions ?? [];
}

class ReadingQuestion {
  final String q;
  final String a;
  final List<String>? options; // 选择题选项（如A/B/C）
  ReadingQuestion(this.q, this.a, {this.options});
}

/// 中央提示块（无语料/AI 未生成等占位）
class WsPlaceholder extends WsNode {
  final String emoji;
  final String title;
  final String desc;
  WsPlaceholder(this.emoji, this.title, this.desc);
}

/// 参考答案行
class WsAnswerLine extends WsNode {
  final int num;
  final String key;   // 题目简述
  final String ans;
  WsAnswerLine(this.num, this.key, this.ans);
}

/// 答案组标题
class WsAnswerGroup extends WsNode {
  final String title;
  final String? unit;
  WsAnswerGroup(this.title, {this.unit});
}

/// 连线题参考（两列）
class WsMatchAnswer extends WsNode {
  final List<String> lines; // "1. apple → b. 苹果"
  WsMatchAnswer(this.lines);
}
