import 'package:flutter/material.dart';

import '../source/dart_document.dart';
import '../toolkit/toolkit.dart';
import 'editor_state.dart';
import 'panels.dart';
import 'theme.dart';

/// Right-hand panel: every constructor parameter of the selected widget,
/// discovered from its toolkit, with the current source expression.
class PropertiesPanel extends StatelessWidget {
  const PropertiesPanel(this.s, {super.key});
  final EditorState s;

  @override
  Widget build(BuildContext context) {
    final n = s.selected;
    if (n == null) {
      return const Column(children: [PanelHeader('Properties'), Expanded(child: Center(child: Text('Select a widget', style: TextStyle(color: Bench.muted))))]);
    }
    final spec = s.registry.findWidget(n.className);
    final ctorSpec = _ctor(spec, n);
    final known = <String>{};
    final rows = <Widget>[];
    // positional arguments first
    final positionalParams = ctorSpec?.params.where((p) => !p.isNamed).toList() ?? const <WidgetParam>[];
    for (var i = 0; i < n.positional.length || i < positionalParams.length; i++) {
      final p = i < positionalParams.length ? positionalParams[i] : null;
      final cur = i < n.positional.length ? n.positional[i].source : '';
      rows.add(_PropRow(
        key: ValueKey('${n.path.join('.')}#$i#$cur'),
        name: p?.name ?? 'arg $i',
        type: p?.type ?? '',
        value: cur,
        isRequired: true,
        onSubmit: (v) => s.setPositional(i, v),
      ));
    }
    final named = ctorSpec?.params.where((p) => p.isNamed).toList() ?? const <WidgetParam>[];
    for (final p in named) {
      known.add(p.name);
      if (p.takesWidget || p.isChildren) continue;
      final a = n.arg(p.name);
      rows.add(_PropRow(
        key: ValueKey('${n.path.join('.')}/${p.name}/${a?.source}'),
        name: p.name,
        type: p.type,
        value: a?.source ?? '',
        hint: p.defaultValue,
        isRequired: p.isRequired,
        onSubmit: (v) => s.setArgument(p.name, v),
      ));
    }
    // arguments present in source but not in the discovered constructor
    for (final a in n.args.where((a) => a.name != null && !known.contains(a.name) && n.children.every((c) => c.slot != a.name))) {
      rows.add(_PropRow(
        key: ValueKey('${n.path.join('.')}/${a.name}/${a.source}'),
        name: a.name!,
        type: '?',
        value: a.source,
        onSubmit: (v) => s.setArgument(a.name!, v),
      ));
    }
    final slots = [for (final p in named) if (p.takesWidget || p.isChildren) p.name];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PanelHeader('Properties'),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text(n.type, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          spec == null ? 'Not in a loaded toolkit; showing source arguments only.' : '${spec.toolkitId}${spec.doc == null ? '' : ' · ${spec.doc}'}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Bench.muted),
        ),
      ),
      if (slots.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Text('Widget slots: ${slots.join(', ')}', style: const TextStyle(fontSize: 11, color: Bench.muted)),
        ),
      const SizedBox(height: 8),
      Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 24), children: rows)),
    ]);
  }

  WidgetSpec? _ctor(WidgetSpec? spec, WidgetNode n) {
    if (spec == null) return null;
    final parts = n.type.split('.');
    final ctor = parts.length > 1 ? parts[1] : null;
    for (final w in s.palette) {
      if (w.className == spec.className && w.constructorName == ctor) return w;
    }
    return spec;
  }
}

class _PropRow extends StatefulWidget {
  const _PropRow({super.key, required this.name, required this.type, required this.value, required this.onSubmit, this.hint, this.isRequired = false});
  final String name;
  final String type;
  final String value;
  final String? hint;
  final bool isRequired;
  final ValueChanged<String> onSubmit;
  @override
  State<_PropRow> createState() => _PropRowState();
}

class _PropRowState extends State<_PropRow> {
  late final c = TextEditingController(text: widget.value);
  static const swatches = ['Colors.red', 'Colors.orange', 'Colors.amber', 'Colors.green', 'Colors.teal', 'Colors.blue', 'Colors.indigo', 'Colors.purple', 'Colors.grey', 'Colors.black', 'Colors.white'];

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.type.replaceAll('?', '');
    Widget editor;
    if (t == 'bool') {
      editor = Row(children: [
        Switch(value: widget.value == 'true', onChanged: (v) => widget.onSubmit('$v')),
        if (widget.value.isNotEmpty) TextButton(onPressed: () => widget.onSubmit(''), child: const Text('reset')),
      ]);
    } else {
      editor = TextField(
        controller: c,
        style: const TextStyle(fontSize: 12, fontFamily: 'Consolas', fontFamilyFallback: ['Menlo', 'DejaVu Sans Mono', 'monospace']),
        decoration: InputDecoration(hintText: widget.hint ?? (t == 'String' ? "'text'" : t)),
        onSubmitted: widget.onSubmit,
        onTapOutside: (_) {
          if (c.text != widget.value) widget.onSubmit(c.text);
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(widget.name, style: TextStyle(fontSize: 12, fontWeight: widget.value.isEmpty ? FontWeight.normal : FontWeight.w600)),
          if (widget.isRequired) const Text(' *', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          const Spacer(),
          Flexible(child: Text(widget.type, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Bench.muted))),
        ]),
        const SizedBox(height: 4),
        editor,
        if (t == 'Color')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 4, children: [
              for (final sw in swatches)
                InkWell(
                  onTap: () => widget.onSubmit(sw),
                  child: Container(width: 16, height: 16, decoration: BoxDecoration(color: _swatch(sw), border: Border.all(color: Bench.border), borderRadius: BorderRadius.circular(3))),
                ),
            ]),
          ),
      ]),
    );
  }

  static Color _swatch(String s) => switch (s) {
        'Colors.red' => Colors.red,
        'Colors.orange' => Colors.orange,
        'Colors.amber' => Colors.amber,
        'Colors.green' => Colors.green,
        'Colors.teal' => Colors.teal,
        'Colors.blue' => Colors.blue,
        'Colors.indigo' => Colors.indigo,
        'Colors.purple' => Colors.purple,
        'Colors.grey' => Colors.grey,
        'Colors.black' => Colors.black,
        _ => Colors.white,
      };
}
