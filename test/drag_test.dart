// Moving widgets in edit mode: a widget dropped anywhere on the grid stays there (a gap too); on another widget, the two
// swap; every widget moves (the clocks, the date, a screen's like Music); held at the screen's edge, the page turns
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hassmic_screen/ha.dart';
import 'package:hassmic_screen/home/home_view.dart';
import 'package:hassmic_screen/home/layout.dart';

// the Echo Show 5 in edit mode: 5 x 2 cells of 180 px, 10 px apart, the grid from (10, 88)
Offset cellCenter(int c, int r) => Offset(10 + c * 190 + 90, 88 + r * 190 + 90);

void main() {
  Future<Layout> home(WidgetTester t, {List<String> screens = const []}) async {
    t.view.physicalSize = const Size(960, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final ha = Ha()..connected = true;
    for (final n in ['a', 'b', 'c', 'd']) { ha.states['lock.$n'] = EntityState('locked', {'friendly_name': 'Lock ${n.toUpperCase()}'}); }
    final lay = Layout()
      ..wallpaper = Wallpaper.amber
      ..favorites = ['lock.a', 'lock.b', 'lock.c', 'lock.d']
      ..ambientSeconds = 0;
    await t.pumpWidget(MaterialApp(home: HomeView(ha: ha, layout: lay, h24: true, screens: screens, onScreen: (_) {})));
    await t.pump(const Duration(milliseconds: 100));
    await t.longPressAt(const Offset(480, 480 - 11));   // hold the page dots: edit mode
    await t.pump(const Duration(milliseconds: 300));
    return lay;
  }

  // Home: analog 0,0; digital 1-2,0; date 3,0; Lock A 4,0; Lock B, C, D 0..2,1; free: 3,1 and 4,1
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

  testWidgets('dropped on an empty cell: it stays there, a gap where it was', (t) async {
    final lay = await home(t);
    await drag(t, t.getCenter(find.text('Lock A')), cellCenter(4, 1));
    expect(at(lay, 'lock.a'), [0, 4, 1]);
    expect(at(lay, 'lock.b'), [0, 0, 1]);                 // the others where they were
    expect(at(lay, 'date-1'), [0, 3, 0]);
    // and it stays: drawn again, Lock A at 4,1 and nothing moved into its old cell
    await t.pump(const Duration(seconds: 1));
    expect(t.getCenter(find.text('Lock A')).dx, greaterThan(cellCenter(4, 1).dx - 90));
    expect(t.getCenter(find.text('Lock A')).dy, greaterThan(cellCenter(4, 1).dy - 90));
  });

  testWidgets('dropped on another widget: the two swap', (t) async {
    final lay = await home(t);
    await drag(t, t.getCenter(find.text('Lock A')), cellCenter(1, 1));
    expect(at(lay, 'lock.a'), [0, 1, 1]);
    expect(at(lay, 'lock.c'), [0, 4, 0]);
  });

  testWidgets('a screen\'s widget (Music) and the date move too', (t) async {
    final lay = await home(t, screens: ['Music']);       // Music: at 3,1
    await drag(t, t.getCenter(find.text('Music')), cellCenter(4, 1));
    expect(at(lay, 'screen0'), [0, 4, 1]);
    await drag(t, cellCenter(3, 0), cellCenter(3, 1));  // the date into the gap Music left
    expect(at(lay, 'date-1'), [0, 3, 1]);
  });

  testWidgets('held at the right edge: onto the next page, and it stays there', (t) async {
    final lay = await home(t);
    await drag(t, t.getCenter(find.text('Lock A')), const Offset(950, 300), hold: const Duration(milliseconds: 1200));
    expect(at(lay, 'lock.a')?.first, 1);
    expect(at(lay, 'lock.b')?.first, 0);
  });
}
