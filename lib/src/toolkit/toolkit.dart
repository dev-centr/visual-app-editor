import '../sdl/sdl.dart';

/// One constructor parameter of a palette widget.
class WidgetParam {
  const WidgetParam({
    required this.name,
    required this.type,
    this.isNamed = true,
    this.isRequired = false,
    this.defaultValue,
  });

  final String name;
  final String type;
  final bool isNamed;
  final bool isRequired;
  final String? defaultValue;

  bool get isChild => name == 'child' || name == 'body' || name == 'home' || name == 'title' && type.startsWith('Widget');
  bool get isChildren => type.startsWith('List<Widget');
  bool get takesWidget => type.replaceAll('?', '') == 'Widget' || type.replaceAll('?', '') == 'PreferredSizeWidget';

  @override
  String toString() => '${isRequired ? 'required ' : ''}$type $name';
}

/// A palette entry: one public widget constructor discovered in a toolkit.
class WidgetSpec {
  WidgetSpec({
    required this.className,
    required this.toolkitId,
    this.constructorName,
    this.params = const [],
    this.doc,
    this.category = 'Other',
    this.sourceFile,
  });

  final String className;
  final String? constructorName;
  final String toolkitId;
  final List<WidgetParam> params;
  final String? doc;
  String category;
  final String? sourceFile;

  String get invocation => constructorName == null ? className : '$className.$constructorName';

  WidgetParam? param(String name) {
    for (final p in params) {
      if (p.name == name) return p;
    }
    return null;
  }

  bool get acceptsChild => params.any((p) => p.isNamed && p.takesWidget && (p.name == 'child' || p.name == 'body'));
  bool get acceptsChildren => params.any((p) => p.isChildren && p.name == 'children');

  /// Minimal source snippet inserted when the entry is dropped on the tree.
  String snippet() {
    final args = <String>[];
    for (final p in params.where((p) => p.isRequired)) {
      final v = placeholderFor(p);
      args.add(p.isNamed ? '${p.name}: $v' : v);
    }
    if (acceptsChildren && !args.any((a) => a.startsWith('children:'))) {
      args.add('children: []');
    }
    return '$invocation(${args.join(', ')})';
  }

  static String placeholderFor(WidgetParam p) {
    final t = p.type.replaceAll('?', '');
    if (t == 'String') return "'${p.name}'";
    if (t == 'int') return '0';
    if (t == 'double') return '0.0';
    if (t == 'bool') return 'false';
    if (t.startsWith('List')) return 'const []';
    if (t == 'Widget' || t == 'PreferredSizeWidget') return "const Text('${p.name}')";
    if (t.contains('Function') || t.startsWith('VoidCallback') || t.startsWith('ValueChanged')) {
      return p.type.contains('ValueChanged') ? '(value) {}' : '() {}';
    }
    if (t == 'IconData') return 'Icons.star';
    return 'null';
  }
}

/// Toolkit plugin manifest (`toolkits/<id>.sdl`).
///
/// ```sdl
/// toolkit "material" {
///   name "Material"
///   package "flutter"
///   import "package:flutter/material.dart"
///   library "src/material" "src/widgets"
///   exclude "^_" "Render" "Inherited"
///   category "Layout" "Column" "Row" "Stack"
/// }
/// ```
class ToolkitManifest {
  ToolkitManifest({
    required this.id,
    required this.name,
    required this.package,
    required this.importUri,
    this.libraries = const ['src'],
    this.exclude = const [],
    this.include = const [],
    this.categories = const {},
    this.baseClasses = const [],
  });

  final String id;
  final String name;
  final String package;
  final String importUri;
  final List<String> libraries;
  final List<String> exclude;
  final List<String> include;
  final Map<String, List<String>> categories;
  final List<String> baseClasses;

  static List<ToolkitManifest> parse(String source) {
    final root = parseSdl(source);
    return [
      for (final t in root.all('toolkit'))
        ToolkitManifest(
          id: t.stringValue ?? 'unnamed',
          name: '${t.childValue('name') ?? t.stringValue}',
          package: '${t.childValue('package') ?? t.stringValue}',
          importUri: '${t.childValue('import') ?? 'package:${t.childValue('package')}/${t.childValue('package')}.dart'}',
          libraries: t.child('library') == null ? const ['src'] : t.childStrings('library'),
          exclude: t.childStrings('exclude'),
          include: t.childStrings('include'),
          baseClasses: t.childStrings('base'),
          categories: {
            for (final c in t.all('category'))
              if (c.values.isNotEmpty) '${c.values.first}': [for (final v in c.values.skip(1)) '$v'],
          },
        ),
    ];
  }

  String categoryOf(String className) {
    for (final e in categories.entries) {
      if (e.value.contains(className)) return e.key;
    }
    return 'Other';
  }
}

/// A loaded toolkit: manifest + discovered widgets.
class Toolkit {
  Toolkit(this.manifest, this.widgets, {this.packageRoot, this.warnings = const []});
  final ToolkitManifest manifest;
  final List<WidgetSpec> widgets;
  final String? packageRoot;
  final List<String> warnings;

  WidgetSpec? find(String className) {
    for (final w in widgets) {
      if (w.className == className && w.constructorName == null) return w;
    }
    for (final w in widgets) {
      if (w.className == className) return w;
    }
    return null;
  }
}
