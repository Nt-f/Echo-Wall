// Every card at every size it has (lib/home/gallery.dart), at the Echo Show 5's cell: nothing may overflow its box (an
// overflow is an error, and the test fails on it), and the picture of them all is written to test/goldens/cards.png on
// every run (not compared: the clocks show the time it ran), in the app's own fonts, on the dusk wallpaper.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_screen/ha.dart';
import 'package:echo_screen/home/backdrop.dart';
import 'package:echo_screen/home/gallery.dart';
import 'package:echo_screen/home/layout.dart';
import 'package:echo_screen/home/widgets.dart';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    final b = File(f).readAsBytesSync();
    l.addFont(Future.value(ByteData.view(b.buffer)));
  }
  await l.load();
}

/// the picture written, never compared
class _Write extends LocalFileComparator {
  _Write(super.testFile);
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async { await update(golden, imageBytes); return true; }
}

void main() {
  setUpAll(() async {
    goldenFileComparator = _Write(Uri.parse('${Directory.current.path}/test/gallery_test.dart'));
    await _font('Inter', [for (final w in ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Inter-$w.ttf']);
    // the icons, from the Flutter SDK and the pub cache (tests draw none of them otherwise)
    final sdk = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/flutter';
    final mat = File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (mat.existsSync()) await _font('MaterialIcons', [mat.path]);
    final pub = Directory('${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev');
    final cup = pub.existsSync() ? pub.listSync().whereType<Directory>().where((d) => d.path.contains('cupertino_icons-')).toList() : <Directory>[];
    if (cup.isNotEmpty) await _font('packages/cupertino_icons/CupertinoIcons', ['${(cup..sort((a, b) => a.path.compareTo(b.path))).last.path}/assets/CupertinoIcons.ttf']);
  });

  testWidgets('every card at every size: nothing overflows; the picture of them all', (t) async {
    t.view.physicalSize = const Size(1960, 5500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final ha = Ha()..connected = true;
    EntityState e(String s, Map<String, dynamic> a) => EntityState(s, a);
    ha.states.addAll({
      'light.kitchen': e('on', {'friendly_name': 'Kitchen Lights', 'brightness': 180, 'rgb_color': [255, 170, 60], 'color_mode': 'rgb'}),
      'lock.front': e('locked', {'friendly_name': 'Front Door'}),
      'lock.back': e('unlocked', {'friendly_name': 'Kitchen Door'}),
      'climate.hvac': e('heat', {'friendly_name': 'Hallway', 'temperature': 21.5, 'current_temperature': 19, 'hvac_action': 'heating'}),
      'climate.ecobee': e('heat_cool', {'friendly_name': 'Ecobee', 'target_temp_low': 20, 'target_temp_high': 24, 'current_temperature': 25, 'hvac_action': 'cooling'}),
      'media_player.living': e('playing', {'friendly_name': 'Living Room', 'media_title': 'I Wanna Be A Hippy (Flamman & Abraxas Radio Mix)', 'media_artist': 'Technohead'}),
      'camera.porch': e('idle', {'friendly_name': 'Porch'}),
      'sensor.out_temp': e('15.6', {'friendly_name': 'Outside', 'unit_of_measurement': '°C', 'device_class': 'temperature'}),
      'sensor.humidity': e('54', {'friendly_name': 'Humidity', 'unit_of_measurement': '%', 'device_class': 'humidity'}),
      'sensor.co2': e('412', {'friendly_name': 'CO₂', 'unit_of_measurement': 'ppm', 'device_class': 'carbon_dioxide'}),
      'weather.home': e('sunny', {'friendly_name': 'Home', 'temperature': 22}),
    });
    final p = Palette.of(Wallpaper.dusk);
    final b = Backdrop();
    await t.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'Inter', brightness: Brightness.dark), debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: Colors.black, body: BackdropScope(backdrop: b, child: Stack(children: [
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: p.wall))),
          RepaintBoundary(key: const ValueKey('gallery'), child: CardGallery(ha: ha, p: p)),
        ])))));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Thermostat, heat/cool'), findsOneWidget);
    await expectLater(find.byKey(const ValueKey('gallery')), matchesGoldenFile('goldens/cards.png'));
    await t.pumpWidget(const SizedBox());       // the cameras' timers stopped
    await t.pump(const Duration(seconds: 11));
  });
}
