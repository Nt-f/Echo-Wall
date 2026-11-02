// Moving widgets in edit mode: a widget dropped anywhere on the grid stays there (a gap too); on another widget, the two
// swap; every widget moves (the clocks, the date, a screen's like Music); held at the screen's edge, the page turns
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hassmic_screen/ha.dart';
import 'package:hassmic_screen/home/backdrop.dart';
import 'package:hassmic_screen/home/home_view.dart';
import 'package:hassmic_screen/home/layout.dart';

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
    await t.pumpWidget(MaterialApp(home: HomeView(ha: ha, layout: lay, h24: true, screens: screens, onScreen: (_) {})));
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
}
