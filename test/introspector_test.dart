import 'package:flutter_test/flutter_test.dart';
import 'package:widget_bench/src/toolkit/introspector.dart';
import 'package:widget_bench/src/toolkit/toolkit.dart';

void main() {
  final m = ToolkitManifest(id: 'kit', name: 'Kit', package: 'fake_kit', importUri: 'package:fake_kit/kit.dart', categories: {
    'Buttons': ['FancyButton'],
  });

  test('finds public concrete widgets and their constructors', () {
    final t = ToolkitIntrospector.introspect(m, 'test/fixtures/fake_kit/lib');
    final names = t.widgets.map((w) => w.invocation).toList();
    expect(names, containsAll(['FancyButton', 'FancyCard', 'FancyCard.compact']));
    expect(names, isNot(contains('_Hidden')));
    expect(names, isNot(contains('BaseCard')));
    expect(names, isNot(contains('NotAWidget')));
  });

  test('extracts parameter types, required flags and defaults', () {
    final t = ToolkitIntrospector.introspect(m, 'test/fixtures/fake_kit/lib');
    final b = t.find('FancyButton')!;
    expect(b.category, 'Buttons');
    expect(b.doc, 'A fancy button.');
    expect(b.param('label')!.type, 'String');
    expect(b.param('label')!.isRequired, isTrue);
    expect(b.param('size')!.defaultValue, '12.0');
    expect(b.param('onPressed')!.type, 'VoidCallback?');
    expect(b.acceptsChild, isTrue);
    expect(b.snippet(), "FancyButton(label: 'label')");
    expect(t.find('FancyCard')!.acceptsChildren, isTrue);
  });
}
