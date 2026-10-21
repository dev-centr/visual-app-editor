import 'sdl.dart';

/// Editor settings stored in `<project>/visual_app_editor.sdl`.
class ProjectConfig {
  ProjectConfig({
    this.toolkits = const ['widgets', 'material'],
    this.device = 'phone',
    this.seedColor = 0xFF6750A4,
    this.dark = false,
    this.fontPreference = 'mixed',
    this.uiSansFace,
    this.uiMonoFace,
  });

  List<String> toolkits;
  String device;
  int seedColor;
  bool dark;

  /// `oss`, `retail`, or `mixed` — aligns with `.devcentr/fonts.sdl` / agent-rules font-project-lock.
  String fontPreference;
  String? uiSansFace;
  String? uiMonoFace;

  static const fileName = 'visual_app_editor.sdl';

  /// Pre-rename name, still read when [fileName] is missing.
  static const legacyFileName = 'widget_bench.sdl';

  static ProjectConfig parse(String text) {
    final root = parseSdl(text);
    final proj = root.child('project') ?? root;
    final theme = proj.child('theme');
    final seed = theme?.attributes['seed'];
    final typo = proj.child('typography');
    return ProjectConfig(
      toolkits: proj.child('toolkits') == null ? const ['widgets', 'material'] : proj.childStrings('toolkits'),
      device: '${proj.childValue('device') ?? 'phone'}',
      seedColor: seed is String ? int.tryParse(seed.replaceFirst('#', 'FF'), radix: 16) ?? 0xFF6750A4 : 0xFF6750A4,
      dark: theme?.attributes['brightness'] == 'dark',
      fontPreference: '${typo?.attributes['preference'] ?? 'mixed'}',
      uiSansFace: typo?.attributes['ui_sans'] as String?,
      uiMonoFace: typo?.attributes['ui_mono'] as String?,
    );
  }

  String write(String projectName) {
    final hex = (seedColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    final children = <SdlTag>[
      SdlTag('toolkits', values: [...toolkits]),
      SdlTag('device', values: [device]),
      SdlTag('theme', attributes: {'seed': '#$hex', 'brightness': dark ? 'dark' : 'light'}),
    ];
    if (fontPreference != 'mixed' || uiSansFace != null || uiMonoFace != null) {
      final attrs = <String, Object?>{'preference': fontPreference};
      if (uiSansFace != null) attrs['ui_sans'] = uiSansFace;
      if (uiMonoFace != null) attrs['ui_mono'] = uiMonoFace;
      children.add(SdlTag('typography', attributes: attrs));
    }
    return '// Visual App Editor project settings. Safe to commit; edited by the app.\n${writeSdl([
      SdlTag('project', values: [projectName], children: children),
    ])}';
  }
}

