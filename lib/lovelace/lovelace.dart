// A prototype: Home Assistant's own dashboards (Lovelace) drawn natively, with the WallView's glass cards, instead of
// in a WebView.  A view of type "sections" is Lovelace's grid: sections side by side, each a 12-column grid of cards
// with rows of 56 px, every card's size its `grid_options` (columns of 12, rows).  What is drawn natively: tile,
// thermostat, media-control, entities, glance, button, picture-entity / picture-glance (a camera), weather-forecast,
// heading; any other card (a custom: one from HACS, a markdown, a history graph) is a tile that opens that view in
// Home Assistant's own UI.
//
// Two ways of laying a view out on the Echo Show's 960 x 470:
//   - grid: the WallView's own square cells (4 x 2 on the Show 5), a page per section (its heading the page's name),
//     each card at the nearest of the WallView's sizes
//   - sections: Lovelace's own layout, sections as columns (three on the screen, swiped sideways), each card in its
//     12-column box, drawn at whatever shape that box has
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ha.dart';
import '../home/model.dart';
import '../home/sheets.dart' show weatherIcon, weatherText;
import '../home/sizes.dart';
import '../home/widgets.dart';

/// one card of a dashboard, as Lovelace's config has it
class LCard {
  final Map<String, dynamic> c;
  LCard(this.c);
  String get type => '${c['type'] ?? ''}';
  String? get entity => c['entity'] as String?;
  List<String> get entities => [
        for (final e in (c['entities'] as List? ?? const []))
          if (e is String) e else if (e is Map && e['entity'] is String) e['entity'] as String
      ];
  /// the name the card gives its entity (Lovelace's `name:`), else none: the entity's own
  String? get name => c['name'] is String && (c['name'] as String).trim().isNotEmpty ? (c['name'] as String).trim() : null;
  /// the names an entities or glance card gives its rows ({entity, name})
  Map<String, String> get names => {
        for (final e in (c['entities'] as List? ?? const []))
          if (e is Map && e['entity'] is String && e['name'] is String) e['entity'] as String: e['name'] as String
      };
  bool get native => const {'tile', 'thermostat', 'media-control', 'entities', 'glance', 'button', 'picture-entity', 'picture-glance',
        'weather-forecast', 'heading'}.contains(type);

  /// Lovelace's own size of it: columns of 12, rows of 56 px (its defaults where the config says none)
  (int, int) get grid {
    final g = c['grid_options'] as Map? ?? const {};
    final (dc, dr) = switch (type) {
      'tile' => (6, 1),
      'button' => (3, 2),
      'thermostat' => (12, 6),
      'media-control' => (12, 3),
      'entities' => (12, 1 + entities.length),
      'glance' => (12, 2),
      'picture-entity' || 'picture-glance' => (12, 4),
      'weather-forecast' => (12, 4),
      'heading' => (12, 1),
      _ => (12, 2),
    };
    int n(Object? v, int d) => v is num ? v.toInt() : v == 'full' ? 12 : d;
    return (n(g['columns'], dc).clamp(1, 12), n(g['rows'], dr).clamp(1, 12));
  }

  /// the nearest of the WallView's sizes for the grid layout
  CardSize get cardSize {
    final (cols, rows) = grid;
    if (rows >= 6 && cols >= 12) return type == 'thermostat' ? CardSize.l : CardSize.xl;
    if (rows >= 3) return cols >= 12 ? CardSize.l : CardSize.l;
    if (cols >= 12 || (rows >= 2 && cols > 6)) return CardSize.m;
    return CardSize.s;
  }
}

class LSection {
  final String title;
  final List<LCard> cards;
  LSection(this.title, this.cards);
}

class LView {
  final String title;
  final String? path;                           // its own url part (/<dashboard>/<path>), else its index
  final List<LSection> sections;
  LView(this.title, this.sections, {this.path});

  /// a view of the dashboard's config: sections (a heading card names its section); a masonry view's cards as one
  static LView parse(Map<String, dynamic> v) {
    final out = <LSection>[];
    for (final s in (v['sections'] as List? ?? [{'cards': v['cards'] ?? const []}])) {
      final cards = <LCard>[];
      void add(Object? c) {
        if (c is! Map) return;
        final t = '${c['type'] ?? ''}';
        if (t == 'vertical-stack' || t == 'horizontal-stack' || t == 'grid') {
          for (final x in (c['cards'] as List? ?? const [])) { add(x); }     // a stack's cards as cards of their own
        } else {
          cards.add(LCard(Map<String, dynamic>.from(c)));
        }
      }
      for (final c in ((s as Map)['cards'] as List? ?? const [])) { add(c); }
      final head = cards.where((c) => c.type == 'heading').firstOrNull;
      out.add(LSection('${head?.c['heading'] ?? s['title'] ?? ''}', cards.where((c) => c != head).toList()));
    }
    return LView('${v['title'] ?? ''}', out, path: v['path'] as String?);
  }
}

/// a card drawn natively in a box of the given shape: the WallView's widget whose layout suits that shape, its fonts
/// from the box's height
class NativeCard extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final LCard card;
  final Size box;
  final CardSize? size;                         // the grid layout's: the WallView's own; null: from the box
  final VoidCallback? onOpen;                   // a card it cannot draw: its view in Home Assistant's own UI
  const NativeCard({super.key, required this.ha, required this.p, required this.card, required this.box, this.size, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final aspect = box.width / box.height;
    final sz = size ?? (box.height < 90 || aspect > 1.7 ? CardSize.m : box.height > 300 ? CardSize.l : CardSize.s);
    final cell = size != null ? box.height / size!.h : (sz == CardSize.l ? box.height / 2 : box.height);
    final id = card.entity ?? (card.entities.isEmpty ? '' : card.entities.first);
    void none() {}
    switch (card.type) {
      case 'tile':
      case 'button':
        if (!ha.states.containsKey(id)) return _missing(id, cell);
        return AccessoryTile(ha: ha, p: p, id: id, cell: cell, onLong: none, holdOpens: false, size: sz == CardSize.xl ? CardSize.l : sz, label: card.name);
      case 'thermostat':
        return ThermostatCard(ha: ha, p: p, id: id, cell: cell, onLong: none, holdOpens: false, size: sz == CardSize.xl ? CardSize.l : sz, label: card.name);
      case 'media-control':
        return NowPlayingCard(ha: ha, p: p, id: id, cell: cell, size: sz, onLong: none, holdOpens: false);
      case 'picture-entity':
      case 'picture-glance':
        return _Picture(ha: ha, p: p, id: card.entity ?? '', title: card.c['title'] as String? ?? card.name, cell: cell);
      case 'entities':
        return _Entities(ha: ha, p: p, ids: card.entities, names: card.names, title: card.c['title'] as String?, cell: cell, box: box);
      case 'glance':
        return _Glance(ha: ha, p: p, ids: card.entities, names: card.names, cell: cell, box: box);
      case 'weather-forecast':
        return _Weather(ha: ha, p: p, id: id, cell: cell, box: box);
      default:
        // a card of HACS's (Mushroom, button-card, mini-graph-card...) is about an entity nearly always: that entity as
        // the WallView draws its kind, with the card's name; only one about none (a chips row, a markdown) stays a tile
        // that opens its view in Home Assistant's own UI
        if (card.type.startsWith('custom:') && ha.states.containsKey(id)) {
          final s = sz == CardSize.xl ? CardSize.l : sz;
          return switch (domainOf(id)) {
            'climate' => ThermostatCard(ha: ha, p: p, id: id, cell: cell, onLong: none, holdOpens: false, size: s, label: card.name),
            'media_player' => NowPlayingCard(ha: ha, p: p, id: id, cell: cell, size: sz, onLong: none, holdOpens: false),
            'camera' => _Picture(ha: ha, p: p, id: id, title: card.name, cell: cell),
            'weather' => _Weather(ha: ha, p: p, id: id, cell: cell, box: box),
            _ => card.entities.length > 1
                ? _Entities(ha: ha, p: p, ids: card.entities, names: card.names, title: card.name ?? card.c['title'] as String?, cell: cell, box: box)
                : AccessoryTile(ha: ha, p: p, id: id, cell: cell, onLong: none, holdOpens: false, size: s, label: card.name),
          };
        }
        return GestureDetector(onTap: onOpen, child: _Fallback(p: p, card: card, cell: cell, open: onOpen != null));
    }
  }

  Widget _missing(String id, double cell) => Glass(p: p, cell: cell, child: Center(child: Text(id, style: TextStyle(color: p.dim, fontSize: 11))));
}

/// a camera or picture: the picture full, its name over it
class _Picture extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final String id;
  final String? title;
  final double cell;
  const _Picture({required this.ha, required this.p, required this.id, required this.title, required this.cell});
  @override
  Widget build(BuildContext context) {
    final u = cell / 100;
    final pic = ha.states[id]?.attr['entity_picture'] as String?;
    return ClipRSuperellipse(borderRadius: BorderRadius.circular(min(30, cell * .17)), child: Stack(fit: StackFit.expand, children: [
      if (pic != null && pic.startsWith('asset:')) Image.asset(pic.substring(6), fit: BoxFit.cover)
      else if (pic != null) Image.network(ha.image(pic).toString(), headers: ha.authHeader, fit: BoxFit.cover, errorBuilder: (_, _, _) => Glass(p: p, cell: cell, child: const SizedBox()))
      else Glass(p: p, cell: cell, child: Center(child: Icon(CupertinoIcons.video_camera, color: p.dim, size: 22 * u))),
      const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x8c000000)], stops: [.55, 1]))),
      Positioned(left: 10 * u, bottom: 8 * u, right: 10 * u, child: Text(title ?? nameIn(ha, id, null), maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: max(11, 9 * u), shadows: const [Shadow(blurRadius: 3)]))),
    ]));
  }
}

/// Lovelace's entities card on glass: a row per entity (icon, name, state; a switch where it toggles)
class _Entities extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final List<String> ids;
  final Map<String, String> names;              // the card's own names of its rows
  final String? title;
  final double cell;
  final Size box;
  const _Entities({required this.ha, required this.p, required this.ids, this.names = const {}, required this.title, required this.cell, required this.box});
  @override
  Widget build(BuildContext context) {
    final rowH = min(44.0, (box.height - 16 - (title != null ? 26 : 0)) / max(1, ids.length));
    return Glass(p: p, cell: cell, padding: const EdgeInsets.fromLTRB(14, 10, 10, 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null) Padding(padding: const EdgeInsets.only(bottom: 4),
          child: Text(title!, style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 15))),
      for (final id in ids)
        SizedBox(height: rowH, child: Row(children: [
          Icon(look(ha, id).icon, size: min(22, rowH * .55), color: look(ha, id).on ? look(ha, id).color : p.dim),
          const SizedBox(width: 10),
          Expanded(child: Text(names[id] ?? nameIn(ha, id, null), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.text, fontSize: min(14.5, rowH * .36), fontWeight: FontWeight.w500))),
          if (const {'light', 'switch', 'fan', 'input_boolean'}.contains(domainOf(id)))
            Transform.scale(scale: min(.8, rowH / 50), child: CupertinoSwitch(value: look(ha, id).on, onChanged: (_) {}, activeTrackColor: const Color(0xff30d158)))
          else
            Text(_state(ha, id), style: TextStyle(color: p.dim, fontSize: min(13.5, rowH * .34))),
        ])),
    ]));
  }
}

String _state(Ha ha, String id) {
  final st = ha.states[id];
  if (st == null) return '—';
  final unit = st.attr['unit_of_measurement'];
  return unit != null ? '${st.state} $unit' : look(ha, id).text;
}

/// Lovelace's glance card: the entities side by side, an icon and a state each
class _Glance extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final List<String> ids;
  final Map<String, String> names;
  final double cell;
  final Size box;
  const _Glance({required this.ha, required this.p, required this.ids, this.names = const {}, required this.cell, required this.box});
  @override
  Widget build(BuildContext context) {
    final s = min(box.height / 4.2, 30.0);
    return Glass(p: p, cell: cell, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Row(children: [
      for (final id in ids)
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(names[id] ?? nameIn(ha, id, null), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.dim, fontSize: s * .42)),
          SizedBox(height: s * .15),
          Icon(look(ha, id).icon, size: s, color: look(ha, id).on ? look(ha, id).color : p.text),
          SizedBox(height: s * .15),
          Text(_state(ha, id), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: s * .45, fontWeight: FontWeight.w600)),
        ])),
    ]));
  }
}

/// the weather and its next days
class _Weather extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final String id;
  final double cell;
  final Size box;
  const _Weather({required this.ha, required this.p, required this.id, required this.cell, required this.box});
  @override
  Widget build(BuildContext context) {
    final st = ha.states[id];
    final u = min(box.height, box.width / 2) / 100;
    final days = (st?.attr['forecast'] as List? ?? const []).take(5).toList();
    return Glass(p: p, cell: cell, padding: EdgeInsets.all(10 * u), child: Column(children: [
      Row(children: [
        Icon(weatherIcon(st?.state ?? ''), size: 26 * u, color: p.text),
        SizedBox(width: 8 * u),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${st?.numAttr('temperature')?.round() ?? '—'}°', style: TextStyle(color: p.text, fontSize: 22 * u, fontWeight: FontWeight.w300, height: 1)),
          Text(weatherText(st?.state ?? ''), style: TextStyle(color: p.dim, fontSize: max(10, 8 * u))),
        ])),
        Text(nameIn(ha, id, null), style: TextStyle(color: p.dim, fontSize: max(10, 7.5 * u))),
      ]),
      const Spacer(),
      if (days.isNotEmpty) Row(children: [
        for (final d in days.cast<Map>())
          Expanded(child: Column(children: [
            Text('${d['day'] ?? ''}', style: TextStyle(color: p.dim, fontSize: max(10, 7 * u))),
            Icon(weatherIcon('${d['condition'] ?? ''}'), size: 14 * u, color: p.text),
            Text('${d['temperature'] ?? ''}°', style: TextStyle(color: p.text, fontSize: max(10, 8 * u), fontWeight: FontWeight.w600)),
          ])),
      ]),
    ]));
  }
}

/// a card with no native drawing: what it is, and a way to it in Home Assistant's own UI
class _Fallback extends StatelessWidget {
  final Palette p;
  final LCard card;
  final double cell;
  final bool open;
  const _Fallback({required this.p, required this.card, required this.cell, this.open = true});
  @override
  Widget build(BuildContext context) {
    final u = min(cell, 140) / 100;
    final name = card.type.startsWith('custom:') ? card.type.substring(7).replaceAll('-', ' ') : card.type.replaceAll('-', ' ');
    return Glass(p: p, cell: cell, padding: EdgeInsets.all(10 * u), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(CupertinoIcons.square_grid_2x2, size: 20 * u, color: p.dim),
      const Spacer(),
      Text(name[0].toUpperCase() + name.substring(1), maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: max(12, 9 * u))),
      if (open) Row(children: [
        Text('Open in dashboard', style: TextStyle(color: p.dim, fontSize: max(11, 7.6 * u))),
        Icon(CupertinoIcons.chevron_right, size: max(11, 7.6 * u), color: p.dim),
      ]) else Text('Not drawn here', style: TextStyle(color: p.dim, fontSize: max(11, 7.6 * u))),
    ]));
  }
}
