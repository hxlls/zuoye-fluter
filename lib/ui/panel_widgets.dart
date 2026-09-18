import 'package:flutter/material.dart';

/// 面板布局：
/// - 桌面/平板（>=760px）：左侧配置 + 右侧预览，两者同时可见
/// - 手机（<760px）：配置页与预览页各自全屏。配置页底部常驻「生成」按钮，
///   点击后切到全屏预览；预览页顶部「调整参数」返回配置。
///
/// 这样手机上配置和预览都能占满屏幕，不必在窄抽屉里滚动找设置，
/// 也不会出现「改完参数还要关抽屉才能看预览」的来回操作。
class PanelLayout extends StatefulWidget {
  final Widget config;
  final Widget preview;

  /// 生成动作。手机端底部常驻按钮与桌面端配置列底部按钮都用它。
  /// 手机端点击后会顺带切到预览页；传 null 则不渲染按钮。
  final VoidCallback? onGenerate;
  final String generateLabel;
  final bool generateBusy;
  final IconData generateIcon;

  const PanelLayout({
    super.key,
    required this.config,
    required this.preview,
    this.onGenerate,
    this.generateLabel = '生成预览',
    this.generateBusy = false,
    this.generateIcon = Icons.refresh,
  });

  @override
  State<PanelLayout> createState() => _PanelLayoutState();
}

class _PanelLayoutState extends State<PanelLayout> {
  bool _showPreview = false;

  void _generate() {
    widget.onGenerate?.call();
    setState(() => _showPreview = true);
  }

  Widget _generateButton() {
    return FilledButton.icon(
      onPressed: widget.generateBusy ? null : _generate,
      icon: Icon(widget.generateIcon, size: 18),
      label: Text(widget.generateBusy ? '生成中…' : widget.generateLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 760;

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 320,
            padding: const EdgeInsets.all(14),
            color: const Color(0xfffaf8f2),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  widget.config,
                  if (widget.onGenerate != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: _generateButton()),
                  ],
                ],
              ),
            ),
          ),
          Expanded(child: widget.preview),
        ],
      );
    }

    // 手机：配置页 / 预览页各自全屏
    final content = Column(
      children: [
        if (_showPreview) _previewBar(),
        Expanded(
          child: _showPreview
              ? widget.preview
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                  child: widget.config,
                ),
        ),
        if (!_showPreview && widget.onGenerate != null) _stickyBar(),
      ],
    );

    // 手机端：在预览页按系统返回键应**先回到配置页**，而不是直接退出整个面板。
    // 实机验证过：不加这个的话，预览页按一次返回会一路退出应用
    // （前台直接变成桌面 NexusLauncherActivity），用户会以为「点返回把应用关了」。
    return PopScope(
      canPop: !_showPreview,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _showPreview = false);
      },
      child: content,
    );
  }

  /// 预览页顶部：返回调整参数
  Widget _previewBar() {
    return Container(
      color: const Color(0xfffaf8f2),
      padding: const EdgeInsets.fromLTRB(4, 2, 14, 2),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => setState(() => _showPreview = false),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('调整参数'),
          ),
          const Spacer(),
          const Text('预览',
              style: TextStyle(fontSize: 12, color: Color(0xff999999))),
        ],
      ),
    );
  }

  /// 配置页底部常驻生成按钮（含安全区，避免被手势条遮挡）
  Widget _stickyBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xfffaf8f2),
        border: Border(top: BorderSide(color: Color(0xffe6e2d8))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: SafeArea(
        top: false,
        child: SizedBox(width: double.infinity, child: _generateButton()),
      ),
    );
  }
}

/// 分段选择按钮
class SegButtons extends StatelessWidget {
  final List<(String, String)> options; // (value, label)
  final String value;
  final ValueChanged<String> onChanged;

  /// 每项等宽铺满整行。用于页内主导航（如「AI 出题 / AI 帮答」），
  /// 默认 false 走 Wrap，适合表单里选项数量不定的场景。
  final bool expand;

  const SegButtons({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.expand = false,
  });

  Widget _item(String v, String l) {
    return InkWell(
      onTap: () => onChanged(v),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: v == value ? const Color(0xff2f6fd0) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: v == value
                  ? const Color(0xff2f6fd0)
                  : const Color(0xffcccccc)),
        ),
        child: Text(l,
            textAlign: expand ? TextAlign.center : null,
            style: TextStyle(
                fontSize: 13,
                color:
                    v == value ? Colors.white : const Color(0xff444444))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (expand) {
      final children = <Widget>[];
      for (var i = 0; i < options.length; i++) {
        if (i > 0) children.add(const SizedBox(width: 6));
        children.add(Expanded(child: _item(options[i].$1, options[i].$2)));
      }
      return Row(children: children);
    }
    return Wrap(
      spacing: 6,
      children: [for (final (v, l) in options) _item(v, l)],
    );
  }
}

/// 表单分组
class FormGroup extends StatelessWidget {
  final String label;
  final Widget child;
  final String? hint;
  const FormGroup({super.key, required this.label, required this.child, this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xff333333))),
          const SizedBox(height: 6),
          child,
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(hint!,
                  style: const TextStyle(fontSize: 12, color: Color(0xffaaaaaa))),
            ),
        ],
      ),
    );
  }
}

/// 勾选标签
class CheckLabel extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const CheckLabel({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

/// 题型行：勾选 + 标签 + 题量下拉
class TypeRow extends StatelessWidget {
  final String label;
  final String? sub;
  final bool checked;
  final int count;
  final ValueChanged<bool> onChecked;
  final ValueChanged<int> onCount;
  const TypeRow({
    super.key,
    required this.label,
    this.sub,
    required this.checked,
    required this.count,
    required this.onChecked,
    required this.onCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: checked,
          onChanged: (v) => onChecked(v ?? false),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 14)),
              if (sub != null)
                Text(sub!,
                    style: const TextStyle(fontSize: 11, color: Color(0xffaaaaaa))),
            ],
          ),
        ),
        // 题量下拉（0=不选，方便手机点选）
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: checked ? count : 0,
            isDense: true,
            style: const TextStyle(fontSize: 14, color: Color(0xff333333)),
            items: [
              for (var i = 0; i <= 30; i++)
                DropdownMenuItem(value: i, child: Text('$i')),
            ],
            onChanged: (v) {
              if (v == null) return;
              onCount(v);
              if (v > 0 && !checked) onChecked(true);
              if (v == 0 && checked) onChecked(false);
            },
          ),
        ),
        const SizedBox(width: 2),
        const Text('题', style: TextStyle(fontSize: 12, color: Color(0xff999999))),
      ],
    );
  }
}

/// 数值下拉选择（1..max 可选，用于练字帖等数字设置）
class NumDropdown extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final bool fillWidth; // 手机端铺满整行，方便点击
  const NumDropdown({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.fillWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final dropdown = DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: value,
        isDense: true,
        isExpanded: fillWidth,
        style: const TextStyle(fontSize: 15, color: Color(0xff333333)),
        items: [
          for (var i = min; i <= max; i++)
            DropdownMenuItem(value: i, child: Text('$i')),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
    // 带边框圆角，视觉更明确、触达面积更大
    return Container(
      width: fillWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffcccccc)),
      ),
      child: dropdown,
    );
  }
}

/// 题量输入（带数值显示）
class CountSlider extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final int divisions;
  final ValueChanged<int> onChanged;
  const CountSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text('$value 字',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
