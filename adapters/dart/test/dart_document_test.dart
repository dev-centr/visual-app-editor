import 'dart:io';

import 'package:test/test.dart';
import 'package:vae_core/vae_core.dart';
import 'package:vae_dart_adapter/vae_dart_adapter.dart';

void main() {
  late DartDocument d;
  setUp(() => d = DartDocument(File('test/fixtures/home_page.dart').readAsStringSync()));

  test('finds pages and the widget tree', () {
    final p = d.page('HomePage')!;
    expect(p.isState, isTrue);
    final root = p.root!;
    expect(root.type, 'Scaffold');
    expect(root.children.map((c) => c.slot), ['appBar', 'body', 'floatingActionButton']);
    final column = root.children[1].children.single;
    expect(column.type, 'Column');
    expect(column.children.length, 8);
    expect(column.children.first.label, 'Text "Good morning"');
  });

  test('setting a property only touches that expression', () {
    final title = d.page('HomePage')!.root!.children.first.children.first;
    expect(title.type, 'Text');
    d.setPositional(title, 0, "'Hello trails'");
    expect(d.source, contains("Text('Hello trails')"));
    expect(d.source, contains('// Custom code: untouched by visual edits.'));
    expect(d.source, contains('void _increment() => setState(() => _taps++);'));
  });

  test('adds a named argument and strips const where needed', () {
    final title = d.nodeAt('HomePage', [0, 0, 0])!;
    d.setArgument(title, 'style', 'TextStyle(color: Colors.red)');
    expect(d.source, contains("Text('Trail Notes', style: TextStyle(color: Colors.red))"));
    expect(d.diagnostics, isEmpty);
  });

  test('inserts, moves and removes children', () {
    var column = d.nodeAt('HomePage', [0, 1, 0])!;
    d.insertChild(column, "Text('Added')");
    column = d.nodeAt('HomePage', [0, 1, 0])!;
    expect(column.children.length, 9);
    expect(column.children.last.label, 'Text "Added"');
    d.moveInList(column.children.last, -1);
    column = d.nodeAt('HomePage', [0, 1, 0])!;
    expect(column.children[7].label, 'Text "Added"');
    d.removeNode(column.children[7]);
    column = d.nodeAt('HomePage', [0, 1, 0])!;
    expect(column.children.length, 8);
    expect(d.source, isNot(contains('Added')));
  });

  test('wraps a node', () {
    final fab = d.nodeAt('HomePage', [0, 2])!;
    expect(fab.type, 'FloatingActionButton');
    d.wrapNode(fab, 'Padding', extraArgs: 'padding: EdgeInsets.all(4)');
    expect(d.nodeAt('HomePage', [0, 2])!.type, 'Padding');
    expect(d.nodeAt('HomePage', [0, 2, 0])!.type, 'FloatingActionButton');
  });

  test('rejects edits that break the file', () {
    final before = d.source;
    final title = d.nodeAt('HomePage', [0, 0, 0])!;
    expect(() => d.setPositional(title, 0, "'unterminated"), throwsA(isA<SourceEditException>()));
    expect(d.source, before);
  });

  test('unrelated bytes are preserved exactly', () {
    final orig = d.source;
    final t = d.nodeAt('HomePage', [0, 1, 0, 2])!;
    d.setPositional(t, 0, "'X'");
    final i = orig.indexOf("'Three hikes planned this week.'");
    expect(d.source.substring(0, i), orig.substring(0, i));
    final tail = orig.substring(i + "'Three hikes planned this week.'".length);
    expect(d.source.endsWith(tail), isTrue);
  });
}
