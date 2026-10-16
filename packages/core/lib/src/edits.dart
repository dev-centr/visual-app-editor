/// Source-edit protocol: the operations every language adapter implements.
/// Serialised as `{"op": "<name>", ...}` in `document/edit` requests.
library;

sealed class EditOp {
  const EditOp();
  String get op;
  Map<String, Object?> get fields;
  Map<String, Object?> toJson() => {'op': op, ...fields};

  static EditOp fromJson(Map<String, Object?> j) {
    List<int> p() => [for (final x in j['path'] as List) x as int];
    return switch (j['op']) {
      'setArgument' => SetArgument(p(), j['name'] as String, j['value'] as String),
      'removeArgument' => RemoveArgument(p(), j['name'] as String),
      'setPositional' => SetPositional(p(), j['index'] as int, j['value'] as String),
      'setText' => SetText(p(), j['value'] as String),
      'insertChild' => InsertChild(p(), j['snippet'] as String, index: j['index'] as int?),
      'removeNode' => RemoveNode(p()),
      'wrapNode' => WrapNode(p(), j['wrapper'] as String, slot: j['slot'] as String? ?? 'child', extraArgs: j['extraArgs'] as String? ?? ''),
      'moveInList' => MoveInList(p(), j['delta'] as int),
      'replaceSource' => ReplaceSource(j['text'] as String),
      final o => throw ArgumentError('Unknown edit op: $o'),
    };
  }
}

/// Targets a node by page name + path.
sealed class NodeEdit extends EditOp {
  const NodeEdit(this.path);
  final List<int> path;
}

class SetArgument extends NodeEdit {
  const SetArgument(super.path, this.name, this.value);
  final String name;
  final String value;
  @override
  String get op => 'setArgument';
  @override
  Map<String, Object?> get fields => {'path': path, 'name': name, 'value': value};
}

class RemoveArgument extends NodeEdit {
  const RemoveArgument(super.path, this.name);
  final String name;
  @override
  String get op => 'removeArgument';
  @override
  Map<String, Object?> get fields => {'path': path, 'name': name};
}

class SetPositional extends NodeEdit {
  const SetPositional(super.path, this.index, this.value);
  final int index;
  final String value;
  @override
  String get op => 'setPositional';
  @override
  Map<String, Object?> get fields => {'path': path, 'index': index, 'value': value};
}

/// Replaces literal text content (JSX text children).
class SetText extends NodeEdit {
  const SetText(super.path, this.value);
  final String value;
  @override
  String get op => 'setText';
  @override
  Map<String, Object?> get fields => {'path': path, 'value': value};
}

class InsertChild extends NodeEdit {
  const InsertChild(super.path, this.snippet, {this.index});
  final String snippet;
  final int? index;
  @override
  String get op => 'insertChild';
  @override
  Map<String, Object?> get fields => {'path': path, 'snippet': snippet, if (index != null) 'index': index};
}

class RemoveNode extends NodeEdit {
  const RemoveNode(super.path);
  @override
  String get op => 'removeNode';
  @override
  Map<String, Object?> get fields => {'path': path};
}

class WrapNode extends NodeEdit {
  const WrapNode(super.path, this.wrapper, {this.slot = 'child', this.extraArgs = ''});
  final String wrapper;
  final String slot;
  final String extraArgs;
  @override
  String get op => 'wrapNode';
  @override
  Map<String, Object?> get fields => {'path': path, 'wrapper': wrapper, 'slot': slot, 'extraArgs': extraArgs};
}

class MoveInList extends NodeEdit {
  const MoveInList(super.path, this.delta);
  final int delta;
  @override
  String get op => 'moveInList';
  @override
  Map<String, Object?> get fields => {'path': path, 'delta': delta};
}

class ReplaceSource extends EditOp {
  const ReplaceSource(this.text);
  final String text;
  @override
  String get op => 'replaceSource';
  @override
  Map<String, Object?> get fields => {'text': text};
}

class SourceEditException implements Exception {
  SourceEditException(this.message);
  final String message;
  @override
  String toString() => message;
}
