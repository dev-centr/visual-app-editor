import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:vae_dart_adapter/vae_dart_adapter.dart' show parseDartExpression;

/// Evaluates literal-ish Dart expressions from source into runtime values
/// for the in-process preview. Anything it cannot evaluate returns null and
/// the renderer falls back to defaults.
class ValueEval {
  static final _cache = <String, Expression?>{};

  /// Evaluates argument source text (as sent by the service).
  static Object? evalSource(String? source) {
    if (source == null) return null;
    final e = _cache.putIfAbsent(source, () => parseDartExpression(source));
    return eval(e);
  }

  static Object? eval(Expression? e) {
    if (e == null) return null;
    if (e is ParenthesizedExpression) return eval(e.expression);
    if (e is SimpleStringLiteral) return e.value;
    if (e is AdjacentStrings) return e.strings.map(eval).join();
    if (e is StringInterpolation) {
      return e.elements.map((x) => x is InterpolationString ? x.value : '\${…}').join();
    }
    if (e is IntegerLiteral) return e.value;
    if (e is DoubleLiteral) return e.value;
    if (e is BooleanLiteral) return e.value;
    if (e is NullLiteral) return null;
    if (e is PrefixExpression && e.operator.lexeme == '-') {
      final v = eval(e.operand);
      return v is num ? -v : null;
    }
    if (e is PrefixedIdentifier) return _constant(e.prefix.name, e.identifier.name);
    if (e is PropertyAccess) {
      final t = e.target;
      if (t is SimpleIdentifier) return _constant(t.name, e.propertyName.name);
      if (t is PrefixedIdentifier) return _constant(t.prefix.name, t.identifier.name, e.propertyName.name);
    }
    if (e is IndexExpression) {
      final t = e.target;
      final idx = eval(e.index);
      if (t is PrefixedIdentifier && t.prefix.name == 'Colors' && idx is int) {
        final c = _colors[t.identifier.name];
        if (c is MaterialColor) return c[idx];
      }
    }
    final call = _call(e);
    if (call != null) return _construct(call.$1, call.$2);
    return null;
  }

  static (String, ArgumentList)? _call(Expression e) {
    if (e is InstanceCreationExpression) {
      final n = e.constructorName;
      final t = n.type.toSource().split('<').first;
      return (n.name == null ? t : '$t.${n.name!.name}', e.argumentList);
    }
    if (e is MethodInvocation) {
      final t = e.target;
      if (t == null) return (e.methodName.name, e.argumentList);
      if (t is SimpleIdentifier) return ('${t.name}.${e.methodName.name}', e.argumentList);
    }
    return null;
  }

  static Map<String, Object?> named(ArgumentList a) => {
        for (final x in a.arguments.whereType<NamedExpression>()) x.name.label.name: eval(x.expression),
      };
  static List<Object?> positional(ArgumentList a) => [for (final x in a.arguments) if (x is! NamedExpression) eval(x)];

  static double? d(Object? v) => v is num ? v.toDouble() : null;

  static Object? _construct(String type, ArgumentList a) {
    final n = named(a);
    final p = positional(a);
    double pd(int i) => i < p.length ? d(p[i]) ?? 0 : 0;
    switch (type) {
      case 'Color':
        return p.isNotEmpty && p[0] is int ? Color(p[0] as int) : null;
      case 'Color.fromARGB':
        return Color.fromARGB(pd(0).toInt(), pd(1).toInt(), pd(2).toInt(), pd(3).toInt());
      case 'EdgeInsets.all':
        return EdgeInsets.all(pd(0));
      case 'EdgeInsets.symmetric':
        return EdgeInsets.symmetric(horizontal: d(n['horizontal']) ?? 0, vertical: d(n['vertical']) ?? 0);
      case 'EdgeInsets.only':
        return EdgeInsets.only(left: d(n['left']) ?? 0, top: d(n['top']) ?? 0, right: d(n['right']) ?? 0, bottom: d(n['bottom']) ?? 0);
      case 'EdgeInsets.fromLTRB':
        return EdgeInsets.fromLTRB(pd(0), pd(1), pd(2), pd(3));
      case 'BorderRadius.circular':
        return BorderRadius.circular(pd(0));
      case 'BorderRadius.all':
        return p.isNotEmpty && p[0] is Radius ? BorderRadius.all(p[0] as Radius) : null;
      case 'Radius.circular':
        return Radius.circular(pd(0));
      case 'TextStyle':
        return TextStyle(
          fontSize: d(n['fontSize']),
          color: n['color'] as Color?,
          fontWeight: n['fontWeight'] as FontWeight?,
          fontStyle: n['fontStyle'] as FontStyle?,
          letterSpacing: d(n['letterSpacing']),
          height: d(n['height']),
        );
      case 'BoxDecoration':
        return BoxDecoration(
          color: n['color'] as Color?,
          borderRadius: n['borderRadius'] as BorderRadius?,
          border: n['border'] as BoxBorder?,
        );
      case 'Border.all':
        return Border.all(color: (n['color'] as Color?) ?? const Color(0xFF000000), width: d(n['width']) ?? 1);
      case 'InputDecoration':
        return InputDecoration(
          labelText: n['labelText'] as String?,
          hintText: n['hintText'] as String?,
          border: n['border'] is InputBorder ? n['border'] as InputBorder : null,
        );
      case 'OutlineInputBorder':
        return const OutlineInputBorder();
      case 'Size':
        return Size(pd(0), pd(1));
      case 'Offset':
        return Offset(pd(0), pd(1));
    }
    return null;
  }

  static Object? _constant(String owner, String name, [String? sub]) {
    switch (owner) {
      case 'Colors':
        final c = _colors[name];
        if (sub != null && c is MaterialColor) return c;
        return c;
      case 'Icons':
        return materialIcons[name] ?? Icons.widgets_outlined;
      case 'CupertinoIcons':
        return _cupertinoIcons[name] ?? CupertinoIcons.square;
      case 'MainAxisAlignment':
        return MainAxisAlignment.values.where((v) => v.name == name).firstOrNull;
      case 'CrossAxisAlignment':
        return CrossAxisAlignment.values.where((v) => v.name == name).firstOrNull;
      case 'MainAxisSize':
        return MainAxisSize.values.where((v) => v.name == name).firstOrNull;
      case 'TextAlign':
        return TextAlign.values.where((v) => v.name == name).firstOrNull;
      case 'FontStyle':
        return FontStyle.values.where((v) => v.name == name).firstOrNull;
      case 'BoxFit':
        return BoxFit.values.where((v) => v.name == name).firstOrNull;
      case 'Axis':
        return Axis.values.where((v) => v.name == name).firstOrNull;
      case 'FontWeight':
        return const {
          'w100': FontWeight.w100, 'w200': FontWeight.w200, 'w300': FontWeight.w300, 'w400': FontWeight.w400,
          'w500': FontWeight.w500, 'w600': FontWeight.w600, 'w700': FontWeight.w700, 'w800': FontWeight.w800,
          'w900': FontWeight.w900, 'bold': FontWeight.bold, 'normal': FontWeight.normal,
        }[name];
      case 'Alignment':
        return const {
          'center': Alignment.center, 'topLeft': Alignment.topLeft, 'topCenter': Alignment.topCenter,
          'topRight': Alignment.topRight, 'centerLeft': Alignment.centerLeft, 'centerRight': Alignment.centerRight,
          'bottomLeft': Alignment.bottomLeft, 'bottomCenter': Alignment.bottomCenter, 'bottomRight': Alignment.bottomRight,
        }[name];
    }
    return null;
  }

  static const Map<String, Color> _colors = {
    'red': Colors.red, 'pink': Colors.pink, 'purple': Colors.purple, 'deepPurple': Colors.deepPurple,
    'indigo': Colors.indigo, 'blue': Colors.blue, 'lightBlue': Colors.lightBlue, 'cyan': Colors.cyan,
    'teal': Colors.teal, 'green': Colors.green, 'lightGreen': Colors.lightGreen, 'lime': Colors.lime,
    'yellow': Colors.yellow, 'amber': Colors.amber, 'orange': Colors.orange, 'deepOrange': Colors.deepOrange,
    'brown': Colors.brown, 'grey': Colors.grey, 'blueGrey': Colors.blueGrey, 'black': Colors.black,
    'white': Colors.white, 'transparent': Colors.transparent, 'black54': Colors.black54, 'white70': Colors.white70,
    'black87': Colors.black87, 'white24': Colors.white24, 'black12': Colors.black12,
  };

  static const Map<String, IconData> materialIcons = {
    'add': Icons.add, 'home': Icons.home, 'settings': Icons.settings, 'search': Icons.search, 'star': Icons.star,
    'favorite': Icons.favorite, 'person': Icons.person, 'menu': Icons.menu, 'close': Icons.close, 'check': Icons.check,
    'delete': Icons.delete, 'edit': Icons.edit, 'email': Icons.email, 'phone': Icons.phone, 'share': Icons.share,
    'info': Icons.info, 'arrow_back': Icons.arrow_back, 'arrow_forward': Icons.arrow_forward, 'notifications': Icons.notifications,
    'shopping_cart': Icons.shopping_cart, 'lock': Icons.lock, 'camera_alt': Icons.camera_alt, 'image': Icons.image,
    'send': Icons.send, 'chat': Icons.chat, 'calendar_today': Icons.calendar_today, 'map': Icons.map, 'more_vert': Icons.more_vert,
    'thumb_up': Icons.thumb_up, 'login': Icons.login, 'logout': Icons.logout, 'dashboard': Icons.dashboard, 'bolt': Icons.bolt,
    'palette': Icons.palette, 'rocket_launch': Icons.rocket_launch, 'account_circle': Icons.account_circle,
    'chevron_right': Icons.chevron_right, 'play_arrow': Icons.play_arrow, 'cloud': Icons.cloud, 'wifi': Icons.wifi,
  };

  static const Map<String, IconData> _cupertinoIcons = {
    'home': CupertinoIcons.home, 'settings': CupertinoIcons.settings, 'search': CupertinoIcons.search,
    'heart': CupertinoIcons.heart, 'person': CupertinoIcons.person, 'add': CupertinoIcons.add,
  };
}
