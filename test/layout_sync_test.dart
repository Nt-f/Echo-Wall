// Echo-Wall's layout in Home Assistant (layout_sync.dart) against a stand-in of Home Assistant's websocket that speaks
// the Echo-Wall integration's echo_wall/* (custom_components/echo_wall/home.py; tools/ha_test.py has the real one).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:echo_screen/device.dart';
import 'package:echo_screen/ha.dart';
import 'package:echo_screen/home/layout.dart';
import 'package:echo_screen/home/layout_sync.dart';

class FakeHa {
  late HttpServer server;
  WebSocket? ws;
  Map<String, dynamic> slot;                    // what the integration keeps for this device
  final registered = <Map<String, dynamic>>[];
  final sets = <Map<String, dynamic>>[];
  int? subId;
  int refuse = 0;                               // registrations refused first: the integration not loaded yet
  bool oldIntegration = false;                  // one of before "replaces": a message with it refused whole
  FakeHa(this.slot);

  Future<String> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final s = await WebSocketTransformer.upgrade(req);
      ws = s;
      s.add(jsonEncode({'type': 'auth_required'}));
      s.listen((raw) {
        final m = jsonDecode(raw as String) as Map<String, dynamic>;
        if (m['type'] == 'auth') { s.add(jsonEncode({'type': 'auth_ok'})); return; }
        final id = m['id'];
        switch (m['type']) {
          case 'echo_wall/register' when refuse > 0:
            refuse--;
            s.add(jsonEncode({'id': id, 'type': 'result', 'success': false, 'error': {'code': 'unknown_command'}}));
          case 'echo_wall/register' when oldIntegration && m.containsKey('replaces'):
            s.add(jsonEncode({'id': id, 'type': 'result', 'success': false, 'error': {'code': 'invalid_format', 'message': "extra keys not allowed @ data['replaces']"}}));
          case 'echo_wall/register':
            registered.add(m);
            s.add(jsonEncode({'id': id, 'type': 'result', 'success': true, 'result': {'device': m['device'], 'name': m['name']}}));
          case 'echo_wall/subscribe':
            expect(m['device'], registered.isEmpty ? 'dev-under-test' : registered.last['device']);
            expect(registered, isNotEmpty);                  // registered first: the device is bound to this login
            subId = id as int;
            s.add(jsonEncode({'id': id, 'type': 'result', 'success': true}));
            s.add(jsonEncode({'id': id, 'type': 'event', 'event': {'layout': slot}}));
          case 'echo_wall/set':
            expect(m['device'], 'dev-under-test');
            slot = (m['layout'] as Map).cast<String, dynamic>();
            sets.add(slot);
            s.add(jsonEncode({'id': id, 'type': 'result', 'success': true, 'result': slot}));
          default:
            s.add(jsonEncode({'id': id, 'type': 'result', 'success': true, 'result': m['type'] == 'config/entity_registry/list_for_display' ? {'entities': []} : []}));
        }
      });
    });
    return 'http://127.0.0.1:${server.port}';
  }

  /// the panel saved: told to the subscriber
  void push(Map<String, dynamic> l) { slot = l; ws!.add(jsonEncode({'id': subId, 'type': 'event', 'event': {'layout': l}})); }
}

Future<void> until(bool Function() f) async {
  for (var i = 0; i < 100 && !f(); i++) { await Future<void>.delayed(const Duration(milliseconds: 20)); }
}

void main() {
  test('nothing in Home Assistant yet: ours goes there', () async {
    final fake = FakeHa({});
    final ha = Ha(), lay = Layout()..wallpaper = Wallpaper.dusk..hidden = {'switch.a'};
    LayoutSync(ha, lay, device: 'dev-under-test', info: () => {'name': 'Test tablet', 'model': 'X', 'version': '1'});
    ha.configure(await fake.start(), 'tok');
    await until(() => fake.sets.isNotEmpty);
    expect(fake.sets.single['wallpaper'], 'dusk');
    expect(fake.registered.single['name'], 'Test tablet');
    expect(fake.sets.single['hidden'], ['switch.a']);
    await fake.server.close(force: true);
  });

  test("Home Assistant's taken at the start; the panel's saves drawn; ours sent, what came in not sent back", () async {
    final fake = FakeHa({'wallpaper': 'light', 'favorites': ['light.a', 'climate.b'], 'ambient': 30, 'place': {'home': {'clock': [0, 1, 0]}}});
    final ha = Ha(), lay = Layout();
    LayoutSync(ha, lay, device: 'dev-under-test', info: () => {'name': 'Test tablet', 'model': 'X', 'version': '1'});
    ha.configure(await fake.start(), 'tok');
    await until(() => lay.wallpaper == Wallpaper.light);
    expect(lay.favorites, ['light.a', 'climate.b']);
    expect(lay.ambientSeconds, 30);
    expect(lay.place['home']!['clock'], [0, 1, 0]);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(fake.sets, isEmpty);                  // the file written, Home Assistant not told its own back

    fake.push({...fake.slot, 'wallpaper': 'amber', 'now_playing': false});
    await until(() => lay.wallpaper == Wallpaper.amber);
    expect(lay.nowPlaying, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(fake.sets, isEmpty);

    lay.hidden.add('light.a');                   // an edit on the Echo
    lay.changed();
    await until(() => fake.sets.isNotEmpty);
    expect(fake.sets.single['hidden'], ['light.a']);
    expect(fake.sets.single['wallpaper'], 'amber');
    await fake.server.close(force: true);
  });

  test("Home Assistant just restarted, Echo Local not loaded yet: asked again, then the panel's saves arrive", () async {
    LayoutSync.retry = const Duration(milliseconds: 200);
    final fake = FakeHa({'wallpaper': 'light'})..refuse = 2;
    final ha = Ha(), lay = Layout();
    LayoutSync(ha, lay, device: 'dev-under-test', info: () => {'name': 'Test tablet', 'model': 'X', 'version': '1'});
    ha.configure(await fake.start(), 'tok');
    await until(() => lay.wallpaper == Wallpaper.light);
    expect(fake.refuse, 0);
    fake.push({'wallpaper': 'amber'});
    await until(() => lay.wallpaper == Wallpaper.amber);
    expect(lay.wallpaper, Wallpaper.amber);
    await fake.server.close(force: true);
  });

  test('a new id that replaces the old one (a reinstall): told once, then kept', () async {
    final fake = FakeHa({'wallpaper': 'light'});
    final ha = Ha(), lay = Layout();
    var kept = 0;
    LayoutSync(ha, lay, device: 'dev-under-test', replaces: 'old-random-id1', onRegistered: () => kept++,
        info: () => {'name': 'Test tablet', 'model': 'X', 'version': '1'});
    ha.configure(await fake.start(), 'tok');
    await until(() => lay.wallpaper == Wallpaper.light && kept > 0);
    expect(fake.registered.single['replaces'], 'old-random-id1');
    expect(kept, 1);
    await fake.server.close(force: true);
  });

  test('an integration of before "replaces": the old id goes on, the move left for its update', () async {
    final fake = FakeHa({'wallpaper': 'light'})..oldIntegration = true;
    final ha = Ha(), lay = Layout();
    var kept = 0;
    LayoutSync(ha, lay, device: 'dev-under-test', replaces: 'old-random-id1', onRegistered: () => kept++,
        info: () => {'name': 'Test tablet', 'model': 'X', 'version': '1'});
    ha.configure(await fake.start(), 'tok');
    await until(() => lay.wallpaper == Wallpaper.light);
    expect(fake.registered.single.containsKey('replaces'), isFalse);
    expect(fake.registered.single['device'], 'old-random-id1');
    expect(kept, 0);                             // not the new id in the file yet: the move asked again next start
    await fake.server.close(force: true);
  });

  test('the stable id: an Echo by its node, else Android\'s id, else none', () {
    expect(Device.stableId(node: 'echo-show-5-3fce9a', androidId: 'abcdef0123456789'), 'echo-echo-show-5-3fce9a');
    expect(Device.stableId(androidId: 'abcdef0123456789'), 'android-abcdef0123456789');
    expect(Device.stableId(androidId: '9774d56d682e549c'), isNull);      // the emulator's, the same everywhere
    expect(Device.stableId(androidId: 'abc'), isNull);
    expect(Device.stableId(), isNull);
  });

  test('without Echo Local: the file alone, nothing breaks', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final s = await WebSocketTransformer.upgrade(req);
      s.add(jsonEncode({'type': 'auth_required'}));
      s.listen((raw) {
        final m = jsonDecode(raw as String) as Map<String, dynamic>;
        if (m['type'] == 'auth') { s.add(jsonEncode({'type': 'auth_ok'})); return; }
        s.add(jsonEncode({'id': m['id'], 'type': 'result', 'success': false, 'error': {'code': 'unknown_command'}}));
      });
    });
    final ha = Ha(), lay = Layout();
    LayoutSync(ha, lay, device: 'dev-under-test', info: () => {'name': 'Test tablet', 'model': 'X', 'version': '1'});
    ha.configure('http://127.0.0.1:${server.port}', 'tok');
    await until(() => ha.connected);
    lay.wallpaper = Wallpaper.dusk; lay.changed();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(lay.wallpaper, Wallpaper.dusk);
    await server.close(force: true);
  });

  test("keys this app does not know (the integration's Immich settings) survive its own saves; the settings from them", () {
    final lay = Layout()..apply({'wallpaper': 'dusk', 'immich_url': 'https://photos.example', 'immich_key': 'k', 'photos_minutes': 5, 'future_key': [1]});
    lay.hidden = {'light.a'};
    final j = lay.toJson();
    expect([j['immich_url'], j['immich_key'], j['photos_minutes'], j['future_key']], ['https://photos.example', 'k', 5, [1]]);
    expect(j['hidden'], ['light.a']);
    final st = lay.settingsOver({'immich.url': 'http://old', 'other': 'x'});
    expect(st, {'immich.url': 'https://photos.example', 'other': 'x', 'immich.key': 'k', 'photos.minutes': '5'});
    expect(Layout().settingsOver({'immich.url': 'http://old'}), {'immich.url': 'http://old'});   // nothing set: hassmic's
  });
}
