// Moving widgets in edit mode: a drag across the page puts the widget where the finger is, and the order is kept
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hassmic_screen/ha.dart';
import 'package:hassmic_screen/home/home_view.dart';
import 'package:hassmic_screen/home/layout.dart';

void main() {
  Future<(Ha, Layout)> home(WidgetTester t) async {
    t.view.physicalSize = const Size(960, 480);      // the Echo Show 5
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final ha = Ha()..connected = true;
    for (final n in ['a', 'b', 'c', 'd']) { ha.states['lock.$n'] = EntityState('locked', {'friendly_name': 'Lock ${n.toUpperCase()}'}); }
    final lay = Layout()
      ..wallpaper = Wallpaper.amber
      ..favorites = ['lock.a', 'lock.b', 'lock.c', 'lock.d']
      ..ambientSeconds = 0;
    await t.pumpWidget(MaterialApp(home: HomeView(ha: ha, layout: lay, h24: true, screens: const [], onScreen: (_) {})));
    await t.pump(const Duration(milliseconds: 100));
    // hold the page dots: edit mode
    await t.longPressAt(Offset(480, 480 - 11));
    await t.pump(const Duration(milliseconds: 300));
    return (ha, lay);
  }

  Future<void> drag(WidgetTester t, String from, String to) async {
    final a = t.getCenter(find.text(from).first), b = t.getCenter(find.text(to).first);
    final g = await t.startGesture(a);
    await t.pump(const Duration(milliseconds: 50));
    // in small steps, as a finger: the widgets move out of the way while it goes
    for (var i = 1; i <= 20; i++) { await g.moveTo(Offset.lerp(a, b, i / 20)!); await t.pump(const Duration(milliseconds: 30)); }
    await t.pump(const Duration(milliseconds: 300));
    await g.up();
    await t.pump(const Duration(milliseconds: 600));    // the layout saved (its timer)
  }

  testWidgets('a widget dragged onto another takes its place; the others move on', (t) async {
    final (_, lay) = await home(t);
    await drag(t, 'Lock A', 'Lock C');
    expect(lay.favorites, ['lock.b', 'lock.c', 'lock.a', 'lock.d']);
    // the clocks and the date kept their places before them
    expect(lay.homeOrder.take(3), ['analog-1', 'digital-1', 'date-1']);
  });

  testWidgets('the last one dragged to the front of the devices', (t) async {
    final (_, lay) = await home(t);
    await drag(t, 'Lock D', 'Lock A');
    expect(lay.favorites, ['lock.d', 'lock.a', 'lock.b', 'lock.c']);
    expect(lay.homeOrder.indexOf('lock.d') < lay.homeOrder.indexOf('lock.a'), isTrue);
  });

  testWidgets('back and forth over a tile does not swap it back and forth', (t) async {
    final (_, lay) = await home(t);
    final a = t.getCenter(find.text('Lock A').first), b = t.getCenter(find.text('Lock B').first);
    final g = await t.startGesture(a);
    await t.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 10; i++) { await g.moveTo(Offset.lerp(a, b, i / 10)!); await t.pump(const Duration(milliseconds: 30)); }
    // the finger stays on (and wiggles over) where B was: A has taken that place, B moved; no swap back
    for (var i = 0; i < 10; i++) { await g.moveTo(b + Offset(i.isEven ? 6 : -6, 0)); await t.pump(const Duration(milliseconds: 30)); }
    await g.up();
    await t.pump(const Duration(milliseconds: 600));
    expect(lay.favorites, ['lock.b', 'lock.a', 'lock.c', 'lock.d']);
  });
}
