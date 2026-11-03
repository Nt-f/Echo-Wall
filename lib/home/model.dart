// What the WallView shows of Home Assistant and how each thing looks: on or off, its icon and colour, the line under
// its name, a level bar; what a tap does.  Rooms are Home Assistant's areas.
import 'package:flutter/material.dart';

import '../ha.dart';
import 'layout.dart';

const tileDomains = ['light', 'switch', 'fan', 'cover', 'climate', 'media_player', 'lock', 'input_boolean', 'humidifier', 'vacuum', 'binary_sensor'];
const sensorClasses = ['door', 'window', 'garage_door', 'opening', 'motion', 'occupancy', 'presence'];

class Look {
  final bool on, unavailable;
  final IconData icon;
  final Color color;
  final String text;
  final double? level;                          // 0..1 for the bar (brightness, position)
  const Look(this.on, this.icon, this.color, this.text, {this.level, this.unavailable = false});
}

const amber = Color(0xfff29a12), green = Color(0xff2fb350), blue = Color(0xff3d8bf2), orange = Color(0xffef6c2a),
    red = Color(0xffe5484d), purple = Color(0xff8b6cf0);

/// shown at all: Home Assistant's own hiding first, then the layout's
bool shown(Ha ha, Layout l, String id) {
  final st = ha.states[id];
  if (st == null || ha.hiddenByHa.contains(id) || l.hidden.contains(id)) return false;
  final d = domainOf(id);
  if (d == 'binary_sensor') return sensorClasses.contains(st.attr['device_class']);
  return tileDomains.contains(d) || d == 'scene' || d == 'script';
}

/// "Kitchen Ceiling" in Kitchen is "Ceiling", as Apple's Home shows it
String nameIn(Ha ha, String id, String? room) {
  var n = ha.states[id]?.name ?? id;
  if (n.isEmpty) n = id;
  if (room != null && room.isNotEmpty && n.toLowerCase().startsWith('${room.toLowerCase()} ') && n.length > room.length + 2) {
    n = n.substring(room.length + 1);
  }
  return n;
}

Look look(Ha ha, String id) {
  final st = ha.states[id];
  if (st == null) return const Look(false, Icons.help_outline, Colors.grey, '—', unavailable: true);
  final s = st.state, a = st.attr, d = domainOf(id);
  final unav = s == 'unavailable' || s == 'unknown';
  String t(String on, String off) => unav ? (s == 'unknown' ? '—' : 'No response') : (s == 'on' ? on : off);
  switch (d) {
    case 'light':
      final on = s == 'on';
      final b = st.numAttr('brightness');
      final pct = b == null ? null : (b / 2.55).round();
      var c = amber;
      final rgb = a['rgb_color'];
      if (on && rgb is List && rgb.length == 3 && '${a['color_mode']}'.contains(RegExp('rgb|hs|xy'))) {
        c = Color.fromARGB(255, (rgb[0] as num).toInt(), (rgb[1] as num).toInt(), (rgb[2] as num).toInt());
      }
      return Look(on, on ? Icons.lightbulb : Icons.lightbulb_outline, c, t(pct != null ? '$pct%' : 'On', 'Off'),
          level: on && pct != null ? pct / 100 : null, unavailable: unav);
    case 'switch':
    case 'input_boolean':
      return Look(s == 'on', a['device_class'] == 'outlet' ? Icons.power : Icons.toggle_on, green, t('On', 'Off'), unavailable: unav);
    case 'fan':
      final p = st.numAttr('percentage');
      return Look(s == 'on', Icons.mode_fan_off_outlined, blue, t(p != null ? '${p.round()}%' : 'On', 'Off'), unavailable: unav);
    case 'humidifier':
      return Look(s == 'on', Icons.water_drop, blue, t('On', 'Off'), unavailable: unav);
    case 'cover':
      final pos = st.numAttr('current_position');
      final open = s == 'open' || s == 'opening';
      final text = unav ? 'No response' : {'open': pos != null && pos < 100 ? '${pos.round()}% open' : 'Open', 'closed': 'Closed',
          'opening': 'Opening…', 'closing': 'Closing…'}[s] ?? s;
      return Look(open, open ? Icons.blinds : Icons.blinds_closed, blue, text, level: open && pos != null ? pos / 100 : null, unavailable: unav);
    case 'climate':
      final cur = st.numAttr('current_temperature'), tgt = st.numAttr('temperature');
      return Look(s != 'off' && !unav, Icons.thermostat, s == 'cool' ? blue : orange,
          unav ? 'No response' : '${cur != null ? '$cur°' : ''}${s == 'off' ? ' · Off' : tgt != null ? ' → $tgt°' : ' · $s'}', unavailable: unav);
    case 'media_player':
      final title = a['media_title'], artist = a['media_artist'];
      final text = unav ? 'No response' : (s == 'playing' || s == 'paused') ? '${title ?? s}${artist != null ? ' · $artist' : ''}' : s == 'off' ? 'Off' : 'Idle';
      return Look(s == 'playing', Icons.music_note, red, text, unavailable: unav);
    case 'lock':
      final text = unav ? 'No response' : {'locked': 'Locked', 'unlocked': 'Unlocked', 'locking': 'Locking…', 'unlocking': 'Unlocking…',
          'jammed': 'Jammed', 'open': 'Open'}[s] ?? s;
      return Look(s != 'locked' && !unav, s == 'locked' ? Icons.lock : Icons.lock_open, orange, text, unavailable: unav);
    case 'vacuum':
      return Look(s == 'cleaning', Icons.cleaning_services, green, unav ? 'No response' : s, unavailable: unav);
    case 'binary_sensor':
      final dc = a['device_class'];
      final motion = dc == 'motion' || dc == 'occupancy' || dc == 'presence';
      return Look(s == 'on', motion ? Icons.directions_walk : dc == 'window' ? Icons.window : Icons.door_front_door, orange,
          unav ? 'No response' : motion ? (s == 'on' ? 'Motion' : 'Clear') : (s == 'on' ? 'Open' : 'Closed'), unavailable: unav);
    case 'scene':
      return const Look(false, Icons.auto_awesome, purple, 'Scene');
    case 'script':
      return const Look(false, Icons.auto_awesome, purple, 'Shortcut');
  }
  return Look(s == 'on', Icons.circle_outlined, amber, s, unavailable: unav);
}

/// a tap: what toggles toggles; what should not open by a stray touch (a lock) or has more to it opens its controls
bool tap(Ha ha, String id) {
  final st = ha.states[id];
  if (st == null || st.state == 'unavailable') return true;
  final d = domainOf(id);
  switch (d) {
    case 'light': case 'switch': case 'fan': case 'input_boolean': case 'humidifier':
      ha.call(d, 'toggle', id); return true;
    case 'cover':
      ha.call(d, st.state == 'open' || st.state == 'opening' ? 'close_cover' : 'open_cover', id); return true;
    case 'media_player':
      ha.playPause(id); return true;
    case 'scene': case 'script':
      ha.call(d, 'turn_on', id); return true;
    case 'vacuum':
      ha.call(d, st.state == 'cleaning' ? 'return_to_base' : 'start', id); return true;
  }
  return false;                                 // the controls instead
}

/// the room's temperature and humidity, as Apple's Home writes them under a room's name
String roomSummary(Ha ha, String area) {
  String? pick(String dc) {
    for (final e in ha.states.entries) {
      if (domainOf(e.key) != 'sensor' || ha.hiddenByHa.contains(e.key) || ha.areaOf(e.key) != area) continue;
      if (e.value.attr['device_class'] == dc && double.tryParse(e.value.state) != null) return e.key;
    }
    return null;
  }
  final out = <String>[];
  final t = pick('temperature'), h = pick('humidity');
  if (t != null) out.add('${(double.parse(ha.states[t]!.state) * 10).round() / 10}${ha.states[t]!.attr['unit_of_measurement'] ?? '°'}');
  if (h != null) out.add('${double.parse(ha.states[h]!.state).round()}%');
  return out.join(' · ');
}
