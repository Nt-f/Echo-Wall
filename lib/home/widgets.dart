// The WallView's widgets: square glass over the wallpaper, in the manner of Apple's HomeView.  Sizes are fractions of
// the cell (`u`: a hundredth of a cell's side), so a tile reads the same on a Show 5's 139 px cells and a Show 15's.
// The glass is Apple's material: the wallpaper behind it blurred once and drawn piece by piece (backdrop.dart).
import 'dart:async';
import '../io/io.dart';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../echo_ui.dart' show Ticker, clockText, ampm;
import '../ha.dart';
import 'backdrop.dart';
import 'layout.dart';
import 'model.dart';
import 'press.dart';
import 'sizes.dart';
import 'sheets.dart' show weatherIcon, weatherText;

class Palette {
  final Gradient wall;
  final Color glass, edge, glassOn, text, dim, textOn, dimOn, sheet, accentDay;
  final Color sheetText;                        // on the detail's card (a thick, dark material)
  const Palette(this.wall, this.glass, this.edge, this.glassOn, this.text, this.dim, this.textOn, this.dimOn, this.sheet, this.accentDay,
      [this.sheetText = Colors.white]);

  static Palette of(Wallpaper w) => switch (w) {
        // a photo behind the glass: Apple's Home on a wallpaper; the tint thin, the text white
        Wallpaper.photo => const Palette(
            LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xff2c3e50), Color(0xff4a6274)]),
            Color(0x1fffffff), Color(0x40ffffff), Color(0xebffffff), Colors.white, Color(0xbfffffff), Color(0xff1c1c1e),
            Color(0x8c1c1c1e), Color(0x99141416), Color(0xffffd60a)),
        Wallpaper.amber => const Palette(
            LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xffb8601c), Color(0xffd98a33), Color(0xffe9a74b), Color(0xffc46f22)], stops: [0, .45, .7, 1]),
            Color(0x2bffffff), Color(0x47ffffff), Color(0xdbfffaf0), Colors.white, Color(0xb8ffffff), Color(0xff2b2118),
            Color(0x992b2118), Color(0xf53c2612), Color(0xffffe2b0)),
        Wallpaper.dusk => const Palette(
            LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xff1d2140), Color(0xff34306a), Color(0xff1a1d38)]),
            Color(0x24ffffff), Color(0x3dffffff), Color(0xe0ece8ff), Colors.white, Color(0xb3ffffff), Color(0xff221d3a),
            Color(0x99221d3a), Color(0xf71e1c38), Color(0xffc7b8ff)),
        Wallpaper.light => const Palette(
            LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xfff4f3f8), Color(0xffe7e5ee)]),
            Color(0xb3ffffff), Color(0x0f000000), Color(0xffd9d2f7), Color(0xff2a2833), Color(0x8c2a2833), Color(0xff3c2f86),
            Color(0xa63c2f86), Color(0xfffbfaff), Color(0xffe0533d)),
      };
}

/// the wallpaper: the palette's gradient and soft, out-of-focus shapes of light over it (as Apple's wallpapers have
/// them), painted once and kept (RepaintBoundary): nothing of it moves
class WallpaperPainter extends CustomPainter {
  final Palette p;
  WallpaperPainter(this.p);
  @override
  void paint(Canvas canvas, Size s) => _Wall(p).paint(canvas, s);
  @override
  bool shouldRepaint(WallpaperPainter old) => old.p != p;
}

class WallpaperView extends StatelessWidget {
  final Palette p;
  const WallpaperView(this.p, {super.key});
  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(painter: _Wall(p), size: Size.infinite));
}

class _Wall extends CustomPainter {
  final Palette p;
  _Wall(this.p);
  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    canvas.drawRect(r, Paint()..shader = p.wall.createShader(r));
    final light = p.text == Colors.white;
    // big soft discs, light and shade, as out-of-focus shapes behind glass
    for (final (x, y, rad, c) in [
      (.18, .12, .55, light ? const Color(0x38fff4dc) : const Color(0x40ffffff)),
      (.82, .28, .45, light ? const Color(0x2effe0a0) : const Color(0x30d9d2f7)),
      (.62, 1.05, .6, const Color(0x26000000)),
      (.05, .95, .4, light ? const Color(0x1fffffff) : const Color(0x24c8c0ff)),
    ]) {
      final o = Offset(s.width * x, s.height * y), radius = s.longestSide * rad;
      canvas.drawCircle(o, radius, Paint()..shader = RadialGradient(colors: [c, c.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: o, radius: radius)));
    }
  }

  @override
  bool shouldRepaint(_Wall old) => old.p != p;
}

/// glass: Apple's thin material over the wallpaper (its blurred piece, lifted colour, a light tint), continuous
/// corners, a light top edge, a soft shadow; `on` lights it near-white, as Apple's Home lights an accessory that is on
class Glass extends StatelessWidget {
  final Palette p;
  final bool on, big;
  final double cell;
  final Widget child;
  final EdgeInsets? padding;
  const Glass({super.key, required this.p, required this.cell, required this.child, this.on = false, this.big = false, this.padding});
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(min(30, cell * .17));
    final b = BackdropScope.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: radius),
          shadows: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 10))]),
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: on ? p.glassOn : p.glass), duration: const Duration(milliseconds: 260), curve: Curves.easeOut,
        builder: (context, tint, child) => Frosted(blurred: b?.blurred, screen: b?.size ?? Size.zero, radius: radius, tint: tint ?? p.glass,
            edgeTop: on ? const Color(0xb3ffffff) : p.edge.withValues(alpha: min(1, p.edge.a * 1.7)), edgeBottom: p.edge.withValues(alpha: p.edge.a * .3),
            child: child),
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
  }
}

/// a 1 px border lighter at the top than at the bottom
class GradientBoxBorder extends BoxBorder {
  final Color upper, lower;
  const GradientBoxBorder(this.upper, this.lower);
  @override
  BorderSide get top => BorderSide.none;
  @override
  BorderSide get bottom => BorderSide.none;
  @override
  bool get isUniform => true;
  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(1);
  @override
  ShapeBorder scale(double t) => this;
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection, BoxShape shape = BoxShape.rectangle, BorderRadius? borderRadius}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [upper, lower]).createShader(rect);
    canvas.drawRRect((borderRadius ?? BorderRadius.zero).toRRect(rect).deflate(.5), paint);
  }
}

/// an accessory, laid out as Home Assistant's tile card has it: its icon in a round badge (lit in its state's colour)
/// at the top, its name and its state at the bottom, left-aligned
class AccessoryTile extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final String id;
  final String? room;                           // shown under the name (Home), else its state
  final double cell;
  final VoidCallback onLong;
  final bool holdOpens;                         // a long press opens the detail (the category sheets); the WallView's own hold is its menu
  final CardSize size;                          // s: Apple's tile; m: the badge beside the words; l: all of it bigger, a level bar
  final String? label;                          // the name a dashboard's card gives it (Lovelace's `name:`), else its own
  const AccessoryTile({super.key, required this.ha, required this.p, required this.id, required this.cell, required this.onLong, this.room,
      this.holdOpens = true, this.size = CardSize.s, this.label});
  @override
  Widget build(BuildContext context) {
    final l = look(ha, id), u = cell / 100;
    final fg = l.on ? p.textOn : p.text, dim = l.on ? p.dimOn : p.dim;
    final name = label ?? nameIn(ha, id, room ?? ha.areaName(ha.areaOf(id)));
    final big = size == CardSize.l || size == CardSize.xl, wide = size == CardSize.m;
    final badge = (big ? 40 : wide ? 32 : 26) * u;
    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: badge, height: badge,
      decoration: BoxDecoration(shape: BoxShape.circle,
          color: l.on ? l.color.withValues(alpha: .2) : (p.text == Colors.white ? const Color(0x24ffffff) : const Color(0x14000000))),
      child: Icon(l.icon, size: badge * .56, color: l.on ? l.color : fg),
    );
    final words = [
      Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: max(12.0, (big ? 13 : wide ? 10 : 9) * u), height: 1.15)),
      SizedBox(height: 1.5 * u),
      Text(room != null && !l.unavailable ? room! : l.text, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: dim, fontSize: max(11.0, (big ? 10 : 7.8) * u), fontWeight: FontWeight.w500)),
    ];
    final Widget body = wide
        ? Row(children: [circle, SizedBox(width: 10 * u),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: words))])
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            circle,
            const Spacer(),
            ...words,
            if (big && l.level != null) Padding(padding: EdgeInsets.only(top: 6 * u), child: ClipRRect(borderRadius: BorderRadius.circular(3 * u),
                child: LinearProgressIndicator(value: l.level, minHeight: 5 * u, color: l.color, backgroundColor: dim.withValues(alpha: .25)))),
          ]);
    return Press(
      onTap: () { if (!tap(ha, id)) onLong(); },
      onLongPress: holdOpens ? onLong : null,
      child: Opacity(
        opacity: l.unavailable ? .5 : 1,
        child: Hero(tag: 'tile/$id', child: Glass(p: p, cell: cell, on: l.on, padding: EdgeInsets.all((big ? 14 : 10) * u), child: body)),
      ),
    );
  }
}

/// the thermostat: its set temperature big, arrows to change it (sent once the arrows rest)
class ThermostatCard extends StatefulWidget {
  final Ha ha;
  final Palette p;
  final String id;
  final double cell;
  final VoidCallback onLong;
  final bool holdOpens;
  final CardSize size;                          // l: Apple's thermostat; s: the same in a cell; m: the number beside the words
  final String? label;                          // the name a dashboard's card gives it (Lovelace's `name:`), else its own
  const ThermostatCard({super.key, required this.ha, required this.p, required this.id, required this.cell, required this.onLong,
      this.holdOpens = true, this.size = CardSize.l, this.label});
  @override
  State<ThermostatCard> createState() => _ThermostatCardState();
}

/// a thermostat's colours, as Apple's Home and Home Assistant's card have them: orange heating, blue cooling
const heatColor = Color(0xffff9f0a), coolColor = Color(0xff0a84ff), dryColor = Color(0xffffd60a), fanColor = Color(0xff30d158);

class _ThermostatCardState extends State<ThermostatCard> {
  double? want, wantLo, wantHi;
  Timer? _send;

  /// a step up or down: the one set temperature, or in heat_cool both ends of the range together
  void nudge(int d) {
    final st = widget.ha.states[widget.id];
    if (st == null) return;
    final step = (st.numAttr('target_temp_step') ?? (st.attr['temperature_unit'] == '°F' ? 1 : .5)).toDouble();
    final lo = (st.numAttr('min_temp') ?? -100).toDouble(), hi = (st.numAttr('max_temp') ?? 100).toDouble();
    double moved(double v) => (((v + d * step) / step).round() * step).clamp(lo, hi).toDouble();
    final dual = st.numAttr('temperature') == null && st.numAttr('target_temp_low') != null && st.numAttr('target_temp_high') != null;
    setState(() {
      if (dual) {
        wantLo = moved(wantLo ?? st.numAttr('target_temp_low')!.toDouble());
        wantHi = moved(wantHi ?? st.numAttr('target_temp_high')!.toDouble());
      } else {
        want = moved(want ?? (st.numAttr('temperature') ?? 20).toDouble());
      }
    });
    _send?.cancel();
    _send = Timer(const Duration(milliseconds: 800), () {
      widget.ha.call('climate', 'set_temperature', widget.id,
          dual ? {'target_temp_low': wantLo, 'target_temp_high': wantHi} : {'temperature': want});
      Timer(const Duration(seconds: 3), () { if (mounted) setState(() => want = wantLo = wantHi = null); });
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.ha.states[widget.id], p = widget.p;
    final big = widget.size == CardSize.l || widget.size == CardSize.xl;
    final u = widget.cell * (big ? 2.07 : widget.size == CardSize.m ? 1.15 : 1) / 100;
    String n(num v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
    final t = want ?? st?.numAttr('temperature');
    // heat_cool (an Ecobee's auto): no one temperature but a range, its low end the heating's, its high the cooling's
    final lo = wantLo ?? st?.numAttr('target_temp_low'), hi = wantHi ?? st?.numAttr('target_temp_high');
    final dual = t == null && lo != null && hi != null;
    final mode = st?.state ?? '', action = '${st?.attr['hvac_action'] ?? ''}';
    // what it is doing (hvac_action), else what it is set to do: the card's colour and its line
    final accent = switch (action) {
      'heating' || 'preheating' => heatColor,
      'cooling' => coolColor,
      'drying' => dryColor,
      'fan' => fanColor,
      '' => switch (mode) { 'heat' => heatColor, 'cool' => coolColor, _ => null },
      _ => null,
    };
    final active = const {'heating', 'preheating', 'cooling', 'drying', 'fan'}.contains(action) || (action.isEmpty && accent != null);
    final setTo = dual ? (action == 'cooling' ? hi : lo) : t;
    final line = switch (action) {
      'heating' || 'preheating' => setTo != null ? 'Heating to ${n(setTo)}°' : 'Heating',
      'cooling' => setTo != null ? 'Cooling to ${n(setTo)}°' : 'Cooling',
      'drying' => 'Drying',
      'fan' => 'Fan',
      'idle' => 'Idle',
      'off' => 'Off',
      _ => switch (mode) {
          'heat' => 'Heat', 'cool' => 'Cool', 'heat_cool' => 'Heat · Cool', 'auto' => 'Auto', 'dry' => 'Dry', 'fan_only' => 'Fan', 'off' => 'Off',
          _ => mode,
        },
    };
    final cur = st?.numAttr('current_temperature');
    final room = widget.ha.areaName(widget.ha.areaOf(widget.id));
    final name = widget.label ?? nameIn(widget.ha, widget.id, room);
    final off = mode == 'off';
    Widget chevron(IconData i, int d) => Press(onTap: off ? null : () => nudge(d), depth: .12,
        child: Padding(padding: EdgeInsets.all(4 * u), child: Icon(i, size: 11 * u, color: off ? p.dim : p.text)));
    TextStyle big_(Color c) => TextStyle(color: c, fontSize: 44 * u, height: 1, fontWeight: FontWeight.w400, letterSpacing: -1.5 * u);
    Widget value(num v, Color c) {
      final parts = n(v).split('.');
      return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(parts[0], style: big_(c)),
        if (parts.length > 1) Text('.${parts[1]}', style: TextStyle(color: c, fontSize: 16 * u)),
      ]);
    }
    // the set temperature big; a range as two, the heating's end orange, the cooling's blue
    final number = dual
        ? Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            value(lo, off ? p.dim : heatColor),
            Text('–', style: big_(p.dim).copyWith(fontWeight: FontWeight.w300)),
            value(hi, off ? p.dim : coolColor),
          ])
        : t == null ? Text('—', style: big_(p.text)) : value(t, off ? p.dim : p.text);
    final status = Text.rich(TextSpan(children: [
      // working: white on its colour's glow (orange on orange was lost: the gallery); else the colour of what it is set to
      TextSpan(text: line, style: TextStyle(color: active ? p.text : accent ?? p.dim, fontWeight: FontWeight.w700)),
      if (cur != null) TextSpan(text: '  ·  Now ${n(cur)}°', style: TextStyle(color: p.dim)),
    ]), maxLines: 1, overflow: TextOverflow.ellipsis);
    // working: its colour glows up from the bottom of the glass, as Apple's tile is lit
    Widget glow(Widget child) => Stack(fit: StackFit.expand, children: [
          if (active && accent != null) Positioned.fill(child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [accent.withValues(alpha: 0), accent.withValues(alpha: .34)]))))),
          child,
        ]);
    if (widget.size == CardSize.m) {
      return Press(
        onTap: widget.onLong, onLongPress: widget.holdOpens ? widget.onLong : null, depth: .025,
        child: Hero(tag: 'tile/${widget.id}', child: Glass(p: p, cell: widget.cell, big: true, child: glow(Padding(padding: EdgeInsets.symmetric(horizontal: 8 * u),
            child: Row(children: [
          // the number its share, the words theirs: a range (20–24) would take the whole width and leave "E…" of the name
          Flexible(flex: 5, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: number)),
          SizedBox(width: 6 * u),
          Expanded(flex: 4, child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: max(12, 8.5 * u))),
            DefaultTextStyle.merge(style: TextStyle(fontSize: max(11, 6.8 * u)), child: status),
          ])),
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            chevron(CupertinoIcons.chevron_up, 1), chevron(CupertinoIcons.chevron_down, -1)]),
        ]))))),
      );
    }
    return Press(
      onTap: widget.onLong, onLongPress: widget.holdOpens ? widget.onLong : null, depth: .025,
      child: Hero(tag: 'tile/${widget.id}', child: Glass(p: p, cell: widget.cell, big: true, child: glow(Stack(children: [
        // the name along the top, as Apple's tiles have theirs (under the number it was lost: 11 px on a Show 5)
        Positioned(left: max(18, 8 * u), top: max(15, 6 * u), right: max(18, 8 * u), child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: max(12, 7 * u)))),
        Center(child: Padding(padding: EdgeInsets.fromLTRB(6 * u, 12 * u, 6 * u, 12 * u), child: Column(mainAxisSize: MainAxisSize.min, children: [
          FittedBox(fit: BoxFit.scaleDown, child: number),
          SizedBox(height: 3 * u),
          DefaultTextStyle.merge(style: TextStyle(fontSize: max(10, 4.8 * u)), child: status),
        ]))),
        // the chevrons, as on Apple's thermostat card: no ripple, a press that gives
        Positioned(left: 4 * u, bottom: 4 * u, child: chevron(CupertinoIcons.chevron_down, -1)),
        Positioned(right: 4 * u, bottom: 4 * u, child: chevron(CupertinoIcons.chevron_up, 1)),
      ])))),
    );
  }
}

/// what plays: its cover, the title big, the buttons.  Always on Home (wall_view.dart nowPlayer), at the size that fits
/// on its first page or the owner's: l = 2 x 2 cells, m = 2 x 1 (the cover beside the words), s = a tile (the cover, the
/// title, play), xl = 4 x 2 (as m, all of it bigger)
class NowPlayingCard extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final String id;
  final double cell;
  final CardSize size;
  final VoidCallback onLong;
  final bool holdOpens;
  const NowPlayingCard({super.key, required this.ha, required this.p, required this.id, required this.cell, this.size = CardSize.l, required this.onLong,
      this.holdOpens = true});
  @override
  Widget build(BuildContext context) {
    final st = ha.states[id], u = cell * (size == CardSize.xl ? 3.4 : 2.07) / 100;
    final pic = st?.attr['entity_picture'] as String?;
    final title = st?.attr['media_title'] as String?, idle = title == null && st?.state != 'playing';
    final top = (idle ? 'Not Playing' : title ?? st?.name ?? '').toUpperCase();
    final under = idle || title == null ? st?.name ?? '' : '${st?.attr['media_artist'] ?? st?.attr['media_album_name'] ?? ''}';
    final playing = ha.sounding(id);
    void c(String s) => s == 'media_play_pause' ? ha.playPause(id) : ha.call('media_player', s, id);
    Widget cover(double note) => pic != null
        ? Image.network(ha.image(pic).toString(), headers: ha.authHeader, fit: BoxFit.cover, gaplessPlayback: true,
            errorBuilder: (_, _, _) => Container(color: const Color(0xff2a2f45)))
        : Container(color: const Color(0xff2a2f45), alignment: Alignment.center, child: Icon(Icons.music_note, color: Colors.white24, size: note));
    Widget button(IconData i, double s, String svc) => GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => c(svc),
        child: Padding(padding: EdgeInsets.all(2 * u), child: Icon(i, color: Colors.white, size: s)));
    Text topText(double f) => Text(top, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: f));
    Text underText(double f) => Text(under, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white70, fontSize: f));
    const shade = DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0x00000000), Color(0xa6000000)], stops: [.3, 1])));
    final body = switch (size) {
      CardSize.s => Stack(fit: StackFit.expand, children: [
          cover(22 * u),
          shade,
          Positioned(top: 2 * u, right: 2 * u, child: button(playing ? Icons.pause_circle_filled : Icons.play_circle_filled, 15 * u, 'media_play_pause')),
          Padding(padding: EdgeInsets.fromLTRB(5 * u, 0, 5 * u, 4 * u), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end, children: [topText(5.6 * u), underText(max(10, 4.4 * u))])),
        ]),
      CardSize.m || CardSize.xl => Container(color: const Color(0xff1f2233), child: Row(children: [
          AspectRatio(aspectRatio: 1, child: cover(26 * u)),
          Expanded(child: Padding(padding: EdgeInsets.fromLTRB(6 * u, 4 * u, 4 * u, 3 * u), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center, children: [
            topText(6.6 * u),
            underText(max(10, 5 * u)),
            SizedBox(height: 2 * u),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Row(mainAxisSize: MainAxisSize.min, children: [
              button(Icons.skip_previous, 12 * u, 'media_previous_track'),
              SizedBox(width: 4 * u),
              button(playing ? Icons.pause : Icons.play_arrow, 16 * u, 'media_play_pause'),
              SizedBox(width: 4 * u),
              button(Icons.skip_next, 12 * u, 'media_next_track'),
            ])),
          ]))),
        ])),
      _ => Stack(fit: StackFit.expand, children: [
          Align(alignment: const Alignment(0, -.35), child: SizedBox.expand(child: cover(34 * u))),
          shade,
          Padding(padding: EdgeInsets.fromLTRB(7 * u, 6 * u, 7 * u, 4 * u), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end, children: [
            topText(8 * u),
            underText(max(10, 5.4 * u)),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              IconButton(iconSize: 13 * u, color: Colors.white, onPressed: () => c('media_previous_track'), icon: const Icon(Icons.skip_previous)),
              IconButton(iconSize: 17 * u, color: Colors.white, onPressed: () => c('media_play_pause'), icon: Icon(playing ? Icons.pause : Icons.play_arrow)),
              IconButton(iconSize: 13 * u, color: Colors.white, onPressed: () => c('media_next_track'), icon: const Icon(Icons.skip_next)),
            ]),
          ])),
        ]),
    };
    return GestureDetector(onTap: onLong, onLongPress: holdOpens ? onLong : null,
        child: ClipRRect(borderRadius: BorderRadius.circular(size == CardSize.s || size == CardSize.m ? cell * .16 : cell * .2), child: body));
  }
}

/// the analog clock, drawn
class AnalogClockCard extends StatelessWidget {
  final Palette p;
  final double cell;
  const AnalogClockCard({super.key, required this.p, required this.cell});
  @override
  Widget build(BuildContext context) => Glass(p: p, cell: cell, padding: EdgeInsets.all(cell * .06),
      child: Ticker(builder: (_, now) => CustomPaint(painter: _Face(now, p.text), size: Size.infinite)));
}

class _Face extends CustomPainter {
  final DateTime t;
  final Color c;
  _Face(this.t, this.c);
  @override
  void paint(Canvas canvas, Size size) {
    final r = min(size.width, size.height) / 2, o = size.center(Offset.zero);
    final pen = Paint()..color = c..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6, r1 = r * (i % 3 == 0 ? .74 : .8);
      pen.strokeWidth = r * (i % 3 == 0 ? .052 : .032);
      canvas.drawLine(o + Offset(sin(a) * r1, -cos(a) * r1), o + Offset(sin(a) * r * .88, -cos(a) * r * .88), pen..color = c.withValues(alpha: .85));
    }
    void hand(double deg, double len, double w) {
      final a = deg * pi / 180;
      canvas.drawLine(o, o + Offset(sin(a) * r * len, -cos(a) * r * len), pen..strokeWidth = r * w..color = c);
    }
    hand((t.hour % 12 + t.minute / 60) * 30, .48, .08);
    hand(t.minute * 6.0, .7, .052);
    canvas.drawCircle(o, r * .052, pen);
  }

  @override
  bool shouldRepaint(_Face old) => old.t.minute != t.minute || old.c != c;
}

/// the digital clock: the time big, the date under it
class DigitalClockCard extends StatelessWidget {
  final Palette p;
  final double cell;
  final bool h24;
  final bool wide;                              // 2 cells wide: room for the seconds and the whole date
  final CardSize? size;                         // s, m (wide), l (wide and bigger); none: by `wide`
  const DigitalClockCard({super.key, required this.p, required this.cell, required this.h24, this.wide = false, this.size});
  @override
  Widget build(BuildContext context) {
    final big = size == CardSize.l || size == CardSize.xl, wide = size == null ? this.wide : size != CardSize.s;
    final u = cell * (big ? 1.7 : 1) / 100;
    return Glass(p: p, cell: cell, padding: EdgeInsets.symmetric(horizontal: 8 * u, vertical: 10 * u), child: Ticker(builder: (_, now) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
          Text(clockText(now, h24), style: TextStyle(color: p.text, fontSize: 38 * u, fontWeight: FontWeight.w300,
              fontFeatures: const [FontFeature.tabularFigures()], height: 1, letterSpacing: -1 * u)),
          if (!h24) Padding(padding: EdgeInsets.only(left: 3 * u),
              child: Text(ampm(now, h24), style: TextStyle(color: p.dim, fontSize: 11 * u, fontWeight: FontWeight.w600))),
        ])),
        SizedBox(height: 4 * u),
        Text(_weekday(now) + (wide ? ', ${_month(now)} ${now.day}' : ''), maxLines: 1,
            style: TextStyle(color: p.accentDay, fontSize: max(11, 10 * u), fontWeight: FontWeight.w700)),
      ]);
    }));
  }
}

const _wd = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _mo = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
String _weekday(DateTime t) => _wd[t.weekday - 1];
String _month(DateTime t) => _mo[t.month - 1];

/// the date (Apple's order: "Mon Nov", the day big) and the weather
class DateWeatherCard extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final double cell;
  final CardSize size;                          // s: Apple's; m: the date, and the weather beside it big
  const DateWeatherCard({super.key, required this.ha, required this.p, required this.cell, this.size = CardSize.s});
  @override
  Widget build(BuildContext context) {
    final u = cell / 100;
    final w = ha.states.entries.where((e) => domainOf(e.key) == 'weather').map((e) => e.value).firstOrNull;
    if (size != CardSize.s) {
      return Glass(p: p, cell: cell, padding: EdgeInsets.symmetric(horizontal: 12 * u, vertical: 10 * u), child: Ticker(builder: (_, now) => Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${_weekday(now)}, ${_month(now).substring(0, 3)}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.accentDay, fontWeight: FontWeight.w700, fontSize: max(11, 10.5 * u))),
          Text('${now.day}', style: TextStyle(color: p.text, fontSize: 40 * u, fontWeight: FontWeight.w300, height: .95)),
        ])),
        if (w != null) Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(weatherIcon(w.state), size: 26 * u, color: p.text),
          Text(w.numAttr('temperature') != null ? '${w.numAttr('temperature')!.round()}°' : '',
              style: TextStyle(color: p.text, fontSize: 22 * u, fontWeight: FontWeight.w400)),
          Text(weatherText(w.state), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.dim, fontSize: max(10, 8.5 * u))),
        ])),
      ])));
    }
    return Glass(p: p, cell: cell, padding: EdgeInsets.symmetric(horizontal: 11 * u, vertical: 10 * u), child: Ticker(builder: (_, now) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${_weekday(now).substring(0, 3)} ${_month(now).substring(0, 3)}',
              style: TextStyle(color: p.accentDay, fontWeight: FontWeight.w700, fontSize: max(11, 10.5 * u))),
          Text('${now.day}', style: TextStyle(color: p.text, fontSize: 32 * u, fontWeight: FontWeight.w300, height: .95)),
          if (w != null) Row(children: [
            Icon(weatherIcon(w.state), size: 16 * u, color: p.text),
            SizedBox(width: 4 * u),
            Text(w.numAttr('temperature') != null ? '${w.numAttr('temperature')!.round()}°' : '',
                style: TextStyle(color: p.text, fontSize: 15 * u, fontWeight: FontWeight.w500)),
          ]),
          if (w != null) Text(weatherText(w.state),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.dim, fontSize: max(10, 8.5 * u))),
        ])));
  }
}


/// a camera: its picture, again every 10 s while shown
class CameraCard extends StatefulWidget {
  final Ha ha;
  final Palette p;
  final String id;
  final double cell;
  final bool live;                              // on screen and seen (not under the lock screen, not in edit mode)
  const CameraCard({super.key, required this.ha, required this.p, required this.id, required this.cell, this.live = true});
  @override
  State<CameraCard> createState() => _CameraCardState();
}

/// The camera, live: Home Assistant's HLS stream of it (the entity's profile: an ONVIF camera's second is its substream,
/// small for the Show 5's decoder), muted, only while the card is seen.  Without a stream, stills; Home Assistant's
/// own still can fail where the stream works (measured: an ONVIF Uniview, HTTP 500 after HA's 10 s timeout, every time).
class _CameraCardState extends State<CameraCard> {
  /// each camera's stream playing in its card: a copy of the card that is not live (the one lifted under the finger in
  /// the edit mode) shows that one's picture, no second stream for the Show 5 to decode, nothing to wait for
  static final playing = <String, VideoPlayerController>{};
  VideoPlayerController? _v;
  final _shown = ValueNotifier<VideoPlayerController?>(null);   // the playing stream, for the full screen view
  bool _full = false;                           // the full screen view is open: live whatever is under it
  bool get _live => widget.live || _full;
  bool _streamFailed = false, _tooBig = false;
  String _tooBigSize = '';                      // the stream's that the decoder refused: "2592 × 1520"
  int _try = 0;                                 // which of the camera's streams: the entity's, then its device's other cameras
  List<String> get _streams => [widget.id, ...widget.ha.sameDevice(widget.id).where((x) => x.startsWith('camera.') && widget.ha.states.containsKey(x))];
  int _gen = 0;
  // the still, fetched here rather than by Image.network: one request at a time (a still taken from the stream by
  // ffmpeg takes seconds; requests every 10 s would pile up behind it), less often once it failed, what went wrong logged
  Timer? _t;
  Uint8List? _jpg;
  bool _busy = false;
  int _fails = 0;
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 10), (t) { if (_fails < 3 || t.tick % 6 == 0) _still(); });
    _follow();
  }

  @override
  void didUpdateWidget(CameraCard old) { super.didUpdateWidget(old); if (old.live != widget.live || old.id != widget.id) _follow(); }

  @override
  void dispose() { _disposed = true; _t?.cancel(); _http.close(force: true); _stop(); _shown.dispose(); super.dispose(); }

  void _follow() {
    if (_live && !_streamFailed) { _play(); } else { _stop(); }
    if (_v == null) _still();
  }

  Future<void> _play() async {
    if (_v != null) return;
    final gen = ++_gen, streams = _streams;
    if (_try >= streams.length) { _streamFailed = true; _still(); return; }
    final cam = streams[_try];
    final url = await widget.ha.cameraStream(cam);
    if (gen != _gen || !mounted) return;
    if (url == null) { debugPrint('camera $cam: no stream'); _next(); return; }
    final v = VideoPlayerController.networkUrl(url, formatHint: VideoFormat.hls, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _v = v;
    v.addListener(() {
      if (v.value.hasError && _v == v) {
        final e = v.value.errorDescription ?? '';
        debugPrint('camera $cam: stream $e');
        // more than the Show 5's decoder takes (measured: 2592 x 1520 H.264 level 5.0, an ONVIF camera's main
        // profile): the camera's other stream, its substream, where Home Assistant has it enabled
        if (e.contains('EXCEEDS_CAPABILITIES')) {
          _tooBig = true;
          final m = RegExp(r'\[(\d+), (\d+),').firstMatch(e);
          if (m != null) _tooBigSize = '${m[1]} × ${m[2]}';
        }
        _next();
      }
    });
    try {
      await v.initialize();
      await v.setVolume(0);
      await v.play();
      debugPrint('camera $cam: live, ${v.value.size.width.round()} x ${v.value.size.height.round()}');
      if (_v == v) { _shown.value = v; playing[widget.id] = v; }
    } catch (e) {
      if (_v == v) _next();
    }
    if (mounted) setState(() {});
  }

  /// this stream did not play: the next of the camera's, else stills
  void _next() {
    _stop();
    _try++;
    if (_try >= _streams.length) {
      debugPrint('camera ${widget.id}: no stream plays here (of ${_streams.join(', ')})');
      _streamFailed = true;
      _still();
    } else if (_live) {
      _play();
    }
    if (mounted) setState(() {});
  }

  void _stop() {
    _gen++;
    final v = _v;
    _v = null;
    if (!_disposed) _shown.value = null;
    playing.removeWhere((_, x) => x == v);
    v?.dispose();
  }

  Future<void> _still() async {
    final pic = widget.ha.states[widget.id]?.attr['entity_picture'] as String?;
    if (_busy || pic == null || (_v?.value.isInitialized ?? false) || !mounted) return;
    _busy = true;
    final sw = Stopwatch()..start();
    try {
      final rq = await _http.getUrl(widget.ha.image(pic));
      widget.ha.authHeader.forEach(rq.headers.set);
      final rs = await rq.close().timeout(const Duration(seconds: 30));
      final bytes = await consolidateBytes(rs);
      if (rs.statusCode == 200) {
        _fails = 0;
        if (mounted) setState(() => _jpg = bytes);
      } else {
        if (_fails++ == 0) debugPrint('camera ${widget.id}: still: HTTP ${rs.statusCode} after ${sw.elapsedMilliseconds} ms');
      }
    } catch (e) {
      if (_fails++ == 0) debugPrint('camera ${widget.id}: still: $e after ${sw.elapsedMilliseconds} ms');
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.cell / 100, m = widget.live ? null : playing[widget.id], v = _v ?? m;
    final live = v != null && v.value.isInitialized && v.value.size.width > 0;
    // no picture (Home Assistant could not get one from the camera): said so, on glass, instead of a black square
    final none = Glass(p: widget.p, cell: widget.cell, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(_overRes ? CupertinoIcons.exclamationmark_triangle : CupertinoIcons.video_camera, size: 22 * u, color: widget.p.dim),
      SizedBox(height: 3 * u),
      Text(_v != null && !live ? 'Connecting…' : _overRes ? 'Resolution too high' : 'No picture',
          style: TextStyle(color: widget.p.dim, fontSize: max(10.0, 7.5 * u), fontWeight: FontWeight.w600)),
      if (_overRes) Padding(padding: EdgeInsets.fromLTRB(8 * u, 1.5 * u, 8 * u, 0), child: Text(
          _tooBigSize.isEmpty ? 'Enable a substream' : '$_tooBigSize · enable a substream',
          textAlign: TextAlign.center, maxLines: 2, style: TextStyle(color: widget.p.dim.withValues(alpha: .8), fontSize: max(9.0, 5.4 * u)))),
    ])));
    return GestureDetector(onTap: _open, child: ClipRSuperellipse(borderRadius: BorderRadius.circular(min(30, widget.cell * .17)), child: Stack(fit: StackFit.expand, children: [
      none,
      if (_jpg != null && !live) Image.memory(_jpg!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox()),
      if (live) FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge,
          child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v))),
      if (live) Positioned(top: 7 * u, right: 8 * u, child: Container(
          padding: EdgeInsets.symmetric(horizontal: 4 * u, vertical: 1.5 * u),
          decoration: BoxDecoration(color: const Color(0xccff3b30), borderRadius: BorderRadius.circular(4 * u)),
          child: Text('LIVE', style: TextStyle(color: Colors.white, fontSize: max(9.0, 5.5 * u), fontWeight: FontWeight.w700, letterSpacing: .5)))),
      Positioned(left: 8 * u, bottom: 6 * u, right: 8 * u, child: Text(nameIn(widget.ha, widget.id, null), maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: max(10, 9 * u), shadows: const [Shadow(blurRadius: 3)]))),
    ])));
  }

  bool _disposed = false;

  /// every stream of the camera refused by the Show 5's decoder as too big, and no still to show instead
  bool get _overRes => _tooBig && _streamFailed && _v == null;

  /// the camera full screen: the tile's own stream (no second one for the Show 5 to decode, and no wait), kept live
  /// while it is open, the lock screen's time-out notwithstanding; a tap closes it
  Future<void> _open() async {
    setState(() => _full = true);
    _follow();
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => CameraFullScreen(name: nameIn(widget.ha, widget.id, null), stream: _shown, still: () => _jpg,
          tooBig: () => _overRes ? _tooBigSize : null),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: ScaleTransition(
          scale: Tween(begin: .94, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)), child: child)),
    ));
    if (!mounted) return;
    setState(() => _full = false);
    _follow();
  }
}

class CameraFullScreen extends StatelessWidget {
  final String name;
  final ValueListenable<VideoPlayerController?> stream;
  final Uint8List? Function() still;
  final String? Function() tooBig;              // every stream refused by the decoder: the resolution ('' unknown)
  const CameraFullScreen({super.key, required this.name, required this.stream, required this.still, required this.tooBig});
  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).maybePop();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: close,
      onVerticalDragEnd: (d) { if ((d.primaryVelocity ?? 0) > 300) close(); },   // swiped down
      child: Material(color: Colors.black, child: Stack(fit: StackFit.expand, children: [
        ValueListenableBuilder(valueListenable: stream, builder: (_, v, _) {
          if (v != null && v.value.isInitialized && v.value.size.width > 0) {
            return Center(child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)));
          }
          final jpg = still();
          if (jpg != null) return Image.memory(jpg, fit: BoxFit.contain, gaplessPlayback: true);
          if (tooBig() case final size?) {
            return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(CupertinoIcons.exclamationmark_triangle, color: Color(0xffffd60a), size: 44),
              const SizedBox(height: 14),
              const Text('Resolution too high', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('${size.isEmpty ? 'This camera\'s stream' : 'This camera\'s stream ($size)'} is more than this screen can play.\n'
                  'In Home Assistant, enable a smaller stream of the camera (its substream): '
                  'Settings › Devices › the camera › its disabled camera entities. It is used here by itself.',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4)),
            ])));
          }
          return const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 16));
        }),
        Positioned(left: 20, top: 16, child: Row(children: [
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 4)])),
          const SizedBox(width: 10),
          ValueListenableBuilder(valueListenable: stream, builder: (_, v, _) => v == null ? const SizedBox() : Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xccff3b30), borderRadius: BorderRadius.circular(4)),
              child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .5)))),
        ])),
        Positioned(right: 16, top: 12, child: GestureDetector(onTap: close, child: Container(width: 40, height: 40,
            decoration: const BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
            child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 20)))),
      ])),
    );
  }
}

/// another screen of the app (Home Assistant's own UI, Music Assistant): a tile that goes there, as the accessories'
class ScreenTile extends StatelessWidget {
  final Palette p;
  final String name;
  final double cell;
  final VoidCallback onTap;
  final CardSize size;                          // s, or m: the badge beside the name
  const ScreenTile({super.key, required this.p, required this.name, required this.cell, required this.onTap, this.size = CardSize.s});
  @override
  Widget build(BuildContext context) {
    final u = cell / 100, badge = 26 * u;
    final icon = RegExp('music', caseSensitive: false).hasMatch(name) ? Icons.music_note
        : RegExp('clock', caseSensitive: false).hasMatch(name) ? Icons.schedule
        : RegExp('assistant|home', caseSensitive: false).hasMatch(name) ? Icons.home : Icons.web;
    if (size != CardSize.s) {
      return GestureDetector(onTap: onTap, child: Glass(p: p, cell: cell, padding: EdgeInsets.all(12 * u), child: Row(children: [
        Container(width: badge * 1.3, height: badge * 1.3,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.text == Colors.white ? const Color(0x24ffffff) : const Color(0x14000000)),
            child: Icon(icon, size: badge * .72, color: p.text)),
        SizedBox(width: 10 * u),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: max(13.0, 10 * u))),
          Text('Open', style: TextStyle(color: p.dim, fontSize: max(11.0, 7.8 * u), fontWeight: FontWeight.w500)),
        ])),
      ])));
    }
    return GestureDetector(onTap: onTap, child: Glass(p: p, cell: cell, padding: EdgeInsets.all(10 * u), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: badge, height: badge,
          decoration: BoxDecoration(shape: BoxShape.circle, color: p.text == Colors.white ? const Color(0x24ffffff) : const Color(0x14000000)),
          child: Icon(icon, size: badge * .56, color: p.text)),
      const Spacer(),
      Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: max(12.0, 9 * u))),
      SizedBox(height: 1.5 * u),
      Row(children: [
        Text('Open', style: TextStyle(color: p.dim, fontSize: max(11.0, 7.8 * u), fontWeight: FontWeight.w500)),
        Icon(Icons.chevron_right, size: max(12.0, 8 * u), color: p.dim),
      ]),
    ])));
  }
}
