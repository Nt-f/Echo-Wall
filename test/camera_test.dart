// A tap on a camera: full screen, a tap closes it
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hassmic_screen/ha.dart';
import 'package:hassmic_screen/home/home_view.dart';
import 'package:hassmic_screen/home/layout.dart';
import 'package:hassmic_screen/home/widgets.dart';

void main() {
  testWidgets('tapped: the camera full screen; tapped again: back', (t) async {
    t.view.physicalSize = const Size(960, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final ha = Ha()..connected = true;
    ha.states['camera.porch'] = EntityState('idle', {'friendly_name': 'Porch'});
    final lay = Layout()..wallpaper = Wallpaper.amber..favorites = ['camera.porch']..ambientSeconds = 0;
    await t.pumpWidget(MaterialApp(home: HomeView(ha: ha, layout: lay, h24: true, screens: const [], onScreen: (_) {})));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.byType(CameraCard));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(CameraFullScreen), findsOneWidget);
    await t.tapAt(const Offset(480, 300));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(CameraFullScreen), findsNothing);
    await t.pump(const Duration(seconds: 1));
  });
}
