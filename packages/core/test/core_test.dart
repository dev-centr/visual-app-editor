import 'package:test/test.dart';
import 'package:vae_core/vae_core.dart';

void main() {
  test('edit ops round-trip through JSON', () {
    const ops = <EditOp>[
      SetArgument([0, 1], 'color', 'Colors.red'),
      RemoveArgument([0], 'style'),
      SetPositional([0, 2], 0, "'Hi'"),
      SetText([1], 'Hello'),
      InsertChild([0], "Text('x')", index: 2),
      RemoveNode([0, 3]),
      WrapNode([0, 1], 'Padding', extraArgs: 'padding: EdgeInsets.all(8)'),
      MoveInList([0, 1], -1),
      ReplaceSource('void main() {}'),
    ];
    for (final o in ops) {
      final back = EditOp.fromJson(o.toJson());
      expect(back.toJson(), o.toJson());
      expect(back.runtimeType, o.runtimeType);
    }
    expect(() => EditOp.fromJson({'op': 'nope'}), throwsArgumentError);
  });

  test('tree nodes serialise and resolve paths', () {
    final root = TreeNode(type: 'Column', path: [0], args: [], children: [
      TreeNode(type: 'Text', path: [0, 0], slot: 'children', args: [const ArgInfo(source: "'Hello'")]),
      TreeNode(type: 'View', path: [0, 1], slot: 'children', text: 'Hi there'),
    ]);
    final back = TreeNode.fromJson(root.toJson());
    expect(back.find([0, 0])!.label, 'Text "Hello"');
    expect(back.find([0, 1])!.label, 'View "Hi there"');
    expect(back.parentOf(back.find([0, 1])!)!.type, 'Column');
    final page = PageInfo.fromJson(PageInfo(name: 'Home', file: 'lib/home.dart', root: root).toJson());
    expect(page.root!.walk().length, 3);
  });

  test('device presets cover every mode and support custom sizes', () {
    for (final m in DeviceMode.values) {
      expect(DevicePresets.forMode(m), isNotEmpty);
    }
    expect(DevicePresets.byId('missing').id, 'phone');
    expect(DevicePresets.byId('tablet').rotated.width, 1180);
    final c = DevicePresets.custom(700, 500);
    expect(c.frame, isFalse);
    expect(DevicePresets.modeForWidth(700), DeviceMode.tablet);
  });

  test('widget specs serialise with snippets', () {
    final s = WidgetSpec(className: 'Text', toolkitId: 'widgets', params: const [WidgetParam(name: 'data', type: 'String', isNamed: false, isRequired: true)]);
    final back = WidgetSpec.fromJson(s.toJson());
    expect(back.snippet(), "Text('data')");
    expect(back.params.single.isNamed, isFalse);
  });
}
