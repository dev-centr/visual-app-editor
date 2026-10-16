import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:vae_core/vae_core.dart';

import 'dart_document.dart';
import 'introspector.dart';
import 'toolkit_locator.dart';

/// Dart / Flutter adapter: pages are widget classes with a `build` method;
/// edits are AST-offset text edits that preserve all other bytes.
class DartFlutterAdapter extends LanguageAdapter {
  @override
  String get id => 'dart-flutter';

  @override
  List<String> get extensions => const ['.dart'];

  @override
  bool handles(String path) => path.endsWith('.dart') && !path.endsWith('.g.dart') && !path.endsWith('.freezed.dart');

  @override
  List<PageInfo> pages(String path, String source) {
    final d = DartDocument(source, path: path);
    return [
      for (final pg in d.pages)
        PageInfo(name: pg.name, file: path, kind: pg.isState ? 'state' : 'stateless', root: pg.root == null ? null : toTree(pg.root!)),
    ];
  }

  @override
  String applyEdit(String path, String source, String page, EditOp op) {
    final d = DartDocument(source, path: path);
    WidgetNode node(List<int> p) => d.nodeAt(page, p) ?? (throw SourceEditException('No widget at ${p.join('.')} in $page'));
    switch (op) {
      case SetArgument(:final path, :final name, :final value):
        d.setArgument(node(path), name, value);
      case RemoveArgument(:final path, :final name):
        d.removeArgument(node(path), name);
      case SetPositional(:final path, :final index, :final value):
        d.setPositional(node(path), index, value);
      case SetText(:final path, :final value):
        d.setPositional(node(path), 0, "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'");
      case InsertChild(:final path, :final snippet, :final index):
        d.insertChild(node(path), snippet, index: index);
      case RemoveNode(:final path):
        d.removeNode(node(path));
      case WrapNode(:final path, :final wrapper, :final slot, :final extraArgs):
        d.wrapNode(node(path), wrapper, slot: slot, extraArgs: extraArgs);
      case MoveInList(:final path, :final delta):
        d.moveInList(node(path), delta);
      case ReplaceSource(:final text):
        d.replaceSource(text);
    }
    return d.source;
  }

  @override
  Toolkit? loadToolkit(ToolkitManifest manifest, String projectRoot) {
    final lib = ToolkitLocator.locate(manifest, projectRoot);
    if (lib == null) return null;
    final t = ToolkitIntrospector.introspect(manifest, lib);
    DartDocument.knownWidgets.addAll(t.widgets.map((w) => w.className));
    return t;
  }

  static TreeNode toTree(WidgetNode n) => TreeNode(
        type: n.type,
        path: n.path,
        slot: n.slot,
        args: [for (final a in n.args) ArgInfo(name: a.name, source: a.source)],
        children: [for (final c in n.children) toTree(c)],
        offset: n.offset,
        end: n.end,
      );
}

/// Parses a single Dart expression (e.g. an argument's source text).
Expression? parseDartExpression(String source) {
  final r = parseString(content: 'final _v = $source;', throwIfDiagnostics: false);
  if (r.errors.isNotEmpty) return null;
  final decl = r.unit.declarations.whereType<TopLevelVariableDeclaration>().firstOrNull;
  return decl?.variables.variables.first.initializer;
}
