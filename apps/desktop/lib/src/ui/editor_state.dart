import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vae_core/vae_core.dart';
import 'package:vae_protocol/vae_protocol.dart';
import 'package:vae_service/vae_service.dart';

import '../preview/live_runner.dart';
import '../version.dart';

enum LeftPanel { pages, toolbox, tree, theme, toolkits }

enum CenterView { canvas, code, split }

/// Project as seen by this front end (mirrors service state).
class ProjectView {
  ProjectView(this.name, this.root, this.config);
  final String name;
  final String root;
  ProjectConfig config;
  List<({String file, PageInfo page})> pages = [];
}

class ToolkitEntry {
  ToolkitEntry(Map<String, Object?> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        package = j['package'] as String,
        importUri = j['import'] as String,
        loaded = j['loaded'] as bool? ?? false,
        count = j['count'] as int? ?? 0;
  final String id, name, package, importUri;
  final bool loaded;
  final int count;
}

/// All editor state. Everything about projects, documents and toolkits goes
/// through the editor protocol to the headless service (in-process by
/// default, or an external `vae_service` when VAE_SERVICE is set).
class EditorState extends ChangeNotifier {
  EditorState({RpcPeer? peer}) : _peer = peer;

  RpcPeer? _peer;
  RpcPeer get peer => _peer!;
  Process? _serviceProcess;

  final LiveRunner live = LiveRunner();
  final List<String> liveLog = [];
  final List<String> log = [];
  StreamSubscription<String>? _liveSub;

  ProjectView? project;
  String? file;
  String? pageName;
  PageInfo? page;
  String source = '';
  List<int>? selectedPath;
  List<WidgetSpec> palette = [];
  List<ToolkitEntry> toolkits = [];
  LeftPanel left = LeftPanel.tree;
  CenterView center = CenterView.canvas;
  double zoom = 0.8;
  String status = 'Ready';
  String? error;
  final Set<String> dirty = {};
  final List<String> _undo = [];
  final List<String> _redo = [];

  TreeNode? get selected => (page?.root == null || selectedPath == null) ? null : page!.root!.find(selectedPath!);
  DevicePreset get device => DevicePresets.byId(project?.config.device ?? 'phone');

  Future<void> init() async {
    if (_peer == null) {
      final cmd = Platform.environment['VAE_SERVICE'];
      if (cmd != null && cmd.isNotEmpty) {
        final parts = cmd.split(' ');
        final p = await Process.start(parts.first, parts.skip(1).toList(), runInShell: true);
        _serviceProcess = p;
        _peer = RpcPeer(p.stdout.transform(const MessageDecoder()), (m) => p.stdin.add(encodeMessage(m)));
      } else {
        _peer = connectInProcess();
      }
    }
    peer.notifications.listen((n) {
      if (n.method == Methods.logMessage) {
        log.add('${n.params['message']}');
        notifyListeners();
      }
    });
    await peer.request(Methods.initialize, {'clientInfo': {'name': 'visual_app_editor', 'version': kVersion}});
    await _refreshToolkits();
    notifyListeners();
  }

  Future<T?> _call<T>(String method, [Map<String, Object?> params = const {}]) async {
    try {
      final r = await peer.request(method, params);
      error = null;
      return r as T?;
    } on RpcException catch (e) {
      error = e.message;
      notifyListeners();
      return null;
    }
  }

  ProjectConfig _cfg(Map j) => ProjectConfig(
        toolkits: [for (final x in j['toolkits'] as List) '$x'],
        device: j['device'] as String,
        seedColor: j['seedColor'] as int,
        dark: j['dark'] as bool,
      );

  Future<void> openProject(String root) async {
    final r = await _call<Map>(Methods.projectOpen, {'root': root});
    if (r == null) return;
    project = ProjectView(r['name'] as String, root, _cfg(r['config'] as Map));
    dirty.clear();
    _undo.clear();
    _redo.clear();
    await _refreshPages(r['pages'] as List);
    await _refreshToolkits();
    final pages = project!.pages;
    if (pages.isNotEmpty) {
      await selectPage(pages.first.file, pages.first.page.name);
    } else {
      file = null;
      pageName = null;
      page = null;
    }
    status = 'Opened ${project!.name}: ${pages.length} page(s), ${palette.length} widget constructors';
    notifyListeners();
  }

  Future<void> _refreshPages([List? raw]) async {
    raw ??= await _call<List>(Methods.projectPages) ?? const [];
    project!.pages = [
      for (final x in raw)
        (file: (x as Map)['file'] as String, page: PageInfo.fromJson(x.cast())),
    ];
  }

  Future<void> _refreshToolkits() async {
    toolkits = [for (final t in await _call<List>(Methods.toolkitList) ?? const []) ToolkitEntry((t as Map).cast())];
    palette = [for (final w in await _call<List>(Methods.toolkitPalette) ?? const []) WidgetSpec.fromJson((w as Map).cast())];
  }

  Future<void> selectPage(String f, String name) async {
    file = f;
    pageName = name;
    selectedPath = const [0];
    await _reloadDocument();
    notifyListeners();
  }

  Future<void> _reloadDocument() async {
    final f = file;
    if (f == null) return;
    final src = await _call<Map>(Methods.documentSource, {'file': f});
    source = src?['source'] as String? ?? '';
    final tree = await _call<Map>(Methods.documentTree, {'file': f, 'page': pageName});
    page = tree == null ? null : PageInfo.fromJson(tree.cast());
  }

  void select(TreeNode n) {
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

  Future<void> _setConfig(Map<String, Object?> p) async {
    final r = await _call<Map>(Methods.projectSetConfig, p);
    if (r != null) project!.config = _cfg(r);
    notifyListeners();
  }

  Future<void> setDevice(String id) => _setConfig({'device': id});
  Future<void> setTheme({int? seed, bool? dark}) => _setConfig({if (seed != null) 'seedColor': seed, if (dark != null) 'dark': dark});

  /// Sends one edit op to the service; keeps a source snapshot for undo.
  Future<bool> edit(String label, EditOp op, {bool recordUndo = true}) async {
    final f = file;
    if (f == null) return false;
    final before = source;
    final r = await _call<Map>(Methods.documentEdit, {'file': f, 'page': pageName, 'op': op.toJson()});
    if (r == null) return false;
    source = r['source'] as String;
    page = r['page'] == null ? page : PageInfo.fromJson((r['page'] as Map).cast());
    if (recordUndo) {
      _undo.add(before);
      _redo.clear();
    }
    dirty.add(f);
    status = label;
    _fixSelection();
    notifyListeners();
    return true;
  }

  void _fixSelection() {
    if (selected == null) {
      final s = selectedPath;
      selectedPath = (s != null && s.length > 1) ? s.sublist(0, s.length - 1) : const [0];
      if (selected == null) selectedPath = const [0];
    }
  }

  Future<void> undo() async {
    if (_undo.isEmpty) return;
    final target = _undo.removeLast();
    _redo.add(source);
    await edit('Undo', ReplaceSource(target), recordUndo: false);
  }

  Future<void> redo() async {
    if (_redo.isEmpty) return;
    final target = _redo.removeLast();
    _undo.add(source);
    await edit('Redo', ReplaceSource(target), recordUndo: false);
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  WidgetSpec? findSpec(String className, [String? ctor]) {
    WidgetSpec? any;
    for (final w in palette) {
      if (w.className != className) continue;
      if (w.constructorName == ctor) return w;
      any ??= w;
    }
    return any;
  }

  Future<void> setArgument(String name, String value) async {
    final n = selected;
    if (n == null) return;
    await edit('Set ${n.type}.$name', value.trim().isEmpty ? RemoveArgument(n.path, name) : SetArgument(n.path, name, value));
  }

  Future<void> setPositional(int index, String value) async {
    final n = selected;
    if (n == null) return;
    await edit('Set ${n.type} argument', SetPositional(n.path, index, value));
  }

  Future<void> insert(WidgetSpec spec, {TreeNode? target}) => insertSnippet(spec.snippet(), target: target, label: 'Insert ${spec.invocation}');

  static const _singleChild = {
    'Container', 'Padding', 'Center', 'Align', 'SizedBox', 'Card', 'Expanded', 'Flexible', 'SingleChildScrollView',
    'Opacity', 'ElevatedButton', 'FilledButton', 'OutlinedButton', 'TextButton', 'FloatingActionButton', 'CircleAvatar',
  };

  bool _accepts(TreeNode n) {
    if (n.arg('children') != null) return true;
    if (n.arg('child') != null) return false;
    final spec = findSpec(n.className);
    if (spec != null) return spec.acceptsChild && spec.param('child') != null;
    return _singleChild.contains(n.type);
  }

  Future<void> insertSnippet(String snippet, {TreeNode? target, String label = 'Insert widget'}) async {
    final t = target ?? selected;
    final root = page?.root;
    if (t == null || root == null) return;
    TreeNode? cur = t;
    while (cur != null && !_accepts(cur)) {
      cur = root.parentOf(cur);
    }
    if (cur == null) {
      error = 'No container above ${t.type} can take another child. Wrap something in a Column first.';
      notifyListeners();
      return;
    }
    final path = cur.path;
    if (await edit(label, InsertChild(path, snippet))) {
      final nd = page?.root?.find(path);
      if (nd != null && nd.children.isNotEmpty) {
        selectedPath = nd.children.last.path;
        notifyListeners();
      }
    }
  }

  Future<void> removeSelected() async {
    final n = selected;
    if (n == null) return;
    await edit('Delete ${n.type}', RemoveNode(n.path));
  }

  Future<void> wrapSelected(String wrapper) async {
    final n = selected;
    if (n == null) return;
    const multi = {'Column', 'Row', 'Stack', 'Wrap', 'ListView'};
    final extra = switch (wrapper) {
      'Padding' => 'padding: const EdgeInsets.all(8)',
      'SizedBox' => 'width: 100',
      _ => '',
    };
    await edit('Wrap in $wrapper', WrapNode(n.path, wrapper, slot: multi.contains(wrapper) ? 'children' : 'child', extraArgs: extra));
  }

  Future<void> moveSelected(int delta) async {
    final n = selected;
    if (n == null) return;
    if (await edit('Move ${n.type}', MoveInList(n.path, delta))) {
      final p = [...n.path];
      p[p.length - 1] = p.last + delta;
      selectedPath = p;
      if (selected == null) selectedPath = n.path;
      notifyListeners();
    }
  }

  Future<void> replaceCode(String text) => edit('Edit code', ReplaceSource(text));

  Future<void> save() async {
    if (project == null) return;
    final r = await _call<Map>(Methods.documentSave, {});
    if (r == null) return;
    status = 'Saved ${(r['saved'] as List).length} file(s)';
    dirty.clear();
    if (live.running) live.hotReload();
    notifyListeners();
  }

  Future<void> addPage(String className) async {
    final r = await _call<Map>(Methods.projectAddPage, {'className': className});
    if (r == null) return;
    await _refreshPages();
    await selectPage(r['file'] as String, className);
    status = 'Created ${r['file']}';
    notifyListeners();
  }

  Future<void> toggleToolkit(String id, bool on) async {
    await _call(on ? Methods.toolkitLoad : Methods.toolkitUnload, {'id': id});
    await _refreshToolkits();
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
    await openProject(p.root);
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    live.stop();
    _peer?.request(Methods.shutdown).ignore();
    _serviceProcess?.kill();
    super.dispose();
  }
}
