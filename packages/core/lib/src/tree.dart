/// Language-neutral component tree as exchanged over the editor protocol.
///
/// Adapters (Dart/Flutter, React, ...) build these from source; front ends
/// render and edit them. A node is addressed by its [path] of child indexes
/// from the page root.
library;

class ArgInfo {
  const ArgInfo({this.name, required this.source});
  /// Named argument / prop name; null for positional (Dart) arguments.
  final String? name;
  /// Source text of the value expression, exactly as written.
  final String source;

  Map<String, Object?> toJson() => {if (name != null) 'name': name, 'source': source};
  factory ArgInfo.fromJson(Map<String, Object?> j) => ArgInfo(name: j['name'] as String?, source: j['source'] as String);
}

class TreeNode {
  TreeNode({
    required this.type,
    required this.path,
    this.slot,
    this.args = const [],
    List<TreeNode>? children,
    this.offset = 0,
    this.end = 0,
    this.text,
  }) : children = children ?? [];

  /// Component type: `Text`, `ElevatedButton.icon`, `View`, `Card`...
  final String type;
  final List<int> path;
  /// Slot in the parent: `child`, `children`, `appBar`, or null for root.
  final String? slot;
  final List<ArgInfo> args;
  final List<TreeNode> children;
  /// Source range of the node expression / element.
  final int offset;
  final int end;
  /// Literal text content (JSX text children), if any.
  final String? text;

  String get className => type.split('.').first;

  ArgInfo? arg(String name) {
    for (final a in args) {
      if (a.name == name) return a;
    }
    return null;
  }

  List<ArgInfo> get positional => [for (final a in args) if (a.name == null) a];

  String get label {
    if (text != null && text!.trim().isNotEmpty) return '$type "${text!.trim()}"';
    final first = positional.isEmpty ? null : positional.first.source;
    if (first != null && first.length >= 2 && (first.startsWith("'") || first.startsWith('"'))) {
      return '$type "${first.substring(1, first.length - 1)}"';
    }
    return type;
  }

  String get pathKey => path.join('.');

  Iterable<TreeNode> walk() sync* {
    yield this;
    for (final c in children) {
      yield* c.walk();
    }
  }

  TreeNode? find(List<int> p) {
    final k = p.join('.');
    for (final n in walk()) {
      if (n.pathKey == k) return n;
    }
    return null;
  }

  TreeNode? parentOf(TreeNode n) {
    if (n.path.length <= 1) return null;
    return find(n.path.sublist(0, n.path.length - 1));
  }

  Map<String, Object?> toJson() => {
        'type': type,
        'path': path,
        if (slot != null) 'slot': slot,
        'args': [for (final a in args) a.toJson()],
        'children': [for (final c in children) c.toJson()],
        'offset': offset,
        'end': end,
        if (text != null) 'text': text,
      };

  factory TreeNode.fromJson(Map<String, Object?> j) => TreeNode(
        type: j['type'] as String,
        path: [for (final x in j['path'] as List) x as int],
        slot: j['slot'] as String?,
        args: [for (final a in (j['args'] as List? ?? const [])) ArgInfo.fromJson((a as Map).cast())],
        children: [for (final c in (j['children'] as List? ?? const [])) TreeNode.fromJson((c as Map).cast())],
        offset: j['offset'] as int? ?? 0,
        end: j['end'] as int? ?? 0,
        text: j['text'] as String?,
      );
}

/// A page / screen: a component whose rendered tree can be edited.
class PageInfo {
  const PageInfo({required this.name, required this.file, this.root, this.kind = 'page'});
  final String name;
  final String file;
  final TreeNode? root;
  /// Adapter-specific: `stateless`, `state`, `function`, ...
  final String kind;

  Map<String, Object?> toJson({bool withTree = true}) => {
        'name': name,
        'file': file,
        'kind': kind,
        if (withTree && root != null) 'root': root!.toJson(),
      };

  factory PageInfo.fromJson(Map<String, Object?> j) => PageInfo(
        name: j['name'] as String,
        file: j['file'] as String,
        kind: j['kind'] as String? ?? 'page',
        root: j['root'] == null ? null : TreeNode.fromJson((j['root'] as Map).cast()),
      );
}
