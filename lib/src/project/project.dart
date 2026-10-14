import 'dart:io';

import 'package:path/path.dart' as p;

import '../sdl/sdl.dart';
import '../source/dart_document.dart';

/// Editor settings stored in `<project>/widget_bench.sdl`.
class ProjectConfig {
  ProjectConfig({
    this.toolkits = const ['widgets', 'material'],
    this.device = 'phone',
    this.seedColor = 0xFF6750A4,
    this.dark = false,
  });

  List<String> toolkits;
  String device;
  int seedColor;
  bool dark;

  static const fileName = 'widget_bench.sdl';

  static ProjectConfig parse(String text) {
    final root = parseSdl(text);
    final proj = root.child('project') ?? root;
    final theme = proj.child('theme');
    final seed = theme?.attributes['seed'];
    return ProjectConfig(
      toolkits: proj.child('toolkits') == null ? const ['widgets', 'material'] : proj.childStrings('toolkits'),
      device: '${proj.childValue('device') ?? 'phone'}',
      seedColor: seed is String ? int.tryParse(seed.replaceFirst('#', 'FF'), radix: 16) ?? 0xFF6750A4 : 0xFF6750A4,
      dark: theme?.attributes['brightness'] == 'dark',
    );
  }

  String write(String projectName) {
    final hex = (seedColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    return '// Widget Bench project settings. Safe to commit; edited by the app.\n${writeSdl([
      SdlTag('project', values: [projectName], children: [
        SdlTag('toolkits', values: [...toolkits]),
        SdlTag('device', values: [device]),
        SdlTag('theme', attributes: {'seed': '#$hex', 'brightness': dark ? 'dark' : 'light'}),
      ]),
    ])}';
  }
}

/// An opened Flutter project on disk.
class FlutterProject {
  FlutterProject._(this.root, this.name, this.config);

  final String root;
  final String name;
  ProjectConfig config;
  final Map<String, DartDocument> documents = {};

  static FlutterProject open(String root) {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw FileSystemException('Not a Flutter/Dart project (no pubspec.yaml)', root);
    }
    final nameLine = pubspec.readAsLinesSync().firstWhere((l) => l.startsWith('name:'), orElse: () => 'name: app');
    final name = nameLine.substring(5).trim();
    final cfgFile = File(p.join(root, ProjectConfig.fileName));
    final cfg = cfgFile.existsSync() ? ProjectConfig.parse(cfgFile.readAsStringSync()) : ProjectConfig();
    final proj = FlutterProject._(root, name, cfg);
    proj.reload();
    return proj;
  }

  void reload() {
    documents.clear();
    final lib = Directory(p.join(root, 'lib'));
    if (!lib.existsSync()) return;
    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
      final rel = p.relative(f.path, from: root).replaceAll('\\', '/');
      documents[rel] = DartDocument(f.readAsStringSync(), path: rel);
    }
  }

  /// Every page across files: (file, page).
  List<({String file, PageModel page})> get pages => [
        for (final e in documents.entries)
          for (final pg in e.value.pages)
            if (pg.root != null) (file: e.key, page: pg),
      ]..sort((a, b) => a.page.name.compareTo(b.page.name));

  void save(String relPath) {
    final d = documents[relPath];
    if (d == null) return;
    File(p.join(root, relPath)).writeAsStringSync(d.source);
  }

  void saveConfig() {
    File(p.join(root, ProjectConfig.fileName)).writeAsStringSync(config.write(name));
  }

  /// Creates `lib/pages/<snake>.dart` with a new StatelessWidget page.
  String addPage(String className) {
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
    documents[rel] = DartDocument(src, path: rel);
    return rel;
  }
}
