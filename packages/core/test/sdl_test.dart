import 'package:test/test.dart';
import 'package:vae_core/vae_core.dart';

void main() {
  test('parses tags, values, attributes and blocks', () {
    final root = parseSdl('''
// comment
project "demo" {
  toolkits "widgets" "material"   # trailing
  theme seed="#112233" brightness="dark"
  size 12 3.5 true null
}
''');
    final p = root.child('project')!;
    expect(p.stringValue, 'demo');
    expect(p.childStrings('toolkits'), ['widgets', 'material']);
    expect(p.child('theme')!.attributes['seed'], '#112233');
    expect(p.child('size')!.values, [12, 3.5, true, null]);
  });

  test('round-trips project config', () {
    final c = ProjectConfig(toolkits: ['material', 'forui'], device: 'tablet', seedColor: 0xFF123456, dark: true);
    final back = ProjectConfig.parse(c.write('x'));
    expect(back.toolkits, ['material', 'forui']);
    expect(back.device, 'tablet');
    expect(back.seedColor, 0xFF123456);
    expect(back.dark, isTrue);
  });

  test('parses toolkit manifests', () {
    final m = ToolkitManifest.parse('''
toolkit "kit" {
  name "Kit"
  package "fake_kit"
  library "src"
  exclude "^Base"
  category "Buttons" "FancyButton"
}''').single;
    expect(m.id, 'kit');
    expect(m.importUri, 'package:fake_kit/fake_kit.dart');
    expect(m.categoryOf('FancyButton'), 'Buttons');
  });

  test('reports errors with line numbers', () {
    expect(() => parseSdl('a {\n b 1\n'), throwsA(isA<SdlParseException>()));
  });
}
