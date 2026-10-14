import 'package:flutter/material.dart';

import 'editor_state.dart';
import 'theme.dart';

/// Source of the current file. Editable; "Apply" re-parses and keeps the
/// visual model in sync with hand-written code.
class CodeView extends StatefulWidget {
  const CodeView(this.s, {super.key});
  final EditorState s;
  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  final c = TextEditingController();
  String? shown;

  @override
  Widget build(BuildContext context) {
    final src = widget.s.doc?.source ?? '';
    if (shown != src) {
      shown = src;
      c.text = src;
    }
    return Container(
      color: Bench.canvas,
      child: Column(children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: Bench.panel,
          child: Row(children: [
            Text(widget.s.file ?? '', style: const TextStyle(fontSize: 12, color: Bench.muted)),
            const Spacer(),
            TextButton.icon(onPressed: () => widget.s.replaceCode(c.text), icon: const Icon(Icons.check, size: 16), label: const Text('Apply')),
          ]),
        ),
        Expanded(
          child: TextField(
            controller: c,
            maxLines: null,
            expands: true,
            style: const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['monospace'], fontSize: 13, height: 1.4),
            decoration: const InputDecoration(filled: true, fillColor: Bench.canvas, border: InputBorder.none, enabledBorder: InputBorder.none, contentPadding: EdgeInsets.all(16)),
          ),
        ),
      ]),
    );
  }
}
