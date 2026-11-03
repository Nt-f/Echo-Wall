// The lock screen the WallView rests on: a photo (Immich's, or the app's nature photos), the time and date where the
// photo leaves room for them (placement.dart), a new photo every few minutes (crossfaded), and a swipe up that lifts
// it off the WallView.  A tap shows how.
import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
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
  final String? player;                         // the media card's player: shown while it plays or is paused
  final VoidCallback onUnlock;
  const LockScreen({super.key, required this.photos, required this.ha, required this.h24, required this.onUnlock,
      this.nextAlarm = '', this.minutes = 3, this.round = false, this.player});
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
                // what plays, as an iPhone's lock screen has it: on the half the clock leaves free
                if (_playing() case final id?) Align(
                  alignment: Alignment(0, at.clock.y > .3 ? -1 : 1),
                  child: Padding(padding: EdgeInsets.fromLTRB(4 * u, 4 * u, 4 * u, at.clock.y > .3 ? 4 * u : 13 * u),
                      child: _NowPlaying(ha: widget.ha, id: id, u: u)),
                ),
                // how to open it, always there: a chevron over the words on a capsule of dark glass (white text alone
                // went under in a bright sky or snow), sized with the screen; a tap lifts it once
                Positioned(left: 0, right: 0, bottom: 3.2 * u, child: AnimatedBuilder(animation: hint, builder: (_, _) {
                  final t = sin(hint.value * pi);
                  return Transform.translate(offset: Offset(0, -3 * u * t), child: Center(child: Container(
                    padding: EdgeInsets.fromLTRB(4.4 * u, 1.4 * u, 4.4 * u, 1.8 * u),
                    decoration: ShapeDecoration(color: Color.fromRGBO(0, 0, 0, .42 + .14 * t),
                        shape: const StadiumBorder(side: BorderSide(color: Color(0x33ffffff), width: 1)),
                        shadows: const [BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 4))]),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(CupertinoIcons.chevron_up, color: Colors.white, size: 4.4 * u),
                      SizedBox(width: 1.6 * u),
                      Text('Swipe up to open', style: TextStyle(color: Colors.white, fontSize: 4.4 * u, fontWeight: FontWeight.w600,
                          letterSpacing: -.1)),
                    ]),
                  )));
                })),
                if (p != null && p.credit.isNotEmpty)
                  Positioned(right: 10, bottom: 6, child: Text(p.credit,
                      style: const TextStyle(color: Color(0x99ffffff), fontSize: 10, shadows: [Shadow(blurRadius: 4)]))),
              ]),
            ),
          ),
        );
      });

  String? _playing() {
    final id = widget.player, st = id == null ? null : widget.ha.states[id];
    return st != null && (st.state == 'playing' || st.state == 'paused') ? id : null;
  }

  static String _date(DateTime t) {
    const d = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const m = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${d[t.weekday - 1]}, ${m[t.month - 1]} ${t.day}';
  }
}

/// the lock screen's media: the cover, title and artist, the buttons, on dark glass (the photo under it is anything)
class _NowPlaying extends StatelessWidget {
  final Ha ha;
  final String id;
  final double u;
  const _NowPlaying({required this.ha, required this.id, required this.u});
  @override
  Widget build(BuildContext context) {
    final st = ha.states[id]!;
    final pic = st.attr['entity_picture'] as String?;
    final title = st.attr['media_title'] as String? ?? st.name;
    final artist = st.attr['media_artist'] as String? ?? st.attr['media_album_name'] as String? ?? (title == st.name ? '' : st.name);
    final playing = ha.sounding(id);
    void c(String s) => s == 'media_play_pause' ? ha.playPause(id) : ha.call('media_player', s, id);
    Widget button(IconData i, double s, String svc) => GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => c(svc),
        child: Padding(padding: EdgeInsets.all(1.6 * u), child: Icon(i, color: Colors.white, size: s)));
    final h = 17 * u;
    return GestureDetector(
      onTap: () {},                             // its own: not the lock screen's hint
      child: Container(
        constraints: BoxConstraints(maxWidth: 110 * u),
        height: h,
        padding: EdgeInsets.all(1.8 * u),
        decoration: ShapeDecoration(color: const Color(0x8c000000),
            shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(4.5 * u), side: const BorderSide(color: Color(0x26ffffff))),
            shadows: const [BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 6))]),
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(2.6 * u), child: SizedBox.square(dimension: h - 3.6 * u, child: pic != null
              ? Image.network(ha.image(pic).toString(), headers: ha.authHeader, fit: BoxFit.cover, gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xff2a2f45)))
              : ColoredBox(color: const Color(0xff2a2f45), child: Icon(CupertinoIcons.music_note, color: Colors.white38, size: 6 * u)))),
          SizedBox(width: 3 * u),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 4.6 * u, fontWeight: FontWeight.w700)),
            if (artist.isNotEmpty) Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white70, fontSize: 3.8 * u)),
          ])),
          button(CupertinoIcons.backward_fill, 5.4 * u, 'media_previous_track'),
          button(playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, 7 * u, 'media_play_pause'),
          button(CupertinoIcons.forward_fill, 5.4 * u, 'media_next_track'),
        ]),
      ),
    );
  }
}
