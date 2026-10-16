import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:vae_protocol/vae_protocol.dart';

void main() {
  test('framing survives arbitrary chunking and unicode', () async {
    final bytes = [
      ...encodeMessage({'jsonrpc': '2.0', 'method': 'a', 'params': {'s': 'héllo ✓'}}),
      ...encodeMessage({'jsonrpc': '2.0', 'id': 1, 'result': 42}),
    ];
    final chunks = [for (var i = 0; i < bytes.length; i += 7) bytes.sublist(i, i + 7 > bytes.length ? bytes.length : i + 7)];
    final msgs = await Stream.fromIterable(chunks).transform(const MessageDecoder()).toList();
    expect(msgs.length, 2);
    expect((msgs[0]['params'] as Map)['s'], 'héllo ✓');
    expect(msgs[1]['result'], 42);
    expect(ascii.decode(encodeMessage({'x': 1}).take(16).toList()), startsWith('Content-Length:'));
  });

  test('peers exchange requests, errors and notifications', () async {
    final aToB = StreamController<Map<String, Object?>>();
    final bToA = StreamController<Map<String, Object?>>();
    final server = RpcPeer(aToB.stream, bToA.add);
    final client = RpcPeer(bToA.stream, aToB.add);
    server.on('add', (p) => (p['a'] as int) + (p['b'] as int));
    server.on('fail', (p) => throw RpcException(ErrorCodes.editRejected, 'nope'));
    expect(await client.request('add', {'a': 2, 'b': 3}), 5);
    await expectLater(client.request('fail'), throwsA(isA<RpcException>().having((e) => e.code, 'code', ErrorCodes.editRejected)));
    await expectLater(client.request('missing'), throwsA(isA<RpcException>().having((e) => e.code, 'code', ErrorCodes.methodNotFound)));
    final got = client.notifications.first;
    server.notify(Methods.documentChanged, {'file': 'a.dart'});
    expect((await got).params['file'], 'a.dart');
  });
}
