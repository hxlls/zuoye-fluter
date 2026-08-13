import 'package:flutter/material.dart';

/// 面板布局：
/// 桌面/平板（>=760px）：左侧配置 + 右侧预览
/// 手机（<760px）：配置收进左侧抽屉，主区全屏预览
class PanelLayout extends StatefulWidget {
  final Widget config;
  final Widget preview;
  const PanelLayout({super.key, required this.config, required this.preview});

  @override
  State<PanelLayout> createState() => _PanelLayoutState();
}

class _PanelLayoutState extends State<PanelLayout> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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
            child: SingleChildScrollView(child: widget.config),
          ),
          Expanded(child: widget.preview),
        ],
      );
    }
    // 手机：抽屉 + 全屏预览
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
        backgroundColor: const Color(0xfffaf8f2),
        title: Row(
          children: [
            TextButton.icon(
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('设置'),
            ),
          ],
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            child: widget.config,
          ),
        ),
      ),
      body: widget.preview,
    );
  }
}

/// 分段选择按钮
class SegButtons extends StatelessWidget {
  final List<(String, String)> options; // (value, label)
  final String value;
  final ValueChanged<String> onChanged;
  const SegButtons({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        for (final (v, l) in options)
          InkWell(
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
                  style: TextStyle(
                      fontSize: 13,
                      color: v == value
                          ? Colors.white
                          : const Color(0xff444444))),
            ),
          ),
      ],
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

/// 题型行：勾选 + 标签 + 题量输入
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
        SizedBox(
          width: 56,
          child: TextField(
            keyboardType: TextInputType.number,
            enabled: checked,
            controller: TextEditingController(text: '$count'),
            onChanged: (v) {
              final n = int.tryParse(v);
              onCount(n == null ? 0 : n.clamp(0, 30));
            },
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Text('题', style: TextStyle(fontSize: 12, color: Color(0xff999999))),
      ],
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
