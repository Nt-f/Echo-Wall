// The HomeView's widgets: square glass over the wallpaper, in the manner of Apple's HomeView.  Sizes are fractions of
// the cell (`u`: a hundredth of a cell's side), so a tile reads the same on a Show 5's 139 px cells and a Show 15's.
// No live blur: translucent white over a wallpaper drawn once (a Mali-T720 drops to 25-43 fps under a full blur).
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../echo_ui.dart' show Ticker, clockText, ampm;
import '../ha.dart';
import 'layout.dart';
import 'model.dart';

class Palette {
  final Gradient wall;
  final Color glass, edge, glassOn, text, dim, textOn, dimOn, sheet, accentDay;
  const Palette(this.wall, this.glass, this.edge, this.glassOn, this.text, this.dim, this.textOn, this.dimOn, this.sheet, this.accentDay);

  static Palette of(Wallpaper w) => switch (w) {
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

/// the wallpaper with two soft lights, once
class Wallpaper_ extends StatelessWidget {
  final Palette p;
  const Wallpaper_(this.p, {super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(gradient: p.wall),
        child: const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(center: Alignment(.5, -.3), radius: .9,
            colors: [Color(0x40ffe0a0), Color(0x00ffe0a0)]))),
      );
}

/// a glass card; `on` lights it
class Glass extends StatelessWidget {
  final Palette p;
  final bool on, big;
  final double cell;
  final Widget child;
  final EdgeInsets? padding;
  const Glass({super.key, required this.p, required this.cell, required this.child, this.on = false, this.big = false, this.padding});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: padding,
        decoration: BoxDecoration(
          color: on ? p.glassOn : p.glass,
          borderRadius: BorderRadius.circular(cell * (big ? .2 : .19)),
          border: Border.all(color: p.edge, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

/// an accessory: the icon on top, its name bold, its room or its state under it
class AccessoryTile extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final String id;
  final String? room;                           // shown under the name (Home), else its state
  final double cell;
  final VoidCallback onLong;
  const AccessoryTile({super.key, required this.ha, required this.p, required this.id, required this.cell, required this.onLong, this.room});
  @override
  Widget build(BuildContext context) {
    final l = look(ha, id), u = cell / 100;
    final fg = l.on ? p.textOn : p.text, dim = l.on ? p.dimOn : p.dim;
    final name = nameIn(ha, id, room ?? ha.areaName(ha.areaOf(id)));
    return GestureDetector(
      onTap: () { if (!tap(ha, id)) onLong(); },
      onLongPress: onLong,
      child: Opacity(
        opacity: l.unavailable ? .5 : 1,
        child: Glass(p: p, cell: cell, on: l.on, child: Stack(children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 6 * u),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              AnimatedScale(scale: l.on ? 1.08 : 1, duration: const Duration(milliseconds: 220),
                  child: Icon(l.icon, size: 25 * u, color: l.on ? l.color : fg)),
              SizedBox(height: 7 * u),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: max(11, 10.5 * u))),
              Text(room != null && !l.unavailable ? room! : l.text, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: dim, fontSize: max(10, 9.2 * u))),
            ]),
          ),
          if (l.level != null)
            Positioned(left: 16 * u, right: 16 * u, bottom: 7 * u, child: ClipRRect(borderRadius: BorderRadius.circular(2), child:
                LinearProgressIndicator(value: l.level, minHeight: 3, backgroundColor: const Color(0x14000000), color: l.color))),
        ])),
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
  const ThermostatCard({super.key, required this.ha, required this.p, required this.id, required this.cell, required this.onLong});
  @override
  State<ThermostatCard> createState() => _ThermostatCardState();
}

class _ThermostatCardState extends State<ThermostatCard> {
  double? want;
  Timer? _send;
  void nudge(int d) {
    final st = widget.ha.states[widget.id];
    if (st == null) return;
    final step = (st.numAttr('target_temp_step') ?? (st.attr['temperature_unit'] == '°F' ? 1 : .5)).toDouble();
    final cur = want ?? (st.numAttr('temperature') ?? 20).toDouble();
    final lo = (st.numAttr('min_temp') ?? -100).toDouble(), hi = (st.numAttr('max_temp') ?? 100).toDouble();
    setState(() => want = (((cur + d * step) / step).round() * step).clamp(lo, hi).toDouble());
    _send?.cancel();
    _send = Timer(const Duration(milliseconds: 800), () {
      widget.ha.call('climate', 'set_temperature', widget.id, {'temperature': want});
      Timer(const Duration(seconds: 3), () { if (mounted) setState(() => want = null); });
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.ha.states[widget.id], p = widget.p, u = widget.cell * 2.07 / 100;
    final t = want ?? st?.numAttr('temperature');
    final txt = t == null ? '—' : (t % 1 == 0 ? t.toInt().toString() : t.toStringAsFixed(1));
    final parts = txt.split('.');
    final room = widget.ha.areaName(widget.ha.areaOf(widget.id));
    final cur = st?.numAttr('current_temperature');
    return GestureDetector(
      onTap: widget.onLong, onLongPress: widget.onLong,
      child: Glass(p: p, cell: widget.cell, big: true, child: Stack(children: [
        Center(child: Padding(padding: EdgeInsets.only(bottom: 12 * u), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(parts[0], style: TextStyle(color: p.text, fontSize: 44 * u, height: 1, fontWeight: FontWeight.w400, letterSpacing: -1.5 * u)),
            if (parts.length > 1) Text('.${parts[1]}', style: TextStyle(color: p.text, fontSize: 16 * u)),
          ]),
          SizedBox(height: 3 * u),
          Text(nameIn(widget.ha, widget.id, room), style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: max(11, 5.4 * u))),
          Text([room, if (cur != null) '$cur°', if (st?.state == 'off') 'Off'].where((s) => s.isNotEmpty).join(' • '),
              style: TextStyle(color: p.dim, fontSize: max(10, 4.8 * u))),
        ]))),
        Positioned(left: 2 * u, bottom: 2 * u, child: IconButton(iconSize: 13 * u, color: p.text, onPressed: () => nudge(-1), icon: const Icon(Icons.expand_more))),
        Positioned(right: 2 * u, bottom: 2 * u, child: IconButton(iconSize: 13 * u, color: p.text, onPressed: () => nudge(1), icon: const Icon(Icons.expand_less))),
      ])),
    );
  }
}

/// what plays: its cover, the title big, the buttons
class NowPlayingCard extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final String id;
  final double cell;
  final VoidCallback onLong;
  const NowPlayingCard({super.key, required this.ha, required this.p, required this.id, required this.cell, required this.onLong});
  @override
  Widget build(BuildContext context) {
    final st = ha.states[id], u = cell * 2.07 / 100;
    final pic = st?.attr['entity_picture'] as String?;
    void c(String s) => ha.call('media_player', s, id);
    return GestureDetector(
      onTap: onLong, onLongPress: onLong,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cell * .2),
        child: Stack(fit: StackFit.expand, children: [
          if (pic != null) Image.network(ha.image(pic).toString(), headers: ha.authHeader, fit: BoxFit.cover, gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Container(color: const Color(0xff2a2f45)))
          else Container(color: const Color(0xff2a2f45)),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xa6000000)], stops: [.3, 1]))),
          Padding(padding: EdgeInsets.fromLTRB(7 * u, 6 * u, 7 * u, 4 * u), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('${st?.attr['media_title'] ?? st?.name ?? ''}'.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 8 * u)),
            Text('${st?.attr['media_artist'] ?? st?.attr['media_album_name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white70, fontSize: max(10, 5.4 * u))),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              IconButton(iconSize: 13 * u, color: Colors.white, onPressed: () => c('media_previous_track'), icon: const Icon(Icons.skip_previous)),
              IconButton(iconSize: 17 * u, color: Colors.white, onPressed: () => c('media_play_pause'),
                  icon: Icon(st?.state == 'playing' ? Icons.pause : Icons.play_arrow)),
              IconButton(iconSize: 13 * u, color: Colors.white, onPressed: () => c('media_next_track'), icon: const Icon(Icons.skip_next)),
            ]),
          ])),
        ]),
      ),
    );
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
  const DigitalClockCard({super.key, required this.p, required this.cell, required this.h24, this.wide = false});
  @override
  Widget build(BuildContext context) {
    final u = cell / 100;
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
  const DateWeatherCard({super.key, required this.ha, required this.p, required this.cell});
  @override
  Widget build(BuildContext context) {
    final u = cell / 100;
    final w = ha.states.entries.where((e) => domainOf(e.key) == 'weather').map((e) => e.value).firstOrNull;
    return Glass(p: p, cell: cell, padding: EdgeInsets.symmetric(horizontal: 11 * u, vertical: 10 * u), child: Ticker(builder: (_, now) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${_weekday(now).substring(0, 3)} ${_month(now).substring(0, 3)}',
              style: TextStyle(color: p.accentDay, fontWeight: FontWeight.w700, fontSize: max(11, 10.5 * u))),
          Text('${now.day}', style: TextStyle(color: p.text, fontSize: 32 * u, fontWeight: FontWeight.w300, height: .95)),
          if (w != null) Row(children: [
            Icon(_wx[w.state] ?? Icons.cloud, size: 16 * u, color: p.text),
            SizedBox(width: 4 * u),
            Text(w.numAttr('temperature') != null ? '${w.numAttr('temperature')!.round()}°' : '',
                style: TextStyle(color: p.text, fontSize: 15 * u, fontWeight: FontWeight.w500)),
          ]),
          if (w != null) Text(w.state.replaceAll('-', ' ').replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase()),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.dim, fontSize: max(10, 8.5 * u))),
        ])));
  }
}

const _wx = {'sunny': Icons.wb_sunny, 'clear-night': Icons.nights_stay, 'cloudy': Icons.cloud, 'partlycloudy': Icons.wb_cloudy,
    'rainy': Icons.grain, 'pouring': Icons.grain, 'lightning': Icons.flash_on, 'lightning-rainy': Icons.flash_on, 'snowy': Icons.ac_unit,
    'snowy-rainy': Icons.ac_unit, 'fog': Icons.foggy, 'windy': Icons.air, 'windy-variant': Icons.air, 'hail': Icons.grain};

/// a camera: its picture, again every 10 s while shown
class CameraCard extends StatefulWidget {
  final Ha ha;
  final Palette p;
  final String id;
  final double cell;
  const CameraCard({super.key, required this.ha, required this.p, required this.id, required this.cell});
  @override
  State<CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<CameraCard> {
  Timer? _t;
  int n = 0;
  @override
  void initState() { super.initState(); _t = Timer.periodic(const Duration(seconds: 10), (_) { if (mounted) setState(() => n++); }); }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final st = widget.ha.states[widget.id], u = widget.cell / 100;
    final pic = st?.attr['entity_picture'] as String?;
    return ClipRRect(borderRadius: BorderRadius.circular(widget.cell * .19), child: Stack(fit: StackFit.expand, children: [
      Container(color: const Color(0xff222222)),
      if (pic != null) Image.network('${widget.ha.image(pic)}&t=$n', headers: widget.ha.authHeader, fit: BoxFit.cover, gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox()),
      Positioned(left: 8 * u, bottom: 6 * u, right: 8 * u, child: Text(nameIn(widget.ha, widget.id, null), maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: max(10, 9 * u), shadows: const [Shadow(blurRadius: 3)]))),
    ]));
  }
}

/// another screen of the app (Home Assistant's own UI, Music Assistant): a tile that goes there
class ScreenTile extends StatelessWidget {
  final Palette p;
  final String name;
  final double cell;
  final VoidCallback onTap;
  const ScreenTile({super.key, required this.p, required this.name, required this.cell, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final u = cell / 100;
    final icon = RegExp('music', caseSensitive: false).hasMatch(name) ? Icons.music_note
        : RegExp('assistant|home', caseSensitive: false).hasMatch(name) ? Icons.home : Icons.web;
    return GestureDetector(onTap: onTap, child: Glass(p: p, cell: cell, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 25 * u, color: p.text),
      SizedBox(height: 7 * u),
      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: max(11, 10.5 * u))),
      Text('Open', style: TextStyle(color: p.dim, fontSize: max(10, 9.2 * u))),
    ])));
  }
}
