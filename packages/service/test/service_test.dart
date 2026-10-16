import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vae_protocol/vae_protocol.dart';
import 'package:vae_service/vae_service.dart';

Directory copySample() {
  final tmp = Directory.systemTemp.createTempSync('vae');
  for (final f in Directory('test/sample_app').listSync(recursive: true).whereType<File>()) {
    final out = File(p.join(tmp.path, p.relative(f.path, from: 'test/sample_app')));
    out.parent.createSync(recursive: true);
    f.copySync(out.path);
  }
  return tmp;
}

void main() {
  test('in-process session: open, tree, edit, save', () async {
    final dir = copySample();
    final c = connectInProcess();
    await expectLater(c.request(Methods.projectOpen, {'root': dir.path}), throwsA(isA<RpcException>()));
    final init = await c.request(Methods.initialize, {'clientName': 'test'}) as Map;
    expect((init['capabilities'] as Map)['editOps'], contains('insertChild'));
    final open = await c.request(Methods.projectOpen, {'root': dir.path}) as Map;
    expect(open['name'], 'sample_app');
    final pages = [for (final x in open['pages'] as List) (x as Map)['name']];
    expect(pages, containsAll(['HomePage', 'SettingsPage']));
    final tree = await c.request(Methods.documentTree, {'file': 'lib/pages/home_page.dart', 'page': 'HomePage'}) as Map;
    expect((tree['root'] as Map)['type'], 'Scaffold');
    final changed = c.notifications.firstWhere((n) => n.method == Methods.documentChanged);
    final r = await c.request(Methods.documentEdit, {
      'file': 'lib/pages/home_page.dart',
      'page': 'HomePage',
      'op': {'op': 'insertChild', 'path': [0, 1, 0], 'snippet': "Text('From service')"},
    }) as Map;
    expect(r['source'], contains("Text('From service')"));
    expect((await changed).params['file'], 'lib/pages/home_page.dart');
    await expectLater(
      c.request(Methods.documentEdit, {
        'file': 'lib/pages/home_page.dart',
        'page': 'HomePage',
        'op': {'op': 'setPositional', 'path': [0, 0, 0], 'index': 0, 'value': "'broken"},
      }),
      throwsA(isA<RpcException>().having((e) => e.code, 'code', ErrorCodes.editRejected)),
    );
    await c.request(Methods.documentSave, {});
    expect(File(p.join(dir.path, 'lib/pages/home_page.dart')).readAsStringSync(), contains('From service'));
    final kits = await c.request(Methods.toolkitList) as List;
    expect(kits.map((k) => (k as Map)['id']), containsAll(['material', 'shadcn_ui']));
    final presets = await c.request(Methods.devicePresets) as List;
    expect(presets.map((d) => (d as Map)['mode']).toSet(), {'phone', 'tablet', 'desktop', 'web'});
  });

  test('stdio executable speaks the framed protocol', () async {
    final proc = await Process.start(Platform.resolvedExecutable, ['run', 'bin/vae_service.dart']);
    final peer = RpcPeer(proc.stdout.transform(const MessageDecoder()), (m) => proc.stdin.add(encodeMessage(m)));
    proc.stderr.transform(utf8.decoder).listen((_) {});
    final init = await peer.request(Methods.initialize, {}) as Map;
    expect((init['serverInfo'] as Map)['name'], 'vae_service');
    await peer.request(Methods.shutdown);
    expect(await proc.exitCode.timeout(const Duration(seconds: 30)), 0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  final reactCli = File(p.join('..', '..', 'adapters', 'react', 'dist', 'cli.js')).absolute;
  test('external React adapter over stdio', () async {
    final dir = Directory.systemTemp.createTempSync('vae_react');
    File(p.join(dir.path, 'package.json')).writeAsStringSync('{"name":"rn_demo","dependencies":{"react-native":"*"}}');
    final comp = File(p.join(dir.path, 'src', 'Home.tsx'))..createSync(recursive: true);
    comp.writeAsStringSync(File(p.join('..', '..', 'adapters', 'react', 'test', 'fixtures', 'Home.tsx')).readAsStringSync());
    final c = connectInProcess();
    await c.request(Methods.initialize, {
      'externalAdapters': [
        {'id': 'react', 'extensions': ['.tsx', '.jsx'], 'command': ['node', reactCli.path]},
      ],
    });
    final open = await c.request(Methods.projectOpen, {'root': dir.path}) as Map;
    expect([for (final x in open['pages'] as List) (x as Map)['name']], containsAll(['Home', 'Card']));
    final r = await c.request(Methods.documentEdit, {
      'file': 'src/Home.tsx',
      'page': 'Home',
      'op': {'op': 'setArgument', 'path': [1], 'name': 'title', 'value': "'Next'"},
    }) as Map;
    expect(r['source'], contains('<Button title="Next"'));
    await expectLater(
      c.request(Methods.documentEdit, {
        'file': 'src/Home.tsx',
        'page': 'Home',
        'op': {'op': 'insertChild', 'path': <int>[], 'snippet': '<Text>'},
      }),
      throwsA(isA<RpcException>()),
    );
    await c.request(Methods.shutdown);
  }, skip: reactCli.existsSync() ? false : 'build adapters/react first (pnpm build)', timeout: const Timeout(Duration(minutes: 1)));
}
