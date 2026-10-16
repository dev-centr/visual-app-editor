import 'dart:async';
import 'dart:convert';

import 'package:vae_protocol/vae_protocol.dart';

import 'server.dart';

/// Runs an [EditorService] in the current isolate behind a real protocol
/// pipe: messages are JSON-encoded and decoded both ways, exactly as over
/// stdio. Returns the client end.
RpcPeer connectInProcess({void Function(EditorService)? onService}) {
  final toServer = StreamController<Map<String, Object?>>();
  final toClient = StreamController<Map<String, Object?>>();
  Map<String, Object?> wire(Map<String, Object?> m) => (jsonDecode(jsonEncode(m)) as Map).cast<String, Object?>();
  final service = EditorService(RpcPeer(toServer.stream, (m) => toClient.add(wire(m))));
  onService?.call(service);
  return RpcPeer(toClient.stream, (m) => toServer.add(wire(m)));
}
