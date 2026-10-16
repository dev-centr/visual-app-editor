import 'dart:io';

import 'package:test/test.dart';
import 'package:vae_core/vae_core.dart';
import 'package:vae_dart_adapter/vae_dart_adapter.dart';

void main() {
  final a = DartFlutterAdapter();
  final src = File('test/fixtures/home_page.dart').readAsStringSync();

  test('exposes pages as neutral trees', () {
    final pages = a.pages('lib/pages/home_page.dart', src);
    expect(pages.single.name, 'HomePage');
    expect(pages.single.kind, 'state');
    final root = pages.single.root!;
    expect(root.type, 'Scaffold');
    expect(root.find([0, 1, 0, 0])!.label, 'Text "Good morning"');
  });

  test('applies protocol edit ops', () {
    var s = a.applyEdit('x.dart', src, 'HomePage', const SetText([0, 1, 0, 0], "Hi 'there'"));
    expect(s, contains(r"'Hi \'there\''"));
    s = a.applyEdit('x.dart', s, 'HomePage', const InsertChild([0, 1, 0], "Text('New')"));
    expect(a.pages('x.dart', s).single.root!.find([0, 1, 0])!.children.length, 9);
    s = a.applyEdit('x.dart', s, 'HomePage', const SetArgument([0, 0], 'centerTitle', 'true'));
    expect(s, contains('centerTitle: true'));
    expect(() => a.applyEdit('x.dart', s, 'HomePage', const RemoveNode([9, 9])), throwsA(isA<SourceEditException>()));
  });

  test('bundled toolkit manifests parse', () {
    final ids = [for (final t in bundledToolkits.values) ...ToolkitManifest.parse(t).map((m) => m.id)];
    expect(ids, containsAll(['widgets', 'material', 'cupertino', 'shadcn_ui', 'forui', 'fluent_ui', 'macos_ui']));
  });

  test('bundled_toolkits.dart is in sync with toolkits/', () {
    for (final f in Directory('toolkits').listSync().whereType<File>()) {
      expect(bundledToolkits[f.uri.pathSegments.last], f.readAsStringSync().replaceAll('\r\n', '\n'), reason: 'run dart run tool/gen_bundled.dart');
    }
  });

  test('parses single expressions', () {
    expect(parseDartExpression('EdgeInsets.all(8)'), isNotNull);
    expect(parseDartExpression('(('), isNull);
  });
}
