import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../toolkit/introspector.dart' show classNameOf, superclassOf;

/// A single argument of a widget constructor call in source.
class SourceArg {
  SourceArg(this.name, this.expression);
  final String? name;
  final Expression expression;
  String get source => expression.toSource();

  /// Range of the whole argument (including `name:`).
  int get argOffset => expression.parent is NamedExpression ? expression.parent!.offset : expression.offset;
  int get argEnd => expression.parent is NamedExpression ? expression.parent!.end : expression.end;
}

/// A widget constructor call found in a `build` method.
class WidgetNode {
  WidgetNode({
    required this.type,
    required this.expression,
    required this.argumentList,
    required this.args,
    required this.path,
    this.slot,
    this.parent,
  });

  /// Class name, or `Class.named` for named constructors.
  final String type;
  final Expression expression;
  final ArgumentList argumentList;
  final List<SourceArg> args;
  final List<int> path;
  final String? slot;
  final WidgetNode? parent;
  final List<WidgetNode> children = [];

  String get className => type.split('.').first;
  int get offset => expression.offset;
  int get end => expression.end;

  SourceArg? arg(String name) {
    for (final a in args) {
      if (a.name == name) return a;
    }
    return null;
  }

  List<SourceArg> get positional => [for (final a in args) if (a.name == null) a];

  /// Short label for tree views: `Text "Hello"`.
  String get label {
    final first = positional.isEmpty ? null : positional.first.expression;
    if (first is SimpleStringLiteral) return '$type "${first.value}"';
    return type;
  }

  ListLiteral? get childrenList {
    final a = arg('children');
    final e = a?.expression;
    return e is ListLiteral ? e : null;
  }

  Iterable<WidgetNode> walk() sync* {
    yield this;
    for (final c in children) {
      yield* c.walk();
    }
  }
}

/// A page: a widget class with a `build` method whose returned tree we edit.
class PageModel {
  PageModel(this.name, this.root, this.buildMethod, {this.isState = false});
  final String name;
  final WidgetNode? root;
  final MethodDeclaration buildMethod;
  final bool isState;
}

class SourceEditException implements Exception {
  SourceEditException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A text edit: replace `[offset, offset+length)` with [replacement].
class TextEdit {
  TextEdit(this.offset, this.length, this.replacement);
  final int offset;
  final int length;
  final String replacement;
}

/// Parsed Dart source that can be edited structurally while preserving
/// every byte the edit does not touch (comments, hand-written logic,
/// formatting).
class DartDocument {
  DartDocument(this.source, {this.path = 'lib/main.dart'}) {
    _parse();
  }

  String source;
  final String path;
  late CompilationUnit unit;
  List<String> diagnostics = [];
  List<PageModel> pages = [];

  void _parse() {
    final r = parseString(content: source, path: path, throwIfDiagnostics: false);
    unit = r.unit;
    diagnostics = [for (final d in r.errors) '${d.message} @${d.offset}'];
    pages = _findPages();
  }

  PageModel? page(String name) {
    for (final p in pages) {
      if (p.name == name) return p;
    }
    return null;
  }

  List<PageModel> _findPages() {
    final out = <PageModel>[];
    for (final d in unit.declarations.whereType<ClassDeclaration>()) {
      final sup = superclassOf(d);
      if (sup == null) continue;
      final isState = sup == 'State';
      if (!(isState || sup == 'StatelessWidget' || sup.endsWith('Widget'))) continue;
      for (final m in d.members.whereType<MethodDeclaration>()) {
        if (m.name.lexeme != 'build') continue;
        final expr = _returnedExpression(m.body);
        final root = expr == null ? null : _toNode(expr, const [0], null, null);
        var name = classNameOf(d);
        if (isState) {
          final args = d.extendsClause!.superclass.typeArguments?.arguments;
          if (args != null && args.isNotEmpty) name = args.first.toSource();
        }
        out.add(PageModel(name, root, m, isState: isState));
      }
    }
    return out;
  }

  static Expression? _returnedExpression(FunctionBody body) {
    if (body is ExpressionFunctionBody) return body.expression;
    if (body is BlockFunctionBody) {
      Expression? found;
      body.block.accept(_ReturnFinder((e) => found ??= e));
      return found;
    }
    return null;
  }

  /// Recognises `Foo(...)`, `const Foo(...)`, `Foo.named(...)`, `new Foo()`.
  static ({String type, ArgumentList args})? widgetCall(Expression e) {
    if (e is InstanceCreationExpression) {
      final n = e.constructorName;
      final t = n.type.toSource().split('<').first;
      return (type: n.name == null ? t : '$t.${n.name!.name}', args: e.argumentList);
    }
    if (e is MethodInvocation) {
      final m = e.methodName.name;
      final target = e.target;
      if (target == null && _isTypeName(m)) return (type: m, args: e.argumentList);
      if (target is SimpleIdentifier && _isTypeName(target.name) && !_isTypeName(m)) {
        return (type: '${target.name}.$m', args: e.argumentList);
      }
      // prefixed import: m.Text(...)
      if (target is SimpleIdentifier && _isTypeName(m)) return (type: m, args: e.argumentList);
    }
    return null;
  }

  static bool _isTypeName(String s) => s.isNotEmpty && s[0].toUpperCase() == s[0] && s[0] != '_' && RegExp(r'^[A-Z]').hasMatch(s);

  /// Value classes that look like constructor calls but are not widgets.
  static const valueTypes = {
    'EdgeInsets', 'EdgeInsetsDirectional', 'TextStyle', 'BoxDecoration', 'ShapeDecoration', 'Color', 'BorderRadius',
    'Radius', 'Border', 'BorderSide', 'BoxShadow', 'InputDecoration', 'OutlineInputBorder', 'UnderlineInputBorder',
    'RoundedRectangleBorder', 'CircleBorder', 'StadiumBorder', 'Size', 'Offset', 'Duration', 'Alignment',
    'BoxConstraints', 'ButtonStyle', 'ThemeData', 'ColorScheme', 'TextTheme', 'IconThemeData', 'Key', 'ValueKey',
    'GlobalKey', 'LinearGradient', 'RadialGradient', 'DecorationImage', 'NetworkImage', 'AssetImage', 'TextEditingController',
    'FocusNode', 'ScrollController', 'Uri', 'DateTime', 'FontWeight', 'Locale', 'Matrix4', 'Rect', 'SliverGridDelegateWithFixedCrossAxisCount',
    'IconData', 'Icons', 'Colors', 'MaterialStateProperty', 'WidgetStateProperty', 'SystemUiOverlayStyle', 'Curves',
  };

  /// Extra widget class names known from loaded toolkits (optional).
  static Set<String> knownWidgets = {};

  static bool isWidgetType(String type) {
    final cls = type.split('.').first;
    if (knownWidgets.contains(cls)) return true;
    return !valueTypes.contains(cls) && !cls.endsWith('Style') && !cls.endsWith('Data') && !cls.endsWith('Controller');
  }

  WidgetNode? _toNode(Expression e, List<int> path, String? slot, WidgetNode? parent) {
    final call = widgetCall(e);
    if (call == null || !isWidgetType(call.type)) return null;
    final args = <SourceArg>[
      for (final a in call.args.arguments)
        if (a is NamedExpression) SourceArg(a.name.label.name, a.expression) else SourceArg(null, a),
    ];
    final node = WidgetNode(type: call.type, expression: e, argumentList: call.args, args: args, path: path, slot: slot, parent: parent);
    var i = 0;
    for (final a in args) {
      final ex = a.expression;
      if (ex is ListLiteral) {
        for (final el in ex.elements) {
          if (el is Expression) {
            final c = _toNode(el, [...path, i], a.name ?? 'children', node);
            if (c != null) {
              node.children.add(c);
              i++;
            }
          }
        }
      } else if (a.name != null) {
        final c = _toNode(ex, [...path, i], a.name, node);
        if (c != null) {
          node.children.add(c);
          i++;
        }
      }
    }
    return node;
  }

  WidgetNode? nodeAt(String pageName, List<int> path) {
    final root = page(pageName)?.root;
    if (root == null) return null;
    for (final n in root.walk()) {
      if (_samePath(n.path, path)) return n;
    }
    return null;
  }

  static bool _samePath(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------- edits

  void _apply(List<TextEdit> edits, {required int anchor}) {
    final constSafe = edits.every((e) => _constSafe.hasMatch(e.replacement.trim()) || e.replacement.trim().startsWith('const '));
    final consts = (constSafe ? const <TextEdit>[] : _constRemovals(anchor)).where((c) =>
        !edits.any((e) => c.offset >= e.offset && c.offset < e.offset + e.length));
    final all = [...edits, ...consts];
    all.sort((a, b) => b.offset.compareTo(a.offset));
    var s = source;
    int? last;
    for (final e in all) {
      if (last != null && e.offset + e.length > last) continue; // overlapping
      s = s.replaceRange(e.offset, e.offset + e.length, e.replacement);
      last = e.offset;
    }
    final before = source;
    source = s;
    _parse();
    if (diagnostics.isNotEmpty) {
      final errs = diagnostics;
      source = before;
      _parse();
      throw SourceEditException('Edit would produce invalid Dart: ${errs.first}');
    }
  }

  /// Replacements that are themselves constant (literals, enum/static
  /// constants) do not require stripping `const` from ancestors.
  static final _constSafe = RegExp(r'''^(|'[^'\\$]*'|"[^"\\$]*"|-?\d+(\.\d+)?|true|false|null|[A-Z]\w*\.\w+|[A-Z]\w*\.\w+\[\d+\])$''');

  /// Removes `const` from ancestors of [offset] so that inserting
  /// non-constant expressions stays valid.
  List<TextEdit> _constRemovals(int offset) {
    final out = <TextEdit>[];
    final finder = _NodeAtOffset(offset);
    unit.accept(finder);
    AstNode? n = finder.found;
    while (n != null) {
      Token? k;
      if (n is InstanceCreationExpression && n.keyword?.lexeme == 'const') k = n.keyword;
      if (n is TypedLiteral && n.constKeyword != null) k = n.constKeyword;
      if (n is VariableDeclarationList && n.keyword?.lexeme == 'const') {
        out.add(TextEdit(n.keyword!.offset, n.keyword!.length, 'final'));
      }
      if (k != null) {
        var len = k.length;
        if (k.end < source.length && source[k.end] == ' ') len++;
        out.add(TextEdit(k.offset, len, ''));
      }
      n = n.parent;
    }
    return out;
  }

  /// Sets (or adds) a named argument [name] to [valueSource] on [node].
  void setArgument(WidgetNode node, String name, String valueSource) {
    final existing = node.arg(name);
    if (existing != null) {
      _apply([TextEdit(existing.expression.offset, existing.expression.length, valueSource)], anchor: existing.expression.offset);
      return;
    }
    _insertArgument(node, '$name: $valueSource');
  }

  /// Sets the positional argument at [index] (e.g. the string of `Text`).
  void setPositional(WidgetNode node, int index, String valueSource) {
    final pos = node.positional;
    if (index < pos.length) {
      final e = pos[index].expression;
      _apply([TextEdit(e.offset, e.length, valueSource)], anchor: e.offset);
    } else {
      final list = node.argumentList;
      _apply([TextEdit(list.leftParenthesis.end, 0, list.arguments.isEmpty ? valueSource : '$valueSource, ')], anchor: list.leftParenthesis.end);
    }
  }

  void _insertArgument(WidgetNode node, String text) {
    final list = node.argumentList;
    final close = list.rightParenthesis.offset;
    String ins;
    if (list.arguments.isEmpty) {
      ins = text;
    } else {
      final trailingComma = list.rightParenthesis.previous?.lexeme == ',';
      ins = trailingComma ? ' $text,' : ', $text';
      if (trailingComma && _multiline(list)) {
        final indent = _indentOf(list.arguments.last.offset);
        ins = '$indent$text,\n${_indentOf(close)}';
        final lineStart = source.lastIndexOf('\n', close - 1) + 1;
        _apply([TextEdit(lineStart, close - lineStart, ins)], anchor: close);
        return;
      }
    }
    _apply([TextEdit(close, 0, ins)], anchor: close);
  }

  bool _multiline(ArgumentList l) => source.substring(l.offset, l.end).contains('\n');

  String _indentOf(int offset) {
    final lineStart = source.lastIndexOf('\n', offset - 1) + 1;
    final m = RegExp(r'^[ \t]*').firstMatch(source.substring(lineStart));
    return m?.group(0) ?? '';
  }

  void removeArgument(WidgetNode node, String name) {
    final a = node.arg(name);
    if (a == null) return;
    _apply([_removalWithComma(a.argOffset, a.argEnd)], anchor: a.argOffset);
  }

  TextEdit _removalWithComma(int start, int end) {
    var e = end;
    final rest = source.substring(e);
    final m = RegExp(r'^\s*,[ \t]*').firstMatch(rest);
    if (m != null) {
      e += m.group(0)!.length;
    } else {
      // remove preceding comma instead
      final before = source.substring(0, start);
      final pm = RegExp(r',\s*$').firstMatch(before);
      if (pm != null) return TextEdit(pm.start, end - pm.start, '');
    }
    return TextEdit(start, e - start, '');
  }

  /// Inserts widget source [snippet] as a child of [parent]: appended to its
  /// `children:` list, or as `child:` when it takes a single child.
  void insertChild(WidgetNode parent, String snippet, {bool singleChildAllowed = true, int? index}) {
    final list = parent.childrenList;
    if (list != null) {
      final els = list.elements;
      if (index != null && index < els.length) {
        final at = els[index].offset;
        _apply([TextEdit(at, 0, '$snippet, ')], anchor: at);
        return;
      }
      if (els.isEmpty) {
        _apply([TextEdit(list.leftBracket.end, 0, snippet)], anchor: list.leftBracket.end);
      } else {
        final close = list.rightBracket.offset;
        final trailing = list.rightBracket.previous?.lexeme == ',';
        _apply([TextEdit(close, 0, trailing ? '$snippet, ' : ', $snippet')], anchor: close);
      }
      return;
    }
    if (singleChildAllowed && parent.arg('child') == null) {
      _insertArgument(parent, 'child: $snippet');
      return;
    }
    if (parent.arg('child') != null) {
      throw SourceEditException('${parent.type} already has a child. Wrap it in a Column or Row first.');
    }
    throw SourceEditException('${parent.type} does not take children.');
  }

  /// Deletes [node] from its parent (list element or named slot).
  void removeNode(WidgetNode node) {
    final p = node.expression.parent;
    if (p is ListLiteral) {
      _apply([_removalWithComma(node.offset, node.end)], anchor: node.offset);
    } else if (p is NamedExpression) {
      _apply([_removalWithComma(p.offset, p.end)], anchor: p.offset);
    } else {
      throw SourceEditException('The root widget of a page cannot be removed; replace it instead.');
    }
  }

  /// Wraps [node] as `Wrapper(<slot>: node, extra)`.
  void wrapNode(WidgetNode node, String wrapper, {String slot = 'child', String extraArgs = ''}) {
    final inner = source.substring(node.offset, node.end);
    final extra = extraArgs.isEmpty ? '' : '$extraArgs, ';
    final body = slot == 'children' ? 'children: [$inner]' : '$slot: $inner';
    _apply([TextEdit(node.offset, node.end - node.offset, '$wrapper($extra$body)')], anchor: node.offset);
  }

  /// Moves a list element one position up (-1) or down (+1).
  void moveInList(WidgetNode node, int delta) {
    final p = node.expression.parent;
    if (p is! ListLiteral) throw SourceEditException('Only items inside a children list can be reordered.');
    final els = p.elements.toList();
    final i = els.indexOf(node.expression);
    final j = i + delta;
    if (j < 0 || j >= els.length) return;
    final a = els[i < j ? i : j];
    final b = els[i < j ? j : i];
    final as = source.substring(a.offset, a.end);
    final bs = source.substring(b.offset, b.end);
    _apply([TextEdit(b.offset, b.length, as), TextEdit(a.offset, a.length, bs)], anchor: a.offset);
  }

  /// Replaces the whole file (code view edits); throws when it does not parse.
  void replaceSource(String text) {
    final before = source;
    source = text;
    _parse();
    if (diagnostics.isNotEmpty) {
      final errs = diagnostics;
      source = before;
      _parse();
      throw SourceEditException('Not valid Dart: ${errs.first}');
    }
  }
}

class _ReturnFinder extends RecursiveAstVisitor<void> {
  _ReturnFinder(this.onFound);
  final void Function(Expression) onFound;
  @override
  void visitReturnStatement(ReturnStatement node) {
    final e = node.expression;
    if (e != null) onFound(e);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {} // skip closures
}

class _NodeAtOffset extends GeneralizingAstVisitor<void> {
  _NodeAtOffset(this.offset);
  final int offset;
  AstNode? found;
  @override
  void visitNode(AstNode node) {
    if (node.offset <= offset && offset <= node.end) {
      found = node;
      super.visitNode(node);
    }
  }
}
