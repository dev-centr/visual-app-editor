import 'dart:io';

import 'package:vae_core/src/sdl.dart';

/// Curated OSS + retail metadata (no font binaries). Sync with agent-rules catalog.
class TypefaceEntry {
  TypefaceEntry({
    required this.id,
    required this.display,
    required this.tier,
    this.fontsourceNpm,
    this.foundryUrl,
    this.recommendTags = const [],
  });

  final String id;
  final String display;
  final String tier;
  final String? fontsourceNpm;
  final String? foundryUrl;
  final List<String> recommendTags;

  bool get isOss => tier == 'oss';
  bool get isRetail => tier == 'retail';
}

class TypefaceCatalog {
  TypefaceCatalog(this.faces);

  final List<TypefaceEntry> faces;

  TypefaceEntry? byId(String id) {
    for (final f in faces) {
      if (f.id == id) return f;
    }
    return null;
  }

  Iterable<TypefaceEntry> ossWithRecommend(String tag) =>
      faces.where((f) => f.isOss && f.recommendTags.contains(tag));

  static TypefaceCatalog bundled() => parse(loadBundledSdl());

  static String loadBundledSdl() {
    final override = Platform.environment['VAE_TYPEFACE_CATALOG'];
    if (override != null && override.isNotEmpty) {
      final f = File(override);
      if (f.existsSync()) return f.readAsStringSync();
    }
    for (final path in _catalogCandidates()) {
      final f = File(path);
      if (f.existsSync()) return f.readAsStringSync();
    }
    return _embeddedCatalogSdl;
  }

  static List<String> _catalogCandidates() {
    final sep = Platform.pathSeparator;
    final cwd = Directory.current.path;
    final script = Platform.script.toFilePath();
    return [
      '$cwd${sep}packages${sep}core${sep}lib${sep}catalog${sep}project-typefaces.sdl',
      if (script.contains('${sep}lib${sep}src${sep}'))
        script.replaceFirst('${sep}src${sep}', '${sep}catalog${sep}').replaceAll(RegExp(r'typeface_catalog\.dart$'), 'project-typefaces.sdl'),
      '$cwd${sep}lib${sep}catalog${sep}project-typefaces.sdl',
    ];
  }

  static TypefaceCatalog parse(String sdl) {
    final root = parseSdl(sdl);
    final cat = root.child('catalog') ?? root;
    final out = <TypefaceEntry>[];
    for (final tag in cat.all('face')) {
      final id = tag.stringValue;
      if (id == null || id.isEmpty) continue;
      final tags = <String>[];
      for (final r in tag.all('recommend')) {
        if (r.values.isNotEmpty) {
          tags.add('${r.values.first}');
        } else {
          tags.addAll(r.attributes.values.map((v) => '$v'));
        }
      }
      out.add(
        TypefaceEntry(
          id: id,
          display: '${tag.child('display')?.stringValue ?? id}',
          tier: '${tag.child('tier')?.stringValue ?? 'oss'}',
          fontsourceNpm: tag.child('fontsource')?.attributes['npm'] as String?,
          foundryUrl: tag.child('foundry_url')?.stringValue,
          recommendTags: tags,
        ),
      );
    }
    return TypefaceCatalog(out);
  }
}

/// Minimal embedded catalog when the SDL file is not on disk (compiled snapshots).
const _embeddedCatalogSdl = r'''
catalog "project-typefaces" version "2026.10.20" {
  face "dm-sans" { display "DM Sans" tier oss fontsource npm "@fontsource-variable/dm-sans" recommend oss_ui_sans }
  face "inter" { display "Inter" tier oss fontsource npm "@fontsource-variable/inter" recommend oss_ui_sans }
  face "jetbrains-mono" { display "JetBrains Mono" tier oss fontsource npm "@fontsource/jetbrains-mono" recommend oss_code_mono }
  face "graphik" { display "Graphik" tier retail foundry_url "https://commercialtype.com/catalog/graphik" }
}
''';
