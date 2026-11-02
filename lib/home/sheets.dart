// Apple's Home's categories, as sheets of glass: a tap on Home's Lights, Climate, Security or Speakers chip (or a room's
// lights) shows just those devices, each a tile that switches (a long press: its detail).  And the weather's forecast,
// a tap on the date's card (Home Assistant's weather.get_forecasts).
import 'dart:math';

import 'package:flutter/cupertino.dart';

import '../ha.dart';
import 'backdrop.dart';
import 'detail.dart';
import 'layout.dart';
import 'model.dart';
import 'widgets.dart';

enum Category { lights, climate, security, speakers }

const categoryIcon = {Category.lights: CupertinoIcons.lightbulb_fill, Category.climate: CupertinoIcons.thermometer,
    Category.security: CupertinoIcons.lock_fill, Category.speakers: CupertinoIcons.music_note_2};
const categoryName = {Category.lights: 'Lights', Category.climate: 'Climate', Category.security: 'Security', Category.speakers: 'Speakers'};

/// the devices of a category (of a room: area), shown ones only
List<String> inCategory(Ha ha, Layout lay, Category c, {String? area}) {
  bool here(String id) => area == null || (ha.areaOf(id) ?? '') == area;
  final out = ha.states.keys.where((id) {
    if (!shown(ha, lay, id) || !here(id)) return false;
    final d = domainOf(id), dc = ha.states[id]!.attr['device_class'];
    return switch (c) {
      Category.lights => d == 'light',
      Category.climate => d == 'climate' || d == 'fan' || d == 'humidifier',
      Category.security => d == 'lock' || (d == 'binary_sensor' && dc != 'motion' && dc != 'occupancy' && dc != 'presence') || (d == 'cover' && dc == 'garage'),
      Category.speakers => d == 'media_player',
    };
  }).toList()
    ..sort((a, b) => nameIn(ha, a, null).compareTo(nameIn(ha, b, null)));
  return out;
}

/// what a category's chip says: "3 on", "21°", "2 unlocked", "1 playing"; null: nothing of it in the house
String? categorySummary(Ha ha, Layout lay, Category c, {String? area}) {
  final ids = inCategory(ha, lay, c, area: area);
  if (ids.isEmpty) return null;
  int n(bool Function(EntityState) f) => ids.where((id) => f(ha.states[id]!)).length;
  switch (c) {
    case Category.lights:
      final on = n((s) => s.state == 'on');
      return on == 0 ? 'Off' : '$on on';
    case Category.climate:
      final t = ids.map((id) => ha.states[id]!.numAttr('current_temperature')).whereType<num>().firstOrNull;
      return t != null ? '$t°' : '${ids.length}';
    case Category.security:
      final open = n((s) => s.state == 'unlocked' || s.state == 'on' || s.state == 'open');
      return open == 0 ? 'Secure' : '$open open';
    case Category.speakers:
      final p = n((s) => s.state == 'playing');
      return p == 0 ? 'Idle' : '$p playing';
  }
}

Future<void> showCategory(BuildContext context, Ha ha, Layout lay, Palette p, Backdrop backdrop, Category c, {String? area}) =>
    showSheet(context, p, backdrop, (context, small) => ListenableBuilder(listenable: ha, builder: (context, _) {
      final ids = inCategory(ha, lay, c, area: area);
      final title = area == null ? categoryName[c]! : '${ha.areaName(area)} · ${categoryName[c]}';
      return Padding(padding: EdgeInsets.all(small ? 14 : 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(categoryIcon[c], color: p.sheetText, size: small ? 22 : 28),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: TextStyle(color: p.sheetText, fontSize: small ? 20 : 28, fontWeight: FontWeight.w700, letterSpacing: -.4))),
          if (c == Category.lights && ids.any((id) => ha.states[id]!.state == 'on'))
            _Pill(text: 'All off', p: p, onTap: () { for (final id in ids) { if (ha.states[id]!.state == 'on') ha.call('light', 'turn_off', id); } }),
          const SizedBox(width: 8),
          RoundButton(icon: CupertinoIcons.xmark, fg: p.sheetText, size: small ? 34 : 40, onTap: () => Navigator.of(context).maybePop()),
        ]),
        SizedBox(height: small ? 10 : 18),
        Expanded(child: LayoutBuilder(builder: (context, box) {
          final cell = small ? 110.0 : 150.0, gap = small ? 10.0 : 14.0;
          final cols = max(2, ((box.maxWidth + gap) / (cell + gap)).floor());
          final cw = (box.maxWidth - gap * (cols - 1)) / cols;
          // no repaint boundary per tile: a tile's glass is drawn from where it is on the screen (see home_view.dart)
          return GridView.builder(
            addRepaintBoundaries: false,
            physics: const BouncingScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: gap, crossAxisSpacing: gap,
                childAspectRatio: cw / cell),
            itemCount: ids.length,
            itemBuilder: (context, i) => AccessoryTile(ha: ha, p: p, id: ids[i], cell: cell, room: area == null ? ha.areaName(ha.areaOf(ids[i])) : null,
                onLong: () => showDetail(context, ha, p, ids[i], backdrop)),
          );
        })),
      ]));
    }));

class _Pill extends StatelessWidget {
  final String text;
  final Palette p;
  final VoidCallback onTap;
  const _Pill({required this.text, required this.p, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: const Color(0x24ffffff), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(color: p.sheetText, fontWeight: FontWeight.w600))));
}

/// the forecast: today big, the next days in a row of glass, from Home Assistant's weather.get_forecasts
Future<void> showWeather(BuildContext context, Ha ha, Palette p, Backdrop backdrop) {
  final id = ha.states.keys.where((x) => domainOf(x) == 'weather').firstOrNull;
  if (id == null) return Future.value();
  final forecast = ha.send({'type': 'call_service', 'domain': 'weather', 'service': 'get_forecasts', 'service_data': {'type': 'daily'},
      'target': {'entity_id': id}, 'return_response': true}).then((r) => ((r as Map)['response']?[id]?['forecast'] as List? ?? const []).cast<Map>());
  return showSheet(context, p, backdrop, widthOf: .72, heightOf: .78, maxHeight: 560, (context, small) => ListenableBuilder(listenable: ha, builder: (context, _) {
    final st = ha.states[id]!;
    final fg = p.sheetText;
    return Padding(padding: EdgeInsets.all(small ? 14 : 26), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(st.name, style: TextStyle(color: fg.withValues(alpha: .7), fontSize: small ? 13 : 16, fontWeight: FontWeight.w600)),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text('${st.numAttr('temperature')?.round() ?? '—'}°', style: TextStyle(color: fg, fontSize: small ? 54 : 84, fontWeight: FontWeight.w300, height: 1)),
            const SizedBox(width: 12),
            Icon(weatherIcon(st.state), color: fg, size: small ? 36 : 54),
          ]),
          Text(weatherText(st.state), style: TextStyle(color: fg, fontSize: small ? 16 : 20, fontWeight: FontWeight.w600)),
          Text([
            if (st.numAttr('humidity') != null) 'Humidity ${st.numAttr('humidity')!.round()}%',
            if (st.numAttr('wind_speed') != null) 'Wind ${st.numAttr('wind_speed')!.round()} ${st.attr['wind_speed_unit'] ?? ''}',
          ].join('  ·  '), style: TextStyle(color: fg.withValues(alpha: .65), fontSize: small ? 12 : 15)),
        ])),
        RoundButton(icon: CupertinoIcons.xmark, fg: fg, size: small ? 34 : 40, onTap: () => Navigator.of(context).maybePop()),
      ]),
      const Spacer(),
      FutureBuilder<List<Map>>(future: forecast, builder: (context, f) {
        final days = (f.data ?? const []).take(small ? 4 : 6).toList();
        if (days.isEmpty) return Text(f.hasError ? 'No forecast from Home Assistant' : 'The forecast…', style: TextStyle(color: fg.withValues(alpha: .6)));
        return Row(children: [
          for (final d in days) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Container(
            padding: EdgeInsets.symmetric(vertical: small ? 8 : 14),
            decoration: BoxDecoration(color: const Color(0x1affffff), borderRadius: BorderRadius.circular(small ? 14 : 18)),
            child: Column(children: [
              Text(_day(d['datetime'] as String?), style: TextStyle(color: fg.withValues(alpha: .7), fontSize: small ? 12 : 14, fontWeight: FontWeight.w600)),
              SizedBox(height: small ? 4 : 8),
              Icon(weatherIcon('${d['condition']}'), color: fg, size: small ? 22 : 30),
              SizedBox(height: small ? 4 : 8),
              Text('${(d['temperature'] as num?)?.round() ?? '—'}°', style: TextStyle(color: fg, fontSize: small ? 15 : 19, fontWeight: FontWeight.w600)),
              if (d['templow'] != null) Text('${(d['templow'] as num).round()}°', style: TextStyle(color: fg.withValues(alpha: .55), fontSize: small ? 12 : 15)),
            ]),
          ))),
        ]);
      }),
    ]));
  }));
}

String _day(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '';
  final now = DateTime.now();
  if (t.year == now.year && t.month == now.month && t.day == now.day) return 'Today';
  return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1];
}

IconData weatherIcon(String s) => const {
      'sunny': CupertinoIcons.sun_max_fill, 'clear-night': CupertinoIcons.moon_stars_fill, 'cloudy': CupertinoIcons.cloud_fill,
      'partlycloudy': CupertinoIcons.cloud_sun_fill, 'rainy': CupertinoIcons.cloud_rain_fill, 'pouring': CupertinoIcons.cloud_heavyrain_fill,
      'lightning': CupertinoIcons.cloud_bolt_fill, 'lightning-rainy': CupertinoIcons.cloud_bolt_rain_fill, 'snowy': CupertinoIcons.snow,
      'snowy-rainy': CupertinoIcons.cloud_sleet_fill, 'fog': CupertinoIcons.cloud_fog_fill, 'hail': CupertinoIcons.cloud_hail_fill,
      'windy': CupertinoIcons.wind, 'windy-variant': CupertinoIcons.wind, 'exceptional': CupertinoIcons.exclamationmark_triangle_fill,
    }[s] ?? CupertinoIcons.cloud_fill;

String weatherText(String s) => const {'partlycloudy': 'Partly cloudy', 'clear-night': 'Clear', 'lightning-rainy': 'Thunderstorms',
      'snowy-rainy': 'Sleet', 'windy-variant': 'Windy'}[s] ?? (s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1));
