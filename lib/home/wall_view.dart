// The WallView: pages of square glass widgets over a wallpaper, swiped sideways.  Home first (the clocks, the date and
// weather, the favourites: a thermostat big, a camera, scenes, locks; what plays; the app's other screens), then the
// sections of the owner's Home Assistant dashboard drawn natively (Layout.dashboard, lib/lovelace/), or without one a
// page per room (Home Assistant's areas), then the owner's own pages.  Hold any card: its menu (controls, size, move,
// remove); hold on, or hold an empty place or the page dots: the edit mode, where the widgets wobble, a drag moves one,
// ★ puts it on Home, − takes it off the page, ⤡ resizes it.  What the edit mode changes is the Echo's own (the
// layout), never the dashboard.  Left alone, the ambient clock.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../ha.dart';
import 'backdrop.dart';
import 'detail.dart';
import 'layout.dart';
import 'lock_screen.dart';
import 'model.dart';
import 'photos.dart';
import 'press.dart';
import 'sheets.dart';
import 'voice.dart';
import '../apps.dart' show AndroidApp;
import '../hassmic.dart' show EchoState;
import 'app_tile.dart';
import '../keyboard.dart';
import '../lovelace/lovelace.dart';
import '../lovelace/source.dart';
import 'sizes.dart';
import 'widgets.dart';

/// media: a dashboard's media-control card, its own player (playing: Home's card, whichever player plays); card: a
/// dashboard's card with no widget of the WallView's own (entities, glance, weather, a fallback), drawn by NativeCard
enum Kind { analog, digital, date, thermo, playing, camera, tile, screen, app, media, card }

const _defaultSize = {
  Kind.analog: CardSize.s, Kind.digital: CardSize.m, Kind.date: CardSize.s, Kind.thermo: CardSize.l, Kind.playing: CardSize.l,
  Kind.camera: CardSize.s, Kind.tile: CardSize.s, Kind.screen: CardSize.s, Kind.app: CardSize.s, Kind.media: CardSize.l, Kind.card: CardSize.m,
};

class Item {
  final Kind kind;
  final String? id;                             // the entity (not for the clocks, the date, the screens)
  final String? room;                           // a tile on Home shows its room under its name
  final int screen;                             // Kind.screen: the app's screen index; Kind.app: the index in WallView.apps
  final String name;
  final CardSize? _size;                        // none: the kind's own
  final LCard? card;                            // Kind.card: the dashboard's card
  final String? cardKey;                        // Kind.card: its key on its page ("card:<type>:<n>")
  const Item(this.kind, {this.id, this.room, this.screen = -1, this.name = '', CardSize? size, this.card, this.cardKey}) : _size = size;
  CardSize get size => _size ?? _defaultSize[kind]!;
  int get w => size.w;
  int get h => size.h;
  String get key => kind == Kind.playing ? 'playing' : kind == Kind.card ? cardKey! : id ?? '${kind.name}$screen';   // the media card: one place, whichever player
  Item withSize(CardSize s) => Item(kind, id: id, room: room, screen: screen, name: name, size: s, card: card, cardKey: cardKey);
}

/// the sizes a card has (sizes.dart; how each looks: test/gallery_test.dart)
List<CardSize> sizesOf(Item it) => switch (it.kind) {
      Kind.analog => const [CardSize.s, CardSize.l],
      Kind.digital => const [CardSize.s, CardSize.m, CardSize.l],
      Kind.date => const [CardSize.s, CardSize.m],
      Kind.thermo => const [CardSize.s, CardSize.m, CardSize.l],
      Kind.playing || Kind.media || Kind.camera => const [CardSize.s, CardSize.m, CardSize.l, CardSize.xl],
      Kind.tile => const [CardSize.s, CardSize.m, CardSize.l],
      Kind.screen || Kind.app => const [CardSize.s, CardSize.m],
      Kind.card => switch (it.card?.type) {
          'entities' => const [CardSize.m, CardSize.l, CardSize.xl],
          'glance' => const [CardSize.m, CardSize.l],
          'weather-forecast' => const [CardSize.s, CardSize.m, CardSize.l],
          _ => const [CardSize.s, CardSize.m],
        },
    };

/// a size of the card's own that fits a page of cols x rows: the wanted one where it does, else the largest that does
Item fitted(Item it, CardSize? want, int cols, int rows) {
  final ok = sizesOf(it).where((s) => s.w <= cols && s.h <= rows).toList();
  if (ok.isEmpty) return it;
  final w = want ?? it.size;
  if (ok.contains(w)) return it.size == w ? it : it.withSize(w);
  final best = ok.lastWhere((s) => s.w <= w.w && s.h <= w.h, orElse: () => ok.first);
  return best == it.size ? it : it.withSize(best);
}

class PageSpec {
  final String name, sub;
  final String? area;                           // the room its chips come from (a room's page, a dashboard section named as one)
  final List<(Item, int col, int row)> placed;
  final int index;                              // which of its group's pages (the positions' page number)
  final String group;                           // its page group (layout.dart: home, area:<id>, ll:<view>/<section>, page:<id>)
  const PageSpec(this.name, this.sub, this.area, this.placed, {this.index = 0, this.group = ''});
}

/// where a widget was put: page, column, row
typedef Spot = (int page, int col, int row);

/// items into pages.  Those with a spot of their own (`fixed`: where they were put) go there first, `first` (the one
/// being dragged, or resized) before all.  One whose spot is taken (pushed aside by `first`, or grown into) goes to
/// `swapTo` (where the dragged one came from: the two swap) if it fits there, else to the free place nearest its own on
/// its own page, else on the pages after it, then before: never to the group's first page because that had a gap (the
/// "jumps" of a drag or a resize).  The rest (new cards) each at the first free place, from page `prefer` on, else from
/// the first.  `extra`: an empty page after the last (to drag a widget onto).  Every page up to the last one used is
/// returned, empty ones included.
List<PageSpec> pack(String name, String sub, String? area, List<Item> items, int cols, int rows,
    {Map<String, Spot> fixed = const {}, String? first, Spot? swapTo, bool extra = false, String group = '', int prefer = 0}) {
  final grids = <List<List<bool>>>[], placed = <List<(Item, int, int)>>[];
  void page(int pi) { while (grids.length <= pi) { grids.add(List.generate(rows, (_) => List.filled(cols, false))); placed.add([]); } }
  bool fits(Item it, int pi, int c, int r) {
    if (pi < 0 || c < 0 || r < 0 || c + it.w > cols || r + it.h > rows) return false;
    page(pi);
    final g = grids[pi];
    for (var y = r; y < r + it.h; y++) { for (var x = c; x < c + it.w; x++) { if (g[y][x]) return false; } }
    return true;
  }
  void put(Item it, int pi, int c, int r) {
    for (var y = r; y < r + it.h; y++) { for (var x = c; x < c + it.w; x++) { grids[pi][y][x] = true; } }
    placed[pi].add((it, c, r));
  }
  bool at(Item it, Spot? s) {
    if (s == null || !fits(it, s.$1, s.$2, s.$3)) return false;
    put(it, s.$1, s.$2, s.$3);
    return true;
  }
  /// the free place on page pi nearest (c, r), reading order on a tie
  bool near(Item it, int pi, int c, int r) {
    Spot? best; var bd = 1 << 30;
    for (var y = 0; y + it.h <= rows; y++) {
      for (var x = 0; x + it.w <= cols; x++) {
        final d = (x - c).abs() + (y - r).abs() * 2;            // a row away is further than a column (pages are wide)
        if (d < bd && fits(it, pi, x, y)) { bd = d; best = (pi, x, y); }
      }
    }
    return at(it, best);
  }
  /// the first free place on page pi, in reading order
  bool firstFit(Item it, int pi) {
    for (var y = 0; y + it.h <= rows; y++) { for (var x = 0; x + it.w <= cols; x++) { if (fits(it, pi, x, y)) { put(it, pi, x, y); return true; } } }
    return false;
  }
  final fitting = items.where((it) => it.w <= cols && it.h <= rows).toList();   // bigger than a page: left out
  final done = <String>{};
  // the dragged one where the finger is, then those that were put somewhere, by where they were (reading order)
  int ord(Item it) { final s = fixed[it.key]; return s == null ? 1 << 30 : (s.$1 * rows + s.$3) * cols + s.$2; }
  final byPlace = [...fitting.where((it) => it.key != first)]..sort((a, b) => ord(a).compareTo(ord(b)));
  for (final it in [...fitting.where((it) => it.key == first), ...byPlace]) {
    if (fixed.containsKey(it.key) && at(it, fixed[it.key])) done.add(it.key);
  }
  // pushed aside: the dragged one's old place, else near its own on its own page, then the pages after, then before
  for (final it in byPlace) {
    final s = fixed[it.key];
    if (done.contains(it.key) || s == null) continue;
    done.add(it.key);
    if (at(it, swapTo)) continue;
    if (near(it, s.$1, s.$2, s.$3)) continue;
    var ok = false;
    for (var pi = s.$1 + 1; pi < grids.length && !ok; pi++) { ok = firstFit(it, pi); }
    for (var pi = s.$1 - 1; pi >= 0 && !ok; pi--) { ok = firstFit(it, pi); }
    if (!ok) { page(grids.length); firstFit(it, grids.length - 1); }
  }
  // the rest: new cards, from the page asked for on
  for (final it in fitting) {
    if (done.contains(it.key)) continue;
    var ok = false;
    for (var pi = max(0, prefer); !ok; pi++) { page(pi); ok = firstFit(it, pi); }
  }
  var last = placed.lastIndexWhere((pl) => pl.isNotEmpty);
  if (extra) last++;
  if (last < 0) return [PageSpec(name, sub, area, const [], group: group)];
  page(last);
  return [for (var i = 0; i <= last; i++) PageSpec(name, sub, area, placed[i], index: i, group: group)];
}

class WallView extends StatefulWidget {
  final Ha ha;
  final Layout layout;
  final bool h24;
  final List<String> screens;                   // the app's other screens (Home Assistant's UI, Music Assistant)
  final void Function(int) onScreen;
  final List<AndroidApp> apps;                  // the owner's other apps (a YouTube client): a card each, on by itself
  final void Function(String package)? onApp;
  /// the pages after Home changed (pageList): Echo Local's preview tells its panel
  final void Function(List<Map<String, dynamic>> pages)? onPages;
  final Map<String, String> settings;           // the integration's screen app settings (immich.*, photos.minutes)
  final bool round;                             // an Echo Spot: the widgets inside the circle's square
  final EchoState? echo;                        // hassmic's: a request, a ring (drawn here on the glass)
  final String nextAlarm;
  /// the Echo Local panel's preview (lib/preview.dart): its switch turns the edit mode on and off, and the WallView
  /// never goes to the lock screen there
  final ValueNotifier<bool>? editMode;
  final bool preview;
  /// a dashboard's card the WallView cannot draw: that view in Home Assistant's own UI ("/(dashboard)/(view)")
  final void Function(String path)? onDashboard;
  /// where the dashboard comes from (tests: LovelaceSource.fixed); none: Home Assistant, over `ha`
  final LovelaceSource? lovelace;
  const WallView({super.key, required this.ha, required this.layout, required this.h24, required this.screens, required this.onScreen,
      this.apps = const [], this.onApp, this.onPages, this.settings = const {}, this.nextAlarm = '', this.round = false, this.echo,
      this.editMode, this.preview = false, this.onDashboard, this.lovelace});
  @override
  State<WallView> createState() => _WallViewState();
}

class _WallViewState extends State<WallView> with TickerProviderStateMixin, WidgetsBindingObserver {
  final pc = PageController();
  int page = 0;
  bool editing = false, ambient = false;
  DateTime touched = DateTime.now();
  Timer? idle;
  String? dragging;                             // the key of the widget being moved
  String? liveArea;                             // its page group (_gk)
  Map<String, Spot>? startSpots;                // every widget of that group where it was when the drag began
  Spot? dragFrom, dragAt;                       // where the dragged one came from, where it is now
  Timer? _edgeFlip;                             // held at the screen's edge: the next page
  String? _dragOrigin;                          // the group the dragged card came from (liveArea: the one it is over)
  Item? _dragItem;                              // the dragged card, to be drawn on another group's page
  Map<String, Spot>? _originSpots;              // its group as it was: back over it, the drag goes on from there
  /// the page looked at, by group and index: the flat page number shifts when a page before it comes or goes (a drag's
  /// empty page, a card pushed onto a new page, a page left empty after a drop), and the view follows the page, not the
  /// number
  (String, int)? _viewing;
  late final AnimationController wobble;       // made in initState: lazily, a dispose() without editing made it then

  final photos = PhotoLibrary();
  final backdrop = Backdrop();
  Wallpaper? _wallFor;
  Timer? _wallTimer;

  /// the wallpaper behind the glass: a photo (the lock screen's library; another every two hours), or a gradient
  Future<void> _wallpaper() async {
    _wallTimer?.cancel();
    _wallFor = lay.wallpaper;
    if (lay.wallpaper == Wallpaper.photo) {
      photos.configure(widget.settings);
      try {
        final ph = await photos.next(wide: backdrop.size.isEmpty || backdrop.size.width >= backdrop.size.height);
        if (lay.wallpaper == Wallpaper.photo) await backdrop.photo(ph.bytes);   // a gradient picked meanwhile wins
      } catch (_) {}
      _wallTimer = Timer(const Duration(hours: 2), _wallpaper);
    } else {
      await backdrop.painted(WallpaperPainter(Palette.of(lay.wallpaper)));
    }
  }
  Ha get ha => widget.ha;
  Layout get lay => widget.layout;
  late final LovelaceSource ll = widget.lovelace ?? LovelaceSource(widget.ha);

  int? ambientOverride;                         // debug.echoscreen.ambient (screenshots)

  /// the app in front with its screen on (Android pauses the activity when the screen goes off or another app comes)
  bool resumed = true;
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final r = s == AppLifecycleState.resumed;
    if (r != resumed) setState(() => resumed = r);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    wobble = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    widget.editMode?.addListener(_editMode);
    if (widget.editMode?.value == true) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) edit(true); });
    const MethodChannel('echo_screen/keys').invokeMethod<String>('prop', 'debug.echoscreen.ambient').then((v) {
      final n = int.tryParse(v ?? '');
      if (n != null && n > 0) ambientOverride = n;
    }).catchError((_) {});
    idle = Timer.periodic(const Duration(seconds: 5), (_) {
      final s = widget.preview ? 0 : ambientOverride ?? lay.ambientSeconds;
      if (s > 0 && !ambient && !editing && DateTime.now().difference(touched).inSeconds >= s && ModalRoute.of(context)?.isCurrent != false) {
        setState(() => ambient = true);
      }
    });
  }

  @override
  void dispose() { if (widget.lovelace == null) ll.dispose(); _menuTimer?.cancel(); widget.editMode?.removeListener(_editMode); WidgetsBinding.instance.removeObserver(this); idle?.cancel(); _wallTimer?.cancel(); _edgeFlip?.cancel(); wobble.dispose(); pc.dispose(); backdrop.dispose(); super.dispose(); }

  void edit(bool on) {
    setState(() { editing = on; ambient = false; });
    on ? wobble.repeat(reverse: true) : wobble.stop();
    if (widget.editMode != null && widget.editMode!.value != on) widget.editMode!.value = on;   // Done on the bar: the panel's switch follows
  }

  void _editMode() { if (widget.editMode!.value != editing) edit(widget.editMode!.value); }

  // ---------------------------------------------------------------- what goes where

  List<String> favorites() {
    final f = lay.favorites;
    if (f != null) return f.where((id) => ha.states.containsKey(id) && !lay.hidden.contains(id)).toList();
    String? first(bool Function(String) p) => ha.states.keys.where(p).firstOrNull;
    return [
      ?first((x) => domainOf(x) == 'climate' && ha.states[x]!.numAttr('temperature') != null && shown(ha, lay, x)),
      ?first((x) => domainOf(x) == 'camera' && ha.states[x]!.state != 'unavailable' && !lay.hidden.contains(x)),
      ...ha.states.keys.where((x) => domainOf(x) == 'scene' && shown(ha, lay, x)).take(3),
      ...ha.states.keys.where((x) => domainOf(x) == 'lock' && shown(ha, lay, x)),
    ];
  }

  Item itemOf(String id, {String? room}) => switch (domainOf(id)) {
        'climate' when ha.states[id]?.numAttr('temperature') != null => Item(Kind.thermo, id: id),
        'camera' => Item(Kind.camera, id: id),
        _ => Item(Kind.tile, id: id, room: room),
      };

  /// the media card's player: always one, so the card stays where it was put (an AirPlay stream has no title, a paused
  /// one is not playing): what plays (the one shown before, else one with a title), else the last that played, else
  /// one that is on
  String? nowPlayer() {
    bool ok(String id) => ha.states.containsKey(id) && !lay.hidden.contains(id) && ha.states[id]!.state != 'unavailable';
    final players = ha.states.keys.where((id) => domainOf(id) == 'media_player' && ok(id)).toList();
    if (players.isEmpty) return null;
    bool titled(String id) => ha.states[id]!.attr['media_title'] != null;
    final playing = players.where((id) => ha.states[id]!.state == 'playing').toList();
    final now = (playing.contains(lay.player) ? lay.player : null) ?? playing.where(titled).firstOrNull ?? playing.firstOrNull;
    if (now != null) {
      if (now != lay.player) { lay.player = now; lay.saveLater(); }
      return now;
    }
    if (lay.player != null && ok(lay.player!)) return lay.player;
    bool on(String id) => !const {'off', 'standby', 'unknown'}.contains(ha.states[id]!.state);
    return players.where(titled).firstOrNull ?? players.where(on).firstOrNull ?? players.first;
  }

  /// a card of a page group's own list (Layout.cards): one of Home's widgets, an app, or an entity
  Item? cardItem(String key, {String? area}) {
    switch (key) {
      case 'analog': return const Item(Kind.analog);
      case 'digital': return const Item(Kind.digital);
      case 'date': return const Item(Kind.date);
      case 'playing':
        final pl = nowPlayer();
        return pl == null ? null : Item(Kind.playing, id: pl);
    }
    if (key.startsWith('app:')) {
      final i = widget.apps.indexWhere((a) => a.key == key);
      return i < 0 ? null : Item(Kind.app, id: key, screen: i, name: widget.apps[i].label);
    }
    if (!ha.states.containsKey(key) || lay.hidden.contains(key) || ha.hiddenByHa.contains(key)) return null;
    final own = ha.areaOf(key);
    return itemOf(key, room: own != null && own != area ? ha.areaName(own) : null);
  }

  /// a dashboard card as the WallView draws it: its own widgets where it has one (a tile, a thermostat, a player, a
  /// camera, live), NativeCard for the rest; at the nearest of the WallView's sizes
  Item? llItem(LCard c, int n) {
    final e = c.entity, have = e != null && ha.states.containsKey(e) && !lay.hidden.contains(e);
    switch (c.type) {
      case 'tile' || 'button' || 'light' || 'sensor' || 'entity':
        return have ? Item(Kind.tile, id: e, size: c.cardSize) : null;
      case 'thermostat':
        return have ? Item(Kind.thermo, id: e, size: c.cardSize) : null;
      case 'media-control':
        return have ? Item(Kind.media, id: e, size: c.cardSize) : null;
      case 'picture-entity' || 'picture-glance' when have && e.startsWith('camera.'):
        return Item(Kind.camera, id: e, size: c.cardSize);
    }
    final it = Item(Kind.card, card: c, cardKey: 'card:${c.type}:$n', size: c.cardSize);
    return fitted(it, c.cardSize, 4, 2);          // its size one of a NativeCard's
  }

  /// a page group's own cards with the Echo's changes: what was taken off this page (exclude) out, what was added
  /// (cards) in, each card at the size set on the Echo where it has that size and it fits
  List<Item> _edited(String g, List<Item> own, int cols, int rows, {String? area}) {
    final ex = lay.exclude[g] ?? const [], sz = lay.sizes[g] ?? const {};
    final seen = <String>{}, out = <Item>[];
    void take(Item? it) {
      if (it == null || ex.contains(it.key) || !seen.add(it.key)) return;
      out.add(fitted(it, CardSize.of(sz[it.key]), cols, rows));
    }
    for (final it in own) { take(it); }
    for (final k in lay.cards[g] ?? const <String>[]) { take(cardItem(k, area: area)); }
    // the card being dragged here from another group's page: drawn where it would land
    final v = _visitor(g);
    if (v != null && !out.any((it) => it.key == v.key)) out.add(fitted(v, v.size, cols, rows));
    return out;
  }

  /// the card dragged over this group's pages from another group's, if any
  Item? _visitor(String g) => dragging != null && liveArea == g && _dragOrigin != null && _dragOrigin != g ? _dragItem : null;

  /// whether a card may be dragged onto a group's pages: a dashboard's own card stays in its section (it is the
  /// dashboard's), a screen's tile on Home (a room has no place for it)
  bool _canGo(Item it, String to, String from) =>
      to == from || (it.kind != Kind.card && !(it.kind == Kind.screen && to != homeGroup));

  /// the key a card has in Layout.cards (Home's own widgets by name: an Item's key carries its screen number)
  static String cardKeyOf(Item it) => switch (it.kind) {
        Kind.analog => 'analog', Kind.digital => 'digital', Kind.date => 'date', Kind.playing => 'playing', _ => it.key };

  List<PageSpec> pages(int cols, int rows) {
    final out = <PageSpec>[];
    _items.clear();
    final home = <Item>[
      if (lay.analogClock) const Item(Kind.analog),
      if (lay.digitalClock) const Item(Kind.digital),
      if (lay.dateCard) const Item(Kind.date),
    ];
    final fav = favorites();
    for (final id in fav) { home.add(itemOf(id, room: ha.areaName(ha.areaOf(id)))); }
    final player = lay.nowPlaying ? nowPlayer() : null;
    if (player != null) home.add(Item(Kind.playing, id: player));
    for (var i = 0; i < widget.screens.length; i++) { if (!lay.hiddenScreens.contains(widget.screens[i])) home.add(Item(Kind.screen, screen: i, name: widget.screens[i])); }
    // an app installed comes onto Home by itself; taken off, its key ("app:<package>") is kept with the screens' names
    for (var i = 0; i < widget.apps.length; i++) {
      final a = widget.apps[i];
      if (!lay.hiddenScreens.contains(a.key)) home.add(Item(Kind.app, id: a.key, screen: i, name: a.label));
    }
    final ho = lay.homeOrder;
    if (ho.isNotEmpty) {                        // as moved (List.sort is not stable: ties keep their index)
      final idx = {for (var i = 0; i < home.length; i++) home[i].key: i};
      int at(Item it) { final i = ho.indexOf(it.key); return i < 0 ? (1 << 20) + idx[it.key]! : i; }
      home.sort((a, b) => at(a).compareTo(at(b)));
    }
    final homeSizes = lay.sizes[homeGroup] ?? const {};
    final homeItems = [for (final it in home) it.kind == Kind.playing ? it : fitted(it, CardSize.of(homeSizes[it.key]), cols, rows)];
    final visiting = _visitor(homeGroup);
    if (visiting != null && !homeItems.any((it) => it.key == visiting.key)) homeItems.add(fitted(visiting, visiting.size, cols, rows));
    // the media card on Home's first page: as big as there is room for there (the owner's widgets keep their places),
    // unless it was put on another page or given a size on the Echo; while a widget is dragged, the size it had
    List<Item> sized(CardSize n) => [for (final it in homeItems) it.kind == Kind.playing ? it.withSize(n) : it];
    final putAt = lay.place[homeGroup]?['playing']?.first ?? 0;
    final setPlay = CardSize.of(homeSizes['playing']);
    final sizes = player == null || (dragging != null && liveArea == homeGroup) ? [_playSize]
        : setPlay != null ? [fitted(const Item(Kind.playing), setPlay, cols, rows).size]
        : putAt > 0 ? const [CardSize.l] : const [CardSize.l, CardSize.m, CardSize.s];
    for (final n in sizes) {
      final hp = _pack(homeGroup, 'Home', '', null, sized(n), cols, rows);
      _playSize = n;
      if (n == sizes.last || hp.first.placed.any((e) => e.$1.kind == Kind.playing)) { out.addAll(hp); break; }
    }

    // the pages after Home, by group, in their own order, then as the owner ordered them (Layout.pageOrder)
    final groups = <(String, List<PageSpec>)>[];
    ll.use(lay.dashboard);
    if (lay.dashboard.isNotEmpty && ll.views.isNotEmpty) {
      for (var vi = 0; vi < ll.views.length; vi++) {
        final v = ll.views[vi];
        for (var si = 0; si < v.sections.length; si++) {
          final sec = v.sections[si];
          final g = 'll:${v.path ?? vi}/${sec.title.isNotEmpty ? sec.title : si}';
          final area = ha.areas.where((a) => a.name.toLowerCase() == sec.title.toLowerCase()).firstOrNull?.id;
          final own = [for (var n = 0; n < sec.cards.length; n++) llItem(sec.cards[n], n)].whereType<Item>().toList();
          // the big ones first: a thermostat after four tiles would find no two rows left on the page (stable)
          final idx = {for (var n = 0; n < own.length; n++) own[n]: n};
          own.sort((a, b) => b.w * b.h != a.w * a.h ? (b.w * b.h).compareTo(a.w * a.h) : idx[a]!.compareTo(idx[b]!));
          final items = _edited(g, own, cols, rows, area: area);
          if (items.isEmpty && (lay.cards[g] ?? const []).isEmpty) continue;
          _llPath[g] = '/${lay.dashboard}/${v.path ?? vi}';
          groups.add((g, _pack(g, sec.title.isNotEmpty ? sec.title : v.title, sec.title.isNotEmpty && ll.views.length > 1 ? v.title : '',
              area, items, cols, rows)));
        }
      }
    } else {
      final byArea = <String, List<String>>{};
      for (final id in ha.states.keys) {
        if (!shown(ha, lay, id)) continue;
        byArea.putIfAbsent(ha.areaOf(id) ?? '', () => []).add(id);
      }
      final rooms = [...ha.areas.where((a) => byArea.containsKey(a.id) || (lay.cards[areaGroup(a.id)] ?? const []).isNotEmpty).map((a) => (a.id, a.name)),
        if (byArea.containsKey('')) ('', 'Other')];
      for (final (area, name) in rooms) {
        final own = lay.order[area] ?? const [];
        int at(String id) { final i = own.indexOf(id); return i < 0 ? 1 << 20 : i; }
        int kind(String id) { final d = domainOf(id); return d == 'scene' || d == 'script' ? -1 : tileDomains.indexOf(d); }
        final ids = (byArea[area] ?? <String>[])..sort((a, b) {
          final c = at(a).compareTo(at(b));
          if (c != 0) return c;
          final k = kind(a).compareTo(kind(b));
          return k != 0 ? k : nameIn(ha, a, name).compareTo(nameIn(ha, b, name));
        });
        final g = areaGroup(area);
        final items = _edited(g, ids.map((id) => itemOf(id)).toList(), cols, rows, area: area);
        if (items.isEmpty) continue;
        groups.add((g, _pack(g, name, roomSummary(ha, area), area, items, cols, rows)));
      }
    }
    for (final cp in lay.customPages) {
      final g = pageGroup(cp.id);
      groups.add((g, _pack(g, cp.name, '', null, _edited(g, const [], cols, rows), cols, rows)));
    }
    final order = lay.pageOrder;
    if (order.isNotEmpty) {
      final idx = {for (var i = 0; i < groups.length; i++) groups[i].$1: i};
      int at((String, List<PageSpec>) g) { final i = order.indexOf(g.$1); return i < 0 ? (1 << 20) + idx[g.$1]! : i; }
      groups.sort((a, b) => at(a).compareTo(at(b)));
    }
    // every page after Home, taken off ones too: Echo Local's panel lists them (its Pages: order, add, delete, show)
    pageList = [
      for (final (g, ps) in groups)
        {'group': g, 'title': ps.first.name, 'kind': g.startsWith('page:') ? 'own' : g.startsWith('ll:') ? 'dashboard' : 'room',
         'hidden': lay.hiddenPages.contains(g)},
    ];
    for (final (g, ps) in groups) { if (!lay.hiddenPages.contains(g)) out.addAll(ps); }
    return out;
  }

  /// a page group packed: each widget where it was put (the layout's places), the one being dragged where the finger
  /// has it; what was where it goes to where it came from; the rest flows into free places.  Where everything ended up
  /// is kept (_spotsOf): a drag starts from it, a drop saves it
  List<PageSpec> _pack(String g, String name, String sub, String? area, List<Item> items, int cols, int rows) {
    final live = dragging != null && liveArea == g;
    final saved = {for (final e in (lay.place[g] ?? const <String, List<int>>{}).entries) if (e.value.length == 3) e.key: (e.value[0], e.value[1], e.value[2])};
    final rs = _resizing != null && _resizing!.$1 == g ? _resizing : null;
    final fixed = live ? {...startSpots!, dragging!: ?dragAt} : rs != null ? {...?_spotsOf[g], ...saved, rs.$2: rs.$3} : saved;
    final ps = pack(name, sub, area, items, cols, rows, fixed: fixed, first: live ? dragging : rs?.$2,
        swapTo: live && dragAt != null ? dragFrom : null, extra: dragging != null && g == (_dragOrigin ?? liveArea), group: g);
    _spotsOf[g] = {for (final pg in ps) for (final (it, c, r) in pg.placed) it.key: (pg.index, c, r)};
    if (rs != null) { _resizing = null; _commit(g); }
    for (final it in items) { _items[it.key] = it; }
    return ps;
  }
  final _llPath = <String, String>{};           // a dashboard section's group: its view in Home Assistant's UI
  final _spotsOf = <String, Map<String, Spot>>{};
  CardSize _playSize = CardSize.l;

  // ---------------------------------------------------------------- drawing

  @override
  Widget build(BuildContext context) {
    // the palette and the wallpaper inside the layout's builder: a theme picked in edit mode shows at once (in build()
    // above it they changed only once the WallView itself was built again, at Done)
    return BackdropScope(backdrop: backdrop, child: ListenableBuilder(listenable: Listenable.merge([ha, lay, ll]), builder: (context, _) {
      final p = Palette.of(lay.wallpaper);
      if (_wallFor != lay.wallpaper) { _wallFor = lay.wallpaper; WidgetsBinding.instance.addPostFrameCallback((_) => _wallpaper()); }
      return Listener(
      onPointerDown: (_) => touched = DateTime.now(),
      // a finger lifted ends a drag here too: when the page turned under it, the widget's old page (and its
      // Draggable) may be gone and the page now under it not yet entered, and neither would tell of the drop
      onPointerUp: (_) => _drop(),
      onPointerCancel: (_) => _drop(),
      child: Stack(children: [
        Positioned.fill(child: LayoutBuilder(builder: (context, box) {
          final sz = Size(box.maxWidth, box.maxHeight);
          if (sz != backdrop.size) WidgetsBinding.instance.addPostFrameCallback((_) => backdrop.resize(sz));
          return BackdropView(fallback: p.wall);
        })),
        // round: everything in the square that fits in the circle
        LayoutBuilder(builder: (context, outer) => Padding(padding: EdgeInsets.all(widget.round ? min(outer.maxWidth, outer.maxHeight) * .146 : 0),
            child: LayoutBuilder(builder: (context, box) {
          // room to breathe, as Apple's Home has it: few large tiles (4 x 2 on an Echo Show 5), wide gaps, a page title
          final small = box.maxHeight < 360;
          final gap = small ? 10.0 : 14.0, pad = small ? 10.0 : 16.0, bottom = 22.0, header = small ? 34.0 : 52.0;
          // the grid's rows and columns from the page as it is when not editing: the edit bar (44 px) only makes the
          // cells a little lower, so a widget put in the last column is still there after Done
          final full = box.maxHeight - pad - header - bottom, avail = full - (editing ? 44 : 0);
          final rows = full < 430 ? 2 : full < 720 ? 3 : 4;
          final cols = max(2, ((box.maxWidth - 2 * pad + gap) / ((full - gap * (rows - 1)) / rows + gap)).floor());
          final cell = (avail - gap * (rows - 1)) / rows;
          final cw = (box.maxWidth - 2 * pad - gap * (cols - 1)) / cols;
          final ps = pages(cols, rows);
          _lastPages = ps; _cols = cols; _rows = rows; _stepX = cw + gap; _stepY = cell + gap;
          if (widget.onPages != null) {
            final j = jsonEncode(pageList);
            if (j != _pagesTold) { _pagesTold = j; final l = pageList; WidgetsBinding.instance.addPostFrameCallback((_) => widget.onPages?.call(l)); }
          }
          // the page looked at kept when pages before it came or went (it may itself be gone: the nearest of its group)
          final v = _viewing;
          if (v != null && (page >= ps.length || ps[page].group != v.$1 || ps[page].index != v.$2)) {
            var at = ps.indexWhere((x) => x.group == v.$1 && x.index == v.$2);
            if (at < 0) at = ps.lastIndexWhere((x) => x.group == v.$1 && x.index < v.$2);
            if (at >= 0 && at != page) {
              page = at;
              WidgetsBinding.instance.addPostFrameCallback((_) { if (pc.hasClients && (pc.page ?? -1).round() != page) pc.jumpToPage(page); });
            }
          }
          if (page >= ps.length) page = ps.length - 1;
          if (ps.isNotEmpty) _viewing = (ps[page].group, ps[page].index);
          return Stack(children: [
            // no repaint boundary per page (PageView.builder adds one): the glass draws its piece of the blurred
            // wallpaper from where it is on the screen when painted, and a page kept as a layer from a paint off to the
            // side (or half swiped in) slid in later with that piece: clear glass, no blur.  Without them each frame
            // of a swipe paints the page again, the glass at its true place (drawing the glass is copying a picture)
            PageView.custom(
              controller: pc,
              physics: editing ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(parent: PageScrollPhysics()),
              // no setState outside the edit mode: halfway through a swipe that built the whole WallView again (every
              // page group packed), a frame of 70-100 ms on the Show 5 in the middle of the swipe; the dots follow the
              // scroll themselves.  The edit bar is the page's (+ Add, Rename): there it builds again
              onPageChanged: (i) {
                page = i;
                if (i < ps.length) _viewing = (ps[i].group, ps[i].index);
                if (editing) setState(() {});
              },
              childrenDelegate: SliverChildBuilderDelegate(childCount: ps.length, addRepaintBoundaries: false, (context, i) => _grid(ps, i, cols, rows, cw + gap, cell + gap, Padding(
                padding: EdgeInsets.fromLTRB(pad, pad + (editing ? 44 : 0), pad, bottom),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(height: header, child: _header(ps[i], p, small)),
                  Expanded(child: _GridBox(onBox: (b) => _gridBox['${ps[i].group}/${ps[i].index}'] = b, child: Stack(children: [
                  // an empty place held: the edit mode, as on an iPhone's home screen
                  if (!editing) Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onLongPress: () => edit(true))),
                  for (final (it, c, r) in ps[i].placed)
                    AnimatedPositioned(
                      key: ValueKey('${ps[i].group}/${it.key}'),
                      duration: const Duration(milliseconds: 220), curve: Curves.easeOut,
                      left: c * (cw + gap), top: r * (cell + gap),
                      width: it.w * cw + (it.w - 1) * gap, height: it.h * cell + (it.h - 1) * gap,
                      // the card's own state kept into the edit mode and out (a camera's stream, a player's
                      // artwork): the edit mode wraps it in more, which would otherwise make it anew
                      child: _editable(ps[i], it, p, cell, KeyedSubtree(key: _cardKeys.putIfAbsent('${ps[i].group}/${it.key}', GlobalKey.new),
                          child: _widget(ps[i], it, p, cell))),
                    ),
                  ]))),
                ]),
              ))),
            ),
            if (ps.isNotEmpty) _dots(ps, p),
            if (editing) _bar(ps, p),
            if (ps.length == 1 && ha.areas.isEmpty && ha.connected)
              Center(child: Text('Give your devices areas in Home Assistant:\nthe WallView shows them room by room.',
                  textAlign: TextAlign.center, style: TextStyle(color: p.text, fontSize: 16))),
            if (!ha.connected)
              Positioned(left: 0, right: 0, top: 6, child: Center(child: Text(ha.error ?? 'Connecting to Home Assistant…',
                  style: TextStyle(color: p.dim, fontSize: 12)))),
          ]);
        }))),
        // resting: the lock screen over the WallView, lifted off by a swipe up
        if (ambient) Positioned.fill(child: LockScreen(photos: photos..configure(widget.settings), ha: ha, h24: widget.h24,
            player: lay.nowPlaying ? nowPlayer() : null,
            nextAlarm: widget.nextAlarm, minutes: int.tryParse(widget.settings['photos.minutes'] ?? '') ?? 3, round: widget.round,
            onUnlock: () { touched = DateTime.now(); setState(() => ambient = false); })),
        // the voice assistant and the alarms, on the glass, over everything (the lock screen too)
        if (widget.echo != null) Positioned.fill(child: VoiceLayer(s: widget.echo!, backdrop: backdrop, round: widget.round)),
      ]),
    );
    }));
  }

  final _cardKeys = <String, GlobalKey>{};

  /// `lifted`: the copy under the finger while dragging (a camera's still, not a second stream)
  Widget _widget(PageSpec page, Item it, Palette p, double cell, {bool lifted = false}) {
    void more() => showDetail(context, ha, p, it.id!, backdrop);
    return switch (it.kind) {
      Kind.analog => AnalogClockCard(p: p, cell: cell),
      Kind.digital => DigitalClockCard(p: p, cell: cell, h24: widget.h24, size: it.size),
      Kind.date => Press(onTap: () => showWeather(context, ha, p, backdrop), child: DateWeatherCard(ha: ha, p: p, cell: cell, size: it.size)),
      Kind.thermo => ThermostatCard(ha: ha, p: p, id: it.id!, cell: cell, onLong: more, holdOpens: false, size: it.size),
      Kind.playing || Kind.media => NowPlayingCard(ha: ha, p: p, id: it.id!, cell: cell, size: it.size, onLong: more, holdOpens: false),
      // live under the lock screen too, so that it is there the moment the screen is woken (a stream started then took
      // seconds: Home Assistant's HLS, the decoder), and in edit mode (as an iPhone's widgets go on); off only with the
      // screen, and in the lifted copy while dragging (a second stream for the Show 5's decoder)
      Kind.camera => CameraCard(ha: ha, p: p, id: it.id!, cell: cell, live: resumed && !lifted),
      Kind.screen => ScreenTile(p: p, name: it.name, cell: cell, size: it.size, onTap: () => widget.onScreen(it.screen)),
      Kind.app => AppTile(p: p, name: it.name, icon: widget.apps[it.screen].icon, cell: cell, size: it.size,
          onTap: () => widget.onApp?.call(widget.apps[it.screen].package)),
      Kind.tile => AccessoryTile(ha: ha, p: p, id: it.id!, room: it.room, cell: cell, onLong: more, holdOpens: false, size: it.size),
      Kind.card => LayoutBuilder(builder: (_, b) => NativeCard(ha: ha, p: p, card: it.card!, box: b.biggest, size: it.size,
          onOpen: _llPath[page.group] == null || widget.onDashboard == null ? null : () => widget.onDashboard!(_llPath[page.group]!))),
    };
  }

  /// the page's title and beside it, as Apple's Home has them, chips of frosted glass: on Home the categories (Lights,
  /// Climate, Security, Speakers: what each is doing; a tap shows its devices), in a room its temperature, humidity
  /// and lights
  Widget _header(PageSpec pg, Palette p, bool small) {
    final chips = <(IconData, String, VoidCallback?)>[];
    if (pg.area == null) {
      for (final c in Category.values) {
        final sum = categorySummary(ha, lay, c);
        if (sum != null) chips.add((categoryIcon[c]!, '${categoryName[c]}  $sum', () => showCategory(context, ha, lay, p, backdrop, c)));
      }
    } else {
      for (final part in roomSummary(ha, pg.area!).split(' · ').where((x) => x.isNotEmpty)) {
        chips.add((part.endsWith('%') ? CupertinoIcons.drop_fill : CupertinoIcons.thermometer, part, null));
      }
      final lights = categorySummary(ha, lay, Category.lights, area: pg.area);
      if (lights != null) chips.add((CupertinoIcons.lightbulb_fill, 'Lights  $lights', () => showCategory(context, ha, lay, p, backdrop, Category.lights, area: pg.area)));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text(pg.name, style: TextStyle(color: p.text, fontSize: small ? 18 : 28, fontWeight: FontWeight.w700, letterSpacing: -.4,
          shadows: const [Shadow(color: Color(0x33000000), blurRadius: 8)])),
      const SizedBox(width: 12),
      Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(), child: Row(children: [
        for (final (icon, text, onTap) in chips)
          Padding(padding: const EdgeInsets.only(right: 8), child: Press(onTap: onTap, depth: onTap == null ? 0 : .06, child: Frosted(
            blurred: backdrop.blurred, screen: backdrop.size, radius: BorderRadius.circular(999), tint: p.glass,
            edgeTop: p.edge.withValues(alpha: min(1, p.edge.a * 1.6)), edgeBottom: p.edge.withValues(alpha: p.edge.a * .3),
            child: Padding(padding: EdgeInsets.symmetric(horizontal: small ? 9 : 13, vertical: small ? 5 : 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: small ? 13 : 16, color: p.text),
              const SizedBox(width: 6),
              Text(text, style: TextStyle(color: p.text, fontSize: small ? 11 : 13.5, fontWeight: FontWeight.w600)),
              if (onTap != null) ...[const SizedBox(width: 2), Icon(CupertinoIcons.chevron_right, size: small ? 10 : 12, color: p.dim)],
            ])),
          ))),
      ]))),
    ]);
  }

  // ---------------------------------------------------------------- the edit mode

  Widget _editable(PageSpec page, Item it, Palette p, double cell, Widget w) {
    // not editing: a hold is the card's menu, as an iPhone's; held on, the edit mode (_Hold)
    if (!editing) {
      return _Hold(onMenu: (at) => _menu(page, it, p, at), onEdit: () { _closeMenu(); edit(true); }, child: w);
    }
    final id = it.id;
    final onHome = page.group == homeGroup;
    final fav = favorites();
    final body = AnimatedBuilder(
      animation: wobble,
      builder: (_, child) => Transform.rotate(angle: (wobble.value - .5) * .024 * (it.key.hashCode.isEven ? 1 : -1), child: child),
      // nothing of the widget's own while editing; a tap is its menu (its sizes, another page, off)
      child: Builder(builder: (bc) => GestureDetector(
          onTap: () { final b = bc.findRenderObject() as RenderBox?; if (b != null) _menu(page, it, p, b.localToGlobal(Offset.zero) & b.size); },
          child: AbsorbPointer(child: w))),
    );
    // a finger's worth to hit (44 px), the circle drawn smaller inside it, half outside the card's corner
    Widget badge(Widget icon, Color bg, VoidCallback f, {required Alignment at}) => Positioned(
          left: at.x < 0 ? -8 : null, right: at.x > 0 ? -8 : null, top: at.y < 0 ? -8 : null, bottom: at.y > 0 ? -8 : null,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: f, child: SizedBox(width: 48, height: 48, child: Center(child: Container(
              width: 34, height: 34, alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6)]),
              child: icon)))),
        );
    Text glyph(String s, Color c) => Text(s, style: TextStyle(color: c, fontSize: 19, fontWeight: FontWeight.w700, height: 1));
    final key = it.key;
    final draggable = LayoutBuilder(builder: (context, box) => Draggable<String>(
      key: _dragKeys.putIfAbsent('${page.group}/$key', GlobalKey.new),   // kept when it moves to another page
      data: key,
      // the finger at the tile's middle, the tile at its own size, lifted
      dragAnchorStrategy: (d, context, position) => Offset(box.maxWidth / 2, box.maxHeight / 2),
      // the lifted copy is drawn in the Overlay, outside the WallView: its glass needs the backdrop handed on
      feedback: BackdropScope(backdrop: backdrop, child: SizedBox(width: box.maxWidth, height: box.maxHeight,
          child: Transform.scale(scale: 1.06, child: Opacity(opacity: .92, child: Material(color: Colors.transparent,
              child: _widget(page, it, p, cell, lifted: true)))))),
      childWhenDragging: Opacity(opacity: .25, child: body),
      onDragStarted: () {
        HapticFeedback.selectionClick();
        _dragHalf[key] = Offset(box.maxWidth / 2, box.maxHeight / 2);
        final g = page.group;
        setState(() {
          dragging = key; liveArea = g; _dragOrigin = g; _dragItem = it; _edgeDir = 0;
          startSpots = Map.of(_spotsOf[g] ?? const {});
          _originSpots = startSpots;
          dragFrom = startSpots![key]; dragAt = dragFrom;
        });
      },
      onDragEnd: (_) => _drop(),
      child: body,
    ));
    // the dragged card where it would land on another group's page: a dim stand-in, no Draggable of its own
    if (dragging == key && _dragOrigin != null && page.group != _dragOrigin) {
      return Opacity(opacity: .25, child: AbsorbPointer(child: _widget(page, it, p, cell, lifted: true)));   // no second stream
    }
    final sizes = _fits(it);
    return Builder(
      builder: (_) => Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: draggable),
        if (id != null && !onHome && ha.states.containsKey(id)) badge(glyph('★', fav.contains(id) ? const Color(0xfff5a623) : const Color(0xffb8b8b8)), Colors.white, () {
          lay.favorites = fav.contains(id) ? (fav..remove(id)) : [...fav, id];
          lay.changed();
        }, at: Alignment.topLeft),
        badge(glyph('−', Colors.white), const Color(0xffff453a), () { _removeFrom(page.group, it); lay.changed(); }, at: Alignment.topRight),
        if (sizes.length > 1) badge(const Icon(CupertinoIcons.arrow_up_left_arrow_down_right, size: 17, color: Color(0xff1c1c1e)), Colors.white,
            () => _resize(page.group, it, sizes[(sizes.indexOf(it.size) + 1) % sizes.length]), at: Alignment.bottomRight),
      ]),
    );
  }

  int _cols = 4, _rows = 2;                     // the grid's, from the last build: which sizes fit
  List<CardSize> _fits(Item it) => sizesOf(it).where((s) => s.w <= _cols && s.h <= _rows).toList();

  /// a new size, kept where it is (its top-left corner, moved in only as far as the page's edge makes it): the cards
  /// it grows over are pushed aside on their own page (pack), the rest stay; every place of the group saved after
  /// (_commit), as a drop does, so that nothing flows about on a later build
  void _resize(String g, Item it, CardSize to) {
    lay.sizes = {...lay.sizes, g: {...?lay.sizes[g], it.key: to.code}};
    final cur = _spotsOf[g]?[it.key];
    if (cur != null) _resizing = (g, it.key, (cur.$1, min(cur.$2, max(0, _cols - to.w)), min(cur.$3, max(0, _rows - to.h))));
    lay.changed();
  }
  (String, String, Spot)? _resizing;            // the group, the card and the corner it keeps, until the next pages()

  /// a card's menu, as an iPhone's long press has it, beside the card: its controls, its sizes, another page for it,
  /// off this page, and the edit mode.  An overlay, not a route: pushing a route cancels the finger still on the card,
  /// and the hold could then not go on into the edit mode (_Hold)
  OverlayEntry? _menuEntry;
  Timer? _menuTimer;
  void _closeMenu() { _menuEntry?.remove(); _menuEntry = null; }

  void _menu(PageSpec page, Item it, Palette p, Rect at) {
    if (_menuEntry != null) return;
    HapticFeedback.selectionClick();
    final screen = MediaQuery.sizeOf(context);
    final sizes = _fits(it);
    final hasControls = it.id != null && ha.states.containsKey(it.id) && const {Kind.tile, Kind.thermo, Kind.playing, Kind.media}.contains(it.kind);
    final targets = it.kind == Kind.card ? const <(String, String)>[] : _pageTargets(page.group);
    const fg = Colors.white;
    void go(VoidCallback f) { _closeMenu(); f(); }
    Widget row(IconData icon, String label, VoidCallback f, {Color color = fg}) => InkWell(onTap: () => go(f), child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(children: [Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 16))), Icon(icon, color: color, size: 19)])));
    final menu = Material(key: const ValueKey('card-menu'), color: const Color(0xf02c2c2e), borderRadius: BorderRadius.circular(14), clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (hasControls) row(CupertinoIcons.slider_horizontal_3, 'Controls', () => showDetail(context, ha, p, it.id!, backdrop)),
      if (sizes.length > 1) Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in sizes) ChoiceChip(label: Text(s.label), selected: s == it.size, showCheckmark: false,
            labelStyle: TextStyle(color: s == it.size ? const Color(0xff1c1c1e) : fg, fontSize: 13),
            selectedColor: Colors.white, backgroundColor: const Color(0x24ffffff), side: BorderSide.none,
            onSelected: (_) => go(() => _resize(page.group, it, s))),
      ])),
      if (targets.isNotEmpty) row(CupertinoIcons.arrow_right_square, 'Move to…', () => _moveSheet(page, it, p, targets)),
      row(CupertinoIcons.square_grid_2x2, 'Edit Home Screen', () => edit(true)),
      const Divider(height: 1, color: Color(0x33ffffff)),
      row(CupertinoIcons.minus_circle, page.group == homeGroup ? 'Remove from Home' : 'Remove from this page',
          () { _removeFrom(page.group, it); lay.changed(); }, color: const Color(0xffff453a)),
    ])));
    // below the card, else above it, else beside it (a 470 px screen has room for neither under a top-row card)
    const w = 250.0, need = 250.0;
    final below = screen.height - at.bottom - 8, above = at.top - 8;
    final Widget placed;
    if (below >= need || above >= need) {
      final left = (at.center.dx - w / 2).clamp(12.0, screen.width - w - 12);
      placed = Positioned(left: left, width: w, top: below >= need ? at.bottom + 8 : null, bottom: below >= need ? null : screen.height - at.top + 8,
          child: ConstrainedBox(constraints: BoxConstraints(maxHeight: max(below, above)), child: menu));
    } else {
      final right = screen.width - at.right - 8 >= w + 12;
      placed = Positioned(left: right ? at.right + 8 : null, right: right ? null : screen.width - at.left + 8, width: w, top: 12, bottom: 12,
          child: Align(alignment: Alignment(0, (at.center.dy / screen.height * 2 - 1).clamp(-1.0, 1.0)), child: menu));
    }
    _menuEntry = OverlayEntry(builder: (_) => Stack(children: [
      Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _closeMenu, child: const ColoredBox(color: Color(0x59000000)))),
      placed,
    ]));
    Overlay.of(context).insert(_menuEntry!);
  }

  /// the pages a card may go to: every group but its own (Home, the dashboard's sections or the rooms, the own pages)
  List<(String, String)> _pageTargets(String from) {
    final out = <(String, String)>[];
    for (final pg in _lastPages) {
      if (pg.group != from && pg.index == 0 && !out.any((t) => t.$1 == pg.group)) out.add((pg.group, pg.name));
    }
    return out;
  }
  List<PageSpec> _lastPages = const [];
  /// the pages after Home as pages() last made them, with those taken off: {group, title, kind own|room|dashboard, hidden}
  List<Map<String, dynamic>> pageList = const [];
  String _pagesTold = '';

  void _moveSheet(PageSpec page, Item it, Palette p, List<(String, String)> targets) => showDialog(context: context, builder: (c) => SimpleDialog(
        backgroundColor: _solid(p), title: Text('Move to', style: TextStyle(color: p.text)),
        children: [
          for (final (g, name) in targets)
            SimpleDialogOption(onPressed: () { Navigator.of(c).pop(); _moveTo(page.group, g, it); },
                child: Text(name, style: TextStyle(color: p.text, fontSize: 16))),
        ]));

  void _moveTo(String from, String to, Item it) {
    final size = lay.sizes[from]?[it.key];
    _removeFrom(from, it);
    _addTo(to, it.key);
    if (size != null) lay.sizes = {...lay.sizes, to: {...?lay.sizes[to], it.key: size}};
    lay.changed();
    final i = _lastPages.indexWhere((pg) => pg.group == to);
    if (i >= 0) WidgetsBinding.instance.addPostFrameCallback((_) { if (pc.hasClients) pc.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); });
  }

  /// a widget off its page.  Home: its own widgets (clocks, date, media card, a screen's, an app's) switched off, a
  /// device off the favourites.  Elsewhere: one the Echo added there goes; one the page has by itself (a room's
  /// device, a dashboard's card) is left out on this Echo only (Layout.exclude: the dashboard is not changed).  Its place
  /// and size forgotten.  "+ Add" brings any of them back
  void _removeFrom(String g, Item it, {bool pull = true}) {
    if (g == homeGroup) {
      switch (it.kind) {
        case Kind.analog: lay.analogClock = false;
        case Kind.digital: lay.digitalClock = false;
        case Kind.date: lay.dateCard = false;
        case Kind.playing: lay.nowPlaying = false;
        case Kind.screen: lay.hiddenScreens.add(it.name);
        case Kind.app: lay.hiddenScreens.add(it.id!);
        default: if (it.id != null) lay.favorites = favorites()..remove(it.id);
      }
    } else if (!(lay.cards[g]?.remove(cardKeyOf(it)) ?? false) && !(lay.cards[g]?.remove(it.key) ?? false)) {
      lay.exclude = {...lay.exclude, g: [...?lay.exclude[g], it.key]};
    }
    final freed = lay.place[g]?.remove(it.key);
    lay.sizes[g]?.remove(it.key);
    if (pull && freed != null && freed.length == 3) _pullBack(g, freed[0]);
  }

  /// a card gone from page `pi` of a group: the cards of the page after it come back into the room it left, first
  /// come first (reading order), each at the free place nearest where it was; a page left empty goes, as on an
  /// iPhone's home screen.  Nothing moves on the pages before
  void _pullBack(String g, int pi) {
    final pl = lay.place[g];
    if (pl == null) return;
    final cols = _cols, rows = _rows;
    final grid = List.generate(rows, (_) => List.filled(cols, false));
    (int, int) wh(String k) { final it = _items[k]; return it == null ? (1, 1) : (it.w, it.h); }
    for (final e in pl.entries) {
      if (e.value.length != 3 || e.value[0] != pi) continue;
      final (w, h) = wh(e.key);
      for (var y = e.value[2]; y < min(rows, e.value[2] + h); y++) { for (var x = e.value[1]; x < min(cols, e.value[1] + w); x++) { grid[y][x] = true; } }
    }
    bool free(int c, int r, int w, int h) {
      if (c + w > cols || r + h > rows) return false;
      for (var y = r; y < r + h; y++) { for (var x = c; x < c + w; x++) { if (grid[y][x]) return false; } }
      return true;
    }
    final next = pl.entries.where((e) => e.value.length == 3 && e.value[0] == pi + 1).toList()
      ..sort((a, b) => (a.value[2] * cols + a.value[1]).compareTo(b.value[2] * cols + b.value[1]));
    for (final e in next) {
      final (w, h) = wh(e.key);
      (int, int)? best; var bd = 1 << 30;
      for (var y = 0; y + h <= rows; y++) { for (var x = 0; x + w <= cols; x++) {
        final d = y * cols + x;                                        // the first free place, reading order
        if (d < bd && free(x, y, w, h)) { bd = d; best = (x, y); }
      } }
      if (best == null) break;                                         // no room left: the rest stay, in order
      for (var y = best.$2; y < best.$2 + h; y++) { for (var x = best.$1; x < best.$1 + w; x++) { grid[y][x] = true; } }
      pl[e.key] = [pi, best.$1, best.$2];
    }
    // a page emptied: those after it one page earlier
    final used = (pl.values.where((v) => v.length == 3).map((v) => v[0]).toSet().toList()..sort());
    for (final v in pl.values) { if (v.length == 3) v[0] = used.indexOf(v[0]); }
  }

  /// a card onto a page: Home's own widgets on again or a favourite; elsewhere back if it was left out, else added
  /// "+ Add" on a page: the card onto that page (the free place nearest its top-left, else the pages after), not into
  /// the group's first gap somewhere before it.  `show`: a Home app's tile switched back on
  void _addHere(PageSpec pg, String key, {bool show = false}) {
    final g = pg.group;
    if (show) { lay.hiddenScreens.remove(key); } else { _addTo(g, key); }
    final it = cardItem(key);
    if (it != null && !(lay.place[g]?.containsKey(it.key) ?? false)) lay.place = {...lay.place, g: {...?lay.place[g], it.key: [pg.index, 0, 0]}};
  }

  void _addTo(String g, String key) {
    if (g == homeGroup) {
      switch (key) {
        case 'analog': lay.analogClock = true;
        case 'digital': lay.digitalClock = true;
        case 'date': lay.dateCard = true;
        case 'playing': lay.nowPlaying = true;
        default:
          if (key.startsWith('app:')) { lay.hiddenScreens.remove(key); }
          else if (ha.states.containsKey(key)) { lay.hidden.remove(key); if (!favorites().contains(key)) lay.favorites = [...favorites(), key]; }
      }
      return;
    }
    if (lay.exclude[g]?.remove(key) ?? false) return;
    lay.hidden.remove(key);
    final l = lay.cards[g] ?? [];
    if (!l.contains(key)) lay.cards = {...lay.cards, g: [...l, key]};
  }

  // ---------------------------------------------------------------- the owner's own pages

  void _newPage(Palette p) async {
    final name = await _askName(p, 'New page', 'Page ${lay.customPages.length + 1}');
    if (name == null || name.trim().isEmpty) return;
    final id = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    lay.customPages = [...lay.customPages, CustomPage(id, name.trim())];
    // after the page it is made on (Home: first after it)
    final cur = _lastPages.isEmpty ? homeGroup : _lastPages[page.clamp(0, _lastPages.length - 1)].group;
    final order = [for (final pg in _lastPages) if (pg.index == 0 && pg.group != homeGroup) pg.group];
    final at = cur == homeGroup ? 0 : order.indexOf(cur) + 1;
    lay.pageOrder = [...order]..insert(at.clamp(0, order.length), pageGroup(id));
    lay.changed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final i = _lastPages.indexWhere((pg) => pg.group == pageGroup(id));
      if (i >= 0 && pc.hasClients) pc.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  void _renamePage(Palette p, String g) async {
    final cp = lay.customPages.where((c) => pageGroup(c.id) == g).firstOrNull;
    if (cp == null) return;
    final name = await _askName(p, 'Rename page', cp.name);
    if (name == null || name.trim().isEmpty) return;
    cp.name = name.trim();
    lay.changed();
  }

  void _deletePage(String g) {
    lay.customPages = lay.customPages.where((c) => pageGroup(c.id) != g).toList();
    lay.cards.remove(g); lay.place.remove(g); lay.sizes.remove(g);
    lay.pageOrder = lay.pageOrder.where((x) => x != g).toList();
    lay.changed();
  }

  /// a name typed: on the Echo with the app's own keyboard (it has no input method), in the panel's preview with the
  /// computer's (a real text field)
  Future<String?> _askName(Palette p, String title, String initial) {
    final fg = p.text == Colors.white ? Colors.white : const Color(0xff1c1c1e);
    final text = TextEditingController(text: initial);
    var v = initial;
    return showDialog<String>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Material(type: MaterialType.transparency,
        child: SafeArea(child: Column(children: [
      Expanded(child: Center(child: Container(
        width: 420, padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
        decoration: BoxDecoration(color: _solid(p), borderRadius: BorderRadius.circular(22)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Padding(padding: const EdgeInsets.only(right: 8), child: widget.preview
              ? TextField(controller: text, autofocus: true, onChanged: (x) => v = x, onSubmitted: (x) => Navigator.of(ctx).pop(x),
                  style: TextStyle(color: fg, fontSize: 17))
              : Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(color: fg.withValues(alpha: .1), borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xff0a84ff), width: 1.5)),
                  child: Text(v, style: TextStyle(color: fg, fontSize: 17)))),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(widget.preview ? text.text : v), child: const Text('Save')),
          ]),
        ]),
      ))),
      if (!widget.preview) Keyboard(numbers: false, round: widget.round, onHide: () => Navigator.of(ctx).pop(v),
          onText: (x) => set(() => v += x), onBackspace: () => set(() { if (v.isNotEmpty) v = v.substring(0, v.length - 1); }),
          onEnter: () => Navigator.of(ctx).pop(v)),
    ]))))).whenComplete(text.dispose);
  }

  /// the edit mode's dialogs: solid (the palette's sheet is glass, made for a backdrop behind it; over the busy
  /// WallView its words were lost)
  Color _solid(Palette p) => p.text == Colors.white ? const Color(0xf71c1c1e) : const Color(0xf7f2f2f7);

  void _clearPage(List<PageSpec> ps, Palette p) {
    if (page >= ps.length || ps[page].placed.isEmpty) return;
    final pg = ps[page], n = pg.placed.length;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: _solid(p),
      title: Text('Clear this page?', style: TextStyle(color: p.text)),
      content: Text(pg.group == homeGroup ? 'Its $n widget${n == 1 ? '' : 's'} come off Home. “+ Add” brings any of them back.'
          : 'Its $n card${n == 1 ? '' : 's'} come off this page, on this Echo only. “+ Add” brings any of them back.', style: TextStyle(color: p.dim)),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () {
          // every card of the group kept where it is first: those without a place would flow into the emptied page
          _commit(pg.group);
          for (final (it, _, _) in pg.placed) { _removeFrom(pg.group, it, pull: false); }   // emptied, not refilled
          lay.changed();
          Navigator.of(ctx).pop();
        }, child: const Text('Clear', style: TextStyle(color: Color(0xffff453a), fontWeight: FontWeight.w700))),
      ],
    ));
  }

  /// what can go on Home: its own widgets that are off, then every device, cameras first, then by room (those on
  /// Home already left out); a search over names and rooms, typed on the app's own keyboard (the Echo has no input
  /// method), and a scrollbar that says there is more
  void _addSheet(Palette p, PageSpec pg) {
    final g = pg.group, home = g == homeGroup;
    final there = (_spotsOf[g] ?? const <String, Spot>{}).keys.toSet();
    final text = TextEditingController();
    var q = '';
    var kb = false;
    final scroll = ScrollController();
    final fg = p.text == Colors.white ? Colors.white : const Color(0xff1c1c1e);
    showDialog(context: context, barrierColor: const Color(0x66000000), builder: (ctx) => StatefulBuilder(builder: (ctx, set) =>
        ListenableBuilder(listenable: Listenable.merge([lay, ha]), builder: (ctx, _) {
      final needle = q.trim().toLowerCase();
      bool match(String text) => needle.isEmpty || text.toLowerCase().contains(needle);
      final own = <(String, VoidCallback)>[
        if (home) ...[
          if (!lay.analogClock) ('Analog clock', () => lay.analogClock = true),
          if (!lay.digitalClock) ('Digital clock', () => lay.digitalClock = true),
          if (!lay.dateCard) ('Date & weather', () => lay.dateCard = true),
          if (!lay.nowPlaying) ('Now Playing', () => lay.nowPlaying = true),
          for (final s in widget.screens) if (lay.hiddenScreens.contains(s)) (s, () => lay.hiddenScreens.remove(s)),
        ] else ...[
          // the WallView's own cards go on any page (one of each a page)
          for (final (k, name) in const [('analog', 'Analog clock'), ('digital', 'Digital clock'), ('date', 'Date & weather'), ('playing', 'Now Playing')])
            if (!there.contains(k)) (name, () => _addHere(pg, k)),
        ],
        for (final a in widget.apps)
          if (home ? lay.hiddenScreens.contains(a.key) : !there.contains(a.key)) (a.label, () => home ? _addHere(pg, a.key, show: true) : _addHere(pg, a.key)),
        // what was taken off this page from what it has by itself (a dashboard's card)
        if (!home) for (final k in lay.exclude[g] ?? const <String>[])
          if (k.startsWith('card:')) ('${k.split(':')[1].replaceAll('-', ' ')} (dashboard)', () => _addHere(pg, k)),
      ].where((e) => match(e.$1)).toList();
      final onHome = home ? favorites().toSet() : there;
      bool can(String id) {
        final d = domainOf(id);
        if (onHome.contains(id) || ha.hiddenByHa.contains(id)) return false;
        if (d == 'binary_sensor') return sensorClasses.contains(ha.states[id]!.attr['device_class']);
        return tileDomains.contains(d) || d == 'scene' || d == 'script' || d == 'camera';
      }
      // cameras first (a camera added again in Home Assistant is a new entity, looked for here), then by room
      final byRoom = <String, List<String>>{};
      for (final id in ha.states.keys.where(can)) {
        final room = ha.areaName(ha.areaOf(id));
        if (!match('${nameIn(ha, id, null)} $room $id')) continue;
        byRoom.putIfAbsent(domainOf(id) == 'camera' ? '\u0000Cameras' : room, () => []).add(id);
      }
      final rooms = byRoom.keys.toList()..sort((a, b) => a.isEmpty ? 1 : b.isEmpty ? -1 : a.compareTo(b));
      final rows = <Widget>[
        if (own.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (name, on) in own) ActionChip(label: Text('+ $name'), onPressed: () { on(); lay.changed(); }),
        ])),
        for (final r in rooms) ...[
          Padding(padding: const EdgeInsets.only(top: 14, bottom: 2), child: Text(r.isEmpty ? 'Other' : r.replaceFirst('\u0000', ''),
              style: TextStyle(color: p.dim, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .4))),
          for (final id in (byRoom[r]!..sort((a, b) => nameIn(ha, a, r).compareTo(nameIn(ha, b, r)))))
            ListTile(dense: true, contentPadding: EdgeInsets.zero,
                title: Text(nameIn(ha, id, r.startsWith('\u0000') ? null : r), style: TextStyle(color: fg, fontSize: 15)),
                subtitle: lay.hidden.contains(id) ? Text('hidden', style: TextStyle(color: p.dim, fontSize: 12)) : null,
                trailing: const Icon(Icons.add_circle, color: Color(0xff30d158)),
                onTap: () { _addHere(pg, id); lay.changed(); }),
        ],
        if (own.isEmpty && rooms.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(needle.isEmpty ? 'Everything is on Home already.' : 'Nothing called “$q”.', style: TextStyle(color: p.dim))),
      ];
      final search = widget.preview ? TextField(controller: text, autofocus: true, onChanged: (v) => set(() => q = v),
          style: TextStyle(color: fg, fontSize: 15),
          decoration: InputDecoration(isDense: true, filled: true, fillColor: fg.withValues(alpha: .1), hintText: 'Search devices and widgets',
              hintStyle: TextStyle(color: p.dim), prefixIcon: Icon(CupertinoIcons.search, color: p.dim, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))) : GestureDetector(
        onTap: () => set(() => kb = true),
        child: Container(
          height: 40, padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(color: fg.withValues(alpha: .1), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kb ? const Color(0xff0a84ff) : Colors.transparent, width: 1.5)),
          child: Row(children: [
            Icon(CupertinoIcons.search, color: p.dim, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(q.isEmpty ? 'Search devices and widgets' : q, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: q.isEmpty ? p.dim : fg, fontSize: 15))),
            if (q.isNotEmpty) GestureDetector(onTap: () => set(() => q = ''),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Icon(CupertinoIcons.xmark_circle_fill, color: p.dim, size: 18))),
          ]),
        ),
      );
      final card = Container(
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(color: _solid(p), borderRadius: BorderRadius.circular(24),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30)]),
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Add to ${pg.name}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w700))),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Done')),
          ]),
          Padding(padding: const EdgeInsets.only(right: 8, bottom: 4), child: search),
          Expanded(child: RawScrollbar(controller: scroll, thumbVisibility: true, thickness: 4, radius: const Radius.circular(2),
              thumbColor: fg.withValues(alpha: .45), child: ListView.builder(
              controller: scroll, padding: const EdgeInsets.only(right: 14, bottom: 8),
              itemCount: rows.length, itemBuilder: (_, i) => rows[i]))),
        ]),
      );
      return Material(type: MaterialType.transparency, child: SafeArea(child: Column(children: [
        Expanded(child: Padding(padding: EdgeInsets.fromLTRB(16, kb ? 8 : 24, 16, kb ? 6 : 24), child: Center(child: card))),
        if (kb) Keyboard(numbers: false, round: widget.round, onHide: () => set(() => kb = false),
            onText: (s) => set(() => q += s),
            onBackspace: () => set(() { if (q.isNotEmpty) q = q.substring(0, q.length - 1); }),
            onEnter: () => set(() => kb = false)),
      ])));
    }))).then((_) { scroll.dispose(); text.dispose(); });
  }

  /// a page as a drop target: the dragged widget goes to the cell its top-left corner is nearest to (anywhere, a
  /// gap too), and stays there; a widget that was there takes the dragged one's old place, or the nearest free one on
  /// its page.  Held at the screen's left or right edge, the page turns, to any page: another room's, Home, a page of
  /// one's own (a dashboard's card stays in its section, a screen's tile on Home); an empty page waits after the last of
  /// the card's own group (a new page for it there).  One target per page, not one per widget: widgets moving under the finger made
  /// per-widget targets swap back and forth
  Widget _grid(List<PageSpec> ps, int i, int cols, int rows, double stepX, double stepY, Widget child) {
    final page = ps[i], g = page.group;
    return DragTarget<String>(
      // by the group's widgets too, not only by `dragging`: a drag enters its own page before onDragStarted has run
      onWillAcceptWithDetails: (d) => (_spotsOf[g]?.containsKey(d.data) ?? false)
          || (dragging == d.data && _dragItem != null && _dragOrigin != null && _canGo(_dragItem!, g, _dragOrigin!)),
      onMove: (d) {
        if (dragging != d.data) return;
        _dragTopLeft = d.offset;
        _over(page, stepX, stepY);
        // the edges: the page before or after, once held there a moment
        final finger = d.offset + (_dragHalf[d.data] ?? Offset.zero), w = MediaQuery.sizeOf(context).width;
        final dir = finger.dx < 28 ? -1 : finger.dx > w - 28 ? 1 : 0;
        if (dir != _edgeDir) { _edgeFlip?.cancel(); _edgeFlip = null; _edgeDir = dir; }   // the other edge: its own wait
        if (dir == 0) return;
        _edgeFlip ??= Timer(const Duration(milliseconds: 600), () {
          _edgeFlip = null;
          final ps = _lastPages, to = this.page + dir;
          if (dragging == null || to < 0 || to >= ps.length) return;
          // past pages the card cannot go to (another dashboard section for a dashboard's card): to the next it can
          var t = to;
          while (t >= 0 && t < ps.length && _dragItem != null && _dragOrigin != null && !_canGo(_dragItem!, ps[t].group, _dragOrigin!)) { t += dir; }
          if (t >= 0 && t < ps.length) {
            // while the pages slide Flutter's scrollable takes no pointer, and a finger held still sends none after: the
            // card is over the page it came to as soon as it is there, without waiting for the finger to move
            pc.animateToPage(t, duration: const Duration(milliseconds: 300), curve: Curves.easeOut).then((_) {
              if (dragging == null || !mounted) return;
              final now = _lastPages, at = this.page.clamp(0, now.length - 1);
              if (now.isNotEmpty) _over(now[at], _stepX, _stepY);
            });
          }
        });
      },
      onAcceptWithDetails: (_) => _drop(),
      builder: (context, _, _) => child,
    );
  }
  int _edgeDir = 0;                             // which edge the finger is at (-1, 0, 1)
  Offset? _dragTopLeft;                         // the lifted card's top-left on the screen, as last told
  double _stepX = 1, _stepY = 1;                // a cell and its gap, from the last build

  /// the dragged card over a page: the cell its top-left is nearest to; over another group's page, that group live
  /// from where its cards are now (back over its own, from where they were when the drag began)
  void _over(PageSpec page, double stepX, double stepY) {
    final g = page.group, key = dragging, at = _dragTopLeft;
    final box = _gridBox['$g/${page.index}'], it = _dragItem ?? (key == null ? null : _itemOf(key));
    if (key == null || at == null || box == null || !box.attached || it == null) return;
    if (_dragOrigin != null && !_canGo(it, g, _dragOrigin!)) return;
    final topLeft = box.globalToLocal(at);
    final c = (topLeft.dx / stepX).round().clamp(0, max(0, _cols - it.w)).toInt(), r = (topLeft.dy / stepY).round().clamp(0, max(0, _rows - it.h)).toInt();
    final to = (page.index, c, r);
    if (liveArea != g) {
      final back = g == _dragOrigin;
      setState(() {
        liveArea = g;
        startSpots = back ? Map.of(_originSpots ?? const {}) : (Map.of(_spotsOf[g] ?? const {})..remove(key));
        dragFrom = back ? (_originSpots?[key]) : null;
        dragAt = to;
      });
    } else if (to != dragAt) {
      setState(() => dragAt = to);
    }
  }

  final _gridBox = <String, RenderBox>{};
  final _dragKeys = <String, GlobalKey>{};
  final _items = <String, Item>{};              // the dragged one's item (its size), from the last pages()
  Item? _itemOf(String key) => _items[key];
  final _dragHalf = <String, Offset>{};

  /// the drop: every widget of the group where it is now, kept (empty pages between taken out)
  /// every card of a group kept where it is now, the empty pages between taken out (saved with the next save)
  void _commit(String g) {
    final spots = _spotsOf[g] ?? const {};
    final used = (spots.values.map((s) => s.$1).toSet().toList()..sort());
    lay.place = {...lay.place, g: {for (final e in spots.entries) e.key: [used.indexOf(e.value.$1), e.value.$2, e.value.$3]}};
  }

  void _drop() {
    final g = liveArea, from = _dragOrigin, it = _dragItem, key = dragging;
    if (key == null || g == null) return;
    if (from != null && from != g && it != null) {
      // onto another group's page: it leaves its own (its size with it), joins this one where it was let go
      final size = lay.sizes[from]?[it.key];
      final here = _spotsOf[g] ?? const {}, there = {...?_spotsOf[from]}..remove(key);
      _spotsOf[from] = {...there, key: ?_originSpots?[key]};
      _commit(from);                            // its own page as it was, then without it (_removeFrom pulls the next page back)
      _removeFrom(from, it);
      _addTo(g, cardKeyOf(it));
      if (size != null) lay.sizes = {...lay.sizes, g: {...?lay.sizes[g], it.key: size}};
      _spotsOf[g] = here;
    }
    _commit(g);
    _edgeFlip?.cancel(); _edgeFlip = null;
    setState(() { dragging = null; liveArea = null; startSpots = null; dragFrom = null; dragAt = null;
      _dragOrigin = null; _dragItem = null; _originSpots = null; _edgeDir = 0; });
    lay.changed();
  }

  // the arrows and Done at the ends, always on the screen; what is between scrolls where it does not fit (a room's
  // page has more: Clear page, Remove page)
  Widget _bar(List<PageSpec> ps, Palette p) {
    final cur = ps[page.clamp(0, ps.length - 1)];
    return Positioned(top: 8, left: 8, right: 8, child: Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xe01c1c1e), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _pill('‹', () => pc.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)),
          Flexible(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final w in Wallpaper.values)
              GestureDetector(onTap: () { lay.wallpaper = w; lay.changed(); }, child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4), width: 30, height: 30,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: Palette.of(w).wall,
                      border: Border.all(color: lay.wallpaper == w ? Colors.white : Colors.transparent, width: 2)))),
            _pill('+ Add', () => _addSheet(p, cur)),
            _pill('+ Page', () => _newPage(p)),
            if (cur.group.startsWith('page:')) ...[
              _pill('Rename', () => _renamePage(p, cur.group)),
              _pill('Delete page', () => _deletePage(cur.group)),
            ] else ...[
              _pill('Clear page', () => _clearPage(ps, p)),
              if (cur.group != homeGroup) _pill('Remove page', () { lay.hiddenPages = {...lay.hiddenPages, cur.group}; lay.changed(); }),
            ],
            _pill(lay.hidden.isEmpty ? 'Hidden' : 'Hidden (${lay.hidden.length})', () => _hiddenSheet(p)),
            _pill('Reset', lay.reset),
          ]))),
          _pill('Done', () => edit(false), primary: true),
          _pill('›', () => pc.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)),
        ]),
      )));
  }

  Widget _pill(String s, VoidCallback f, {bool primary = false}) => GestureDetector(onTap: f, child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: primary ? Colors.white : const Color(0x24ffffff), borderRadius: BorderRadius.circular(999)),
        child: Text(s, style: TextStyle(color: primary ? const Color(0xff1c1c1e) : Colors.white, fontWeight: FontWeight.w600, fontSize: 14))));

  void _hiddenSheet(Palette p) => showDialog(context: context, builder: (ctx) => ListenableBuilder(listenable: lay, builder: (ctx, _) => Dialog(
        backgroundColor: _solid(p), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420), child: ListView(padding: const EdgeInsets.all(20), shrinkWrap: true, children: [
          Text('Hidden', style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w700)),
          Text(lay.hidden.isEmpty ? 'Nothing hidden: tap − on a tile to hide it.' : 'Tap one to show it again.', style: TextStyle(color: p.dim)),
          for (final id in lay.hidden.toList())
            ListTile(title: Text(nameIn(ha, id, null), style: TextStyle(color: p.text)), onTap: () { lay.hidden.remove(id); lay.changed(); }),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Done')),
        ])),
      )));

  Widget _dots(List<PageSpec> ps, Palette p) => Positioned(left: 0, right: 0, bottom: 0, height: 22, child: Center(child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => edit(!editing),          // hold the dots: edit
        // a tap left or right of the lit dot: a page that way, as an iPhone's dots (and a mouse's way in the panel)
        onTapUp: (d) {
          final row = (context.findRenderObject() as RenderBox?);
          if (row == null) return;
          final mid = row.size.width / 2, x = row.globalToLocal(d.globalPosition).dx;
          (x < mid ? pc.previousPage : pc.nextPage)(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        },
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: AnimatedBuilder(animation: pc, builder: (_, _) {
          final at = pc.hasClients && pc.positions.length == 1 && pc.page != null ? pc.page!.round() : page;   // the page under the scroll, as it moves
          return Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < ps.length; i++)
              Container(margin: const EdgeInsets.symmetric(horizontal: 3), width: 6, height: 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.dim.withValues(alpha: i == at ? 1 : .45))),
          ]);
        })),
      )));
}

/// builds again on every minute's turn
class TickerBuilder extends StatefulWidget {
  final Widget Function(DateTime) builder;
  const TickerBuilder({super.key, required this.builder});
  @override
  State<TickerBuilder> createState() => _TickerBuilderState();
}

class _TickerBuilderState extends State<TickerBuilder> {
  Timer? _t;
  @override
  void initState() { super.initState(); _arm(); }
  void _arm() {
    final n = DateTime.now();
    _t = Timer(Duration(seconds: 60 - n.second), () { if (mounted) { setState(() {}); _arm(); } });
  }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => widget.builder(DateTime.now());
}

/// hands its render box to the page's drop target (where the finger is, in the grid's own coordinates)
/// a card's hold, as an iPhone's: half a second, its menu (onMenu, with where the card is); held on to 1.3 s without
/// moving, the edit mode (onEdit).  A Listener for the second part: the menu's route takes the gestures, but a pointer's
/// moves and its lift still reach where it went down
class _Hold extends StatefulWidget {
  final Widget child;
  final void Function(Rect) onMenu;
  final VoidCallback onEdit;
  const _Hold({required this.child, required this.onMenu, required this.onEdit});
  @override
  State<_Hold> createState() => _HoldState();
}

class _HoldState extends State<_Hold> {
  Timer? _t;
  Offset _down = Offset.zero;
  @override
  void dispose() { _t?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (e) { _down = e.position; _t?.cancel(); _t = Timer(const Duration(milliseconds: 1300), () { if (mounted) widget.onEdit(); }); },
        onPointerMove: (e) { if ((e.position - _down).distance > 12) _t?.cancel(); },
        onPointerUp: (_) => _t?.cancel(),
        onPointerCancel: (_) => _t?.cancel(),
        child: GestureDetector(
          onLongPressStart: (_) {
            final b = context.findRenderObject() as RenderBox?;
            if (b != null && b.attached) widget.onMenu(b.localToGlobal(Offset.zero) & b.size);
          },
          child: widget.child,
        ),
      );
}

class _GridBox extends SingleChildRenderObjectWidget {
  final void Function(RenderBox) onBox;
  const _GridBox({required this.onBox, super.child});
  @override
  RenderProxyBox createRenderObject(BuildContext context) { final b = RenderProxyBox(); onBox(b); return b; }
  @override
  void updateRenderObject(BuildContext context, RenderProxyBox b) => onBox(b);
}
