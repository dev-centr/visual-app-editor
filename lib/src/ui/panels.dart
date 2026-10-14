import 'package:flutter/material.dart';

import '../source/dart_document.dart';
import '../toolkit/toolkit.dart';
import 'editor_state.dart';
import 'theme.dart';

class PanelHeader extends StatelessWidget {
  const PanelHeader(this.title, {super.key, this.actions = const []});
  final String title;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Bench.border))),
        child: Row(children: [
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          ...actions,
        ]),
      );
}

// ------------------------------------------------------------------ tree

class WidgetTreePanel extends StatelessWidget {
  const WidgetTreePanel(this.s, {super.key});
  final EditorState s;
  @override
  Widget build(BuildContext context) {
    final root = s.page?.root;
    return Column(children: [
      PanelHeader('Widget Tree', actions: [
        _icon(Icons.arrow_upward, 'Move up', () => s.moveSelected(-1)),
        _icon(Icons.arrow_downward, 'Move down', () => s.moveSelected(1)),
        PopupMenuButton<String>(
          tooltip: 'Wrap with',
          icon: const Icon(Icons.layers_outlined, size: 18),
          onSelected: s.wrapSelected,
          itemBuilder: (_) => [for (final w in ['Padding', 'Center', 'Container', 'SizedBox', 'Expanded', 'Column', 'Row', 'Card']) PopupMenuItem(value: w, child: Text('Wrap with $w'))],
        ),
        _icon(Icons.delete_outline, 'Delete', s.removeSelected),
      ]),
      Expanded(
        child: root == null
            ? const Center(child: Text('No page selected', style: TextStyle(color: Bench.muted)))
            : ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: [_TreeRow(s, s.page!.name, null, 0), ..._rows(root, 1)]),
      ),
    ]);
  }

  List<Widget> _rows(WidgetNode n, int depth) => [_TreeRow(s, n.label, n, depth), for (final c in n.children) ..._rows(c, depth + 1)];

  static Widget _icon(IconData i, String tip, VoidCallback f) => IconButton(icon: Icon(i, size: 18), tooltip: tip, onPressed: f, visualDensity: VisualDensity.compact);
}

class _TreeRow extends StatelessWidget {
  const _TreeRow(this.s, this.label, this.node, this.depth);
  final EditorState s;
  final String label;
  final WidgetNode? node;
  final int depth;
  @override
  Widget build(BuildContext context) {
    final n = node;
    final sel = n != null && s.selectedPath != null && n.path.join('.') == s.selectedPath!.join('.');
    return DragTarget<WidgetSpec>(
      onWillAcceptWithDetails: (_) => n != null,
      onAcceptWithDetails: (d) => s.insert(d.data, target: n),
      builder: (context, cand, _) => InkWell(
        onTap: n == null ? null : () => s.select(n),
        child: Container(
          height: 28,
          padding: EdgeInsets.only(left: 12.0 + (depth > 12 ? 12 : depth) * 14),
          color: cand.isNotEmpty ? Bench.accent.withValues(alpha: .25) : sel ? Bench.accent.withValues(alpha: .18) : null,
          child: Row(children: [
            Icon(n == null ? Icons.description_outlined : _iconFor(n.className), size: 15, color: sel ? Bench.accent : Bench.muted),
            const SizedBox(width: 6),
            Expanded(child: Text((n?.slot != null && n!.slot != 'children' && n.slot != 'child') ? '${n.slot}: $label' : label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
          ]),
        ),
      ),
    );
  }
}

IconData _iconFor(String t) => switch (t) {
      'Column' => Icons.view_agenda_outlined,
      'Row' => Icons.view_column_outlined,
      'Stack' => Icons.layers_outlined,
      'Text' || 'RichText' => Icons.text_fields,
      'Container' || 'SizedBox' || 'Padding' => Icons.crop_square,
      'Scaffold' => Icons.phone_android,
      'AppBar' => Icons.web_asset,
      'Icon' || 'IconButton' => Icons.emoji_symbols,
      'Image' => Icons.image_outlined,
      'ListView' => Icons.list,
      'Card' => Icons.credit_card,
      'TextField' || 'TextFormField' => Icons.input,
      _ when t.contains('Button') => Icons.smart_button_outlined,
      _ => Icons.widgets_outlined,
    };

// --------------------------------------------------------------- toolbox

class ToolboxPanel extends StatefulWidget {
  const ToolboxPanel(this.s, {super.key});
  final EditorState s;
  @override
  State<ToolboxPanel> createState() => _ToolboxPanelState();
}

class _ToolboxPanelState extends State<ToolboxPanel> {
  String q = '';
  bool commonOnly = true;
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final out = <Widget>[];
    for (final t in s.registry.loaded.values) {
      final ws = t.widgets.where((w) {
        if (q.isNotEmpty) return w.invocation.toLowerCase().contains(q.toLowerCase());
        return !commonOnly || w.category != 'Other';
      }).toList();
      if (ws.isEmpty) continue;
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text('${t.manifest.name.toUpperCase()}  ·  ${t.widgets.length}', style: const TextStyle(fontSize: 11, color: Bench.muted, letterSpacing: 1)),
      ));
      final byCat = <String, List<WidgetSpec>>{};
      for (final w in ws) {
        (byCat[w.category] ??= []).add(w);
      }
      for (final e in byCat.entries) {
        out.add(Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 4), child: Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))));
        out.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Wrap(spacing: 6, runSpacing: 6, children: [for (final w in e.value.take(q.isEmpty && !commonOnly ? 200 : 400)) _Tile(s, w)]),
        ));
      }
    }
    return Column(children: [
      const PanelHeader('Toolbox'),
      Padding(
        padding: const EdgeInsets.all(10),
        child: TextField(decoration: const InputDecoration(hintText: 'Search widgets', prefixIcon: Icon(Icons.search, size: 18)), onChanged: (v) => setState(() => q = v)),
      ),
      Row(children: [
        const SizedBox(width: 10),
        FilterChip(label: const Text('Common', style: TextStyle(fontSize: 11)), selected: commonOnly, onSelected: (v) => setState(() => commonOnly = v)),
        const Spacer(),
        Text('${s.palette.length} constructors', style: const TextStyle(fontSize: 11, color: Bench.muted)),
        const SizedBox(width: 12),
      ]),
      Expanded(child: out.isEmpty ? const Center(child: Text('Load a toolkit from the Toolkits tab', style: TextStyle(color: Bench.muted))) : ListView(children: out)),
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.s, this.w);
  final EditorState s;
  final WidgetSpec w;
  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: 86,
      height: 64,
      decoration: BoxDecoration(color: Bench.panelAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: Bench.border)),
      padding: const EdgeInsets.all(4),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(_iconFor(w.className), size: 20, color: Bench.muted),
        const SizedBox(height: 4),
        Text(w.invocation, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5)),
      ]),
    );
    return Tooltip(
      message: '${w.invocation}\n${w.doc ?? ''}'.trim(),
      child: Draggable<WidgetSpec>(
        data: w,
        feedback: Material(color: Colors.transparent, child: Opacity(opacity: .85, child: tile)),
        child: InkWell(onTap: () => s.insert(w), child: tile),
      ),
    );
  }
}

// ----------------------------------------------------------------- pages

class PagesPanel extends StatelessWidget {
  const PagesPanel(this.s, {super.key});
  final EditorState s;
  @override
  Widget build(BuildContext context) {
    final pages = s.project?.pages ?? const [];
    return Column(children: [
      PanelHeader('Pages', actions: [
        IconButton(icon: const Icon(Icons.add, size: 18), tooltip: 'New page', onPressed: () => _newPage(context)),
      ]),
      Expanded(
        child: ListView(children: [
          for (final p in pages)
            ListTile(
              dense: true,
              selected: p.page.name == s.pageName,
              leading: const Icon(Icons.phone_android, size: 18),
              title: Text(p.page.name),
              subtitle: Text(p.file, style: const TextStyle(fontSize: 11, color: Bench.muted)),
              onTap: () => s.selectPage(p.file, p.page.name),
            ),
        ]),
      ),
    ]);
  }

  Future<void> _newPage(BuildContext context) async {
    final c = TextEditingController(text: 'NewPage');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New page'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Class name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name != null && RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(name)) s.addPage(name);
  }
}

// ----------------------------------------------------------------- theme

class ThemePanel extends StatelessWidget {
  const ThemePanel(this.s, {super.key});
  final EditorState s;
  static const seeds = [0xFF6750A4, 0xFF4B8BFF, 0xFF0F9D58, 0xFFE91E63, 0xFFFF9800, 0xFF009688, 0xFF795548, 0xFF37474F];
  @override
  Widget build(BuildContext context) {
    final c = s.project?.config;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PanelHeader('Theme'),
      if (c != null) ...[
        const Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, 6), child: Text('Seed color', style: TextStyle(fontSize: 12))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in seeds)
              InkWell(
                onTap: () => s.setTheme(seed: v),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: Color(v), shape: BoxShape.circle, border: Border.all(color: c.seedColor == v ? Colors.white : Colors.transparent, width: 2)),
                ),
              ),
          ]),
        ),
        SwitchListTile(dense: true, title: const Text('Dark preview'), value: c.dark, onChanged: (v) => s.setTheme(dark: v)),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Preview theme is stored in widget_bench.sdl. It does not change your app\'s ThemeData.', style: TextStyle(fontSize: 11, color: Bench.muted)),
        ),
      ],
    ]);
  }
}

// -------------------------------------------------------------- toolkits

class ToolkitsPanel extends StatelessWidget {
  const ToolkitsPanel(this.s, {super.key});
  final EditorState s;
  @override
  Widget build(BuildContext context) {
    final r = s.registry;
    return Column(children: [
      PanelHeader('Toolkits', actions: [
        TextButton(onPressed: s.project == null ? null : s.pubGet, child: const Text('pub get')),
      ]),
      Expanded(
        child: ListView(children: [
          for (final m in r.manifests.values)
            CheckboxListTile(
              dense: true,
              value: r.loaded.containsKey(m.id),
              onChanged: (v) => s.toggleToolkit(m.id, v ?? false),
              title: Text(m.name),
              subtitle: Text(
                r.loaded[m.id] != null ? '${r.loaded[m.id]!.widgets.length} constructors · ${m.importUri}' : 'package:${m.package}',
                style: const TextStyle(fontSize: 11, color: Bench.muted),
              ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(r.log.reversed.take(12).join('\n'), style: const TextStyle(fontSize: 11, color: Bench.muted, fontFamily: 'Consolas', fontFamilyFallback: ['Menlo', 'DejaVu Sans Mono', 'monospace'])),
          ),
        ]),
      ),
    ]);
  }
}
