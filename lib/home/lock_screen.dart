// The lock screen the HomeView rests on: a photo (Immich's, or the app's nature photos), the time and date where the
// photo leaves room for them (placement.dart), a new photo every few minutes (crossfaded), and a swipe up that lifts
// it off the HomeView.  A tap shows how.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../echo_ui.dart' show clockText, ampm;
import '../ha.dart';
import 'photos.dart';
import 'placement.dart';

class LockScreen extends StatefulWidget {
  final PhotoLibrary photos;
  final Ha ha;
  final bool h24;
  final String nextAlarm;
  final int minutes;                            // a new photo this often
  final bool round;
  final VoidCallback onUnlock;
  const LockScreen({super.key, required this.photos, required this.ha, required this.h24, required this.onUnlock,
      this.nextAlarm = '', this.minutes = 3, this.round = false});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with TickerProviderStateMixin {
  Photo? photo;
  Placement at = Placement.fallback;
  Timer? _next, _tick;
  double drag = 0;                              // how far it has been lifted (px, upward positive)
  late final AnimationController settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final AnimationController hint = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  Size size = Size.zero;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _next?.cancel(); _tick?.cancel(); settle.dispose(); hint.dispose(); super.dispose(); }

  Future<void> _load() async {
    _next?.cancel();
    if (size == Size.zero) return;
    try {
      final p = await widget.photos.next(wide: size.width >= size.height);
      final pl = await place(p.bytes, p.faces, size, round: widget.round);
      if (!mounted) return;
      await precacheImage(MemoryImage(p.bytes), context);
      if (!mounted) return;
      setState(() { photo = p; at = pl; });
    } catch (_) {}
    _next = Timer(Duration(minutes: max(1, widget.minutes)), _load);
  }

  void _end(DragEndDetails d) {
    final v = -(d.primaryVelocity ?? 0);
    final from = drag, to = (drag > size.height * .22 || v > 700) ? size.height : 0.0;
    final anim = Tween(begin: from, end: to).animate(CurvedAnimation(parent: settle, curve: Curves.easeOut));
    void f() => setState(() => drag = anim.value);
    anim.addListener(f);
    settle.forward(from: 0).whenComplete(() {
      anim.removeListener(f);
      if (to > 0) widget.onUnlock();
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final s = Size(box.maxWidth, box.maxHeight);
        if (s != size) { size = s; WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
        final p = photo;
        final fg = at.dark ? const Color(0xe6141414) : Colors.white;
        final shadow = at.dark ? const <Shadow>[] : const [Shadow(color: Color(0x80000000), blurRadius: 18)];
        final u = min(s.height, s.width * .75) / 100;
        final now = DateTime.now();
        final w = widget.ha.states.entries.where((e) => domainOf(e.key) == 'weather').map((e) => e.value).firstOrNull;
        final temp = w?.numAttr('temperature');
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) => setState(() => drag = max(0, drag - d.delta.dy)),
          onVerticalDragEnd: _end,
          onTap: () => hint.forward(from: 0),
          child: Transform.translate(
            offset: Offset(0, -drag),
            child: Opacity(
              opacity: (1 - drag / max(1, s.height) * .6).clamp(0, 1),
              child: Stack(fit: StackFit.expand, children: [
                Container(color: Colors.black),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 1400),
                  child: p == null ? const SizedBox.expand() : Image.memory(p.bytes, key: ValueKey(p.key), fit: BoxFit.cover,
                      alignment: at.crop, width: s.width, height: s.height, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                ),
                // the clock where the photo has room for it
                AnimatedAlign(
                  alignment: at.clock, duration: const Duration(milliseconds: 900), curve: Curves.easeInOut,
                  child: Padding(padding: EdgeInsets.all(4 * u), child: Column(mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: at.clock.x < -.3 ? CrossAxisAlignment.start : at.clock.x > .3 ? CrossAxisAlignment.end : CrossAxisAlignment.center,
                      children: [
                    Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                      Text(clockText(now, widget.h24), style: TextStyle(color: fg, fontSize: 30 * u, fontWeight: FontWeight.w300, height: 1,
                          letterSpacing: -.8 * u, shadows: shadow, fontFeatures: const [FontFeature.tabularFigures()])),
                      if (!widget.h24) Padding(padding: EdgeInsets.only(left: 1.5 * u),
                          child: Text(ampm(now, widget.h24), style: TextStyle(color: fg, fontSize: 7 * u, fontWeight: FontWeight.w600, shadows: shadow))),
                    ]),
                    Text('${_date(now)}${temp != null ? '  ·  ${temp.round()}°' : ''}',
                        style: TextStyle(color: fg, fontSize: 6 * u, fontWeight: FontWeight.w600, shadows: shadow)),
                    if (widget.nextAlarm.isNotEmpty)
                      Text(widget.nextAlarm, style: TextStyle(color: fg.withValues(alpha: .85), fontSize: 4.6 * u, shadows: shadow)),
                  ])),
                ),
                // how to open it: a chevron that rises on a tap
                Positioned(left: 0, right: 0, bottom: 6, child: AnimatedBuilder(animation: hint, builder: (_, _) {
                  final t = sin(hint.value * pi);
                  return Transform.translate(offset: Offset(0, -12 * t), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.keyboard_arrow_up, color: Colors.white.withValues(alpha: .55 + .4 * t), size: 26),
                    if (t > .05) Opacity(opacity: t, child: const Text('Swipe up to open',
                        style: TextStyle(color: Colors.white, fontSize: 13, shadows: [Shadow(blurRadius: 8)]))),
                  ]));
                })),
                if (p != null && p.credit.isNotEmpty)
                  Positioned(right: 10, bottom: 6, child: Text(p.credit,
                      style: const TextStyle(color: Color(0x99ffffff), fontSize: 10, shadows: [Shadow(blurRadius: 4)]))),
              ]),
            ),
          ),
        );
      });

  static String _date(DateTime t) {
    const d = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const m = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${d[t.weekday - 1]}, ${m[t.month - 1]} ${t.day}';
  }
}
