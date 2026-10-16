import 'sdl.dart';

/// Editor settings stored in `<project>/visual_app_editor.sdl`.
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

  static const fileName = 'visual_app_editor.sdl';

  /// Pre-rename name, still read when [fileName] is missing.
  static const legacyFileName = 'widget_bench.sdl';

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
    return '// Visual App Editor project settings. Safe to commit; edited by the app.\n${writeSdl([
      SdlTag('project', values: [projectName], children: [
        SdlTag('toolkits', values: [...toolkits]),
        SdlTag('device', values: [device]),
        SdlTag('theme', attributes: {'seed': '#$hex', 'brightness': dark ? 'dark' : 'light'}),
      ]),
    ])}';
  }
}

