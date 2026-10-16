// Visual App Editor headless service: JSON-RPC 2.0 with Content-Length
// framing on stdin/stdout. Logs go to stderr.
import 'dart:io';

import 'package:vae_protocol/vae_protocol.dart';
import 'package:vae_service/vae_service.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--version')) {
    stdout.writeln('vae_service $serviceVersion');
    return;
  }
  final peer = RpcPeer(stdin.transform(const MessageDecoder()), (m) => stdout.add(encodeMessage(m)));
  final service = EditorService(peer);
  peer.errors.listen((e) => stderr.writeln('vae_service: $e'));
  await Future.any([service.onShutdown, peer.done]);
  await stdout.flush();
  exit(0);
}
