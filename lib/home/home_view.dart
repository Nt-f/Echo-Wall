// The HomeView: pages of square glass widgets over a wallpaper, swiped sideways.  Home first (the clocks, the date and
// weather, the favourites: a thermostat big, a camera, scenes, locks; what plays; the app's other screens), then a page
// per room (Home Assistant's areas).  Hold the page dots to edit: the widgets wobble, a drag moves one, ★ puts it on
// Home, − hides it; the bar picks the wallpaper.  Left alone, the ambient clock.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ha.dart';
import 'layout.dart';
import 'model.dart';
import 'sheet.dart';
import 'widgets.dart';

enum Kind { analog, digital, date, thermo, playing, camera, tile, screen }

class Item {
  final Kind kind;
  final String? id;                             // the entity (not for the clocks, the date, the screens)
  final String? room;                           // a tile on Home shows its room under its name
  final int screen;                             // Kind.screen: the app's screen index
  final String name;
  const Item(this.kind, {this.id, this.room, this.screen = -1, this.name = ''});
  int get w => kind == Kind.thermo || kind == Kind.playing || kind == Kind.digital ? 2 : 1;
  int get h => kind == Kind.thermo || kind == Kind.playing ? 2 : 1;
  String get key => id ?? '${kind.name}$screen';
}

class PageSpec {
  final String name, sub;
  final String? area;                           // null: Home
  final List<(Item, int col, int row)> placed;
  const PageSpec(this.name, this.sub, this.area, this.placed);
}

/// items into pages: each at the first free place it fits (row by row), a page full: the next one
List<PageSpec> pack(String name, String sub, String? area, List<Item> items, int cols, int rows) {
  final pages = <PageSpec>[];
  var grid = List.generate(rows, (_) => List.filled(cols, false));
  var placed = <(Item, int, int)>[];
  bool fits(Item it, int c, int r) {
    if (c + it.w > cols || r + it.h > rows) return false;
    for (var y = r; y < r + it.h; y++) { for (var x = c; x < c + it.w; x++) { if (grid[y][x]) return false; } }
    return true;
  }
  for (final it in items) {
    (int, int)? at;
    for (var r = 0; r < rows && at == null; r++) { for (var c = 0; c < cols && at == null; c++) { if (fits(it, c, r)) at = (c, r); } }
    if (at == null) {
      if (it.w > cols || it.h > rows) continue; // bigger than a page: left out
      pages.add(PageSpec(name, sub, area, placed));
      grid = List.generate(rows, (_) => List.filled(cols, false));
      placed = [];
      at = (0, 0);
    }
    for (var y = at.$2; y < at.$2 + it.h; y++) { for (var x = at.$1; x < at.$1 + it.w; x++) { grid[y][x] = true; } }
    placed.add((it, at.$1, at.$2));
  }
  if (placed.isNotEmpty || pages.isEmpty) pages.add(PageSpec(name, sub, area, placed));
  return pages;
}

class HomeView extends StatefulWidget {
  final Ha ha;
  final Layout layout;
  final bool h24;
  final List<String> screens;                   // the app's other screens (Home Assistant's UI, Music Assistant)
  final void Function(int) onScreen;
  const HomeView({super.key, required this.ha, required this.layout, required this.h24, required this.screens, required this.onScreen});
  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with TickerProviderStateMixin {
  final pc = PageController();
  int page = 0;
  bool editing = false, ambient = false;
  DateTime touched = DateTime.now();
  Timer? idle;
  String? dragging;                             // the key of the widget being moved
  List<String>? liveOrder;                      // the page's keys while one is moved
  late final AnimationController wobble = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));

  Ha get ha => widget.ha;
  Layout get lay => widget.layout;

  int? ambientOverride;                         // debug.hassmic.ambient (screenshots)

  @override
  void initState() {
    super.initState();
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
  void dispose() { idle?.cancel(); wobble.dispose(); pc.dispose(); super.dispose(); }

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

  List<PageSpec> pages(int cols, int rows) {
    final out = <PageSpec>[];
    final home = <Item>[
      if (lay.analogClock) const Item(Kind.analog),
      if (lay.digitalClock) const Item(Kind.digital),
      const Item(Kind.date),
    ];
    final fav = favorites();
    for (final id in fav) { home.add(itemOf(id, room: ha.areaName(ha.areaOf(id)))); }
    final playing = ha.states.entries.where((e) => domainOf(e.key) == 'media_player' && e.value.state == 'playing'
        && e.value.attr['media_title'] != null && !lay.hidden.contains(e.key)).map((e) => e.key).firstOrNull;
    if (playing != null && !fav.contains(playing)) home.add(Item(Kind.playing, id: playing));
    for (var i = 0; i < widget.screens.length; i++) { home.add(Item(Kind.screen, screen: i, name: widget.screens[i])); }
    out.addAll(pack('Home', '', null, _live(null, home), cols, rows));

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
      out.addAll(pack(name, roomSummary(ha, area), area, _live(area, ids.map((id) => itemOf(id)).toList()), cols, rows));
    }
    return out;
  }

  /// while a widget is dragged across this page: the order the drag has made so far
  String? liveArea;
  List<Item> _live(String? area, List<Item> items) {
    if (liveOrder == null || liveArea != (area ?? '')) return items;
    final by = {for (final it in items) it.key: it};
    return [for (final k in liveOrder!) ?by[k], ...items.where((it) => !liveOrder!.contains(it.key))];
  }

  // ---------------------------------------------------------------- drawing

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(lay.wallpaper);
    return ListenableBuilder(listenable: Listenable.merge([ha, lay]), builder: (context, _) => Listener(
      onPointerDown: (_) { touched = DateTime.now(); if (ambient) setState(() => ambient = false); },
      child: Stack(children: [
        Positioned.fill(child: WallpaperView(p)),
        LayoutBuilder(builder: (context, box) {
          const gap = 10.0, pad = 12.0, bottom = 22.0;
          final rows = box.maxHeight < 600 ? 3 : box.maxHeight < 900 ? 4 : 5;
          final cell = (box.maxHeight - pad - bottom - gap * (rows - 1) - (editing ? 44 : 0)) / rows;
          final cols = max(2, ((box.maxWidth - 2 * pad + gap) / (cell + gap)).floor());
          final cw = (box.maxWidth - 2 * pad - gap * (cols - 1)) / cols;
          final ps = pages(cols, rows);
          if (page >= ps.length) page = ps.length - 1;
          return Stack(children: [
            PageView.builder(
              controller: pc,
              physics: editing ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
              itemCount: ps.length,
              onPageChanged: (i) => setState(() => page = i),
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsets.fromLTRB(pad, pad + (editing ? 44 : 0), pad, bottom),
                child: Stack(children: [
                  for (final (it, c, r) in ps[i].placed)
                    AnimatedPositioned(
                      key: ValueKey('${ps[i].area}/${it.key}'),
                      duration: const Duration(milliseconds: 220), curve: Curves.easeOut,
                      left: c * (cw + gap), top: r * (cell + gap),
                      width: it.w * cw + (it.w - 1) * gap, height: it.h * cell + (it.h - 1) * gap,
                      child: _editable(ps[i], it, p, cell, _widget(it, p, cell)),
                    ),
                ]),
              ),
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
        }),
        if (ambient) Positioned.fill(child: _Ambient(p: p, h24: widget.h24, ha: ha)),
      ]),
    ));
  }

  Widget _widget(Item it, Palette p, double cell) {
    void more() => showControls(context, ha, p, it.id!);
    return switch (it.kind) {
      Kind.analog => AnalogClockCard(p: p, cell: cell),
      Kind.digital => DigitalClockCard(p: p, cell: cell, h24: widget.h24, wide: true),
      Kind.date => DateWeatherCard(ha: ha, p: p, cell: cell),
      Kind.thermo => ThermostatCard(ha: ha, p: p, id: it.id!, cell: cell, onLong: more),
      Kind.playing => NowPlayingCard(ha: ha, p: p, id: it.id!, cell: cell, onLong: more),
      Kind.camera => CameraCard(ha: ha, p: p, id: it.id!, cell: cell),
      Kind.screen => ScreenTile(p: p, name: it.name, cell: cell, onTap: () => widget.onScreen(it.screen)),
      Kind.tile => AccessoryTile(ha: ha, p: p, id: it.id!, room: it.room, cell: cell, onLong: more),
    };
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
    if (id == null && it.kind != Kind.analog && it.kind != Kind.digital) return body;
    Widget badge(String s, Color bg, Color fg, VoidCallback f, {required bool left}) => Positioned(
          left: left ? 4 : null, right: left ? null : 4, top: 4,
          child: GestureDetector(onTap: f, child: Container(width: 30, height: 30, alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6)]),
              child: Text(s, style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w700, height: 1)))),
        );
    final key = it.key, area = page.area ?? '';
    final draggable = Draggable<String>(
      data: key,
      feedback: SizedBox(width: (it.w * cell).toDouble(), height: (it.h * cell).toDouble(),
          child: Transform.scale(scale: 1.05, child: Opacity(opacity: .9, child: Material(color: Colors.transparent, child: w)))),
      childWhenDragging: Opacity(opacity: .25, child: body),
      onDragStarted: () => setState(() { dragging = key; liveArea = area; liveOrder = page.placed.map((e) => e.$1.key).toList(); }),
      onDragEnd: (_) => _drop(page),
      child: body,
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        final o = liveOrder;
        if (o == null || d.data == key || liveArea != area) return false;
        // the dragged one takes this one's place; this one and those after it move on
        setState(() { o.remove(d.data); final at = o.indexOf(key); o.insert(at < 0 ? o.length : at, d.data); });
        return true;
      },
      builder: (_, _, _) => Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: draggable),
        if (id != null && !onHome) badge('★', Colors.white, fav.contains(id) ? const Color(0xfff5a623) : const Color(0xffb8b8b8), () {
          lay.favorites = fav.contains(id) ? (fav..remove(id)) : [...fav, id];
          lay.changed();
        }, left: true),
        if (id != null) badge('−', const Color(0xffff453a), Colors.white, () {
          if (onHome) { lay.favorites = fav..remove(id); } else { lay.hidden.add(id); if (lay.favorites != null) lay.favorites!.remove(id); }
          lay.changed();
        }, left: false),
        if (it.kind == Kind.analog || it.kind == Kind.digital) badge('−', const Color(0xffff453a), Colors.white, () {
          if (it.kind == Kind.analog) { lay.analogClock = false; } else { lay.digitalClock = false; }
          lay.changed();
        }, left: false),
      ]),
    );
  }

  void _drop(PageSpec page) {
    final o = liveOrder;
    setState(() { dragging = null; liveOrder = null; liveArea = null; });
    if (o == null) return;
    final ids = o.where((k) => ha.states.containsKey(k)).toList();
    if (page.area == null) {
      lay.favorites = [...ids, ...favorites().where((x) => !ids.contains(x))];
    } else {
      lay.order = {...lay.order, page.area!: ids};
    }
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
          if (!lay.analogClock || !lay.digitalClock)
            _pill('+ Clock', () { lay.analogClock = true; lay.digitalClock = true; lay.changed(); }),
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
        backgroundColor: p.sheet, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
          Text(ps[page].name + (ps[page].sub.isNotEmpty ? ' · ${ps[page].sub}' : ''),
              style: TextStyle(color: p.dim, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          for (var i = 0; i < ps.length; i++)
            Container(margin: const EdgeInsets.symmetric(horizontal: 3), width: 6, height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: p.dim.withValues(alpha: i == page ? 1 : .45))),
        ])),
      )));
}

/// the ambient clock: the time in big glass digits over the wallpaper, the date and the weather under it
class _Ambient extends StatelessWidget {
  final Palette p;
  final bool h24;
  final Ha ha;
  const _Ambient({required this.p, required this.h24, required this.ha});
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        WallpaperView(p),
        LayoutBuilder(builder: (context, box) {
          final size = min(box.maxHeight * .78, box.maxWidth * .3);
          return TickerBuilder(builder: (now) {
            final h = h24 ? now.hour : (now.hour % 12 == 0 ? 12 : now.hour % 12);
            final t = '$h:${now.minute.toString().padLeft(2, '0')}';
            final w = ha.states.entries.where((e) => domainOf(e.key) == 'weather').map((e) => e.value).firstOrNull;
            final style = TextStyle(fontSize: size, fontWeight: FontWeight.w600, height: 1, letterSpacing: -size * .03,
                fontFeatures: const [FontFeature.tabularFigures()]);
            return Stack(alignment: Alignment.center, children: [
              Text(t, style: style.copyWith(color: const Color(0x33ffffff),
                  shadows: const [Shadow(color: Color(0x40ffffff), blurRadius: 30)])),
              Text(t, style: style.copyWith(foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0x73ffffff))),
              Positioned(bottom: 18, child: Text(
                  '${_long(now)}${w?.numAttr('temperature') != null ? ' · ${w!.numAttr('temperature')!.round()}°' : ''}',
                  style: const TextStyle(color: Color(0xd9ffffff), fontSize: 18, fontWeight: FontWeight.w600))),
            ]);
          });
        }),
      ]);

  static String _long(DateTime t) {
    const d = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const m = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${d[t.weekday - 1]}, ${m[t.month - 1]} ${t.day}';
  }
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
