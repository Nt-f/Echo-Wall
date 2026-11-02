// The HomeView's layout, the owner's: the wallpaper, Home's widgets in order, what is hidden, each room's order, the
// idle clock.  Kept in the app's own files (it is this Echo's), saved half a second after the last change.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum Wallpaper { amber, dusk, light }

class Layout extends ChangeNotifier {
  Wallpaper wallpaper = Wallpaper.amber;
  List<String>? favorites;                      // null: the HomeView picks (a thermostat, a camera, scenes, locks)
  Set<String> hidden = {};
  Map<String, List<String>> order = {};        // area id: its tiles first in this order
  int ambientSeconds = 120;                     // 0: never
  bool analogClock = true, digitalClock = true;
  File? _file;
  Timer? _save;

  static Future<Layout> load() async {
    final l = Layout();
    try {
      l._file = File('${(await getApplicationSupportDirectory()).path}/layout.json');
      if (await l._file!.exists()) l._read(jsonDecode(await l._file!.readAsString()) as Map<String, dynamic>);
    } catch (_) {}                              // a first start, or a file of another version: the defaults
    return l;
  }

  void _read(Map<String, dynamic> j) {
    wallpaper = Wallpaper.values.firstWhere((w) => w.name == j['wallpaper'], orElse: () => Wallpaper.amber);
    favorites = (j['favorites'] as List?)?.cast<String>();
    hidden = {...(j['hidden'] as List? ?? const []).cast<String>()};
    order = {for (final e in (j['order'] as Map<String, dynamic>? ?? const {}).entries) e.key: (e.value as List).cast<String>()};
    ambientSeconds = (j['ambient'] as num? ?? 120).toInt();
    analogClock = j['analog_clock'] != false;
    digitalClock = j['digital_clock'] != false;
  }

  Map<String, dynamic> toJson() => {'wallpaper': wallpaper.name, 'favorites': favorites, 'hidden': hidden.toList(), 'order': order,
      'ambient': ambientSeconds, 'analog_clock': analogClock, 'digital_clock': digitalClock};

  void changed() {
    notifyListeners();
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 500), () => _file?.writeAsString(jsonEncode(toJson())));
  }

  void reset() {
    favorites = null; hidden = {}; order = {};
    changed();
  }
}
