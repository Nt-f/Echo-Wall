// The HomeView: pages of square glass widgets over a wallpaper, swiped sideways.  Home first (the clocks, the date and
// weather, the favourites: a thermostat big, a camera, scenes, locks; what plays; the app's other screens), then a page
// per room (Home Assistant's areas).  Hold the page dots to edit: the widgets wobble, a drag moves one, ★ puts it on
// Home, − hides it; the bar picks the wallpaper.  Left alone, the ambient clock.
import 'dart:async';
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
import '../hassmic.dart' show EchoState;
import '../keyboard.dart';
import 'widgets.dart';

enum Kind { analog, digital, date, thermo, playing, camera, tile, screen }

class Item {
  final Kind kind;
  final String? id;                             // the entity (not for the clocks, the date, the screens)
  final String? room;                           // a tile on Home shows its room under its name
  final int screen;                             // Kind.screen: the app's screen index
  final String name;
  final int size;                               // Kind.playing: 4 = 2 x 2, 2 = 2 x 1, 1 = a cell (what fits on Home's first page)
  const Item(this.kind, {this.id, this.room, this.screen = -1, this.name = '', this.size = 4});
  int get w => kind == Kind.playing ? (size == 1 ? 1 : 2) : kind == Kind.thermo || kind == Kind.digital ? 2 : 1;
  int get h => kind == Kind.playing ? (size == 4 ? 2 : 1) : kind == Kind.thermo ? 2 : 1;
  String get key => kind == Kind.playing ? 'playing' : id ?? '${kind.name}$screen';   // the media card: one place, whichever player
}

class PageSpec {
  final String name, sub;
  final String? area;                           // null: Home
  final List<(Item, int col, int row)> placed;
  final int index;                              // which of its group's pages (the positions' page number)
  const PageSpec(this.name, this.sub, this.area, this.placed, {this.index = 0});
}

/// where a widget was put: page, column, row
typedef Spot = (int page, int col, int row);

/// items into pages.  Those with a spot of their own (`fixed`: where they were put) go there first, `first` (the one
/// being dragged) before all; one whose spot is taken goes to `swapTo` (where the dragged one came from: the two swap)
/// if it fits there; the rest each at the first free place it fits, on the first page with room for it (a big one that
/// does not fit where it comes leaves its gap to the small ones after it), else on a new page.  `extra`: an empty page
/// after the last (to drag a widget onto).  Every page up to the last one used is returned, empty ones included.
List<PageSpec> pack(String name, String sub, String? area, List<Item> items, int cols, int rows,
    {Map<String, Spot> fixed = const {}, String? first, Spot? swapTo, bool extra = false}) {
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
  final fitting = items.where((it) => it.w <= cols && it.h <= rows).toList();   // bigger than a page: left out
  final done = <String>{};
  // the dragged one where the finger is, then those that were put somewhere
  for (final it in [...fitting.where((it) => it.key == first), ...fitting.where((it) => it.key != first)]) {
    if (fixed.containsKey(it.key) && at(it, fixed[it.key])) done.add(it.key);
  }
  var swapped = false;
  for (final it in fitting) {
    if (done.contains(it.key)) continue;
    if (fixed.containsKey(it.key) && !swapped && swapTo != null && at(it, swapTo)) { swapped = true; done.add(it.key); continue; }
    var ok = false;
    for (var pi = 0; !ok; pi++) {
      page(pi);
      for (var r = 0; r < rows && !ok; r++) {
        for (var c = 0; c < cols && !ok; c++) {
          if (fits(it, pi, c, r)) { put(it, pi, c, r); ok = true; }
        }
      }
    }
  }
  var last = placed.lastIndexWhere((pl) => pl.isNotEmpty);
  if (extra) last++;
  if (last < 0) return [PageSpec(name, sub, area, const [])];
  page(last);
  return [for (var i = 0; i <= last; i++) PageSpec(name, sub, area, placed[i], index: i)];
}

class HomeView extends StatefulWidget {
  final Ha ha;
  final Layout layout;
  final bool h24;
  final List<String> screens;                   // the app's other screens (Home Assistant's UI, Music Assistant)
  final void Function(int) onScreen;
  final Map<String, String> settings;           // the integration's screen app settings (immich.*, photos.minutes)
  final bool round;                             // an Echo Spot: the widgets inside the circle's square
  final EchoState? echo;                        // hassmic's: a request, a ring (drawn here on the glass)
  final String nextAlarm;
  const HomeView({super.key, required this.ha, required this.layout, required this.h24, required this.screens, required this.onScreen,
      this.settings = const {}, this.nextAlarm = '', this.round = false, this.echo});
  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with TickerProviderStateMixin, WidgetsBindingObserver {
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

  int? ambientOverride;                         // debug.hassmic.ambient (screenshots)

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
    const MethodChannel('hassmic/keys').invokeMethod<String>('prop', 'debug.hassmic.ambient').then((v) {
      final n = int.tryParse(v ?? '');
      if (n != null && n > 0) ambientOverride = n;
    }).catchError((_) {});
    idle = Timer.periodic(const Duration(seconds: 5), (_) {
      final s = ambientOverride ?? lay.ambientSeconds;
      if (s > 0 && !ambient && !editing && DateTime.now().difference(touched).inSeconds >= s && ModalRoute.of(context)?.isCurrent != false) {
        setState(() => ambient = true);
      }
    });
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); idle?.cancel(); _wallTimer?.cancel(); _edgeFlip?.cancel(); wobble.dispose(); pc.dispose(); backdrop.dispose(); super.dispose(); }

  void edit(bool on) {
    setState(() { editing = on; ambient = false; });
    on ? wobble.repeat(reverse: true) : wobble.stop();
  }

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
    final ho = lay.homeOrder;
    if (ho.isNotEmpty) {                        // as moved (List.sort is not stable: ties keep their index)
      final idx = {for (var i = 0; i < home.length; i++) home[i].key: i};
      int at(Item it) { final i = ho.indexOf(it.key); return i < 0 ? (1 << 20) + idx[it.key]! : i; }
      home.sort((a, b) => at(a).compareTo(at(b)));
    }
    // the media card on Home's first page: as big as there is room for there (the owner's widgets keep their places),
    // unless it was put on another page; while a widget is dragged, the size it had
    List<Item> sized(int n) => [for (final it in home) it.kind == Kind.playing ? Item(Kind.playing, id: it.id, size: n) : it];
    final putAt = lay.place['home']?['playing']?.first ?? 0;
    final sizes = player == null || (dragging != null && liveArea == 'home') ? [_playSize] : putAt > 0 ? const [4] : const [4, 2, 1];
    for (final n in sizes) {
      final hp = _pack('Home', '', null, sized(n), cols, rows);
      _playSize = n;
      if (n == sizes.last || hp.first.placed.any((e) => e.$1.kind == Kind.playing)) { out.addAll(hp); break; }
    }

    final byArea = <String, List<String>>{};
    for (final id in ha.states.keys) {
      if (!shown(ha, lay, id)) continue;
      byArea.putIfAbsent(ha.areaOf(id) ?? '', () => []).add(id);
    }
    final rooms = [...ha.areas.where((a) => byArea.containsKey(a.id)).map((a) => (a.id, a.name)), if (byArea.containsKey('')) ('', 'Other')];
    for (final (area, name) in rooms) {
      final own = lay.order[area] ?? const [];
      int at(String id) { final i = own.indexOf(id); return i < 0 ? 1 << 20 : i; }
      int kind(String id) { final d = domainOf(id); return d == 'scene' || d == 'script' ? -1 : tileDomains.indexOf(d); }
      final ids = byArea[area]!..sort((a, b) {
        final c = at(a).compareTo(at(b));
        if (c != 0) return c;
        final k = kind(a).compareTo(kind(b));
        return k != 0 ? k : nameIn(ha, a, name).compareTo(nameIn(ha, b, name));
      });
      out.addAll(_pack(name, roomSummary(ha, area), area, ids.map((id) => itemOf(id)).toList(), cols, rows));
    }
    return out;
  }

  /// a page group packed: each widget where it was put (the layout's places), the one being dragged where the finger
  /// has it; what was where it goes to where it came from; the rest flows into free places.  Where everything ended up
  /// is kept (_spotsOf): a drag starts from it, a drop saves it
  List<PageSpec> _pack(String name, String sub, String? area, List<Item> items, int cols, int rows) {
    final g = _gk(area), live = dragging != null && liveArea == g;
    final saved = {for (final e in (lay.place[g] ?? const <String, List<int>>{}).entries) if (e.value.length == 3) e.key: (e.value[0], e.value[1], e.value[2])};
    final fixed = live ? {...startSpots!, dragging!: ?dragAt} : saved;
    final ps = pack(name, sub, area, items, cols, rows, fixed: fixed, first: live ? dragging : null,
        swapTo: live && dragAt != null ? dragFrom : null, extra: live);
    _spotsOf[g] = {for (final pg in ps) for (final (it, c, r) in pg.placed) it.key: (pg.index, c, r)};
    for (final it in items) { _items[it.key] = it; }
    return ps;
  }
  final _spotsOf = <String, Map<String, Spot>>{};
  int _playSize = 4;

  // ---------------------------------------------------------------- drawing

  @override
  Widget build(BuildContext context) {
    // the palette and the wallpaper inside the layout's builder: a theme picked in edit mode shows at once (in build()
    // above it they changed only once the HomeView itself was built again, at Done)
    return BackdropScope(backdrop: backdrop, child: ListenableBuilder(listenable: Listenable.merge([ha, lay]), builder: (context, _) {
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
          if (page >= ps.length) page = ps.length - 1;
          return Stack(children: [
            // no repaint boundary per page (PageView.builder adds one): the glass draws its piece of the blurred
            // wallpaper from where it is on the screen when painted, and a page kept as a layer from a paint off to the
            // side (or half swiped in) slid in later with that piece: clear glass, no blur.  Without them each frame
            // of a swipe paints the page again, the glass at its true place (drawing the glass is copying a picture)
            PageView.custom(
              controller: pc,
              physics: editing ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(parent: PageScrollPhysics()),
              onPageChanged: (i) => setState(() => page = i),
              childrenDelegate: SliverChildBuilderDelegate(childCount: ps.length, addRepaintBoundaries: false, (context, i) => _grid(ps, i, cols, rows, cw + gap, cell + gap, Padding(
                padding: EdgeInsets.fromLTRB(pad, pad + (editing ? 44 : 0), pad, bottom),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(height: header, child: _header(ps[i], p, small)),
                  Expanded(child: _GridBox(onBox: (b) => _gridBox['${_gk(ps[i].area)}/${ps[i].index}'] = b, child: Stack(children: [
                  for (final (it, c, r) in ps[i].placed)
                    AnimatedPositioned(
                      key: ValueKey('${ps[i].area}/${it.key}'),
                      duration: const Duration(milliseconds: 220), curve: Curves.easeOut,
                      left: c * (cw + gap), top: r * (cell + gap),
                      width: it.w * cw + (it.w - 1) * gap, height: it.h * cell + (it.h - 1) * gap,
                      child: _editable(ps[i], it, p, cell, _widget(it, p, cell)),
                    ),
                  ]))),
                ]),
              ))),
            ),
            if (ps.isNotEmpty) _dots(ps, p),
            if (editing) _bar(ps, p),
            if (ps.length == 1 && ha.areas.isEmpty && ha.connected)
              Center(child: Text('Give your devices areas in Home Assistant:\nthe HomeView shows them room by room.',
                  textAlign: TextAlign.center, style: TextStyle(color: p.text, fontSize: 16))),
            if (!ha.connected)
              Positioned(left: 0, right: 0, top: 6, child: Center(child: Text(ha.error ?? 'Connecting to Home Assistant…',
                  style: TextStyle(color: p.dim, fontSize: 12)))),
          ]);
        }))),
        // resting: the lock screen over the HomeView, lifted off by a swipe up
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

  Widget _widget(Item it, Palette p, double cell) {
    void more() => showDetail(context, ha, p, it.id!, backdrop);
    return switch (it.kind) {
      Kind.analog => AnalogClockCard(p: p, cell: cell),
      Kind.digital => DigitalClockCard(p: p, cell: cell, h24: widget.h24, wide: true),
      Kind.date => Press(onTap: () => showWeather(context, ha, p, backdrop), child: DateWeatherCard(ha: ha, p: p, cell: cell)),
      Kind.thermo => ThermostatCard(ha: ha, p: p, id: it.id!, cell: cell, onLong: more),
      Kind.playing => NowPlayingCard(ha: ha, p: p, id: it.id!, cell: cell, size: it.size, onLong: more),
      // live under the lock screen too, so that it is there the moment the screen is woken (a stream started then took
      // seconds: Home Assistant's HLS, the decoder); off only with the screen or in edit mode (the lifted copy would
      // start a second one)
      Kind.camera => CameraCard(ha: ha, p: p, id: it.id!, cell: cell, live: resumed && !editing),
      Kind.screen => ScreenTile(p: p, name: it.name, cell: cell, onTap: () => widget.onScreen(it.screen)),
      Kind.tile => AccessoryTile(ha: ha, p: p, id: it.id!, room: it.room, cell: cell, onLong: more),
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
    if (!editing) return w;
    final id = it.id;
    final onHome = page.area == null;
    final fav = favorites();
    final body = AnimatedBuilder(
      animation: wobble,
      builder: (_, child) => Transform.rotate(angle: (wobble.value - .5) * .024 * (it.key.hashCode.isEven ? 1 : -1), child: child),
      child: AbsorbPointer(child: w),           // nothing of the widget's own while editing
    );
    Widget badge(String s, Color bg, Color fg, VoidCallback f, {required bool left}) => Positioned(
          left: left ? 4 : null, right: left ? null : 4, top: 4,
          child: GestureDetector(onTap: f, child: Container(width: 30, height: 30, alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6)]),
              child: Text(s, style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w700, height: 1)))),
        );
    final key = it.key;
    final draggable = LayoutBuilder(builder: (context, box) => Draggable<String>(
      key: _dragKeys.putIfAbsent('${_gk(page.area)}/$key', GlobalKey.new),   // kept when it moves to another page
      data: key,
      // the finger at the tile's middle, the tile at its own size, lifted
      dragAnchorStrategy: (d, context, position) => Offset(box.maxWidth / 2, box.maxHeight / 2),
      // the lifted copy is drawn in the Overlay, outside the HomeView: its glass needs the backdrop handed on
      feedback: BackdropScope(backdrop: backdrop, child: SizedBox(width: box.maxWidth, height: box.maxHeight,
          child: Transform.scale(scale: 1.06, child: Opacity(opacity: .92, child: Material(color: Colors.transparent, child: w))))),
      childWhenDragging: Opacity(opacity: .25, child: body),
      onDragStarted: () {
        HapticFeedback.selectionClick();
        _dragHalf[key] = Offset(box.maxWidth / 2, box.maxHeight / 2);
        final g = _gk(page.area);
        setState(() {
          dragging = key; liveArea = g;
          startSpots = Map.of(_spotsOf[g] ?? const {});
          dragFrom = startSpots![key]; dragAt = dragFrom;
        });
      },
      onDragEnd: (_) => _drop(),
      child: body,
    ));
    return Builder(
      builder: (_) => Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: draggable),
        if (id != null && !onHome) badge('★', Colors.white, fav.contains(id) ? const Color(0xfff5a623) : const Color(0xffb8b8b8), () {
          lay.favorites = fav.contains(id) ? (fav..remove(id)) : [...fav, id];
          lay.changed();
        }, left: true),
        badge('−', const Color(0xffff453a), Colors.white, () { _remove(it, page.area); lay.changed(); }, left: false),
      ]),
    );
  }

  /// a widget off its page: Home's own (clocks, date, media card, a screen's) switched off, a device off Home's
  /// favourites, or in a room hidden (the Hidden list has it); its place forgotten.  "+ Add" brings any of them back
  void _remove(Item it, String? area) {
    switch (it.kind) {
      case Kind.analog: lay.analogClock = false;
      case Kind.digital: lay.digitalClock = false;
      case Kind.date: lay.dateCard = false;
      case Kind.playing: lay.nowPlaying = false;
      case Kind.screen: lay.hiddenScreens.add(it.name);
      default:
        final id = it.id!;
        if (area == null) { lay.favorites = favorites()..remove(id); } else { lay.hidden.add(id); lay.favorites?.remove(id); }
    }
    lay.place[_gk(area)]?.remove(it.key);
  }

  /// the edit mode's dialogs: solid (the palette's sheet is glass, made for a backdrop behind it; over the busy
  /// HomeView its words were lost)
  Color _solid(Palette p) => p.text == Colors.white ? const Color(0xf71c1c1e) : const Color(0xf7f2f2f7);

  void _clearPage(List<PageSpec> ps, Palette p) {
    if (page >= ps.length || ps[page].placed.isEmpty) return;
    final pg = ps[page], n = pg.placed.length;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: _solid(p),
      title: Text('Clear this page?', style: TextStyle(color: p.text)),
      content: Text(pg.area == null ? 'Its $n widget${n == 1 ? '' : 's'} come off Home. “+ Add” brings any of them back.'
          : 'Its $n device${n == 1 ? '' : 's'} are hidden. “Hidden” shows them again.', style: TextStyle(color: p.dim)),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () {
          for (final (it, _, _) in pg.placed) { _remove(it, pg.area); }
          lay.changed();
          Navigator.of(ctx).pop();
        }, child: const Text('Clear', style: TextStyle(color: Color(0xffff453a), fontWeight: FontWeight.w700))),
      ],
    ));
  }

  /// what can go on Home: its own widgets that are off, then every device, cameras first, then by room (those on
  /// Home already left out); a search over names and rooms, typed on the app's own keyboard (the Echo has no input
  /// method), and a scrollbar that says there is more
  void _addSheet(Palette p) {
    var q = '';
    var kb = false;
    final scroll = ScrollController();
    final fg = p.text == Colors.white ? Colors.white : const Color(0xff1c1c1e);
    showDialog(context: context, barrierColor: const Color(0x66000000), builder: (ctx) => StatefulBuilder(builder: (ctx, set) =>
        ListenableBuilder(listenable: Listenable.merge([lay, ha]), builder: (ctx, _) {
      final needle = q.trim().toLowerCase();
      bool match(String text) => needle.isEmpty || text.toLowerCase().contains(needle);
      final own = <(String, VoidCallback)>[
        if (!lay.analogClock) ('Analog clock', () => lay.analogClock = true),
        if (!lay.digitalClock) ('Digital clock', () => lay.digitalClock = true),
        if (!lay.dateCard) ('Date & weather', () => lay.dateCard = true),
        if (!lay.nowPlaying) ('Now Playing', () => lay.nowPlaying = true),
        for (final s in widget.screens) if (lay.hiddenScreens.contains(s)) (s, () => lay.hiddenScreens.remove(s)),
      ].where((e) => match(e.$1)).toList();
      final onHome = favorites().toSet();
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
                onTap: () { lay.hidden.remove(id); lay.favorites = [...favorites(), id]; lay.changed(); }),
        ],
        if (own.isEmpty && rooms.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(needle.isEmpty ? 'Everything is on Home already.' : 'Nothing called “$q”.', style: TextStyle(color: p.dim))),
      ];
      final search = GestureDetector(
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
            Expanded(child: Text('Add to Home', style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w700))),
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
    }))).then((_) => scroll.dispose());
  }

  /// a page as a drop target: the dragged widget goes to the cell its top-left corner is nearest to (anywhere, a
  /// gap too), and stays there; a widget that was there takes the dragged one's old place.  Held at the screen's
  /// left or right edge, the page turns (an empty one waits after the last).  One target per page, not one per
  /// widget: widgets moving under the finger made per-widget targets swap back and forth
  Widget _grid(List<PageSpec> ps, int i, int cols, int rows, double stepX, double stepY, Widget child) {
    final page = ps[i], g = _gk(page.area);
    return DragTarget<String>(
      // by the group's widgets, not by `dragging`: a drag enters the page before onDragStarted has run
      onWillAcceptWithDetails: (d) => _spotsOf[g]?.containsKey(d.data) ?? false,
      onMove: (d) {
        final box = _gridBox['$g/${page.index}'], it = _itemOf(d.data);
        if (dragging != d.data || liveArea != g || box == null || !box.attached || it == null) return;
        final topLeft = box.globalToLocal(d.offset);
        final c = (topLeft.dx / stepX).round().clamp(0, max(0, cols - it.w)).toInt(), r = (topLeft.dy / stepY).round().clamp(0, max(0, rows - it.h)).toInt();
        final to = (page.index, c, r);
        if (to != dragAt) setState(() => dragAt = to);
        // the edges: the page before or after, once held there a moment
        final finger = d.offset + (_dragHalf[d.data] ?? Offset.zero), w = MediaQuery.sizeOf(context).width;
        final dir = finger.dx < 28 ? -1 : finger.dx > w - 28 ? 1 : 0;
        if (dir == 0) { _edgeFlip?.cancel(); _edgeFlip = null; return; }
        _edgeFlip ??= Timer(const Duration(milliseconds: 600), () {
          _edgeFlip = null;
          final to = this.page + dir;
          // within the widget's own group (Home's pages, or its room's): a room's widget does not go to Home
          if (dragging != null && to >= 0 && to < ps.length && _gk(ps[to].area) == g) {
            pc.animateToPage(to, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });
      },
      onAcceptWithDetails: (_) => _drop(),
      builder: (context, _, _) => child,
    );
  }
  final _gridBox = <String, RenderBox>{};
  final _dragKeys = <String, GlobalKey>{};
  final _items = <String, Item>{};              // the dragged one's item (its size), from the last pages()
  Item? _itemOf(String key) => _items[key];
  /// a page group's key, as the layout keeps places: Home's is not the room without an area's
  static String _gk(String? area) => area == null ? 'home' : 'area:$area';
  final _dragHalf = <String, Offset>{};

  /// the drop: every widget of the group where it is now, kept (empty pages between taken out)
  void _drop() {
    final g = liveArea;
    if (dragging == null || g == null) return;
    final spots = _spotsOf[g] ?? const {};
    final used = (spots.values.map((s) => s.$1).toSet().toList()..sort());
    lay.place = {...lay.place, g: {for (final e in spots.entries) e.key: [used.indexOf(e.value.$1), e.value.$2, e.value.$3]}};
    _edgeFlip?.cancel(); _edgeFlip = null;
    setState(() { dragging = null; liveArea = null; startSpots = null; dragFrom = null; dragAt = null; });
    lay.changed();
  }

  Widget _bar(List<PageSpec> ps, Palette p) => Positioned(top: 8, left: 0, right: 0, child: Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xe01c1c1e), borderRadius: BorderRadius.circular(999)),
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: [
          _pill('‹', () => pc.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)),
          for (final w in Wallpaper.values)
            GestureDetector(onTap: () { lay.wallpaper = w; lay.changed(); }, child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4), width: 30, height: 30,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: Palette.of(w).wall,
                    border: Border.all(color: lay.wallpaper == w ? Colors.white : Colors.transparent, width: 2)))),
          _pill('+ Add', () => _addSheet(p)),
          _pill('Clear page', () => _clearPage(ps, p)),
          _pill(lay.hidden.isEmpty ? 'Hidden' : 'Hidden (${lay.hidden.length})', () => _hiddenSheet(p)),
          _pill('Reset', lay.reset),
          _pill('Done', () => edit(false), primary: true),
          _pill('›', () => pc.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)),
        ])),
      )));

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
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(mainAxisSize: MainAxisSize.min, children: [

          for (var i = 0; i < ps.length; i++)
            Container(margin: const EdgeInsets.symmetric(horizontal: 3), width: 6, height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: p.dim.withValues(alpha: i == page ? 1 : .45))),
        ])),
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
class _GridBox extends SingleChildRenderObjectWidget {
  final void Function(RenderBox) onBox;
  const _GridBox({required this.onBox, super.child});
  @override
  RenderProxyBox createRenderObject(BuildContext context) { final b = RenderProxyBox(); onBox(b); return b; }
  @override
  void updateRenderObject(BuildContext context, RenderProxyBox b) => onBox(b);
}
