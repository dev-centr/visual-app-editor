import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../source/dart_document.dart';
import 'introspector.dart';
import 'toolkit.dart';

/// Locates toolkit manifests (bundled + user + project) and loads them
/// against a project's resolved packages.
class ToolkitRegistry {
  static const bundled = ['widgets', 'material', 'cupertino', 'shadcn_ui', 'forui', 'fluent_ui', 'macos_ui'];

  final Map<String, ToolkitManifest> manifests = {};
  final Map<String, Toolkit> loaded = {};
  final List<String> log = [];

  Future<void> loadBundledManifests() async {
    for (final id in bundled) {
      try {
        addManifests(await rootBundle.loadString('toolkits/$id.sdl'));
      } catch (e) {
        log.add('Could not read bundled toolkit $id: $e');
      }
    }
  }

  /// Reads extra `*.sdl` manifests from [dir] (e.g. `<project>/.widget_bench/toolkits`).
  void loadManifestDir(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return;
    for (final f in d.listSync().whereType<File>().where((f) => f.path.endsWith('.sdl'))) {
      addManifests(f.readAsStringSync());
    }
  }

  void addManifests(String sdl) {
    for (final m in ToolkitManifest.parse(sdl)) {
      manifests[m.id] = m;
    }
  }

  /// Finds the package `lib/` for [m] from the project, falling back to the
  /// Flutter SDK for the `flutter` package.
  static String? locate(ToolkitManifest m, String? projectRoot) {
    if (projectRoot != null) {
      final r = ToolkitIntrospector.resolvePackageLib(projectRoot, m.package);
      if (r != null && Directory(r).existsSync()) return r;
    }
    if (m.package == 'flutter') {
      final sdk = flutterSdkRoot();
      if (sdk != null) {
        final lib = p.join(sdk, 'packages', 'flutter', 'lib');
        if (Directory(lib).existsSync()) return lib;
      }
    }
    return null;
  }

  static String? flutterSdkRoot() {
    final env = Platform.environment['FLUTTER_ROOT'];
    if (env != null && env.isNotEmpty) return env;
    final pathVar = Platform.environment['PATH'] ?? '';
    for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
      final exe = File(p.join(dir, Platform.isWindows ? 'flutter.bat' : 'flutter'));
      if (exe.existsSync()) return p.dirname(p.dirname(exe.path));
    }
    return null;
  }

  Toolkit? load(String id, {String? projectRoot}) {
    final m = manifests[id];
    if (m == null) return null;
    final lib = locate(m, projectRoot);
    if (lib == null) {
      log.add('Toolkit ${m.name}: package "${m.package}" not found. Add it to the project and run pub get.');
      return null;
    }
    final t = ToolkitIntrospector.introspect(m, lib);
    DartDocument.knownWidgets.addAll(t.widgets.map((w) => w.className));
    log.add('Toolkit ${m.name}: ${t.widgets.length} constructors from $lib');
    log.addAll(t.warnings);
    return loaded[id] = t;
  }

  WidgetSpec? findWidget(String className) {
    for (final t in loaded.values) {
      final w = t.find(className);
      if (w != null) return w;
    }
    return null;
  }
}
