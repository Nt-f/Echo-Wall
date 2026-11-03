// Moving widgets in edit mode: a widget dropped anywhere on the grid stays there (a gap too); on another widget, the two
// swap; every widget moves (the clocks, the date, a screen's like Music); held at the screen's edge, the page turns
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_screen/ha.dart';
import 'package:echo_screen/home/backdrop.dart';
import 'package:echo_screen/home/wall_view.dart';
import 'package:echo_screen/home/layout.dart';

// the Echo Show 5: 4 x 2 cells, editing or not; in edit mode 221.5 x 166 px, 14 px apart, the grid from (16, 112)
Offset cellCenter(int c, int r) => Offset(16 + c * 235.5 + 110, 112 + r * 180 + 83);

void main() {
  Future<Layout> home(WidgetTester t, {List<String> screens = const [], int locks = 3}) async {
    t.view.physicalSize = const Size(960, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final ha = Ha()..connected = true;
    for (final n in ['a', 'b', 'c', 'd']) { ha.states['lock.$n'] = EntityState('locked', {'friendly_name': 'Lock ${n.toUpperCase()}'}); }
    final lay = Layout()
      ..wallpaper = Wallpaper.amber
      ..favorites = ['lock.a', 'lock.b', 'lock.c', 'lock.d'].take(locks).toList()
      ..ambientSeconds = 0;
    await t.pumpWidget(MaterialApp(home: WallView(ha: ha, layout: lay, h24: true, screens: screens, onScreen: (_) {})));
    await t.pump(const Duration(milliseconds: 100));
    await t.longPressAt(const Offset(480, 480 - 11));   // hold the page dots: edit mode
    await t.pump(const Duration(milliseconds: 300));
    return lay;
  }

  // Home: analog 0,0; digital 1-2,0; date 3,0; Lock A, B, C 0..2,1; free: 3,1
  Future<void> drag(WidgetTester t, Offset a, Offset b, {Duration hold = Duration.zero}) async {
    final g = await t.startGesture(a);
    await t.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 20; i++) { await g.moveTo(Offset.lerp(a, b, i / 20)!); await t.pump(const Duration(milliseconds: 30)); }
    for (var ms = 0; ms < hold.inMilliseconds; ms += 50) { await g.moveTo(b + Offset((ms ~/ 50).isEven ? 1 : -1, 0)); await t.pump(const Duration(milliseconds: 50)); }
    await t.pump(const Duration(milliseconds: 300));
    await g.up();
    await t.pump(const Duration(milliseconds: 600));    // the layout saved (its timer)
  }

  List<int>? at(Layout lay, String key) => lay.place['home']?[key];

  testWidgets('dropped on an empty cell: it stays there, a gap where it was; after Done too', (t) async {
    final lay = await home(t);
    await drag(t, t.getCenter(find.text('Lock A')), cellCenter(3, 1));
    expect(at(lay, 'lock.a'), [0, 3, 1]);
    expect(at(lay, 'lock.b'), [0, 1, 1]);                 // the others where they were
    expect(at(lay, 'date-1'), [0, 3, 0]);
    // Done: the same grid (the edit bar only made the cells lower), Lock A still in the last column
    await t.tap(find.text('Done'));
    await t.pump(const Duration(seconds: 1));
    expect(t.getCenter(find.text('Lock A')).dx, greaterThan(16 + 3 * 235.5));
    expect(t.getCenter(find.text('Lock B')).dx, lessThan(16 + 2 * 235.5));
  });

  testWidgets('dropped on another widget: the two swap', (t) async {
    final lay = await home(t);
    await drag(t, t.getCenter(find.text('Lock A')), cellCenter(2, 1));
    expect(at(lay, 'lock.a'), [0, 2, 1]);
    expect(at(lay, 'lock.c'), [0, 0, 1]);
  });

  testWidgets('a screen\'s widget (Music) and the date move too', (t) async {
    final lay = await home(t, screens: ['Music'], locks: 2);   // Music: at 2,1
    await drag(t, t.getCenter(find.text('Music')), cellCenter(3, 1));
    expect(at(lay, 'screen0'), [0, 3, 1]);
    await drag(t, cellCenter(3, 0), cellCenter(2, 1));  // the date into the gap Music left
    expect(at(lay, 'date-1'), [0, 2, 1]);
  });

  testWidgets('held at the right edge: onto the next page, and it stays there', (t) async {
    final lay = await home(t);
    await drag(t, t.getCenter(find.text('Lock A')), const Offset(950, 300), hold: const Duration(milliseconds: 1200));
    expect(at(lay, 'lock.a')?.first, 1);
    expect(at(lay, 'lock.b')?.first, 0);
  });

  Future<void> resize(WidgetTester t, String key) async {
    await t.tap(find.descendant(of: find.byKey(ValueKey('home/$key')), matching: find.byIcon(CupertinoIcons.arrow_up_left_arrow_down_right)));
    await t.pump(const Duration(milliseconds: 700));
  }

  testWidgets('resized: it keeps its corner; the one it grows over moves next to it, the rest stay; kept after Done', (t) async {
    final lay = await home(t);
    await resize(t, 'lock.a');                            // small -> wide: over Lock B
    expect(lay.sizes['home']?['lock.a'], '2x1');
    expect(at(lay, 'lock.a'), [0, 0, 1]);
    expect(at(lay, 'lock.b'), [0, 3, 1]);                 // the free cell beside, on the same page
    expect(at(lay, 'lock.c'), [0, 2, 1]);
    expect(at(lay, 'date-1'), [0, 3, 0]);
    await t.tap(find.text('Done'));
    await t.pump(const Duration(seconds: 1));
    expect(t.getCenter(find.text('Lock B')).dx, greaterThan(16 + 3 * 235.5));
  });

  testWidgets('resized in the last column: it grows to the left, not onto another page', (t) async {
    final lay = await home(t, locks: 4);                  // Lock D at 3,1
    await resize(t, 'lock.d');
    expect(at(lay, 'lock.d'), [0, 2, 1]);                 // wide, its right edge where it was
    expect(at(lay, 'lock.c')?.first, 1);                  // the page full: Lock C to the next
    expect(at(lay, 'lock.a'), [0, 0, 1]);
  });

  testWidgets('the lifted widget keeps its glass (the backdrop reaches the Overlay)', (t) async {
    await home(t);
    final a = t.getCenter(find.text('Lock A'));
    final g = await t.startGesture(a);
    await t.pump(const Duration(milliseconds: 50));
    await g.moveTo(a + const Offset(60, 0));
    await t.pump(const Duration(milliseconds: 50));
    // two Lock A now: the faded one in its place and the lifted one; both under a BackdropScope
    expect(find.text('Lock A'), findsNWidgets(2));
    for (final e in find.text('Lock A').evaluate()) {
      expect(e.findAncestorWidgetOfExactType<BackdropScope>(), isNotNull);
    }
    await g.up();
    await t.pump(const Duration(milliseconds: 600));
  });

  testWidgets('no glass kept in a cached layer of its page (it would show the blur of where it was painted)', (t) async {
    await home(t);
    final glass = find.descendant(of: find.byType(PageView), matching: find.byType(Frosted));
    expect(glass, findsWidgets);
    for (final e in glass.evaluate()) {
      var cached = false;
      e.visitAncestorElements((a) {
        if (a.widget is PageView) return false;
        if (a.widget is RepaintBoundary) { cached = true; return false; }
        return true;
      });
      expect(cached, isFalse, reason: 'a RepaintBoundary between a widget\'s glass and the pages');
    }
  });

  testWidgets('swiped to a room: every widget\'s glass drawn from where it is', (t) async {
    t.view.physicalSize = const Size(960, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final ha = Ha()..connected = true;
    // unavailable, as the Echo's own entities were: their tiles at half opacity, a layer of their own
    for (final n in ['a', 'b', 'c', 'd', 'e']) { ha.states['switch.$n'] = EntityState('unavailable', {'friendly_name': 'Switch $n'}); }
    final lay = Layout()..wallpaper = Wallpaper.amber..favorites = []..ambientSeconds = 0;
    await t.pumpWidget(MaterialApp(home: WallView(ha: ha, layout: lay, h24: true, screens: const [], onScreen: (_) {})));
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 500)));   // the wallpaper painted and blurred
    await t.pump(const Duration(milliseconds: 100));
    await t.fling(find.byType(PageView), const Offset(-700, 0), 2000);
    for (var i = 0; i < 40; i++) { await t.pump(const Duration(milliseconds: 16)); }
    expect(find.text('Switch a'), findsOneWidget);
    final glass = find.byType(Frosted).evaluate().map((e) => e.renderObject as RenderFrosted).where((r) => r.attached).toList();
    expect(glass, isNotEmpty);
    for (final r in glass) {
      final real = MatrixUtils.transformRect(r.getTransformTo(null), Offset.zero & r.size);
      expect(r.debugPainted, isNotNull);
      expect((r.debugPainted!.left - real.left).abs(), lessThan(1), reason: 'drawn at ${r.debugPainted}, is at $real');
    }
  });

  // two rooms (Bedroom, Kitchen) after Home: Home 0, Bedroom 1, Kitchen 2
  Future<Layout> rooms(WidgetTester t) async {
    t.view.physicalSize = const Size(960, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final ha = Ha()..connected = true;
    ha.areas = [const Area('bed', 'Bedroom'), const Area('kit', 'Kitchen')];
    for (final (id, name, area) in [('lock.k1', 'K one', 'kit'), ('lock.k2', 'K two', 'kit'), ('lock.k3', 'K three', 'kit'), ('lock.b1', 'B one', 'bed')]) {
      ha.states[id] = EntityState('locked', {'friendly_name': name});
      ha.putInArea(id, area);
    }
    final lay = Layout()..wallpaper = Wallpaper.amber..favorites = []..ambientSeconds = 0;
    await t.pumpWidget(MaterialApp(home: WallView(ha: ha, layout: lay, h24: true, screens: const [], onScreen: (_) {})));
    await t.pump(const Duration(milliseconds: 100));
    await t.longPressAt(const Offset(480, 480 - 11));
    await t.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 2; i++) { await t.tap(find.text('›')); for (var k = 0; k < 20; k++) { await t.pump(const Duration(milliseconds: 20)); } }
    return lay;
  }

  /// lifted, held at an edge until `flips` pages turned, then let go over a cell
  Future<void> carry(WidgetTester t, Offset from, Offset edge, int flips, Offset to) async {
    final g = await t.startGesture(from);
    await t.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 12; i++) { await g.moveTo(Offset.lerp(from, edge, i / 12)!); await t.pump(const Duration(milliseconds: 30)); }
    for (var ms = 0; ms < 950 * flips; ms += 50) { await g.moveTo(edge + Offset(0, (ms ~/ 50).isEven ? 1 : -1)); await t.pump(const Duration(milliseconds: 50)); }
    await t.pump(const Duration(milliseconds: 400));
    for (var i = 1; i <= 12; i++) { await g.moveTo(Offset.lerp(edge, to, i / 12)!); await t.pump(const Duration(milliseconds: 30)); }
    await t.pump(const Duration(milliseconds: 300));
    await g.up();
    await t.pump(const Duration(milliseconds: 700));
  }

  testWidgets('dragged to another room: held at the edge, the room before; it stays where it was let go', (t) async {
    final lay = await rooms(t);
    expect(find.text('K one'), findsOneWidget);
    await carry(t, t.getCenter(find.text('K one')), const Offset(8, 300), 1, cellCenter(2, 0));
    expect(lay.cards['area:bed'], contains('lock.k1'));
    expect(lay.exclude['area:kit'], contains('lock.k1'));
    expect(lay.place['area:bed']?['lock.k1'], [0, 2, 0]);
    expect(find.text('K one'), findsOneWidget);                  // the Bedroom shown, K one on it
    expect(find.text('B one'), findsOneWidget);
    expect(lay.place['area:kit']?.containsKey('lock.k1') ?? false, isFalse);
  });

  testWidgets('dragged from a room onto Home: one of Home\'s tiles (a favourite), off the room', (t) async {
    final lay = await rooms(t);
    await carry(t, t.getCenter(find.text('K two')), const Offset(8, 300), 2, cellCenter(3, 1));
    expect(lay.favorites, contains('lock.k2'));
    expect(lay.place['home']?['lock.k2'], [0, 3, 1]);
    expect(lay.exclude['area:kit'], contains('lock.k2'));
  });

  testWidgets('carried over another room and back: home again where it was, nothing moved', (t) async {
    final lay = await rooms(t);
    final start = t.getCenter(find.text('K three'));
    final g = await t.startGesture(start);
    await t.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 12; i++) { await g.moveTo(Offset.lerp(start, const Offset(8, 300), i / 12)!); await t.pump(const Duration(milliseconds: 30)); }
    for (var ms = 0; ms < 950; ms += 50) { await g.moveTo(Offset(8, 300 + ((ms ~/ 50).isEven ? 1.0 : -1.0))); await t.pump(const Duration(milliseconds: 50)); }
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('B one'), findsOneWidget);                  // over the Bedroom
    expect(find.text('K three'), findsNWidgets(2));              // the lifted one and its place there, dim
    for (var ms = 0; ms < 950; ms += 50) { await g.moveTo(Offset(952, 300 + ((ms ~/ 50).isEven ? 1.0 : -1.0))); await t.pump(const Duration(milliseconds: 50)); }
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('K one'), findsOneWidget);                  // back over the Kitchen
    final before = Map.of(lay.place['area:kit'] ?? const {});
    await g.moveTo(start);
    await t.pump(const Duration(milliseconds: 300));
    await g.up();
    await t.pump(const Duration(milliseconds: 700));
    expect(lay.cards['area:bed'] ?? const [], isNot(contains('lock.k3')));
    final after = lay.place['area:kit'] ?? const {};
    for (final k in ['lock.k1', 'lock.k2']) { expect(after[k], before[k] ?? after[k], reason: k); }
    expect(lay.exclude['area:kit'] ?? const [], isNot(contains('lock.k3')));
  });
}
