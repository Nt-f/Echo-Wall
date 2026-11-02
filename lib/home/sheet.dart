// A long press: the device's controls in a sheet.  Apple's tall pill slider for brightness, position, speed and volume
// (sent when let go), the buttons a kind of device has; it follows the device's state while open.
import 'dart:async';

import 'package:flutter/material.dart';

import '../ha.dart';
import 'model.dart';
import 'widgets.dart';

Future<void> showControls(BuildContext context, Ha ha, Palette p, String id) => showDialog(
      context: context,
      barrierColor: const Color(0x73000000),
      builder: (_) => ListenableBuilder(listenable: ha, builder: (context, _) => _Sheet(ha: ha, p: p, id: id)),
    );

class _Sheet extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final String id;
  const _Sheet({required this.ha, required this.p, required this.id});

  @override
  Widget build(BuildContext context) {
    final st = ha.states[id], d = domainOf(id), l = look(ha, id);
    final room = ha.areaName(ha.areaOf(id));
    if (st == null) return const SizedBox();
    final slider = switch (d) {
      'light' => st.state == 'on' ? ((st.numAttr('brightness') ?? 255) / 2.55).round() : 0,
      'cover' => st.numAttr('current_position')?.round(),
      'fan' => st.numAttr('percentage') != null ? (st.state == 'on' ? st.numAttr('percentage')!.round() : 0) : null,
      'media_player' => st.numAttr('volume_level') != null ? (st.numAttr('volume_level')! * 100).round() : null,
      _ => null,
    };
    void setSlider(int v) {
      switch (d) {
        case 'light': v > 0 ? ha.call('light', 'turn_on', id, {'brightness_pct': v}) : ha.call('light', 'turn_off', id);
        case 'cover': ha.call('cover', 'set_cover_position', id, {'position': v});
        case 'fan': v > 0 ? ha.call('fan', 'set_percentage', id, {'percentage': v}) : ha.call('fan', 'turn_off', id);
        case 'media_player': ha.call('media_player', 'volume_set', id, {'volume_level': v / 100});
      }
    }

    Widget btn(String label, VoidCallback f, {bool primary = false, IconData? icon}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: primary ? p.glassOn : const Color(0x24ffffff),
                foregroundColor: primary ? p.textOn : p.text, minimumSize: const Size(130, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: f,
            child: icon != null ? Icon(icon) : Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        );

    final buttons = <Widget>[
      if (['light', 'switch', 'fan', 'input_boolean', 'humidifier'].contains(d))
        btn(st.state == 'on' ? 'Turn off' : 'Turn on', () => ha.call(d, 'toggle', id), primary: st.state != 'on'),
      if (d == 'cover') ...[btn('Open', () => ha.call(d, 'open_cover', id)), btn('Stop', () => ha.call(d, 'stop_cover', id)), btn('Close', () => ha.call(d, 'close_cover', id))],
      if (d == 'lock') btn(st.state == 'locked' ? 'Unlock' : 'Lock', () => ha.call(d, st.state == 'locked' ? 'unlock' : 'lock', id), primary: true),
      if (d == 'media_player') Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(color: p.text, iconSize: 32, onPressed: () => ha.call(d, 'media_previous_track', id), icon: const Icon(Icons.skip_previous)),
        IconButton(color: p.text, iconSize: 44, onPressed: () => ha.call(d, 'media_play_pause', id), icon: Icon(st.state == 'playing' ? Icons.pause_circle : Icons.play_circle)),
        IconButton(color: p.text, iconSize: 32, onPressed: () => ha.call(d, 'media_next_track', id), icon: const Icon(Icons.skip_next)),
      ]),
      if (d == 'climate') _Climate(ha: ha, p: p, id: id),
      btn('Done', () => Navigator.of(context).pop()),
    ];

    return Dialog(
      backgroundColor: p.sheet,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(22, 18, 22, 18), child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nameIn(ha, id, room), style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w700)),
          Text([room, l.text].where((s) => s.isNotEmpty).join(' · '), style: TextStyle(color: p.dim, fontSize: 14)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (slider != null) ...[PillSlider(value: slider, color: l.on ? l.color : Colors.white, onSet: setSlider), const SizedBox(width: 22)],
            Flexible(child: Column(mainAxisSize: MainAxisSize.min, children: buttons)),
          ]),
        ])),
      ),
    );
  }
}

/// Apple's tall pill: drag anywhere on it, sent once let go
class PillSlider extends StatefulWidget {
  final int value;
  final Color color;
  final void Function(int) onSet;
  const PillSlider({super.key, required this.value, required this.color, required this.onSet});
  @override
  State<PillSlider> createState() => _PillSliderState();
}

class _PillSliderState extends State<PillSlider> {
  int? dragging;
  static const h = 230.0;
  void _at(Offset o) => setState(() => dragging = ((h - o.dy) / h * 100).round().clamp(0, 100));
  @override
  Widget build(BuildContext context) {
    final v = dragging ?? widget.value;
    return GestureDetector(
      onVerticalDragStart: (e) => _at(e.localPosition),
      onVerticalDragUpdate: (e) => _at(e.localPosition),
      onVerticalDragEnd: (_) { if (dragging != null) widget.onSet(dragging!); Timer(const Duration(seconds: 2), () { if (mounted) setState(() => dragging = null); }); },
      onTapDown: (e) => _at(e.localPosition),
      onTapUp: (_) { if (dragging != null) widget.onSet(dragging!); },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Container(width: 100, height: h, color: const Color(0x2effffff), child: Stack(children: [
          Align(alignment: Alignment.bottomCenter, child: AnimatedContainer(duration: const Duration(milliseconds: 80),
              height: h * v / 100, color: widget.color)),
          Positioned(top: 12, left: 0, right: 0, child: Text('$v%', textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 4)]))),
        ])),
      ),
    );
  }
}

class _Climate extends StatefulWidget {
  final Ha ha;
  final Palette p;
  final String id;
  const _Climate({required this.ha, required this.p, required this.id});
  @override
  State<_Climate> createState() => _ClimateState();
}

class _ClimateState extends State<_Climate> {
  double? want;
  Timer? _t;
  @override
  Widget build(BuildContext context) {
    final st = widget.ha.states[widget.id]!, p = widget.p;
    final step = (st.numAttr('target_temp_step') ?? (st.attr['temperature_unit'] == '°F' ? 1 : .5)).toDouble();
    final t = want ?? st.numAttr('temperature')?.toDouble();
    void nudge(int d) {
      if (t == null) return;
      setState(() => want = ((t + d * step) / step).round() * step);
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 700), () => widget.ha.call('climate', 'set_temperature', widget.id, {'temperature': want}));
    }
    final modes = (st.attr['hvac_modes'] as List? ?? const []).cast<String>().take(4);
    Widget round(String s, int d) => IconButton.filledTonal(onPressed: () => nudge(d), iconSize: 30,
        style: IconButton.styleFrom(backgroundColor: const Color(0x24ffffff), foregroundColor: p.text),
        icon: Icon(d < 0 ? Icons.remove : Icons.add));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (t != null) Row(mainAxisSize: MainAxisSize.min, children: [
        round('-', -1),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('${t % 1 == 0 ? t.toInt() : t}°', style: TextStyle(color: p.text, fontSize: 50, fontWeight: FontWeight.w300))),
        round('+', 1),
      ]),
      Wrap(spacing: 6, children: [
        for (final m in modes)
          ChoiceChip(label: Text(m), selected: st.state == m, onSelected: (_) => widget.ha.call('climate', 'set_hvac_mode', widget.id, {'hvac_mode': m})),
      ]),
    ]);
  }
}
