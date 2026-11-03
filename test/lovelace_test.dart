// The owner's dashboard drawn natively after Home (lib/lovelace/): its sections as pages, its cards as the WallView's
// own (a tile, a thermostat with its colours, a player) or NativeCard (a card it cannot draw: a tile that opens the
// dashboard), the big ones first; the Echo's own changes on top (a card's menu by a hold: a size, off this page; held
// on: the edit mode), never written into the dashboard.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_screen/ha.dart';
import 'package:echo_screen/home/layout.dart';
import 'package:echo_screen/home/wall_view.dart';
import 'package:echo_screen/home/widgets.dart';
import 'package:echo_screen/lovelace/lovelace.dart';
import 'package:echo_screen/lovelace/source.dart';

Map<String, dynamic> tile(String e) => {'type': 'tile', 'entity': e};
final dash = {'views': [{'title': 'Home', 'type': 'sections', 'sections': [
  {'type': 'grid', 'cards': [{'type': 'heading', 'heading': 'Living Room'}, tile('light.ceiling'), tile('light.lamp'), tile('cover.window'),
    tile('fan.fan'), {'type': 'thermostat', 'entity': 'climate.hvac'}]},
  {'type': 'grid', 'cards': [{'type': 'heading', 'heading': 'Hall'}, {'type': 'thermostat', 'entity': 'climate.ecobee', 'grid_options': {'columns': 12, 'rows': 5}},
    {'type': 'custom:mushroom-chips-card'}, tile('lock.front')]},
]}]};

void main() {
  late Ha ha;
  late Layout lay;
  late List<String> opened;

  Future<void> wall(WidgetTester t) async {
    t.view.physicalSize = const Size(960, 470);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    ha = Ha()..connected = true;
    EntityState e(String s, Map<String, dynamic> a) => EntityState(s, a);
    ha.states.addAll({
      'light.ceiling': e('on', {'friendly_name': 'Ceiling', 'brightness': 180}),
      'light.lamp': e('off', {'friendly_name': 'Lamp'}),
      'cover.window': e('open', {'friendly_name': 'Window', 'current_position': 70}),
      'fan.fan': e('off', {'friendly_name': 'Fan'}),
      'lock.front': e('locked', {'friendly_name': 'Front Door'}),
      'climate.hvac': e('heat', {'friendly_name': 'Hvac', 'temperature': 21, 'current_temperature': 19, 'hvac_action': 'heating'}),
      'climate.ecobee': e('heat_cool', {'friendly_name': 'Ecobee', 'target_temp_low': 20, 'target_temp_high': 24, 'current_temperature': 25,
        'hvac_action': 'cooling'}),
    });
    lay = Layout()..wallpaper = Wallpaper.dusk..ambientSeconds = 0..favorites = []..analogClock = false..digitalClock = false
      ..dateCard = false..nowPlaying = false..dashboard = 'dash-home';
    final src = LovelaceSource.fixed(ha, 'dash-home', [for (final v in dash['views']!) LView.parse(v)]);
    opened = [];
    await t.pumpWidget(MaterialApp(home: WallView(ha: ha, layout: lay, h24: true, screens: const [], onScreen: (_) {}, lovelace: src,
        onDashboard: opened.add)));
    await t.pump(const Duration(milliseconds: 200));
  }

  Future<void> page(WidgetTester t, int i) async {
    await t.fling(find.byType(PageView), const Offset(-600, 0), 1500);
    await t.pumpAndSettle(const Duration(milliseconds: 100));
  }

  testWidgets('the sections after Home, a page each: the big thermostat first, the tiles beside it, colours by what it does', (t) async {
    await wall(t);
    await page(t, 1);
    expect(find.text('Living Room'), findsOneWidget);
    for (final n in ['Ceiling', 'Lamp', 'Window', 'Fan', 'Hvac']) { expect(find.text(n), findsOneWidget, reason: n); }
    // 2 x 2 thermostat at the left, four tiles in the two columns beside it: all on the one page
    expect(t.getTopLeft(find.text('Hvac')).dx, lessThan(400));
    expect(t.getTopLeft(find.text('Ceiling')).dx, greaterThan(480));
    final line = t.widget<Text>(find.byWidgetPredicate((w) => w is Text && (w.textSpan?.toPlainText() ?? '').startsWith('Heating to 21°')));
    // heating: its line white over the card's orange glow (orange on orange was unreadable), the glow its colour
    expect((line.textSpan as TextSpan).children!.first.style!.color, Colors.white);
    expect(find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration
        && ((w.decoration as BoxDecoration).gradient?.colors.last.toARGB32() ?? 0) == heatColor.withValues(alpha: .34).toARGB32()), findsWidgets);
  });

  testWidgets('a heat/cool thermostat: its range, the low end orange, the high blue, cooling to the high end', (t) async {
    await wall(t);
    await page(t, 1); await page(t, 2);
    expect(find.text('Hall'), findsOneWidget);
    final lo = t.widget<Text>(find.text('20')), hi = t.widget<Text>(find.text('24'));
    expect(lo.style!.color, heatColor);
    expect(hi.style!.color, coolColor);
    expect(find.byWidgetPredicate((w) => w is Text && (w.textSpan?.toPlainText() ?? '').startsWith('Cooling to 24°')), findsOneWidget);
  });

  testWidgets('a card it cannot draw: named, and a tap opens its view in the dashboard', (t) async {
    await wall(t);
    await page(t, 1); await page(t, 2);
    expect(find.text('Mushroom chips card'), findsOneWidget);
    await t.tap(find.text('Mushroom chips card'));
    expect(opened, ['/dash-home/0']);
  });

  testWidgets('held: the card\'s menu; a size, then off this page: on this Echo only, the dashboard untouched', (t) async {
    await wall(t);
    await page(t, 1);
    final g = lay.place.keys.isEmpty ? 'll:0/Living Room' : 'll:0/Living Room';
    final at = t.getCenter(find.text('Lamp'));
    final hold = await t.startGesture(at);
    await t.pump(const Duration(milliseconds: 700));
    await hold.up();
    await t.pumpAndSettle();
    expect(find.text('Remove from this page'), findsOneWidget);
    expect(find.text('Wide'), findsOneWidget);
    await t.tap(find.text('Wide'));
    await t.pumpAndSettle();
    expect(lay.sizes[g]?['light.lamp'], '2x1');
    final hold2 = await t.startGesture(t.getCenter(find.text('Lamp')));
    await t.pump(const Duration(milliseconds: 700));
    await hold2.up();
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Remove from this page'));   // the test font's letters are squares: the menu scrolls
    await t.pumpAndSettle();
    await t.tap(find.text('Remove from this page'));
    await t.pumpAndSettle();
    expect(lay.exclude[g], ['light.lamp']);
    expect(find.text('Lamp'), findsNothing);
    expect(find.text('Ceiling'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));                                       // the layout's save
  });

  testWidgets('held on: the edit mode, its resize button cycles the card\'s sizes', (t) async {
    await wall(t);
    await page(t, 1);
    final hold = await t.startGesture(t.getCenter(find.text('Fan')));
    await t.pump(const Duration(milliseconds: 700));
    await t.pump(const Duration(milliseconds: 800));
    await hold.up();
    for (var i = 0; i < 5; i++) { await t.pump(const Duration(milliseconds: 100)); }   // no settling: the cards wobble on
    expect(find.text('Done'), findsOneWidget);
    expect(find.byKey(const ValueKey('card-menu')), findsNothing);                   // its menu went with the edit mode
    // the resize button: Fan is small; one press makes it wide
    final g = 'll:0/Living Room';
    await t.tap(find.descendant(of: find.byKey(ValueKey('$g/fan.fan')), matching: find.byIcon(CupertinoIcons.arrow_up_left_arrow_down_right)));
    for (var i = 0; i < 3; i++) { await t.pump(const Duration(milliseconds: 100)); }
    expect(lay.sizes[g]?['fan.fan'], '2x1', reason: '${lay.sizes} ${find.byIcon(CupertinoIcons.arrow_up_left_arrow_down_right).evaluate().length}');   // (wide, it no longer fits beside the thermostat: next page)
    await t.pump(const Duration(seconds: 1));
  });
}
