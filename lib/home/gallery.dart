// Every card at every size it has (wall_view.dart sizesOf), at the Echo Show 5's cell (183 px, 14 px apart), drawn as
// the WallView draws them: how each looks at each size, side by side.  test/gallery_test.dart draws it with stand-in
// devices (a card that overflows its box fails the test; the picture is test/goldens/cards.png); the Echo Local panel's
// preview shows it with the Home Assistant's own devices (lib/preview.dart, info().gallery).
import 'package:flutter/material.dart';

import '../ha.dart';
import '../lovelace/lovelace.dart';
import 'sizes.dart';
import 'wall_view.dart';
import 'widgets.dart';

class CardGallery extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final bool h24;
  final double cell, gap;
  const CardGallery({super.key, required this.ha, required this.p, this.h24 = true, this.cell = 183, this.gap = 14});

  String? _first(bool Function(String id, EntityState s) f) => ha.states.entries.where((e) => f(e.key, e.value)).map((e) => e.key).firstOrNull;

  /// what to draw: (its name, the item) for each kind there is a device for
  List<(String, Item)> rows() {
    final light = _first((id, s) => id.startsWith('light.') && s.state == 'on') ?? _first((id, _) => id.startsWith('light.'));
    final single = _first((id, s) => id.startsWith('climate.') && s.numAttr('temperature') != null);
    final dual = _first((id, s) => id.startsWith('climate.') && s.numAttr('temperature') == null && s.numAttr('target_temp_low') != null);
    final player = _first((id, s) => id.startsWith('media_player.') && s.state == 'playing') ?? _first((id, _) => id.startsWith('media_player.'));
    final camera = _first((id, _) => id.startsWith('camera.'));
    final sensors = ha.states.keys.where((id) => id.startsWith('sensor.') && ha.states[id]!.attr['unit_of_measurement'] != null).take(3).toList();
    final listed = ha.states.keys.where((id) => id.startsWith('light.') || id.startsWith('lock.')).take(4).toList();
    final weather = _first((id, _) => id.startsWith('weather.'));
    LCard c(Map<String, dynamic> m) => LCard(m);
    return [
      ('Analog clock', const Item(Kind.analog)),
      ('Digital clock', const Item(Kind.digital)),
      ('Date & weather', const Item(Kind.date)),
      if (light != null) ('Tile', Item(Kind.tile, id: light)),
      if (single != null) ('Thermostat', Item(Kind.thermo, id: single)),
      if (dual != null) ('Thermostat, heat/cool', Item(Kind.thermo, id: dual)),
      if (player != null) ('Media', Item(Kind.media, id: player)),
      if (camera != null) ('Camera', Item(Kind.camera, id: camera)),
      ('Screen', const Item(Kind.screen, screen: 0, name: 'Music Assistant')),
      if (listed.isNotEmpty) ('Entities (dashboard)', Item(Kind.card, cardKey: 'card:entities', card: c({'type': 'entities', 'title': 'Doors', 'entities': listed}))),
      if (sensors.isNotEmpty) ('Glance (dashboard)', Item(Kind.card, cardKey: 'card:glance', card: c({'type': 'glance', 'entities': sensors}))),
      if (weather != null) ('Weather (dashboard)', Item(Kind.card, cardKey: 'card:weather', card: c({'type': 'weather-forecast', 'entity': weather}))),
      ('Card it cannot draw', Item(Kind.card, cardKey: 'card:custom', card: c({'type': 'custom:mushroom-chips-card'}))),
    ];
  }

  Widget card(Item it, CardSize s) {
    void none() {}
    return switch (it.kind) {
      Kind.analog => AnalogClockCard(p: p, cell: cell),
      Kind.digital => DigitalClockCard(p: p, cell: cell, h24: h24, size: s),
      Kind.date => DateWeatherCard(ha: ha, p: p, cell: cell, size: s),
      Kind.thermo => ThermostatCard(ha: ha, p: p, id: it.id!, cell: cell, onLong: none, holdOpens: false, size: s),
      Kind.playing || Kind.media => NowPlayingCard(ha: ha, p: p, id: it.id!, cell: cell, size: s, onLong: none, holdOpens: false),
      Kind.camera => CameraCard(ha: ha, p: p, id: it.id!, cell: cell, live: false),
      Kind.screen => ScreenTile(p: p, name: it.name, cell: cell, size: s, onTap: none),
      Kind.tile => AccessoryTile(ha: ha, p: p, id: it.id!, cell: cell, onLong: none, holdOpens: false, size: s),
      Kind.card => LayoutBuilder(builder: (_, b) => NativeCard(ha: ha, p: p, card: it.card!, box: b.biggest, size: s)),
      Kind.app => const SizedBox(),
    };
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (name, it) in rows()) ...[
            Padding(padding: const EdgeInsets.only(top: 6, bottom: 8), child: Text(name,
                style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w700))),
            Wrap(spacing: 24, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.end, children: [
              for (final s in sizesOf(it))
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: s.w * cell + (s.w - 1) * gap, height: s.h * cell + (s.h - 1) * gap, child: card(it, s)),
                  const SizedBox(height: 4),
                  Text('${s.label} · ${s.code}', style: TextStyle(color: p.dim, fontSize: 12)),
                ]),
            ]),
            const SizedBox(height: 14),
          ],
        ]),
      );
}
