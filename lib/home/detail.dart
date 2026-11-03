// A device's detail, as Apple's Home opens one: the tile grows out of its place into a card (a hero flight of its
// glass), the HomeView behind it dims, the card is a thick material and holds one large control:
//   lights, blinds, fans                       the tall pill, live while the finger moves (sent at most 4 times a second)
//   a thermostat                               its temperature big, round − and +, its modes as a segmented control
//   a switch, a lock                           one large round button
//   a speaker                                  its artwork, the controls round, its volume
// and round glass buttons.  A swipe down, a tap beside it or × closes it; the card shrinks back into its tile.
import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ha.dart';
import 'backdrop.dart';
import 'model.dart';
import 'press.dart';
import 'widgets.dart';

String heroTag(String id) => 'tile/$id';

Future<void> showDetail(BuildContext context, Ha ha, Palette p, String id, Backdrop? backdrop) => Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: const Color(0x00000000),            // the dimming is the page's own (it fades with the card)
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      // the route is not under the HomeView: its backdrop handed over, for the card's glass
      pageBuilder: (context, a, _) => backdrop == null ? _DetailPage(ha: ha, p: p, id: id, anim: a)
          : BackdropScope(backdrop: backdrop, child: _DetailPage(ha: ha, p: p, id: id, anim: a)),
    ));

class _DetailPage extends StatefulWidget {
  final Ha ha;
  final Palette p;
  final String id;
  final Animation<double> anim;
  const _DetailPage({required this.ha, required this.p, required this.id, required this.anim});
  @override
  State<_DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<_DetailPage> {
  double drag = 0;                              // pulled down this far (px)
  void close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: widget.anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final size = MediaQuery.sizeOf(context), small = size.shortestSide < 400;
    final w = min(size.width * (small ? .86 : .62), 640.0), h = min(size.height * (small ? .86 : .82), 560.0);
    return AnimatedBuilder(animation: a, builder: (context, _) => Stack(children: [
      // the HomeView behind: dimmed; a tap there closes
      Positioned.fill(child: GestureDetector(onTap: close, child: ColoredBox(color: Color.fromRGBO(0, 0, 0, .5 * a.value * (1 - drag / 600).clamp(0, 1))))),
      Center(child: GestureDetector(
        onVerticalDragUpdate: (d) => setState(() => drag = max(0, drag + d.delta.dy)),
        onVerticalDragEnd: (d) { if (drag > 120 || (d.primaryVelocity ?? 0) > 700) { close(); } else { setState(() => drag = 0); } },
        child: Transform.translate(offset: Offset(0, drag), child: Transform.scale(scale: 1 - drag / 3000, child: SizedBox(width: w, height: h,
          child: Hero(tag: heroTag(widget.id), child: Material(type: MaterialType.transparency, child: ListenableBuilder(listenable: widget.ha,
            builder: (context, _) => _Card(ha: widget.ha, p: widget.p, id: widget.id, small: small, onClose: close))))))),
      )),
    ]));
  }
}

class _Card extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final String id;
  final bool small;
  final VoidCallback onClose;
  const _Card({required this.ha, required this.p, required this.id, required this.small, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final st = ha.states[id];
    final l = look(ha, id), d = domainOf(id);
    final room = ha.areaName(ha.areaOf(id));
    final fg = p.sheetText;
    final b = BackdropScope.of(context);
    final radius = BorderRadius.circular(small ? 28 : 40);
    // Apple's thick material: the wallpaper's blur behind, darkened well (the controls in white on it)
    return DecoratedBox(
      decoration: ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: radius),
          shadows: const [BoxShadow(color: Color(0x59000000), blurRadius: 40, offset: Offset(0, 18))]),
      child: Frosted(
        blurred: b?.blurred, screen: b?.size ?? Size.zero, radius: radius, tint: p.sheet,
        edgeTop: const Color(0x40ffffff), edgeBottom: const Color(0x0affffff),
        child: Padding(padding: EdgeInsets.all(small ? 16 : 26), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // the head: its badge, its name, what it is doing; × to close
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(width: small ? 38 : 50, height: small ? 38 : 50, decoration: BoxDecoration(shape: BoxShape.circle,
                color: l.on ? l.color.withValues(alpha: .22) : fg.withValues(alpha: .1)),
                child: Icon(l.icon, color: l.on ? l.color : fg, size: small ? 22 : 28)),
            SizedBox(width: small ? 10 : 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nameIn(ha, id, room), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: small ? 18 : 24, fontWeight: FontWeight.w700, letterSpacing: -.3)),
              Text([room, l.text].where((s) => s.isNotEmpty).join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg.withValues(alpha: .6), fontSize: small ? 13 : 16, fontWeight: FontWeight.w500)),
            ])),
            RoundButton(icon: CupertinoIcons.xmark, size: small ? 34 : 40, fg: fg, onTap: onClose),
          ]),
          Expanded(child: Center(child: st == null ? const SizedBox() : _control(context, d, st, l, fg))),
        ])),
      ),
    );
  }

  Widget _control(BuildContext context, String d, EntityState st, Look l, Color fg) {
    final big = small ? 150.0 : 260.0;
    switch (d) {
      case 'light':
      case 'cover':
      case 'fan':
        final v = switch (d) {
          'light' => st.state == 'on' ? ((st.numAttr('brightness') ?? 255) / 2.55).round() : 0,
          'cover' => (st.numAttr('current_position') ?? (st.state == 'open' ? 100 : 0)).round(),
          _ => st.state == 'on' ? (st.numAttr('percentage') ?? 100).round() : 0,
        };
        final toggle = d == 'cover'
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                RoundButton(icon: CupertinoIcons.arrow_up, fg: fg, label: 'Open', onTap: () => ha.call(d, 'open_cover', id)),
                const SizedBox(width: 14),
                RoundButton(icon: CupertinoIcons.stop_fill, fg: fg, label: 'Stop', onTap: () => ha.call(d, 'stop_cover', id)),
                const SizedBox(width: 14),
                RoundButton(icon: CupertinoIcons.arrow_down, fg: fg, label: 'Close', onTap: () => ha.call(d, 'close_cover', id)),
              ])
            : RoundButton(icon: CupertinoIcons.power, fg: st.state == 'on' ? Colors.black : fg, fill: st.state == 'on' ? Colors.white : null,
                size: 56, label: st.state == 'on' ? 'On' : 'Off', onTap: () => ha.call(d, 'toggle', id));
        // a light's colours and whites, as Apple's presets: circles that set them (what the light supports)
        final modes = (st.attr['supported_color_modes'] as List? ?? const []).cast<String>();
        final colour = d == 'light' && modes.any((m) => const {'hs', 'xy', 'rgb', 'rgbw', 'rgbww'}.contains(m));
        final white = d == 'light' && modes.contains('color_temp');
        final presets = <(Color, Map<String, dynamic>)>[
          if (white) ...[
            for (final k in const [2700, 3500, 4500, 6000])
              (Color.lerp(const Color(0xffffb46b), const Color(0xffdfeaff), (k - 2700) / 3300)!, {'color_temp_kelvin': k}),
          ],
          if (colour) ...[
            for (final (c, hs) in const [(Color(0xffff5a4e), [4, 80]), (Color(0xffffa53a), [30, 85]), (Color(0xff5ad06a), [125, 70]),
                (Color(0xff42a5ff), [210, 80]), (Color(0xffb36bff), [275, 70])])
              (c, {'hs_color': hs}),
          ],
        ];
        final presetRow = presets.isEmpty ? null : Padding(padding: EdgeInsets.only(top: small ? 12 : 22), child: Wrap(spacing: small ? 8 : 12,
            runSpacing: 8, children: [
          for (final (c, data) in presets)
            Press(onTap: () => ha.call('light', 'turn_on', id, data), depth: .1, child: Container(width: small ? 28 : 38, height: small ? 28 : 38,
                decoration: BoxDecoration(shape: BoxShape.circle, color: c, border: Border.all(color: const Color(0x66ffffff), width: 2),
                    boxShadow: [BoxShadow(color: c.withValues(alpha: .45), blurRadius: 10)]))),
        ]));
        return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          BigPill(value: v, height: big, color: l.on ? l.color : Colors.white, icon: l.icon, onChange: (x) {
            switch (d) {
              case 'light': x > 0 ? ha.call('light', 'turn_on', id, {'brightness_pct': x}) : ha.call('light', 'turn_off', id);
              case 'cover': ha.call('cover', 'set_cover_position', id, {'position': x});
              default: x > 0 ? ha.call('fan', 'set_percentage', id, {'percentage': x}) : ha.call('fan', 'turn_off', id);
            }
          }),
          SizedBox(width: small ? 18 : 40),
          Flexible(child: Column(mainAxisSize: MainAxisSize.min, children: [toggle, ?presetRow])),
        ]);
      case 'switch':
      case 'input_boolean':
      case 'humidifier':
        return BigToggle(on: st.state == 'on', icon: l.icon, color: l.color, size: big * .62, fg: fg, onTap: () => ha.call(d, 'toggle', id));
      case 'lock':
        final locked = st.state == 'locked';
        return BigToggle(on: !locked, icon: locked ? CupertinoIcons.lock_fill : CupertinoIcons.lock_open_fill, color: l.color, size: big * .62, fg: fg,
            label: locked ? 'Tap to unlock' : 'Tap to lock', onTap: () => ha.call(d, locked ? 'unlock' : 'lock', id));
      case 'climate':
        return _Climate(ha: ha, id: id, fg: fg, small: small);
      case 'media_player':
        final vol = ((st.numAttr('volume_level') ?? 0) * 100).round();
        final pic = st.attr['entity_picture'] as String?;
        return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          ClipRSuperellipse(borderRadius: BorderRadius.circular(18), child: SizedBox(width: big * .8, height: big * .8, child: pic != null
              ? Image.network(ha.image(pic).toString(), headers: ha.authHeader, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: fg.withValues(alpha: .1)))
              : ColoredBox(color: fg.withValues(alpha: .1), child: Icon(CupertinoIcons.music_note, color: fg, size: 48)))),
          SizedBox(width: small ? 14 : 30),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              RoundButton(icon: CupertinoIcons.backward_fill, fg: fg, onTap: () => ha.call(d, 'media_previous_track', id)),
              const SizedBox(width: 12),
              RoundButton(icon: st.state == 'playing' ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, fg: Colors.black, fill: Colors.white, size: 64,
                  onTap: () => ha.playPause(id)),
              const SizedBox(width: 12),
              RoundButton(icon: CupertinoIcons.forward_fill, fg: fg, onTap: () => ha.call(d, 'media_next_track', id)),
            ]),
            const SizedBox(height: 18),
            SizedBox(width: small ? 150 : 240, child: Row(children: [
              Icon(CupertinoIcons.speaker_fill, color: fg.withValues(alpha: .6), size: 18),
              Expanded(child: CupertinoSlider(value: vol / 100, activeColor: Colors.white, thumbColor: Colors.white,
                  onChanged: (x) => _throttled('vol$id', () => ha.call(d, 'volume_set', id, {'volume_level': x})))),
            ])),
            if (_groups(st)) Padding(padding: const EdgeInsets.only(top: 14), child: _Speakers(ha: ha, id: id, fg: fg)),
          ]),
        ]);
    }
    return Text(l.text, style: TextStyle(color: fg, fontSize: 22));
  }
}

/// what a slider sends, at most every 250 ms (and the last one always)
final _last = <String, DateTime>{}, _pending = <String, Timer>{};
void _throttled(String key, void Function() f) {
  final now = DateTime.now(), at = _last[key];
  _pending[key]?.cancel();
  if (at == null || now.difference(at).inMilliseconds >= 250) { _last[key] = now; f(); }
  else { _pending[key] = Timer(const Duration(milliseconds: 250), () { _last[key] = DateTime.now(); f(); }); }
}

/// Apple's tall pill: the fill follows the finger, the device follows the fill (live, throttled)
class BigPill extends StatefulWidget {
  final int value;
  final double height;
  final Color color;
  final IconData icon;
  final void Function(int) onChange;
  const BigPill({super.key, required this.value, required this.height, required this.color, required this.icon, required this.onChange});
  @override
  State<BigPill> createState() => _BigPillState();
}

class _BigPillState extends State<BigPill> {
  int? held;                                    // while the finger is on it, and a moment after (the device catches up)
  Timer? _release;
  double get h => widget.height;
  void _at(Offset o) {
    final v = ((h - o.dy) / h * 100).round().clamp(0, 100);
    if (v == held) return;
    setState(() => held = v);
    _throttled('pill${widget.hashCode}', () => widget.onChange(v));
  }

  void _later() => _release = Timer(const Duration(seconds: 2), () { if (mounted) setState(() => held = null); });

  @override
  void dispose() { _release?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final v = held ?? widget.value;
    return GestureDetector(
      onVerticalDragStart: (e) { _release?.cancel(); _at(e.localPosition); },
      onVerticalDragUpdate: (e) => _at(e.localPosition),
      onVerticalDragEnd: (_) => _later(),
      onTapUp: (e) { _at(e.localPosition); _later(); },
      child: Container(
        width: h * .44, height: h,
        decoration: ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(h * .17)), color: const Color(0x33ffffff),
            shadows: const [BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8))]),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Align(alignment: Alignment.bottomCenter, child: AnimatedContainer(
              duration: Duration(milliseconds: held == null ? 300 : 40), curve: Curves.easeOut,
              height: h * v / 100, color: widget.color == Colors.white ? Colors.white : Color.lerp(widget.color, Colors.white, .15))),
          Positioned(left: 0, right: 0, bottom: h * .06, child: Icon(widget.icon, size: h * .12,
              color: v > 12 ? const Color(0xb3000000) : Colors.white70)),
          Positioned(left: 0, right: 0, top: h * .06, child: Text('$v%', textAlign: TextAlign.center,
              style: TextStyle(color: v > 88 ? const Color(0xb3000000) : Colors.white, fontSize: h * .07, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}

/// one large round button that is the device: lit when on
class BigToggle extends StatelessWidget {
  final bool on;
  final IconData icon;
  final Color color, fg;
  final double size;
  final String? label;
  final VoidCallback onTap;
  const BigToggle({super.key, required this.on, required this.icon, required this.color, required this.size, required this.fg,
      required this.onTap, this.label});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Press(onTap: onTap, depth: .06, child: AnimatedContainer(
          duration: const Duration(milliseconds: 260), width: size, height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: on ? Colors.white : const Color(0x24ffffff),
              boxShadow: [BoxShadow(color: on ? color.withValues(alpha: .45) : const Color(0x33000000), blurRadius: 30, offset: const Offset(0, 10))]),
          child: Icon(icon, size: size * .42, color: on ? color : fg),
        )),
        if (label != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(label!, style: TextStyle(color: fg.withValues(alpha: .65), fontSize: 15))),
      ]);
}

/// a round glass button, an icon in it, a word under it
class RoundButton extends StatelessWidget {
  final IconData icon;
  final Color fg;
  final Color? fill;
  final double size;
  final String? label;
  final VoidCallback onTap;
  const RoundButton({super.key, required this.icon, required this.fg, required this.onTap, this.fill, this.size = 48, this.label});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Press(onTap: onTap, depth: .08, child: Container(width: size, height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: fill ?? const Color(0x24ffffff)),
            child: Icon(icon, size: size * .42, color: fg))),
        if (label != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(label!, style: TextStyle(color: fg.withValues(alpha: .6), fontSize: 12))),
      ]);
}

/// a player that can play in a group with others (Home Assistant's MediaPlayerEntityFeature.GROUPING: Music
/// Assistant's, Sonos, ...)
bool _groups(EntityState st) => ((st.numAttr('supported_features') ?? 0).toInt() & 524288) != 0;

/// the speakers playing along: a dropdown of every player that can join this one, ticked where it is in its group
/// (media_player.join / unjoin); it stays open to tick several
class _Speakers extends StatelessWidget {
  final Ha ha;
  final String id;
  final Color fg;
  const _Speakers({required this.ha, required this.id, required this.fg});
  @override
  Widget build(BuildContext context) {
    final members = ((ha.states[id]?.attr['group_members'] as List?) ?? const []).cast<String>().where((m) => m != id).toList();
    final others = ha.states.keys.where((x) => x != id && domainOf(x) == 'media_player' && _groups(ha.states[x]!)
        && ha.states[x]!.state != 'unavailable').toList()
      ..sort((a, b) => nameIn(ha, a, null).compareTo(nameIn(ha, b, null)));
    return MenuAnchor(
      style: MenuStyle(backgroundColor: const WidgetStatePropertyAll(Color(0xf02c2c2e)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      menuChildren: [
        if (others.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('No other speakers can join', style: TextStyle(color: Colors.white70))),
        for (final x in others)
          CheckboxMenuButton(
            value: members.contains(x),
            closeOnActivate: false,
            onChanged: (on) => on == true ? ha.call('media_player', 'join', id, {'group_members': [x]}) : ha.call('media_player', 'unjoin', x),
            child: Padding(padding: const EdgeInsets.only(right: 12),
                child: Text(nameIn(ha, x, null), style: const TextStyle(color: Colors.white, fontSize: 16))),
          ),
      ],
      builder: (context, menu, _) => GestureDetector(
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: fg.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.speaker_2_fill, color: fg, size: 16),
            const SizedBox(width: 8),
            Text(members.isEmpty ? 'Speakers' : '+ ${members.length} speaker${members.length == 1 ? '' : 's'}',
                style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_down, color: fg.withValues(alpha: .7), size: 14),
          ]),
        ),
      ),
    );
  }
}

class _Climate extends StatefulWidget {
  final Ha ha;
  final String id;
  final Color fg;
  final bool small;
  const _Climate({required this.ha, required this.id, required this.fg, required this.small});
  @override
  State<_Climate> createState() => _ClimateState();
}

class _ClimateState extends State<_Climate> {
  double? want;
  Timer? _t;
  @override
  void dispose() { _t?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final st = widget.ha.states[widget.id]!, fg = widget.fg;
    final step = (st.numAttr('target_temp_step') ?? (st.attr['temperature_unit'] == '°F' ? 1 : .5)).toDouble();
    final t = want ?? st.numAttr('temperature')?.toDouble();
    final cur = st.numAttr('current_temperature');
    void nudge(int d) {
      if (t == null) return;
      setState(() => want = ((t + d * step) / step).round() * step);
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 700), () {
        widget.ha.call('climate', 'set_temperature', widget.id, {'temperature': want});
        Timer(const Duration(seconds: 3), () { if (mounted) setState(() => want = null); });
      });
    }
    final modes = (st.attr['hvac_modes'] as List? ?? const []).cast<String>().take(4).toList();
    const icons = {'off': CupertinoIcons.power, 'heat': CupertinoIcons.flame_fill, 'cool': CupertinoIcons.snow, 'heat_cool': CupertinoIcons.thermometer,
        'auto': CupertinoIcons.arrow_2_circlepath, 'dry': CupertinoIcons.drop, 'fan_only': CupertinoIcons.wind};
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        RoundButton(icon: CupertinoIcons.minus, fg: fg, size: widget.small ? 48 : 64, onTap: () => nudge(-1)),
        SizedBox(width: widget.small ? 14 : 30),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t == null ? '—' : '${t % 1 == 0 ? t.toInt() : t}°', style: TextStyle(color: fg, fontSize: widget.small ? 56 : 96,
              fontWeight: FontWeight.w300, height: 1, letterSpacing: -2)),
          if (cur != null) Text('Now $cur°', style: TextStyle(color: fg.withValues(alpha: .6), fontSize: widget.small ? 13 : 16)),
        ]),
        SizedBox(width: widget.small ? 14 : 30),
        RoundButton(icon: CupertinoIcons.plus, fg: fg, size: widget.small ? 48 : 64, onTap: () => nudge(1)),
      ]),
      if (modes.isNotEmpty) Padding(padding: EdgeInsets.only(top: widget.small ? 14 : 28), child: CupertinoSlidingSegmentedControl<String>(
        groupValue: modes.contains(st.state) ? st.state : null,
        backgroundColor: const Color(0x24ffffff),
        thumbColor: const Color(0x66ffffff),
        children: {for (final m in modes) m: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icons[m] ?? CupertinoIcons.circle, size: 15, color: fg),
              if (!widget.small) ...[const SizedBox(width: 5), Text(m.replaceAll('_', ' '), style: TextStyle(color: fg, fontSize: 13))],
            ]))},
        onValueChanged: (m) { if (m != null) widget.ha.call('climate', 'set_hvac_mode', widget.id, {'hvac_mode': m}); },
      )),
    ]);
  }
}

/// a glass sheet of any content (a category's devices, the forecast): the detail's dimming, card and swipe down
Future<void> showSheet(BuildContext context, Palette p, Backdrop? backdrop, Widget Function(BuildContext, bool small) body,
        {double widthOf = .78, double heightOf = .86, double maxHeight = 900}) =>
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: const Color(0x00000000),
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, a, _) {
        final page = _Sheet(p: p, anim: a, body: body, widthOf: widthOf, heightOf: heightOf, maxHeight: maxHeight);
        return backdrop == null ? page : BackdropScope(backdrop: backdrop, child: page);
      },
    ));

class _Sheet extends StatefulWidget {
  final Palette p;
  final Animation<double> anim;
  final Widget Function(BuildContext, bool) body;
  final double widthOf, heightOf, maxHeight;           // a sheet no taller than its content wants (a Show 15 hung upright)
  const _Sheet({required this.p, required this.anim, required this.body, required this.widthOf, required this.heightOf, required this.maxHeight});
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  double drag = 0;
  void close() => Navigator.of(context).maybePop();
  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: widget.anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final size = MediaQuery.sizeOf(context), small = size.shortestSide < 400;
    final w = min(size.width * (small ? .9 : widget.widthOf), 900.0), h = min(size.height * (small ? .9 : widget.heightOf), widget.maxHeight);
    final b = BackdropScope.of(context);
    final radius = BorderRadius.circular(small ? 26 : 36);
    return AnimatedBuilder(animation: a, builder: (context, _) => Stack(children: [
      Positioned.fill(child: GestureDetector(onTap: close, child: ColoredBox(color: Color.fromRGBO(0, 0, 0, .5 * a.value * (1 - drag / 600).clamp(0, 1))))),
      Center(child: GestureDetector(
        onVerticalDragUpdate: (d) => setState(() => drag = max(0, drag + d.delta.dy)),
        onVerticalDragEnd: (d) { if (drag > 120 || (d.primaryVelocity ?? 0) > 700) { close(); } else { setState(() => drag = 0); } },
        // rises from a little lower and a little smaller, as Apple's sheets do
        child: Transform.translate(offset: Offset(0, drag + (1 - a.value) * 40), child: Transform.scale(scale: .94 + .06 * a.value,
          child: Opacity(opacity: a.value, child: SizedBox(width: w, height: h, child: DecoratedBox(
            decoration: ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: radius),
                shadows: const [BoxShadow(color: Color(0x59000000), blurRadius: 40, offset: Offset(0, 18))]),
            child: Frosted(blurred: b?.blurred, screen: b?.size ?? Size.zero, radius: radius, tint: widget.p.sheet,
                edgeTop: const Color(0x40ffffff), edgeBottom: const Color(0x0affffff),
                child: Material(type: MaterialType.transparency, child: widget.body(context, small))),
          ))))),
      )),
    ]));
  }
}
