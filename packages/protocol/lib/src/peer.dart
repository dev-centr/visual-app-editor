import 'dart:async';

import 'methods.dart';

class RpcException implements Exception {
  RpcException(this.code, this.message, [this.data]);
  final int code;
  final String message;
  final Object? data;
  Map<String, Object?> toJson() => {'code': code, 'message': message, if (data != null) 'data': data};
  @override
  String toString() => 'RpcException($code): $message';
}

typedef RpcHandler = FutureOr<Object?> Function(Map<String, Object?> params);

/// A symmetric JSON-RPC 2.0 endpoint. The same class serves as client
/// (send [request]s) and server (register handlers with [on]).
class RpcPeer {
  RpcPeer(Stream<Map<String, Object?>> incoming, this._send) {
    _sub = incoming.listen(_handle, onDone: _closed, onError: (Object e) => _errors.add(e));
  }

  final void Function(Map<String, Object?> message) _send;
  late final StreamSubscription<Map<String, Object?>> _sub;
  final _handlers = <String, RpcHandler>{};
  final _pending = <Object, Completer<Object?>>{};
  final _notifications = StreamController<({String method, Map<String, Object?> params})>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  final _done = Completer<void>();
  var _nextId = 1;

  Stream<({String method, Map<String, Object?> params})> get notifications => _notifications.stream;
  Stream<Object> get errors => _errors.stream;
  Future<void> get done => _done.future;

  void on(String method, RpcHandler handler) => _handlers[method] = handler;

  Future<Object?> request(String method, [Map<String, Object?> params = const {}]) {
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return c.future;
  }

  void notify(String method, [Map<String, Object?> params = const {}]) =>
      _send({'jsonrpc': '2.0', 'method': method, 'params': params});

  Future<void> _handle(Map<String, Object?> m) async {
    final id = m['id'];
    if (m.containsKey('method')) {
      final method = m['method'] as String;
      final params = (m['params'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
      final h = _handlers[method];
      if (id == null) {
        if (h != null) {
          try {
            await h(params);
          } catch (e) {
            _errors.add(e);
          }
        } else {
          _notifications.add((method: method, params: params));
        }
        return;
      }
      if (h == null) {
        _send({'jsonrpc': '2.0', 'id': id, 'error': RpcException(ErrorCodes.methodNotFound, 'Unknown method $method').toJson()});
        return;
      }
      try {
        final result = await h(params);
        _send({'jsonrpc': '2.0', 'id': id, 'result': result});
      } on RpcException catch (e) {
        _send({'jsonrpc': '2.0', 'id': id, 'error': e.toJson()});
      } catch (e) {
        _send({'jsonrpc': '2.0', 'id': id, 'error': RpcException(ErrorCodes.internalError, '$e').toJson()});
      }
      return;
    }
    final c = _pending.remove(id);
    if (c == null) return;
    final err = m['error'];
    if (err is Map) {
      c.completeError(RpcException(err['code'] as int? ?? ErrorCodes.internalError, '${err['message']}', err['data']));
    } else {
      c.complete(m['result']);
    }
  }

  void _closed() {
    for (final c in _pending.values) {
      c.completeError(RpcException(ErrorCodes.internalError, 'Connection closed'));
    }
    _pending.clear();
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> close() async {
    await _sub.cancel();
    _closed();
  }
}
