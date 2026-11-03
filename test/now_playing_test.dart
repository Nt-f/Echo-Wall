// The media card is always on Home: what plays (an AirPlay stream without a title too), and when it stops, the same
// player, "Not Playing", in the same place
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_screen/ha.dart';
import 'package:echo_screen/home/wall_view.dart';
import 'package:echo_screen/home/layout.dart';

void main() {
  testWidgets('the media card stays: playing, untitled, stopped', (t) async {
    t.view.physicalSize = const Size(960, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final ha = Ha()..connected = true;
    ha.states['media_player.tv'] = EntityState('off', {'friendly_name': 'TV'});
    ha.states['media_player.echo'] = EntityState('idle', {'friendly_name': 'Echo Show'});
    final lay = Layout()..wallpaper = Wallpaper.amber..favorites = []..ambientSeconds = 0..digitalClock = false;   // room on page 1
    await t.pumpWidget(MaterialApp(home: WallView(ha: ha, layout: lay, h24: true, screens: const [], onScreen: (_) {})));
    await t.pump(const Duration(milliseconds: 100));
    // nothing played yet: the one that is on
    expect(find.text('NOT PLAYING'), findsOneWidget);
    expect(find.text('Echo Show'), findsOneWidget);
    // AirPlay through Music Assistant: playing, no title
    ha.states['media_player.echo'] = EntityState('playing', {'friendly_name': 'Echo Show'});
    ha.notifyListeners();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('ECHO SHOW'), findsOneWidget);
    expect(lay.player, 'media_player.echo');
    // the TV plays with a title: the card stays on the Echo while it plays
    ha.states['media_player.tv'] = EntityState('playing', {'friendly_name': 'TV', 'media_title': 'News'});
    ha.notifyListeners();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('NEWS'), findsNothing);
    // both stop: the last that played, not playing
    ha.states['media_player.echo'] = EntityState('paused', {'friendly_name': 'Echo Show'});
    ha.states['media_player.tv'] = EntityState('off', {'friendly_name': 'TV'});
    ha.notifyListeners();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('NOT PLAYING'), findsOneWidget);
    expect(find.text('Echo Show'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('one cell left on Home\'s first page: the card fits in it', (t) async {
    t.view.physicalSize = const Size(960, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final ha = Ha()..connected = true;
    for (final n in ['a', 'b', 'c']) { ha.states['lock.$n'] = EntityState('locked', {'friendly_name': 'Lock $n'}); }
    ha.states['media_player.echo'] = EntityState('playing', {'friendly_name': 'Echo Show', 'media_title': 'Song'});
    // clocks, date: the first row; three locks: the second, but its last cell
    final lay = Layout()..wallpaper = Wallpaper.amber..favorites = ['lock.a', 'lock.b', 'lock.c']..ambientSeconds = 0;
    await t.pumpWidget(MaterialApp(home: WallView(ha: ha, layout: lay, h24: true, screens: const [], onScreen: (_) {})));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('SONG'), findsOneWidget);
    expect(t.getCenter(find.text('SONG')).dx, greaterThan(16 + 3 * 235.5));
    await t.pump(const Duration(seconds: 1));
  });
}
