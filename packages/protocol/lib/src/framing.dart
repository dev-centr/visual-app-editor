import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Encodes one JSON-RPC message with an LSP-style header:
/// `Content-Length: <bytes>\r\n\r\n<utf-8 json>`.
List<int> encodeMessage(Map<String, Object?> message) {
  final body = utf8.encode(jsonEncode(message));
  return [...ascii.encode('Content-Length: ${body.length}\r\n\r\n'), ...body];
}

/// Splits a byte stream into decoded JSON messages.
class MessageDecoder extends StreamTransformerBase<List<int>, Map<String, Object?>> {
  const MessageDecoder();

  @override
  Stream<Map<String, Object?>> bind(Stream<List<int>> stream) {
    final out = StreamController<Map<String, Object?>>();
    final buf = BytesBuilder(copy: false);
    var pending = Uint8List(0);
    stream.listen(
      (chunk) {
        buf.add(pending);
        buf.add(chunk);
        pending = buf.takeBytes();
        while (true) {
          final headerEnd = _indexOf(pending, const [13, 10, 13, 10]);
          if (headerEnd < 0) break;
          final header = ascii.decode(pending.sublist(0, headerEnd), allowInvalid: true);
          final m = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false).firstMatch(header);
          if (m == null) {
            out.addError(const FormatException('Missing Content-Length header'));
            pending = pending.sublist(headerEnd + 4);
            continue;
          }
          final len = int.parse(m.group(1)!);
          final start = headerEnd + 4;
          if (pending.length < start + len) break;
          final body = utf8.decode(pending.sublist(start, start + len));
          pending = pending.sublist(start + len);
          try {
            out.add((jsonDecode(body) as Map).cast<String, Object?>());
          } catch (e) {
            out.addError(FormatException('Invalid JSON message: $e'));
          }
        }
      },
      onError: out.addError,
      onDone: out.close,
    );
    return out.stream;
  }

  static int _indexOf(Uint8List data, List<int> pat) {
    outer:
    for (var i = 0; i <= data.length - pat.length; i++) {
      for (var j = 0; j < pat.length; j++) {
        if (data[i + j] != pat[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
