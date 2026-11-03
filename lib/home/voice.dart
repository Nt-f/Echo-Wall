// The voice assistant on the WallView, as Siri shows itself: while the Echo listens, a glow of colour travels round
// the screen's edge; what you said and what the assistant answered rise on a glass card from the bottom; an alarm or
// timer ringing on glass over the dimmed WallView.  What is shown comes from hassmic (its state feed, lib/hassmic.dart
// EchoState: hassmic leaves the screen to this app for these); taps on a ring are hassmic's own (it reads the touch
// screen), so nothing here acts on them.
//
// The glow: three strokes of a turning sweep gradient, wide and faint to narrow and bright, rather than a blur filter
// (a per-frame blur costs the Echo Show 5's GPU half its frames).
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../echo_ui.dart' show clockText;
import '../hassmic.dart';
import 'backdrop.dart';

class VoiceLayer extends StatefulWidget {
  final EchoState s;
  final Backdrop backdrop;
  final bool round;
  const VoiceLayer({super.key, required this.s, required this.backdrop, this.round = false});
  @override
  State<VoiceLayer> createState() => _VoiceLayerState();
}

class _VoiceLayerState extends State<VoiceLayer> with TickerProviderStateMixin {
  late final AnimationController spin = AnimationController(vsync: this, duration: const Duration(seconds: 3));
  late final AnimationController glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late final AnimationController card = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final AnimationController ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() { super.initState(); _follow(); }
  @override
  void didUpdateWidget(VoiceLayer old) { super.didUpdateWidget(old); _follow(); }

  void _follow() {
    final s = widget.s;
    if (s.running) { if (!spin.isAnimating) spin.repeat(); glow.forward(); } else { glow.reverse().whenComplete(() { if (!widget.s.running) spin.stop(); }); }
    (s.words || s.running) && s.ringing.isEmpty ? card.forward() : card.reverse();
    if (s.ringing.isNotEmpty) { if (!ring.isAnimating) ring.repeat(); } else { ring.stop(); }
  }

  @override
  void dispose() { spin.dispose(); glow.dispose(); card.dispose(); ring.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return IgnorePointer(ignoring: s.ringing.isEmpty, child: Stack(fit: StackFit.expand, children: [
      // the edge's glow, while listening
      AnimatedBuilder(animation: Listenable.merge([spin, glow]), builder: (_, _) => glow.value == 0 ? const SizedBox()
          : CustomPaint(painter: _Glow(spin.value, Curves.easeOut.transform(glow.value), widget.round))),
      // the words: a glass card rising from the bottom
      AnimatedBuilder(animation: card, builder: (context, _) {
        final t = Curves.easeOutCubic.transform(card.value);
        if (t == 0) return const SizedBox();
        return Align(alignment: Alignment.bottomCenter, child: Transform.translate(offset: Offset(0, (1 - t) * 60),
            child: Opacity(opacity: t, child: _WordsCard(s: s, backdrop: widget.backdrop, round: widget.round))));
      }),
      if (s.ringing.isNotEmpty) _Ring(s: s, backdrop: widget.backdrop, pulse: ring, round: widget.round),
    ]));
  }
}

class _Glow extends CustomPainter {
  final double turn, strength;
  final bool round;
  _Glow(this.turn, this.strength, this.round);
  static const _colors = [Color(0xff7b5cff), Color(0xff2fb4ff), Color(0xff36e2b4), Color(0xffffc63a), Color(0xffff5a8a), Color(0xff7b5cff)];
  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    final shader = SweepGradient(colors: _colors, transform: GradientRotation(turn * 2 * pi)).createShader(r);
    final shape = round ? RRect.fromRectXY(r, s.width / 2, s.height / 2) : RRect.fromRectXY(r, 18, 18);
    for (final (w, a) in const [(26.0, .12), (12.0, .28), (4.0, .9)]) {
      canvas.drawRRect(shape.deflate(w / 2), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = shader
        ..color = Color.fromRGBO(255, 255, 255, a * strength));
    }
  }

  @override
  bool shouldRepaint(_Glow old) => old.turn != turn || old.strength != strength;
}

class _WordsCard extends StatelessWidget {
  final EchoState s;
  final Backdrop backdrop;
  final bool round;
  const _WordsCard({required this.s, required this.backdrop, required this.round});
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = min(size.width * (round ? .7 : .78), 760.0), small = size.shortestSide < 400;
    final radius = BorderRadius.circular(small ? 22 : 30);
    return Padding(
      padding: EdgeInsets.only(bottom: size.height * (round ? .16 : .05)),
      child: SizedBox(width: w, child: DecoratedBox(
        decoration: ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: radius),
            shadows: const [BoxShadow(color: Color(0x59000000), blurRadius: 36, offset: Offset(0, 14))]),
        child: Frosted(blurred: backdrop.blurred, screen: backdrop.size, radius: radius, tint: const Color(0xa6141416),
            edgeTop: const Color(0x4dffffff), edgeBottom: const Color(0x0affffff),
            child: Padding(padding: EdgeInsets.fromLTRB(small ? 16 : 24, small ? 12 : 18, small ? 16 : 24, small ? 14 : 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (s.heard.isEmpty && s.running)
                _Listening(small: small)
              else
                Text(s.heard, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: .62), fontSize: small ? 14 : 19, fontWeight: FontWeight.w500)),
              if (s.reply.isNotEmpty) Padding(padding: EdgeInsets.only(top: small ? 6 : 10), child: Text(s.reply, maxLines: small ? 4 : 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: small ? 16 : 24, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -.2))),
            ]))),
      )),
    );
  }
}

/// "Listening": a word and three dots that rise and fall
class _Listening extends StatefulWidget {
  final bool small;
  const _Listening({required this.small});
  @override
  State<_Listening> createState() => _ListeningState();
}

class _ListeningState extends State<_Listening> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Listening', style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: widget.small ? 16 : 22, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        for (var i = 0; i < 3; i++)
          AnimatedBuilder(animation: c, builder: (_, _) {
            final v = sin((c.value * 2 * pi) - i * .9);
            return Transform.translate(offset: Offset(0, -3 * max(0, v)), child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2.5), width: 7, height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .45 + .5 * max(0, v)))));
          }),
      ]);
}

/// an alarm or timer ringing: glass over the dimmed WallView, the icon in a ring that pulses, what stops it
class _Ring extends StatelessWidget {
  final EchoState s;
  final Backdrop backdrop;
  final Animation<double> pulse;
  final bool round;
  const _Ring({required this.s, required this.backdrop, required this.pulse, required this.round});
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context), small = size.shortestSide < 400;
    final w = min(size.width * (round ? .66 : .62), 620.0);
    final radius = BorderRadius.circular(small ? 26 : 36);
    final icon = s.ringingAlarm ? CupertinoIcons.alarm_fill : CupertinoIcons.timer;
    // a tap snoozes (an alarm; a timer stops), a hold stops: hassmic does it, this app having claimed the ring
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => Hassmic.ring(stop: false), onLongPress: () => Hassmic.ring(stop: true),
        child: Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Color(0x80000000)),
      Center(child: SizedBox(width: w, child: DecoratedBox(
        decoration: ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: radius),
            shadows: const [BoxShadow(color: Color(0x66000000), blurRadius: 44, offset: Offset(0, 18))]),
        child: Frosted(blurred: backdrop.blurred, screen: backdrop.size, radius: radius, tint: const Color(0x99141416),
            child: Padding(padding: EdgeInsets.all(small ? 16 : 28), child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedBuilder(animation: pulse, builder: (_, _) {
                final t = pulse.value;
                return SizedBox(width: small ? 70 : 104, height: small ? 70 : 104, child: Stack(alignment: Alignment.center, children: [
                  // a ring that leaves the icon and fades, again and again
                  Container(width: (small ? 50 : 76) * (1 + .38 * t), height: (small ? 50 : 76) * (1 + .38 * t),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xffff9f0a).withValues(alpha: 1 - t), width: 3))),
                  Container(width: small ? 50 : 76, height: small ? 50 : 76, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xffff9f0a)),
                      child: Icon(icon, color: Colors.white, size: small ? 26 : 40)),
                ]));
              }),
              SizedBox(height: small ? 8 : 14),
              Text(s.ringing, textAlign: TextAlign.center, maxLines: 2,
                  style: TextStyle(color: Colors.white, fontSize: small ? 20 : 32, fontWeight: FontWeight.w700, letterSpacing: -.4)),
              Text(clockText(DateTime.now(), s.h24), style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: small ? 13 : 17)),
              SizedBox(height: small ? 10 : 18),
              Text(s.ringingAlarm ? 'Tap to snooze  ·  hold or say “stop”' : 'Tap or say “stop”', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: small ? 12 : 15, fontWeight: FontWeight.w500)),
            ]))),
      ))),
    ]));
  }
}
