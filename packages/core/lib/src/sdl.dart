/// Minimal SDLang (Simple Declarative Language) reader/writer used for
/// Visual App Editor configuration files (`*.sdl`).
///
/// Supports: tags with optional names, string / number / boolean / null
/// values, `key=value` attributes, nested `{ }` blocks, `//`, `#`, `--` and
/// `/* */` comments, and `;` as a statement separator.
library;

class SdlTag {
  SdlTag(this.name, {List<Object?>? values, Map<String, Object?>? attributes, List<SdlTag>? children})
      : values = values ?? [],
        attributes = attributes ?? {},
        children = children ?? [];

  final String name;
  final List<Object?> values;
  final Map<String, Object?> attributes;
  final List<SdlTag> children;

  Object? get value => values.isEmpty ? null : values.first;
  String? get stringValue => value is String ? value as String : value?.toString();

  SdlTag? child(String name) {
    for (final c in children) {
      if (c.name == name) return c;
    }
    return null;
  }

  Iterable<SdlTag> all(String name) => children.where((c) => c.name == name);

  /// Value of the first child tag named [name].
  Object? childValue(String name) => child(name)?.value;

  /// All values of every child tag named [name], flattened.
  List<String> childStrings(String name) =>
      [for (final c in all(name)) for (final v in c.values) '$v'];
}

class SdlParseException implements Exception {
  SdlParseException(this.message, this.line);
  final String message;
  final int line;
  @override
  String toString() => 'SdlParseException(line $line): $message';
}

/// Parses an SDL document into a synthetic root tag whose children are the
/// top-level tags.
SdlTag parseSdl(String source) => _SdlParser(source).parseDocument();

class _SdlParser {
  _SdlParser(this.s);
  final String s;
  int i = 0;
  int line = 1;

  SdlTag parseDocument() {
    final root = SdlTag('');
    _parseBody(root, topLevel: true);
    return root;
  }

  void _parseBody(SdlTag parent, {required bool topLevel}) {
    while (true) {
      _skipWsAndNewlines();
      if (i >= s.length) {
        if (!topLevel) throw SdlParseException('Missing }', line);
        return;
      }
      if (s[i] == '}') {
        if (topLevel) throw SdlParseException('Unexpected }', line);
        i++;
        return;
      }
      parent.children.add(_parseTag());
    }
  }

  SdlTag _parseTag() {
    String name;
    if (_isIdentStart(s[i])) {
      final start = i;
      while (i < s.length && _isIdentPart(s[i])) {
        i++;
      }
      final word = s.substring(start, i);
      if (word == 'true' || word == 'false' || word == 'null' || word == 'on' || word == 'off') {
        i = start;
        name = 'content';
      } else {
        name = word;
      }
    } else {
      name = 'content';
    }
    final tag = SdlTag(name);
    while (true) {
      _skipInlineWs();
      if (i >= s.length) return tag;
      final c = s[i];
      if (c == '\n' || c == ';') {
        i++;
        if (c == '\n') line++;
        return tag;
      }
      if (c == '}') return tag;
      if (c == '{') {
        i++;
        _parseBody(tag, topLevel: false);
        return tag;
      }
      if (c == '\\' && i + 1 < s.length && (s[i + 1] == '\n' || s[i + 1] == '\r')) {
        i++;
        _skipWsAndNewlines();
        continue;
      }
      // attribute?
      if (_isIdentStart(c)) {
        final start = i;
        while (i < s.length && _isIdentPart(s[i])) {
          i++;
        }
        if (i < s.length && s[i] == '=') {
          final key = s.substring(start, i);
          i++;
          tag.attributes[key] = _parseValue();
          continue;
        }
        i = start;
      }
      tag.values.add(_parseValue());
    }
  }

  Object? _parseValue() {
    final c = s[i];
    if (c == '"') return _parseString();
    if (c == '`') {
      final end = s.indexOf('`', i + 1);
      if (end < 0) throw SdlParseException('Unterminated raw string', line);
      final v = s.substring(i + 1, end);
      line += '\n'.allMatches(v).length;
      i = end + 1;
      return v;
    }
    final start = i;
    while (i < s.length && !' \t\r\n;{}='.contains(s[i])) {
      i++;
    }
    final word = s.substring(start, i);
    if (word.isEmpty) throw SdlParseException('Expected value at "${s[i]}"', line);
    switch (word) {
      case 'true':
      case 'on':
        return true;
      case 'false':
      case 'off':
        return false;
      case 'null':
        return null;
    }
    final n = num.tryParse(word.replaceAll(RegExp(r'[LlFfDd]$'), ''));
    if (n != null) return n;
    return word; // bare word fallback (dates, etc. kept as text)
  }

  String _parseString() {
    i++;
    final b = StringBuffer();
    while (i < s.length && s[i] != '"') {
      if (s[i] == '\\' && i + 1 < s.length) {
        i++;
        final e = s[i];
        b.write(switch (e) { 'n' => '\n', 't' => '\t', 'r' => '\r', _ => e });
      } else {
        if (s[i] == '\n') line++;
        b.write(s[i]);
      }
      i++;
    }
    if (i >= s.length) throw SdlParseException('Unterminated string', line);
    i++;
    return b.toString();
  }

  void _skipInlineWs() {
    while (i < s.length) {
      final c = s[i];
      if (c == ' ' || c == '\t' || c == '\r') {
        i++;
      } else if (_startsComment()) {
        _skipComment(stopAtNewline: true);
      } else {
        return;
      }
    }
  }

  void _skipWsAndNewlines() {
    while (i < s.length) {
      final c = s[i];
      if (c == ' ' || c == '\t' || c == '\r' || c == ';') {
        i++;
      } else if (c == '\n') {
        line++;
        i++;
      } else if (_startsComment()) {
        _skipComment(stopAtNewline: false);
      } else {
        return;
      }
    }
  }

  bool _startsComment() =>
      s[i] == '#' || s.startsWith('//', i) || s.startsWith('--', i) || s.startsWith('/*', i);

  void _skipComment({required bool stopAtNewline}) {
    if (s.startsWith('/*', i)) {
      final end = s.indexOf('*/', i + 2);
      final stop = end < 0 ? s.length : end + 2;
      line += '\n'.allMatches(s.substring(i, stop)).length;
      i = stop;
      return;
    }
    while (i < s.length && s[i] != '\n') {
      i++;
    }
  }

  static bool _isIdentStart(String c) => RegExp(r'[A-Za-z_]').hasMatch(c);
  static bool _isIdentPart(String c) => RegExp(r'[A-Za-z0-9_\-.:$]').hasMatch(c);
}

/// Serialises tags back to SDL text.
String writeSdl(Iterable<SdlTag> tags, {int indent = 0}) {
  final b = StringBuffer();
  final pad = '\t' * indent;
  for (final t in tags) {
    b.write(pad);
    b.write(t.name);
    for (final v in t.values) {
      b.write(' ${_lit(v)}');
    }
    t.attributes.forEach((k, v) => b.write(' $k=${_lit(v)}'));
    if (t.children.isNotEmpty) {
      b.writeln(' {');
      b.write(writeSdl(t.children, indent: indent + 1));
      b.writeln('$pad}');
    } else {
      b.writeln();
    }
  }
  return b.toString();
}

String _lit(Object? v) {
  if (v == null) return 'null';
  if (v is String) return '"${v.replaceAll('\\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';
  return '$v';
}
