// Previews of the native Lovelace renderer (lib/lovelace/lovelace.dart): a dashboard's view drawn at the Echo Show's
// size: ?dash=<json: the dashboard's config> &token=<Home Assistant's, live states over its websocket; the page served
// from Home Assistant's /local/ so pictures come from the same origin> (or &states=<json of GET /api/states>)
// &view=<n> &page=<n> &layout=grid|sections &wall=photo|amber|dusk|light.  Built for the web and shot by
// headless Chrome (echo-dot-assist tools/lovelace-previews.py).
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;

import 'ha.dart';
import 'home/backdrop.dart';
import 'home/layout.dart';
import 'home/sizes.dart';
import 'home/widgets.dart';
import 'lovelace/lovelace.dart';

Future<dynamic> _json(String url) async {
  final r = await web.window.fetch(url.toJS).toDart;
  return jsonDecode((await r.text().toDart).toDart);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final q = Uri.base.queryParameters;
  final ha = Ha();
  if (q['token'] case final tok?) {
    ha.configure(web.window.location.origin, tok);
    for (var i = 0; i < 100 && ha.states.length < 5; i++) { await Future<void>.delayed(const Duration(milliseconds: 100)); }
  } else {
    ha.connected = true;
    for (final s in (await _json(q['states'] ?? 'states.json')) as List) {
      ha.states['${s['entity_id']}'] = EntityState('${s['state']}', Map<String, dynamic>.from(s['attributes'] as Map));
    }
  }
  final dash = (await _json(q['dash'] ?? 'dash.json')) as Map<String, dynamic>;
  final views = [for (final v in dash['views'] as List) LView.parse(Map<String, dynamic>.from(v as Map))];
  final view = views[int.parse(q['view'] ?? '0').clamp(0, views.length - 1)];
  final wall = Wallpaper.values.firstWhere((w) => w.name == q['wall'], orElse: () => Wallpaper.dusk);
  final b = Backdrop();
  b.resize(Size(web.window.innerWidth.toDouble(), web.window.innerHeight.toDouble()));
  if (wall == Wallpaper.photo) {
    await b.photo((await rootBundle.load('assets/photos/${q['photo'] ?? 'nature3.jpg'}')).buffer.asUint8List());
  } else {
    await b.painted(WallpaperPainter(Palette.of(wall)));
  }
  runApp(MaterialApp(debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Inter', brightness: Brightness.dark),
      home: Scaffold(backgroundColor: Colors.black, body: BackdropScope(backdrop: b, child: Stack(children: [
        Positioned.fill(child: BackdropView(fallback: Palette.of(wall).wall)),
        Positioned.fill(child: ListenableBuilder(listenable: ha, builder: (_, _) => q['layout'] == 'sections'
            ? _Sections(ha: ha, p: Palette.of(wall), view: view, page: int.parse(q['page'] ?? '0'), views: views.length)
            : _Grid(ha: ha, p: Palette.of(wall), view: view, page: int.parse(q['page'] ?? '0')))),
      ])))));
  web.document.title = 'ready';
}

/// the WallView's way: a page per section, its heading the page's name, the cards in square cells at the WallView's sizes
class _Grid extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final LView view;
  final int page;
  const _Grid({required this.ha, required this.p, required this.view, required this.page});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        const gap = 14.0, pad = 16.0, header = 52.0, bottom = 22.0;
        final full = box.maxHeight - pad - header - bottom;
        final rows = full < 430 ? 2 : 3;
        final cell = (full - gap * (rows - 1)) / rows;
        final cols = max(2, ((box.maxWidth - 2 * pad + gap) / (cell + gap)).floor());
        final cw = (box.maxWidth - 2 * pad - gap * (cols - 1)) / cols;
        // every section packed into pages of cols x rows, first fit
        final pages = <(String, List<(LCard, CardSize, int, int)>)>[];
        for (final s in view.sections) {
          var grids = <List<List<bool>>>[], placed = <List<(LCard, CardSize, int, int)>>[];
          // the big ones first (stable): a thermostat after four tiles would find no two free rows left on the page
          final idx = {for (var i = 0; i < s.cards.length; i++) s.cards[i]: i};
          int area(LCard c) => c.cardSize.w * c.cardSize.h;
          final byArea = [...s.cards]..sort((a, b) => area(b) != area(a) ? area(b).compareTo(area(a)) : idx[a]!.compareTo(idx[b]!));   // List.sort is not stable
          for (final c in byArea) {
            var sz = c.cardSize;
            while (sz.w > cols || sz.h > rows) { sz = CardSize.values[sz.index - 1]; }
            var done = false;
            for (var pi = 0; !done; pi++) {
              if (pi == grids.length) { grids.add(List.generate(rows, (_) => List.filled(cols, false))); placed.add([]); }
              for (var r = 0; r + sz.h <= rows && !done; r++) {
                for (var x = 0; x + sz.w <= cols && !done; x++) {
                  var free = true;
                  for (var y = r; y < r + sz.h && free; y++) { for (var z = x; z < x + sz.w; z++) { if (grids[pi][y][z]) free = false; } }
                  if (!free) continue;
                  for (var y = r; y < r + sz.h; y++) { for (var z = x; z < x + sz.w; z++) { grids[pi][y][z] = true; } }
                  placed[pi].add((c, sz, x, r));
                  done = true;
                }
              }
            }
          }
          for (final pl in placed) { pages.add((s.title, pl)); }
        }
        final pg = pages[page.clamp(0, pages.length - 1)];
        return Padding(padding: const EdgeInsets.fromLTRB(pad, pad, pad, bottom), child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(height: header, child: Row(children: [
              Text(pg.$1.isEmpty ? view.title : pg.$1, style: TextStyle(color: p.text, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -.4,
                  shadows: const [Shadow(color: Color(0x33000000), blurRadius: 8)])),
              const SizedBox(width: 12),
              Text(view.title, style: TextStyle(color: p.dim, fontSize: 15, fontWeight: FontWeight.w600)),
            ])),
            Expanded(child: Stack(children: [
              for (final (c, sz, x, r) in pg.$2)
                Positioned(left: x * (cw + gap), top: r * (cell + gap), width: sz.w * cw + (sz.w - 1) * gap, height: sz.h * cell + (sz.h - 1) * gap,
                    child: NativeCard(ha: ha, p: p, card: c, size: sz, box: Size(sz.w * cw + (sz.w - 1) * gap, sz.h * cell + (sz.h - 1) * gap))),
            ])),
          ]),
          Positioned(left: 0, right: 0, bottom: -16, child: _dots(pages.length, page, p)),
        ]));
      });
}

/// Lovelace's own way: the sections as columns, three on the screen, each card in its box of the 12-column grid
class _Sections extends StatelessWidget {
  final Ha ha;
  final Palette p;
  final LView view;
  final int page, views;
  const _Sections({required this.ha, required this.p, required this.view, required this.page, required this.views});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        const pad = 16.0, gap = 8.0, between = 16.0, title = 40.0, head = 30.0;
        final perScreen = box.maxWidth >= 900 ? 3 : 2;
        final sw = (box.maxWidth - 2 * pad - between * (perScreen - 1)) / perScreen;
        final colW = (sw - gap * 11) / 12;
        final rowH = ((box.maxHeight - pad - title - head - 22) - gap * 5) / 6;       // six of Lovelace's rows on the screen
        final shown = view.sections.skip(page * perScreen).take(perScreen).toList();
        Widget section(LSection s) {
          final grid = <List<bool>>[];
          final placed = <(LCard, int, int, int, int)>[];
          for (final c in s.cards) {
            final (w, h) = c.grid;
            for (var r = 0;; r++) {
              while (grid.length < r + h) { grid.add(List.filled(12, false)); }
              var at = -1;
              for (var x = 0; x + w <= 12 && at < 0; x++) {
                var free = true;
                for (var y = r; y < r + h && free; y++) { for (var z = x; z < x + w; z++) { if (grid[y][z]) free = false; } }
                if (free) at = x;
              }
              if (at < 0) continue;
              for (var y = r; y < r + h; y++) { for (var z = at; z < at + w; z++) { grid[y][z] = true; } }
              placed.add((c, at, r, w, h));
              break;
            }
          }
          return SizedBox(width: sw, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(height: head, child: Text(s.title, style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w700,
                shadows: const [Shadow(color: Color(0x33000000), blurRadius: 6)]))),
            Expanded(child: ClipRect(child: Stack(children: [
              for (final (c, x, r, w, h) in placed)
                Positioned(left: x * (colW + gap), top: r * (rowH + gap), width: w * colW + (w - 1) * gap, height: h * rowH + (h - 1) * gap,
                    child: NativeCard(ha: ha, p: p, card: c, box: Size(w * colW + (w - 1) * gap, h * rowH + (h - 1) * gap))),
            ]))),
          ]));
        }
        return Padding(padding: const EdgeInsets.fromLTRB(pad, pad, pad, 22), child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(height: title, child: Text(view.title, style: TextStyle(color: p.text, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -.4))),
            Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < shown.length; i++) ...[if (i > 0) const SizedBox(width: between), section(shown[i])],
            ])),
          ]),
          Positioned(left: 0, right: 0, bottom: -16, child: _dots((view.sections.length / perScreen).ceil(), page, p)),
        ]));
      });
}

Widget _dots(int n, int at, Palette p) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var i = 0; i < n; i++)
        Container(margin: const EdgeInsets.symmetric(horizontal: 3), width: 6, height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.dim.withValues(alpha: i == at ? 1 : .45))),
    ]);
