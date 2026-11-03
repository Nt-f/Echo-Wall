// How a tile answers a finger, as Apple's do: it gives a little under the finger (scaled to 96 %, quickly) and springs
// back when let go; no ripple, no highlight.  A long press is the way into its detail (detail.dart) where the tile has
// one to give; without onLongPress it claims no long press, so that the WallView's own (the card's menu, the edit mode)
// gets it.
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

class Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap, onLongPress;
  final double depth;                           // how far it gives: 1 - scale
  const Press({super.key, required this.child, this.onTap, this.onLongPress, this.depth = .04});
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController.unbounded(vsync: this, value: 1);
  static const _spring = SpringDescription(mass: 1, stiffness: 420, damping: 22);

  void _to(double v, {bool spring = false}) {
    if (spring) {
      c.animateWith(SpringSimulation(_spring, c.value, v, c.velocity));
    } else {
      c.animateTo(v, duration: const Duration(milliseconds: 90), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() { c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _to(1 - widget.depth),
        onTapUp: (_) => _to(1, spring: true),
        onTapCancel: () => _to(1, spring: true),
        onTap: widget.onTap,
        onLongPressStart: widget.onLongPress == null ? null : (_) => _to(1 - widget.depth * 1.6),
        onLongPress: widget.onLongPress == null ? null : () { _to(1, spring: true); widget.onLongPress?.call(); },
        onLongPressEnd: widget.onLongPress == null ? null : (_) => _to(1, spring: true),
        child: AnimatedBuilder(animation: c, builder: (_, child) => Transform.scale(scale: c.value, child: child), child: widget.child),
      );
}
