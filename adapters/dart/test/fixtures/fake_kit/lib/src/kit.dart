// ignore_for_file: unused_element
// Fixture package: stands in for a third-party toolkit.
import 'package:flutter/widgets.dart';

/// A fancy button.
class FancyButton extends StatelessWidget {
  const FancyButton({super.key, required this.label, this.onPressed, this.size = 12.0, this.child});
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Text(label);
}

abstract class BaseCard extends StatelessWidget {
  const BaseCard({super.key});
}

class FancyCard extends BaseCard {
  const FancyCard({super.key, required this.children});
  const FancyCard.compact({super.key}) : children = const [];
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(children: children);
}

class _Hidden extends StatelessWidget {
  const _Hidden();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class NotAWidget {
  const NotAWidget(this.x);
  final int x;
}
