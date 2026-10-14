import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../preview/live_runner.dart';
import '../project/project.dart';
import '../source/dart_document.dart';
import '../toolkit/registry.dart';
import '../toolkit/toolkit.dart';

enum LeftPanel { pages, toolbox, tree, theme, toolkits }

enum CenterView { canvas, code, split }

class DeviceSpec {
  const DeviceSpec(this.id, this.label, this.width, this.height);
  final String id;
  final String label;
  final double width;
  final double height;
  static const all = [
    DeviceSpec('phone', 'Phone 390x844', 390, 844),
    DeviceSpec('tablet', 'Tablet 820x1180', 820, 1180),
    DeviceSpec('desktop', 'Desktop 1280x800', 1280, 800),
  ];
  static DeviceSpec byId(String id) => all.firstWhere((d) => d.id == id, orElse: () => all.first);
}

/// All editor state; widgets listen and call the action methods.
class EditorState extends ChangeNotifier {
  EditorState({ToolkitRegistry? registry}) : registry = registry ?? ToolkitRegistry();

  final ToolkitRegistry registry;
  final LiveRunner live = LiveRunner();
  final List<String> liveLog = [];
  StreamSubscription<String>? _liveSub;

  FlutterProject? project;
  String? file;
  String? pageName;
  List<int>? selectedPath;
  LeftPanel left = LeftPanel.tree;
  CenterView center = CenterView.canvas;
  double zoom = 0.8;
  String status = 'Ready';
  String? error;
  final Set<String> dirty = {};
  final List<String> _undo = [];
  final List<String> _redo = [];

  DartDocument? get doc => file == null ? null : project?.documents[file];
  PageModel? get page => pageName == null ? null : doc?.page(pageName!);
  WidgetNode? get selected => (pageName == null || selectedPath == null) ? null : doc?.nodeAt(pageName!, selectedPath!);
  DeviceSpec get device => DeviceSpec.byId(project?.config.device ?? 'phone');

  List<WidgetSpec> get palette => [for (final t in registry.loaded.values) ...t.widgets];

  Future<void> init() async {
    await registry.loadBundledManifests();
    notifyListeners();
  }

  void openProject(String root) {
    try {
      final p = FlutterProject.open(root);
      project = p;
      dirty.clear();
      _undo.clear();
      _redo.clear();
      registry.loaded.clear();
      registry.loadManifestDir('$root/.widget_bench/toolkits');
      for (final id in p.config.toolkits) {
        registry.load(id, projectRoot: root);
      }
      final pages = p.pages;
      if (pages.isNotEmpty) {
        selectPage(pages.first.file, pages.first.page.name);
      } else {
        file = null;
        pageName = null;
      }
      status = 'Opened ${p.name}: ${pages.length} page(s), ${palette.length} widget constructors';
      error = null;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  void selectPage(String f, String name) {
    file = f;
    pageName = name;
    selectedPath = const [0];
    notifyListeners();
  }

  void select(WidgetNode n) {
    selectedPath = n.path;
    notifyListeners();
  }

  void setLeft(LeftPanel p) {
    left = p;
    notifyListeners();
  }

  void setCenter(CenterView v) {
    center = v;
    notifyListeners();
  }

  void setZoom(double z) {
    zoom = z.clamp(0.25, 2.0);
    notifyListeners();
  }

  void setDevice(String id) {
    project?.config.device = id;
    project?.saveConfig();
    notifyListeners();
  }

  void setTheme({int? seed, bool? dark}) {
    final c = project?.config;
    if (c == null) return;
    if (seed != null) c.seedColor = seed;
    if (dark != null) c.dark = dark;
    project!.saveConfig();
    notifyListeners();
  }

  /// Runs a source edit with undo support and error reporting.
  bool edit(String label, void Function(DartDocument d) f) {
    final d = doc;
    if (d == null) return false;
    final before = d.source;
    try {
      f(d);
      _undo.add(before);
      _redo.clear();
      dirty.add(file!);
      status = label;
      error = null;
      _fixSelection();
      notifyListeners();
      return true;
    } catch (e) {
      error = '$e';
      notifyListeners();
      return false;
    }
  }

  void _fixSelection() {
    if (selected == null) {
      final s = selectedPath;
      selectedPath = (s != null && s.length > 1) ? s.sublist(0, s.length - 1) : const [0];
      if (selected == null) selectedPath = const [0];
    }
  }

  void undo() {
    final d = doc;
    if (d == null || _undo.isEmpty) return;
    _redo.add(d.source);
    d.replaceSource(_undo.removeLast());
    dirty.add(file!);
    _fixSelection();
    notifyListeners();
  }

  void redo() {
    final d = doc;
    if (d == null || _redo.isEmpty) return;
    _undo.add(d.source);
    d.replaceSource(_redo.removeLast());
    dirty.add(file!);
    _fixSelection();
    notifyListeners();
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void setArgument(String name, String value) {
    final n = selected;
    if (n == null) return;
    edit('Set ${n.type}.$name', (d) {
      final node = d.nodeAt(pageName!, n.path)!;
      if (value.trim().isEmpty) {
        d.removeArgument(node, name);
      } else {
        d.setArgument(node, name, value);
      }
    });
  }

  void setPositional(int index, String value) {
    final n = selected;
    if (n == null) return;
    edit('Set ${n.type} argument', (d) => d.setPositional(d.nodeAt(pageName!, n.path)!, index, value));
  }

  /// Inserts [spec] under [target] (or the selection).
  void insert(WidgetSpec spec, {WidgetNode? target}) => insertSnippet(spec.snippet(), target: target, label: 'Insert ${spec.invocation}');

  void insertSnippet(String snippet, {WidgetNode? target, String label = 'Insert widget'}) {
    var t = target ?? selected;
    if (t == null) return;
    // Walk up until something can take a child.
    final d = doc!;
    WidgetNode? cur = t;
    while (cur != null && !_accepts(cur)) {
      cur = cur.parent;
    }
    if (cur == null) {
      error = 'No container above ${t.type} can take another child. Wrap something in a Column first.';
      notifyListeners();
      return;
    }
    final dest = cur;
    final path = dest.path;
    edit(label, (d) => d.insertChild(d.nodeAt(pageName!, path)!, snippet));
    // select the inserted node (last child of dest)
    final nd = d.nodeAt(pageName!, path);
    if (nd != null && nd.children.isNotEmpty) {
      selectedPath = nd.children.last.path;
      notifyListeners();
    }
  }

  static const _singleChild = {
    'Container', 'Padding', 'Center', 'Align', 'SizedBox', 'Card', 'Expanded', 'Flexible', 'SingleChildScrollView',
    'Opacity', 'ElevatedButton', 'FilledButton', 'OutlinedButton', 'TextButton', 'FloatingActionButton', 'CircleAvatar',
  };

  bool _accepts(WidgetNode n) {
    if (n.childrenList != null) return true;
    if (n.arg('child') != null) return false;
    final spec = registry.findWidget(n.className);
    if (spec != null) return spec.acceptsChild && spec.param('child') != null;
    return _singleChild.contains(n.type);
  }

  void removeSelected() {
    final n = selected;
    if (n == null) return;
    edit('Delete ${n.type}', (d) => d.removeNode(d.nodeAt(pageName!, n.path)!));
  }

  void wrapSelected(String wrapper) {
    final n = selected;
    if (n == null) return;
    const multi = {'Column', 'Row', 'Stack', 'Wrap', 'ListView'};
    final extra = switch (wrapper) {
      'Padding' => 'padding: const EdgeInsets.all(8)',
      'Container' => '',
      'SizedBox' => 'width: 100',
      _ => '',
    };
    edit('Wrap in $wrapper', (d) => d.wrapNode(d.nodeAt(pageName!, n.path)!, wrapper, slot: multi.contains(wrapper) ? 'children' : 'child', extraArgs: extra));
  }

  void moveSelected(int delta) {
    final n = selected;
    if (n == null) return;
    final ok = edit('Move ${n.type}', (d) => d.moveInList(d.nodeAt(pageName!, n.path)!, delta));
    if (ok) {
      final p = [...n.path];
      p[p.length - 1] = p.last + delta;
      selectedPath = p;
      if (selected == null) selectedPath = n.path;
      notifyListeners();
    }
  }

  void replaceCode(String text) => edit('Edit code', (d) => d.replaceSource(text));

  void save() {
    final p = project;
    if (p == null) return;
    for (final f in dirty) {
      p.save(f);
    }
    status = 'Saved ${dirty.length} file(s)';
    dirty.clear();
    if (live.running) live.hotReload();
    notifyListeners();
  }

  void addPage(String className) {
    final p = project;
    if (p == null) return;
    try {
      final rel = p.addPage(className);
      selectPage(rel, className);
      status = 'Created $rel';
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  void toggleToolkit(String id, bool on) {
    final p = project;
    if (on) {
      final t = registry.load(id, projectRoot: p?.root);
      if (t == null) error = registry.log.last;
    } else {
      registry.loaded.remove(id);
    }
    if (p != null) {
      p.config.toolkits = registry.loaded.keys.toList();
      p.saveConfig();
    }
    notifyListeners();
  }

  Future<void> toggleLive() async {
    final p = project;
    if (p == null) return;
    if (live.running) {
      await live.stop();
    } else {
      _liveSub ??= live.log.listen((l) {
        liveLog.add(l);
        if (liveLog.length > 400) liveLog.removeAt(0);
        notifyListeners();
      });
      await live.start(p.root);
    }
    notifyListeners();
  }

  Future<void> pubGet() async {
    final p = project;
    if (p == null) return;
    status = 'Running flutter pub get...';
    notifyListeners();
    final r = await Process.run('flutter', ['pub', 'get'], workingDirectory: p.root, runInShell: true);
    status = r.exitCode == 0 ? 'pub get done' : 'pub get failed';
    if (r.exitCode != 0) error = '${r.stderr}';
    openProject(p.root);
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    live.stop();
    super.dispose();
  }
}
