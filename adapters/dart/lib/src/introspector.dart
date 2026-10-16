import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import 'package:vae_core/vae_core.dart';

/// Widget base classes that mark a class as a widget when the package's
/// own hierarchy cannot be followed further.
const kWidgetRoots = {
  'Widget', 'StatelessWidget', 'StatefulWidget', 'InheritedWidget', 'ProxyWidget',
  'RenderObjectWidget', 'LeafRenderObjectWidget', 'SingleChildRenderObjectWidget',
  'MultiChildRenderObjectWidget', 'ParentDataWidget', 'InheritedTheme', 'ImplicitlyAnimatedWidget',
  'AnimatedWidget', 'StatefulHookWidget', 'HookWidget', 'ConsumerWidget', 'ConsumerStatefulWidget',
  'PreferredSizeWidget',
};

/// Discovers the public widget constructors of a Dart package by parsing its
/// sources with `package:analyzer` (syntactic AST; no SDK resolution needed,
/// so it works fully offline on any machine that has the package sources).
class ToolkitIntrospector {
  /// Resolves [package] to its `lib/` directory through a project's
  /// `.dart_tool/package_config.json`.
  static String? resolvePackageLib(String projectRoot, String package) {
    final cfg = File(p.join(projectRoot, '.dart_tool', 'package_config.json'));
    if (!cfg.existsSync()) return null;
    final json = jsonDecode(cfg.readAsStringSync()) as Map<String, dynamic>;
    for (final pkg in (json['packages'] as List).cast<Map<String, dynamic>>()) {
      if (pkg['name'] != package) continue;
      var root = Uri.parse(pkg['rootUri'] as String);
      if (!root.isAbsolute) {
        root = cfg.parent.uri.resolveUri(root.path.endsWith('/') ? root : Uri.parse('${root.path}/'));
      }
      final lib = root.resolve(pkg['packageUri'] as String? ?? 'lib/');
      return p.normalize(lib.toFilePath());
    }
    return null;
  }

  /// Parses every `.dart` file under [libDir] restricted to the manifest's
  /// library prefixes and returns the discovered widgets.
  static Toolkit introspect(ToolkitManifest m, String libDir) {
    final warnings = <String>[];
    final classes = <String, ClassDeclaration>{};
    final files = <String, String>{};
    final roots = [for (final l in m.libraries) Directory(p.join(libDir, l))];
    for (final dir in roots) {
      if (!dir.existsSync()) {
        warnings.add('Missing library folder ${dir.path}');
        continue;
      }
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final result = parseString(content: f.readAsStringSync(), path: f.path, throwIfDiagnostics: false);
        for (final d in result.unit.declarations.whereType<ClassDeclaration>()) {
          final name = classNameOf(d);
          if (name.startsWith('_')) continue;
          classes[name] = d;
          files[name] = f.path;
        }
      }
    }

    final bases = {...kWidgetRoots, ...m.baseClasses};
    final memo = <String, bool>{};
    bool isWidget(String name, [int depth = 0]) {
      if (bases.contains(name)) return true;
      if (depth > 40) return false;
      final cached = memo[name];
      if (cached != null) return cached;
      final d = classes[name];
      if (d == null) return memo[name] = false;
      final sup = superclassOf(d);
      final result = sup != null && isWidget(sup, depth + 1);
      return memo[name] = result;
    }

    final excludes = [for (final e in m.exclude) RegExp(e)];
    final includes = [for (final e in m.include) RegExp(e)];
    final out = <WidgetSpec>[];
    for (final e in classes.entries) {
      final d = e.value;
      if (d.abstractKeyword != null) continue;
      if (!isWidget(e.key)) continue;
      if (excludes.any((r) => r.hasMatch(e.key)) && !includes.any((r) => r.hasMatch(e.key))) continue;
      if (includes.isNotEmpty && m.exclude.contains('*') && !includes.any((r) => r.hasMatch(e.key))) continue;
      for (final c in d.members.whereType<ConstructorDeclaration>()) {
        final cname = c.name?.lexeme;
        if (cname != null && cname.startsWith('_')) continue;
        if (c.factoryKeyword != null && c.redirectedConstructor == null && cname == null) {
          // public unnamed factory: still constructible.
        }
        out.add(WidgetSpec(
          className: e.key,
          constructorName: cname,
          toolkitId: m.id,
          params: _params(c, d),
          doc: _doc(d),
          category: m.categoryOf(e.key),
          sourceFile: files[e.key],
        ));
      }
      if (!d.members.any((x) => x is ConstructorDeclaration)) {
        out.add(WidgetSpec(className: e.key, toolkitId: m.id, doc: _doc(d), category: m.categoryOf(e.key), sourceFile: files[e.key]));
      }
    }
    out.sort((a, b) => a.invocation.compareTo(b.invocation));
    return Toolkit(m, out, packageRoot: libDir, warnings: warnings);
  }

  static String? _doc(ClassDeclaration d) {
    final c = d.documentationComment;
    if (c == null) return null;
    final lines = c.tokens.map((t) => t.lexeme.replaceFirst(RegExp(r'^///\s?'), '')).toList();
    final firstPara = lines.takeWhile((l) => l.trim().isNotEmpty).join(' ');
    return firstPara.isEmpty ? null : firstPara;
  }

  static List<WidgetParam> _params(ConstructorDeclaration c, ClassDeclaration cls) {
    final fieldTypes = <String, String>{};
    for (final f in cls.members.whereType<FieldDeclaration>()) {
      final t = f.fields.type?.toSource() ?? 'dynamic';
      for (final v in f.fields.variables) {
        fieldTypes[v.name.lexeme] = t;
      }
    }
    final out = <WidgetParam>[];
    for (final fp in c.parameters.parameters) {
      final inner = fp is DefaultFormalParameter ? fp.parameter : fp;
      final name = inner.name?.lexeme;
      if (name == null || name == 'key') continue;
      String type;
      if (inner is SimpleFormalParameter) {
        type = inner.type?.toSource() ?? 'dynamic';
      } else if (inner is FieldFormalParameter) {
        type = inner.type?.toSource() ?? fieldTypes[name] ?? 'dynamic';
      } else if (inner is SuperFormalParameter) {
        type = inner.type?.toSource() ?? fieldTypes[name] ?? 'dynamic';
      } else {
        type = 'Function';
      }
      out.add(WidgetParam(
        name: name,
        type: type,
        isNamed: fp.isNamed,
        isRequired: fp.isRequiredNamed || fp.isRequiredPositional,
        defaultValue: fp is DefaultFormalParameter ? fp.defaultValue?.toSource() : null,
      ));
    }
    return out;
  }
}

/// Class name, tolerant of analyzer API generations.
String classNameOf(ClassDeclaration d) {
  final dynamic dd = d;
  try {
    return (dd.name as dynamic).lexeme as String;
  } catch (_) {
    return (dd.namePart.typeName as dynamic).lexeme as String;
  }
}

String? superclassOf(ClassDeclaration d) {
  final ext = d.extendsClause;
  if (ext == null) return null;
  final src = ext.superclass.toSource();
  return src.split('<').first.split('.').last;
}
