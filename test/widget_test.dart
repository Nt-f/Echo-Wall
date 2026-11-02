import 'package:flutter_test/flutter_test.dart';
import 'package:hassmic_screen/hassmic.dart';

void main() {
  test('the config hassmic hands out', () {
    final c = ScreenConfig.parse('{"enabled":true,"ha":"http://ha:8123","token":"t","default":5,"return":120,'
        '"screens":[{"name":"Home Assistant","url":"http://ha:8123/lovelace"},{"name":"Music","url":"http://ha:8123/m"}]}');
    expect(c.enabled, true);
    expect(c.screens.length, 2);
    expect(c.screens[1].name, 'Music');
    expect(c.defaultScreen, 0);          // out of range: the first
    expect(c.returnSeconds, 120);
    expect(c.settings, isEmpty);
    final d = ScreenConfig.parse('{"enabled":true,"screens":[],"settings":{"immich.url":"http://x:2283"}}');
    expect(d.settings['immich.url'], 'http://x:2283');
  });

  test('screens of hassmic\'s own: the clock kept, others left out, the start screen found again', () {
    final c = ScreenConfig.parse('{"enabled":true,"default":2,"screens":[{"name":"Weather","url":"hassmic:weather"},'
        '{"name":"Clock","url":"hassmic:clock"},{"name":"HA","url":"http://ha:8123/"}]}');
    expect(c.screens.map((s) => s.name), ['Clock', 'HA']);
    expect(c.defaultScreen, 1);
  });

  test('the state hassmic hands the app that draws', () {
    final s = EchoState.parse('{"v":3,"running":true,"words":true,"heard":"hi","reply":"","ringing":"","h24":true,'
        '"clock_set":true,"next_alarm":{"at":1793689800,"text":"Alarm 7:30","label":"Gym"},"display":"always"}');
    expect(s.v, 3);
    expect(s.words, true);
    expect(s.nextAlarm, isNotNull);
    expect(s.nextAlarmLabel, 'Gym');
  });
}
