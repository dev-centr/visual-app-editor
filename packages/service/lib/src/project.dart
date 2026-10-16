import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vae_core/vae_core.dart';

/// A project folder opened by the service: config plus the source files
/// that some adapter can edit, held in memory until saved.
class Project {
  Project._(this.root, this.name, this.config, this.kind);

  final String root;
  final String name;
  /// `flutter`, `node`, or `unknown`.
  final String kind;
  ProjectConfig config;
  final Map<String, String> sources = {};
  final Set<String> dirty = {};

  static const _skipDirs = {'node_modules', 'build', '.dart_tool', '.git', 'dist', '.next', 'ios', 'android', 'windows', 'linux', 'macos', 'web'};

  static Project open(String root, bool Function(String path) editable) {
    if (!Directory(root).existsSync()) throw FileSystemException('Folder not found', root);
    String name = p.basename(root);
    String kind = 'unknown';
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    final pkg = File(p.join(root, 'package.json'));
    if (pubspec.existsSync()) {
      kind = 'flutter';
      final line = pubspec.readAsLinesSync().firstWhere((l) => l.startsWith('name:'), orElse: () => 'name: $name');
      name = line.substring(5).trim();
    } else if (pkg.existsSync()) {
      kind = 'node';
      final j = jsonDecode(pkg.readAsStringSync());
      if (j is Map && j['name'] is String) name = j['name'] as String;
    } else {
      throw FileSystemException('Not a project (no pubspec.yaml or package.json)', root);
    }
    var cfgFile = File(p.join(root, ProjectConfig.fileName));
    if (!cfgFile.existsSync()) cfgFile = File(p.join(root, ProjectConfig.legacyFileName));
    final cfg = cfgFile.existsSync() ? ProjectConfig.parse(cfgFile.readAsStringSync()) : ProjectConfig();
    final proj = Project._(root, name, cfg, kind);
    proj._scan(editable);
    return proj;
  }

  void _scan(bool Function(String) editable) {
    sources.clear();
    void walk(Directory d) {
      for (final e in d.listSync()) {
        final base = p.basename(e.path);
        if (e is Directory) {
          if (!_skipDirs.contains(base) && !base.startsWith('.')) walk(e);
        } else if (e is File) {
          final rel = p.relative(e.path, from: root).replaceAll('\\', '/');
          if (editable(rel)) sources[rel] = e.readAsStringSync();
        }
      }
    }

    for (final sub in ['lib', 'src', 'app', 'components', 'screens']) {
      final d = Directory(p.join(root, sub));
      if (d.existsSync()) walk(d);
    }
  }

  void save(String rel) {
    final s = sources[rel];
    if (s == null) return;
    File(p.join(root, rel)).writeAsStringSync(s);
    dirty.remove(rel);
  }

  void saveConfig() => File(p.join(root, ProjectConfig.fileName)).writeAsStringSync(config.write(name));

  /// Creates a Flutter page file `lib/pages/<snake>.dart`.
  String addFlutterPage(String className) {
    final snake = className.replaceAllMapped(RegExp(r'(?<=[a-z0-9])[A-Z]'), (m) => '_${m[0]}').toLowerCase();
    final rel = 'lib/pages/$snake.dart';
    final file = File(p.join(root, rel));
    if (file.existsSync()) throw FileSystemException('Page file already exists', file.path);
    file.parent.createSync(recursive: true);
    final src = '''import 'package:flutter/material.dart';

class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('$className')),
      body: Column(children: []),
    );
  }
}
''';
    file.writeAsStringSync(src);
    sources[rel] = src;
    return rel;
  }
}
