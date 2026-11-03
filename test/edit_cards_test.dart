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
}
