// Edit mode: every widget comes off (the date, the media card, a screen's too), a whole page at once, and "+ Add" puts
// any back, devices included
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_screen/ha.dart';
import 'package:echo_screen/home/wall_view.dart';
import 'package:echo_screen/home/layout.dart';

void main() {
  Future<(Ha, Layout)> home(WidgetTester t) async {
    t.view.physicalSize = const Size(960, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final ha = Ha()..connected = true;
    ha.states['lock.a'] = EntityState('locked', {'friendly_name': 'Lock A'});
    ha.states['light.desk'] = EntityState('off', {'friendly_name': 'Desk'});
    final lay = Layout()..wallpaper = Wallpaper.amber..favorites = ['lock.a']..ambientSeconds = 0..digitalClock = false;
    await t.pumpWidget(MaterialApp(home: WallView(ha: ha, layout: lay, h24: true, screens: const ['Music'], onScreen: (_) {})));
    await t.pump(const Duration(milliseconds: 100));
    await t.longPressAt(const Offset(480, 480 - 11));
    await t.pump(const Duration(milliseconds: 300));
    return (ha, lay);
  }

  testWidgets('every widget has a − that takes it off', (t) async {
    final (_, lay) = await home(t);
    // analog clock, date, Lock A, Music: four −
    expect(find.text('−'), findsNWidgets(4));
    await t.tap(find.text('−').at(1));                  // the date
    await t.pump(const Duration(milliseconds: 300));
    expect(lay.dateCard, isFalse);
    final music = find.ancestor(of: find.text('Music'), matching: find.byType(Stack)).first;
    await t.tap(find.descendant(of: music, matching: find.text('−')).first);
    await t.pump(const Duration(milliseconds: 300));
    expect(lay.hiddenScreens, {'Music'});
    expect(find.text('Music'), findsNothing);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('Clear page empties it; + Add brings a widget and a device back', (t) async {
    final (_, lay) = await home(t);
    await t.tap(find.text('Clear page'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Clear'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('−'), findsNothing);
    expect([lay.analogClock, lay.dateCard, lay.favorites], [false, false, <String>[]]);
    await t.tap(find.text('+ Add'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('+ Date & weather'));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('Desk'));
    await t.pump(const Duration(milliseconds: 100));
    expect(lay.dateCard, isTrue);
    expect(lay.favorites, ['light.desk']);
    expect(find.descendant(of: find.byType(Dialog), matching: find.text('Desk')), findsNothing);   // on Home now: no longer offered
    await t.tap(find.text('Done').last);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('+ Add: a search typed on the app\'s own keyboard', (t) async {
    final (ha, lay) = await home(t);
    ha.states['light.kitchen'] = EntityState('off', {'friendly_name': 'Kitchen'});
    await t.tap(find.text('+ Add'));
    await t.pump(const Duration(milliseconds: 300));
    Finder inSheet(String s) => find.descendant(of: find.byType(RawScrollbar), matching: find.text(s));
    expect(inSheet('Desk'), findsOneWidget);
    expect(inSheet('Kitchen'), findsOneWidget);
    await t.tap(find.text('Search devices and widgets'));
    await t.pump(const Duration(milliseconds: 300));
    for (final k in ['k', 'i', 't']) { await t.tap(find.text(k)); await t.pump(); }
    expect(find.text('kit'), findsOneWidget);
    expect(inSheet('Desk'), findsNothing);
    expect(inSheet('Kitchen'), findsOneWidget);
    await t.tap(inSheet('Kitchen'));
    await t.pump(const Duration(milliseconds: 100));
    expect(lay.favorites, ['lock.a', 'light.kitchen']);
    await t.tap(find.text('Done').last);
    await t.pump(const Duration(seconds: 1));
  });

  // Home on three pages: the clocks and the date, then 15 locks (4 + 8 + 3)
  Future<Layout> long(WidgetTester t) async {
    t.view.physicalSize = const Size(960, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final ha = Ha()..connected = true;
    final ids = [for (var i = 0; i < 15; i++) 'lock.l${i.toString().padLeft(2, '0')}'];
    for (final id in ids) { ha.states[id] = EntityState('locked', {'friendly_name': 'L ${id.substring(6)}'}); }
    ha.states['light.desk'] = EntityState('off', {'friendly_name': 'Desk'});
    final lay = Layout()..wallpaper = Wallpaper.amber..favorites = ids..ambientSeconds = 0;
    await t.pumpWidget(MaterialApp(home: WallView(ha: ha, layout: lay, h24: true, screens: const [], onScreen: (_) {})));
    await t.pump(const Duration(milliseconds: 100));
    await t.longPressAt(const Offset(480, 480 - 11));
    await t.pump(const Duration(milliseconds: 300));
    return lay;
  }

  Future<void> next(WidgetTester t) async {
    await t.tap(find.text('›'));
    for (var k = 0; k < 20; k++) { await t.pump(const Duration(milliseconds: 20)); }
  }

  testWidgets('+ Add on Home\'s third page: the card on that page, not in a gap on the first', (t) async {
    final lay = await long(t);
    await next(t); await next(t);
    expect(find.text('L 14'), findsOneWidget);
    await t.tap(find.text('+ Add'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Desk'));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('Done').last);
    await t.pump(const Duration(milliseconds: 700));
    expect(lay.favorites, contains('light.desk'));
    expect(find.text('Desk'), findsOneWidget);                          // there, on the page looked at
    expect(lay.place['home']?['light.desk']?.first, 2);
  });

  testWidgets('Clear page on the first of two: emptied, the next page\'s cards not pulled onto it', (t) async {
    final lay = await long(t);
    await t.tap(find.text('Clear page'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Clear'));
    await t.pump(const Duration(milliseconds: 300));
    expect([lay.analogClock, lay.digitalClock, lay.dateCard], [false, false, false]);
    expect(find.text('L 00'), findsNothing);
    expect(lay.favorites!.length, 11);                                  // the four of the first page off
    expect(find.text('L 04'), findsNothing);                            // still on its own page, not here
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('− on a card: the next page\'s first card comes back into its place', (t) async {
    final lay = await long(t);
    // a drop first, so every card has a place (as on an Echo that was ever edited): L 00 (0,1) onto L 01 (1,1), a swap
    final from = t.getCenter(find.text('L 00')), to = t.getCenter(find.text('L 01'));
    final g = await t.startGesture(from);
    await t.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 12; i++) { await g.moveTo(Offset.lerp(from, to, i / 12)!); await t.pump(const Duration(milliseconds: 30)); }
    await t.pump(const Duration(milliseconds: 300));
    await g.up(); await t.pump(const Duration(milliseconds: 700));
    expect(lay.place['home']?['lock.l00'], [0, 1, 1]);
    final card = find.ancestor(of: find.text('L 00'), matching: find.byType(Stack)).first;
    await t.tap(find.descendant(of: card, matching: find.text('−')).first);
    await t.pump(const Duration(milliseconds: 700));
    expect(lay.place['home']?['lock.l04'], [0, 1, 1], reason: '${lay.place['home']}');
    expect(find.text('L 04'), findsOneWidget);
  });
}
