// The WallView's layout, the owner's: the wallpaper, Home's widgets in order, what is hidden, each room's order, the
// idle clock; pages of one's own, cards put on a room's page from elsewhere, each card's size, the pages' order.  Kept in the app's own files (it is this Echo's), saved half a second after the last change, and in
// Home Assistant beside it (layout_sync.dart): the Echo Local integration's panel edits, exports and imports it.
import 'dart:async';
import 'dart:convert';
import '../io/io.dart';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum Wallpaper { photo, amber, dusk, light }

/// a page of the owner's own (made in the edit mode's "+ Page"): its cards are all in Layout.cards['page:(id)']
class CustomPage {
  final String id;
  String name;
  CustomPage(this.id, this.name);
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// a page group's key, as places, cards, sizes and the pages' order name it: Home, a room, a page of one's own
const homeGroup = 'home';
String areaGroup(String area) => 'area:$area';
String pageGroup(String id) => 'page:$id';

class Layout extends ChangeNotifier {
  Wallpaper wallpaper = Wallpaper.photo;
  List<String>? favorites;                      // null: the WallView picks (a thermostat, a camera, scenes, locks)
  Set<String> hidden = {};
  Map<String, List<String>> order = {};        // area id: its tiles first in this order
  List<String> homeOrder = [];                  // Home's widgets by key (clocks, date, screens, devices), as moved
  /// where each widget was put, per page group (`home`, `area:<area id>`): key -> [page, column, row]
  Map<String, Map<String, List<int>>> place = {};
  String? player;                               // the media card's: the last player that played (it stays on it)
  int ambientSeconds = 120;                     // 0: never
  bool analogClock = true, digitalClock = true, dateCard = true, nowPlaying = true;   // Home's own widgets, each removable
  Set<String> hiddenScreens = {};               // the app's screens (by name) whose tile was taken off Home
  List<CustomPage> customPages = [];            // the owner's pages, in the order made (pageOrder may move them)
  /// cards of a page group beyond what it has by itself: a custom page's cards, a room's from elsewhere (another
  /// room's light, a clock); keys as Item.key has them (an entity id, analog, digital, date, playing, app:(package))
  Map<String, List<String>> cards = {};
  /// a room's own entities taken off that room's page only (still shown elsewhere; "Hidden" is everywhere)
  Map<String, List<String>> exclude = {};
  /// each card's size per page group: "1x1", "2x1", "2x2", "4x2" (wall_view.dart CardSize); none: the card's own
  Map<String, Map<String, String>> sizes = {};
  /// the page groups in the order swiped through, Home first whatever this says; groups not named follow in their
  /// own order (custom pages, then rooms)
  List<String> pageOrder = [];
  /// page groups taken off (a room's, a dashboard section's: `area:<id>`, `ll:<view>/<section>`); a page of one's own is
  /// deleted instead.  Shown again from Echo Local's panel (its Pages list)
  Set<String> hiddenPages = {};
  /// a Home Assistant dashboard drawn natively after Home (lib/lovelace/): its url path ("lovelace" for Overview);
  /// empty: a page per room, as before
  String dashboard = '';
  File? _file;
  Timer? _save;
  /// after each save to the file (layout_sync.dart sends it on to Home Assistant)
  void Function()? onSaved;

  static Future<Layout> load() async {
    final l = Layout();
    try {
      l._file = File('${(await getApplicationSupportDirectory()).path}/layout.json');
      if (await l._file!.exists()) l._read(jsonDecode(await l._file!.readAsString()) as Map<String, dynamic>);
    } catch (_) {}                              // a first start, or a file of another version: the defaults
    return l;
  }

  /// a layout from elsewhere (Home Assistant's, the panel's save): taken, drawn, kept in the file
  void apply(Map<String, dynamic> j) {
    _read(j);
    notifyListeners();
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 500), () => _file?.writeAsString(jsonEncode(toJson())));
  }

  /// keys this version of the app does not know (a newer app's, the integration's: the Immich settings), kept as they
  /// came: the app's own saves would otherwise take them out of Home Assistant again
  Map<String, dynamic> extra = {};

  /// the photo settings the Echo-Wall integration's panel sets (immich_url, immich_key, immich_album, photos_minutes),
  /// as the app's settings keys (photos.dart): what the layout has, over what hassmic's screen app settings had
  Map<String, String> settingsOver(Map<String, String> base) => {
        ...base,
        for (final (k, s) in const [('immich_url', 'immich.url'), ('immich_key', 'immich.key'), ('immich_album', 'immich.album'),
            ('photos_minutes', 'photos.minutes')])
          if (extra[k] != null && '${extra[k]}'.isNotEmpty) s: '${extra[k]}',
      };

  void _read(Map<String, dynamic> j) {
    wallpaper = Wallpaper.values.firstWhere((w) => w.name == j['wallpaper'], orElse: () => Wallpaper.photo);
    favorites = (j['favorites'] as List?)?.cast<String>();
    hidden = {...(j['hidden'] as List? ?? const []).cast<String>()};
    order = {for (final e in (j['order'] as Map<String, dynamic>? ?? const {}).entries) e.key: (e.value as List).cast<String>()};
    homeOrder = (j['home_order'] as List? ?? const []).cast<String>();
    place = {
      for (final g in (j['place'] as Map<String, dynamic>? ?? const {}).entries)
        g.key: {for (final e in (g.value as Map<String, dynamic>).entries) e.key: (e.value as List).cast<num>().map((n) => n.toInt()).toList()}
    };
    player = j['player'] as String?;
    ambientSeconds = (j['ambient'] as num? ?? 120).toInt();
    analogClock = j['analog_clock'] != false;
    digitalClock = j['digital_clock'] != false;
    dateCard = j['date_card'] != false;
    nowPlaying = j['now_playing'] != false;
    hiddenScreens = {...(j['hidden_screens'] as List? ?? const []).cast<String>()};
    customPages = [
      for (final p in (j['custom_pages'] as List? ?? const []))
        if (p is Map && p['id'] is String) CustomPage(p['id'] as String, '${p['name'] ?? 'Page'}')
    ];
    Map<String, List<String>> lists(Object? m) => {
          for (final e in (m as Map<String, dynamic>? ?? const {}).entries) if (e.value is List) e.key: (e.value as List).whereType<String>().toList()
        };
    cards = lists(j['cards']);
    exclude = lists(j['exclude']);
    sizes = {
      for (final g in (j['sizes'] as Map<String, dynamic>? ?? const {}).entries)
        if (g.value is Map) g.key: {for (final e in (g.value as Map<String, dynamic>).entries) if (e.value is String) e.key: e.value as String}
    };
    pageOrder = (j['page_order'] as List? ?? const []).whereType<String>().toList();
    hiddenPages = {...(j['hidden_pages'] as List? ?? const []).whereType<String>()};
    dashboard = j['dashboard'] is String ? j['dashboard'] as String : '';
    extra = {for (final e in j.entries) if (!_known.contains(e.key)) e.key: e.value};
  }

  static const _known = {'wallpaper', 'favorites', 'hidden', 'order', 'home_order', 'place', 'player', 'ambient', 'analog_clock',
    'digital_clock', 'date_card', 'now_playing', 'hidden_screens', 'custom_pages', 'cards', 'exclude', 'sizes', 'page_order',
    'hidden_pages', 'dashboard'};

  Map<String, dynamic> toJson() => {...extra, 'wallpaper': wallpaper.name, 'favorites': favorites, 'hidden': hidden.toList(), 'order': order, 'home_order': homeOrder, 'place': place, 'player': player,
      'ambient': ambientSeconds, 'analog_clock': analogClock, 'digital_clock': digitalClock,
      'date_card': dateCard, 'now_playing': nowPlaying, 'hidden_screens': hiddenScreens.toList(),
      'custom_pages': [for (final p in customPages) p.toJson()], 'cards': cards, 'exclude': exclude, 'sizes': sizes,
      'page_order': pageOrder, 'hidden_pages': hiddenPages.toList(), 'dashboard': dashboard};

  void changed() {
    notifyListeners();
    saveLater();
  }

  /// saved, without a rebuild (what is remembered while drawing: the media card's player)
  void saveLater() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 500), () { _file?.writeAsString(jsonEncode(toJson())); onSaved?.call(); });
  }

  void reset() {
    favorites = null; hidden = {}; order = {}; homeOrder = []; place = {}; hiddenScreens = {};
    customPages = []; cards = {}; exclude = {}; sizes = {}; pageOrder = []; hiddenPages = {};
    analogClock = digitalClock = dateCard = nowPlaying = true;
    changed();
  }
}
