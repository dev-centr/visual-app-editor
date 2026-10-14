import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../version.dart';
import 'canvas.dart';
import 'code_view.dart';
import 'editor_state.dart';
import 'panels.dart';
import 'properties.dart';
import 'theme.dart';

class EditorShell extends StatelessWidget {
  const EditorShell(this.s, {super.key});
  final EditorState s;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): s.save,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): s.undo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): s.redo,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(children: [
              _Toolbar(s),
              Expanded(
                child: s.project == null
                    ? _Welcome(s)
                    : Row(children: [
                        _Rail(s),
                        Container(
                          width: 290,
                          decoration: const BoxDecoration(color: Bench.panel, border: Border(right: BorderSide(color: Bench.border))),
                          child: switch (s.left) {
                            LeftPanel.tree => WidgetTreePanel(s),
                            LeftPanel.toolbox => ToolboxPanel(s),
                            LeftPanel.pages => PagesPanel(s),
                            LeftPanel.theme => ThemePanel(s),
                            LeftPanel.toolkits => ToolkitsPanel(s),
                          },
                        ),
                        Expanded(
                          child: switch (s.center) {
                            CenterView.canvas => CanvasView(s),
                            CenterView.code => CodeView(s),
                            CenterView.split => Row(children: [Expanded(child: CanvasView(s)), const VerticalDivider(width: 1), Expanded(child: CodeView(s))]),
                          },
                        ),
                        Container(
                          width: 320,
                          decoration: const BoxDecoration(color: Bench.panel, border: Border(left: BorderSide(color: Bench.border))),
                          child: PropertiesPanel(s),
                        ),
                      ]),
              ),
              _StatusBar(s),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar(this.s);
  final EditorState s;
  @override
  Widget build(BuildContext context) {
    final pages = s.project?.pages ?? const [];
    return Container(
      height: 48,
      decoration: const BoxDecoration(color: Bench.rail, border: Border(bottom: BorderSide(color: Bench.border))),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [
        const _Logo(),
        const SizedBox(width: 10),
        const Text('Widget Bench', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 16),
        if (s.project != null) ...[
          Text(s.project!.name, style: const TextStyle(color: Bench.muted)),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: s.pageName,
            underline: const SizedBox(),
            isDense: true,
            items: [for (final p in pages) DropdownMenuItem(value: p.page.name, child: Text(p.page.name, style: const TextStyle(fontSize: 13)))],
            onChanged: (v) {
              final p = pages.firstWhere((x) => x.page.name == v);
              s.selectPage(p.file, p.page.name);
            },
          ),
          const Spacer(),
          SegmentedButton<CenterView>(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: CenterView.canvas, icon: Icon(Icons.brush_outlined, size: 16), label: Text('Design')),
              ButtonSegment(value: CenterView.split, icon: Icon(Icons.vertical_split_outlined, size: 16), label: Text('Split')),
              ButtonSegment(value: CenterView.code, icon: Icon(Icons.code, size: 16), label: Text('Code')),
            ],
            selected: {s.center},
            onSelectionChanged: (v) => s.setCenter(v.first),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: s.device.id,
            underline: const SizedBox(),
            isDense: true,
            items: [for (final d in DeviceSpec.all) DropdownMenuItem(value: d.id, child: Text(d.label, style: const TextStyle(fontSize: 13)))],
            onChanged: (v) => s.setDevice(v!),
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.undo, size: 18), tooltip: 'Undo (Ctrl+Z)', onPressed: s.canUndo ? s.undo : null),
          IconButton(icon: const Icon(Icons.redo, size: 18), tooltip: 'Redo (Ctrl+Y)', onPressed: s.canRedo ? s.redo : null),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: s.dirty.isEmpty ? null : s.save,
            icon: const Icon(Icons.save_outlined, size: 16),
            label: Text(s.dirty.isEmpty ? 'Saved' : 'Save (${s.dirty.length})'),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: s.toggleLive,
            icon: Icon(s.live.running ? Icons.stop : Icons.play_arrow, size: 16),
            label: Text(s.live.running ? 'Stop' : 'Run'),
          ),
          const SizedBox(width: 6),
          IconButton(icon: const Icon(Icons.folder_open_outlined, size: 18), tooltip: 'Open project', onPressed: () => openProjectDialog(context, s)),
          IconButton(icon: const Icon(Icons.info_outline, size: 18), tooltip: 'About', onPressed: () => showAbout(context)),
        ] else ...[
          const Spacer(),
          IconButton(icon: const Icon(Icons.info_outline, size: 18), tooltip: 'About', onPressed: () => showAbout(context)),
        ],
      ]),
    );
  }
}

void showAbout(BuildContext context) => showAboutDialog(
      context: context,
      applicationName: 'Widget Bench',
      applicationVersion: '$kVersion (build $kBuildId)',
      applicationIcon: const _Logo(size: 40),
      applicationLegalese: 'MIT License. Offline visual UI builder for Flutter.',
    );

class _Logo extends StatelessWidget {
  const _Logo({this.size = 26});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter()));
}

/// Painted twin of assets/logo.svg (stacked blocks on a bench).
class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final u = s.width / 64;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s.width, s.height), Radius.circular(14 * u));
    canvas.drawRRect(r, Paint()..color = const Color(0xFF1B2A44));
    void block(double x, double y, double w, double h, Color c) =>
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x * u, y * u, w * u, h * u), Radius.circular(3 * u)), Paint()..color = c);
    block(14, 14, 22, 14, const Color(0xFF4B8BFF));
    block(38, 14, 12, 14, const Color(0xFF7CC4FF));
    block(14, 30, 36, 8, const Color(0xFF9FB4FF));
    block(10, 44, 44, 6, const Color(0xFFE6EAED));
    block(16, 50, 5, 6, const Color(0xFFE6EAED));
    block(43, 50, 5, 6, const Color(0xFFE6EAED));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<void> openProjectDialog(BuildContext context, EditorState s) async {
  final c = TextEditingController(text: s.project?.root ?? '');
  final path = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Open Flutter project'),
      content: SizedBox(
        width: 520,
        child: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Project folder (contains pubspec.yaml)')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Open')),
      ],
    ),
  );
  if (path != null && path.isNotEmpty) s.openProject(path);
}

class _Rail extends StatelessWidget {
  const _Rail(this.s);
  final EditorState s;
  @override
  Widget build(BuildContext context) {
    Widget item(LeftPanel p, IconData i, String label) {
      final sel = s.left == p;
      return Tooltip(
        message: label,
        preferBelow: false,
        child: InkWell(
          onTap: () => s.setLeft(p),
          child: Container(
            width: 56,
            height: 52,
            decoration: BoxDecoration(border: Border(left: BorderSide(color: sel ? Bench.accent : Colors.transparent, width: 3))),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(i, size: 20, color: sel ? Bench.text : Bench.muted),
              Text(label, style: TextStyle(fontSize: 9, color: sel ? Bench.text : Bench.muted)),
            ]),
          ),
        ),
      );
    }

    return Container(
      width: 56,
      color: Bench.rail,
      child: Column(children: [
        const SizedBox(height: 6),
        item(LeftPanel.pages, Icons.layers_outlined, 'Pages'),
        item(LeftPanel.toolbox, Icons.add_box_outlined, 'Toolbox'),
        item(LeftPanel.tree, Icons.account_tree_outlined, 'Tree'),
        item(LeftPanel.theme, Icons.palette_outlined, 'Theme'),
        item(LeftPanel.toolkits, Icons.extension_outlined, 'Toolkits'),
        const Spacer(),
      ]),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar(this.s);
  final EditorState s;
  @override
  Widget build(BuildContext context) => Container(
        height: 24,
        color: Bench.rail,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          if (s.error != null) const Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
          const SizedBox(width: 4),
          Expanded(
            child: Text(s.error ?? s.status, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: s.error != null ? Colors.redAccent : Bench.muted)),
          ),
          if (s.live.running) Text('live: ${s.liveLog.isEmpty ? 'starting' : s.liveLog.last}', style: const TextStyle(fontSize: 11, color: Bench.muted)),
        ]),
      );
}

class _Welcome extends StatelessWidget {
  const _Welcome(this.s);
  final EditorState s;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _Logo(size: 72),
          const SizedBox(height: 16),
          const Text('Widget Bench', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Open a Flutter project to edit its pages visually.', style: TextStyle(color: Bench.muted)),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: () => openProjectDialog(context, s), icon: const Icon(Icons.folder_open), label: const Text('Open project')),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () async {
              final dir = await createSampleProject();
              s.openProject(dir);
            },
            child: const Text('Create and open the sample project'),
          ),
          if (s.error != null) Padding(padding: const EdgeInsets.all(12), child: Text(s.error!, style: const TextStyle(color: Colors.redAccent))),
        ]),
      );
}

/// Writes the bundled sample project into the user's documents folder.
Future<String> createSampleProject() async {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
  final root = Directory('$home${Platform.pathSeparator}WidgetBench${Platform.pathSeparator}sample_app');
  for (final f in ['pubspec.yaml', 'widget_bench.sdl', 'lib/main.dart', 'lib/pages/home_page.dart', 'lib/pages/settings_page.dart']) {
    final out = File('${root.path}/$f');
    if (out.existsSync()) continue;
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(await rootBundle.loadString('example/sample_app/$f'));
  }
  return root.path;
}
