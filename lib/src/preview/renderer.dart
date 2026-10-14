import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../source/dart_document.dart';
import 'values.dart';

typedef NodeCallback = void Function(WidgetNode node);

/// In-process preview: interprets the widget tree parsed from source into
/// real Flutter widgets. Known Material / Cupertino / core widgets render
/// natively; anything else renders as a labelled frame that still shows
/// its children, so trees from any toolkit stay inspectable.
class PreviewRenderer {
  PreviewRenderer({this.selectedPath, this.onSelect});

  final List<int>? selectedPath;
  final NodeCallback? onSelect;

  Widget build(WidgetNode node) {
    final w = _build(node);
    return _decorate(node, w);
  }

  bool _isSelected(WidgetNode n) {
    final s = selectedPath;
    if (s == null || s.length != n.path.length) return false;
    for (var i = 0; i < s.length; i++) {
      if (s[i] != n.path[i]) return false;
    }
    return true;
  }

  // Parent-data widgets must stay direct children of their Flex/Stack.
  static const _parentData = {'Expanded', 'Flexible', 'Positioned', 'Spacer'};

  Widget _decorate(WidgetNode n, Widget w) {
    if (_parentData.contains(n.className)) return w;
    final selected = _isSelected(n);
    return _Selectable(selected: selected, label: n.type, onTap: onSelect == null ? null : () => onSelect!(n), child: w);
  }

  Widget? _slot(WidgetNode n, String name) {
    for (final c in n.children) {
      if (c.slot == name) return build(c);
    }
    final a = n.arg(name);
    if (a != null) {
      final v = ValueEval.eval(a.expression);
      if (v is String) return Text(v);
    }
    return null;
  }

  List<Widget> _list(WidgetNode n, [String name = 'children']) => [for (final c in n.children) if (c.slot == name) build(c)];

  Object? _v(WidgetNode n, String name) => ValueEval.eval(n.arg(name)?.expression);
  double? _d(WidgetNode n, String name) => ValueEval.d(_v(n, name));
  T? _t<T>(WidgetNode n, String name) {
    final v = _v(n, name);
    return v is T ? v : null;
  }

  String _text(WidgetNode n) {
    final pos = n.positional;
    if (pos.isEmpty) return '';
    final v = ValueEval.eval(pos.first.expression);
    return v is String ? v : pos.first.source;
  }

  Widget _build(WidgetNode n) {
    final child = _slot(n, 'child');
    void noop() {}
    switch (n.type) {
      case 'MaterialApp':
        return _slot(n, 'home') ?? const SizedBox();
      case 'Scaffold':
        return Scaffold(
          backgroundColor: _t<Color>(n, 'backgroundColor'),
          appBar: _prefSize(_slot(n, 'appBar')),
          body: _slot(n, 'body'),
          floatingActionButton: _slot(n, 'floatingActionButton'),
          bottomNavigationBar: _slot(n, 'bottomNavigationBar'),
          drawer: _slot(n, 'drawer'),
        );
      case 'AppBar':
        return AppBar(
          title: _slot(n, 'title'),
          backgroundColor: _t<Color>(n, 'backgroundColor'),
          foregroundColor: _t<Color>(n, 'foregroundColor'),
          centerTitle: _t<bool>(n, 'centerTitle'),
          leading: _slot(n, 'leading'),
          actions: _list(n, 'actions'),
          automaticallyImplyLeading: false,
        );
      case 'Text':
        return Text(_text(n), style: _t<TextStyle>(n, 'style'), textAlign: _t<TextAlign>(n, 'textAlign'), maxLines: _t<int>(n, 'maxLines'));
      case 'Column':
      case 'Row':
        final kids = _list(n);
        final mainA = _t<MainAxisAlignment>(n, 'mainAxisAlignment') ?? MainAxisAlignment.start;
        final crossA = _t<CrossAxisAlignment>(n, 'crossAxisAlignment') ?? CrossAxisAlignment.center;
        final size = _t<MainAxisSize>(n, 'mainAxisSize') ?? MainAxisSize.max;
        final spacing = _d(n, 'spacing') ?? 0;
        return n.type == 'Column'
            ? Column(mainAxisAlignment: mainA, crossAxisAlignment: crossA, mainAxisSize: size, spacing: spacing, children: kids)
            : Row(mainAxisAlignment: mainA, crossAxisAlignment: crossA, mainAxisSize: size, spacing: spacing, children: kids);
      case 'Stack':
        return Stack(children: _list(n));
      case 'Wrap':
        return Wrap(spacing: _d(n, 'spacing') ?? 0, runSpacing: _d(n, 'runSpacing') ?? 0, children: _list(n));
      case 'ListView':
        return ListView(padding: _t<EdgeInsets>(n, 'padding'), shrinkWrap: true, children: _list(n));
      case 'SingleChildScrollView':
        return SingleChildScrollView(padding: _t<EdgeInsets>(n, 'padding'), child: child);
      case 'Center':
        return Center(child: child);
      case 'Align':
        return Align(alignment: _t<Alignment>(n, 'alignment') ?? Alignment.center, child: child);
      case 'Padding':
        return Padding(padding: _t<EdgeInsets>(n, 'padding') ?? EdgeInsets.zero, child: child);
      case 'SizedBox':
        return SizedBox(width: _d(n, 'width'), height: _d(n, 'height'), child: child);
      case 'Container':
        return Container(
          width: _d(n, 'width'),
          height: _d(n, 'height'),
          color: _t<Color>(n, 'color'),
          padding: _t<EdgeInsets>(n, 'padding'),
          margin: _t<EdgeInsets>(n, 'margin'),
          alignment: _t<Alignment>(n, 'alignment'),
          decoration: _t<BoxDecoration>(n, 'decoration'),
          child: child,
        );
      case 'Expanded':
        return Expanded(flex: _t<int>(n, 'flex') ?? 1, child: _decorate(n, child ?? const SizedBox()));
      case 'Flexible':
        return Flexible(flex: _t<int>(n, 'flex') ?? 1, child: _decorate(n, child ?? const SizedBox()));
      case 'Spacer':
        return Spacer(flex: _t<int>(n, 'flex') ?? 1);
      case 'Opacity':
        return Opacity(opacity: _d(n, 'opacity') ?? 1, child: child);
      case 'Card':
        return Card(color: _t<Color>(n, 'color'), elevation: _d(n, 'elevation'), child: child);
      case 'ListTile':
        return ListTile(title: _slot(n, 'title'), subtitle: _slot(n, 'subtitle'), leading: _slot(n, 'leading'), trailing: _slot(n, 'trailing'), onTap: noop);
      case 'ElevatedButton':
        return ElevatedButton(onPressed: noop, child: child ?? const SizedBox());
      case 'FilledButton':
        return FilledButton(onPressed: noop, child: child ?? const SizedBox());
      case 'OutlinedButton':
        return OutlinedButton(onPressed: noop, child: child ?? const SizedBox());
      case 'TextButton':
        return TextButton(onPressed: noop, child: child ?? const SizedBox());
      case 'ElevatedButton.icon':
      case 'FilledButton.icon':
      case 'OutlinedButton.icon':
      case 'TextButton.icon':
        return FilledButton.tonalIcon(onPressed: noop, icon: _slot(n, 'icon'), label: _slot(n, 'label') ?? const Text(''));
      case 'IconButton':
        return IconButton(onPressed: noop, icon: _slot(n, 'icon') ?? const Icon(Icons.circle));
      case 'FloatingActionButton':
        return FloatingActionButton(onPressed: noop, child: child ?? const SizedBox());
      case 'FloatingActionButton.extended':
        return FloatingActionButton.extended(onPressed: noop, icon: _slot(n, 'icon'), label: _slot(n, 'label') ?? const Text(''));
      case 'Icon':
        final pos = n.positional;
        final icon = pos.isEmpty ? null : ValueEval.eval(pos.first.expression);
        return Icon(icon is IconData ? icon : Icons.widgets_outlined, size: _d(n, 'size'), color: _t<Color>(n, 'color'));
      case 'TextField':
      case 'TextFormField':
        return TextField(decoration: _t<InputDecoration>(n, 'decoration') ?? const InputDecoration(), obscureText: _t<bool>(n, 'obscureText') ?? false);
      case 'Divider':
        return Divider(height: _d(n, 'height'), thickness: _d(n, 'thickness'));
      case 'Switch':
        return Switch(value: _t<bool>(n, 'value') ?? false, onChanged: (_) {});
      case 'Checkbox':
        return Checkbox(value: _t<bool>(n, 'value') ?? false, onChanged: (_) {});
      case 'Slider':
        return Slider(value: _d(n, 'value') ?? 0.5, onChanged: (_) {});
      case 'CircularProgressIndicator':
        return CircularProgressIndicator(value: _d(n, 'value'));
      case 'LinearProgressIndicator':
        return LinearProgressIndicator(value: _d(n, 'value'));
      case 'Chip':
        return Chip(label: _slot(n, 'label') ?? const Text(''), avatar: _slot(n, 'avatar'));
      case 'CircleAvatar':
        return CircleAvatar(radius: _d(n, 'radius'), backgroundColor: _t<Color>(n, 'backgroundColor'), child: child);
      case 'Badge':
        return Badge(label: _slot(n, 'label'), child: child);
      case 'Placeholder':
        return const SizedBox(height: 80, child: Placeholder());
      case 'Image.network':
      case 'Image.asset':
      case 'Image.file':
      case 'Image':
        return Container(
          width: _d(n, 'width'),
          height: _d(n, 'height') ?? 120,
          color: Colors.black12,
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined),
        );
      case 'NavigationBar':
        final dests = _list(n, 'destinations');
        return dests.length >= 2 ? NavigationBar(destinations: dests) : _generic(n);
      case 'NavigationDestination':
        return NavigationDestination(icon: _slot(n, 'icon') ?? const Icon(Icons.circle), label: '${_v(n, 'label') ?? ''}');
      case 'CupertinoPageScaffold':
        final nav = _slot(n, 'navigationBar');
        return CupertinoPageScaffold(child: Column(children: [if (nav != null) SafeArea(bottom: false, child: SizedBox(height: 44, child: nav)), Expanded(child: child ?? const SizedBox())]));
      case 'CupertinoNavigationBar':
        return CupertinoNavigationBar(middle: _slot(n, 'middle'));
      case 'CupertinoButton':
      case 'CupertinoButton.filled':
        return n.type.endsWith('filled')
            ? CupertinoButton.filled(onPressed: noop, child: child ?? const Text(''))
            : CupertinoButton(onPressed: noop, child: child ?? const Text(''));
      case 'CupertinoSwitch':
        return CupertinoSwitch(value: _t<bool>(n, 'value') ?? false, onChanged: (_) {});
      case 'CupertinoTextField':
        return CupertinoTextField(placeholder: _v(n, 'placeholder') as String?);
      case 'CupertinoActivityIndicator':
        return const CupertinoActivityIndicator();
    }
    return _generic(n);
  }

  PreferredSizeWidget? _prefSize(Widget? w) {
    if (w == null) return null;
    if (w is PreferredSizeWidget) return w;
    return PreferredSize(preferredSize: const Size.fromHeight(kToolbarHeight), child: w);
  }

  /// Fallback for widgets the preview does not natively know (third-party
  /// toolkits): a labelled frame containing its children.
  Widget _generic(WidgetNode n) {
    final kids = [for (final c in n.children) build(c)];
    final text = _text(n);
    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0x557C8CFF)),
        borderRadius: BorderRadius.circular(6),
        color: const Color(0x117C8CFF),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text.isEmpty ? n.type : '${n.type}: $text', style: const TextStyle(fontSize: 11, color: Color(0xFF7C8CFF))),
          ...kids,
        ],
      ),
    );
  }
}

class _Selectable extends StatefulWidget {
  const _Selectable({required this.selected, required this.label, required this.child, this.onTap});
  final bool selected;
  final String label;
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<_Selectable> createState() => _SelectableState();
}

class _SelectableState extends State<_Selectable> {
  static Duration? _lastStamp;
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.selected ? const Color(0xFF4B8BFF) : hover ? const Color(0x884B8BFF) : null;
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          // Listeners fire innermost first; only the innermost selects.
          if (_lastStamp == e.timeStamp) return;
          _lastStamp = e.timeStamp;
          widget.onTap?.call();
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            if (color != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: color, width: widget.selected ? 2 : 1))),
                ),
              ),
            if (widget.selected)
              Positioned(
                left: 0,
                top: -16,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    color: color,
                    child: Text(widget.label, style: const TextStyle(fontSize: 10, color: Colors.white, decoration: TextDecoration.none)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
