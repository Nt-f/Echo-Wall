// The screen app's side of hassmic's contract (echo-dot-assist docs/screen-apps.md): the config, from 127.0.0.1 only
// (hassmic hands it to this app's uid alone), polled every 5 s while in front ("/front": hassmic gives the screen to
// the app while it has nothing of its own to show; "/front/draws": the app draws the request's words, a ring and the
// clock itself) and every 30 s while paused ("/back": alive, not to be started).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class Screen {
  final String name, url;
  const Screen(this.name, this.url);
}

/// the "hassmic:" screens this app draws itself (docs/screen-apps.md)
const drawn = {'hassmic:clock'};

class ScreenConfig {
  final String raw;
  final bool enabled;
  final String ha, token;
  final List<Screen> screens;
  final int defaultScreen, returnSeconds;
  /// the app's own settings, typed into the integration's options ("Screen app settings": key=value lines)
  final Map<String, String> settings;
  ScreenConfig._(this.raw, this.enabled, this.ha, this.token, this.screens, this.defaultScreen, this.returnSeconds, this.settings);

  factory ScreenConfig.parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final all = [
      for (final s in (j['screens'] as List? ?? const [])) Screen('${s['name'] ?? ''}', '${s['url'] ?? ''}'),
    ];
    // web pages, and the screens of hassmic's own this app draws (others: a newer contract's, left out)
    final screens = [for (final s in all) if (s.url.startsWith('http://') || s.url.startsWith('https://') || drawn.contains(s.url)) s];
    final d0 = (j['default'] as num? ?? 0).toInt();
    var def = d0 >= 0 && d0 < all.length ? screens.indexOf(all[d0]) : 0;
    if (def < 0) def = 0;
    return ScreenConfig._(raw, j['enabled'] == true, '${j['ha'] ?? ''}', '${j['token'] ?? ''}', screens, def,
        (j['return'] as num? ?? 0).toInt(),
        {for (final e in (j['settings'] as Map<String, dynamic>? ?? const {}).entries) e.key: '${e.value}'});
  }
}

class Hassmic {
  static const config = 'http://127.0.0.1:28931/kiosk/config';
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 2);

  /// the config (null: hassmic not answering, or not to this app); front: the app is in front
  Future<ScreenConfig?> poll({required bool front}) async {
    try {
      // front/draws: this app draws the request's words and a ring itself (hassmic leaves the screen to it for them)
      final req = await _client.getUrl(Uri.parse('$config/${front ? 'front/draws' : 'back'}'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return null;
      return ScreenConfig.parse(body);
    } catch (_) {
      return null;
    }
  }
}

/// what the screen shows (GET /kiosk/state), for an app that draws it itself: the request's words, a ring, the clock's
/// next alarm; followed with a long poll, so that words appear as hassmic has them
class EchoState {
  final int v;
  final bool running, words, ringingAlarm, h24, clockSet;
  final String heard, reply, ringing, display;
  final DateTime? nextAlarm;
  final String nextAlarmText, nextAlarmLabel;
  const EchoState({this.v = 0, this.running = false, this.words = false, this.heard = '', this.reply = '', this.ringing = '',
      this.ringingAlarm = false, this.h24 = false, this.clockSet = true, this.nextAlarm, this.nextAlarmText = '',
      this.nextAlarmLabel = '', this.display = 'awake'});

  /// the same state, its words shown or not (EchoStateFeed's linger)
  EchoState withWords(bool w) => EchoState(v: v, running: running, words: w, heard: heard, reply: reply, ringing: ringing,
      ringingAlarm: ringingAlarm, h24: h24, clockSet: clockSet, nextAlarm: nextAlarm, nextAlarmText: nextAlarmText,
      nextAlarmLabel: nextAlarmLabel, display: display);

  factory EchoState.parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final n = j['next_alarm'] as Map<String, dynamic>?;
    return EchoState(
      v: (j['v'] as num? ?? 0).toInt(), running: j['running'] == true, words: j['words'] == true,
      heard: '${j['heard'] ?? ''}', reply: '${j['reply'] ?? ''}', ringing: '${j['ringing'] ?? ''}',
      ringingAlarm: j['ringing_alarm'] == true, h24: j['h24'] == true, clockSet: j['clock_set'] != false,
      nextAlarm: n == null ? null : DateTime.fromMillisecondsSinceEpoch((n['at'] as num).toInt() * 1000),
      nextAlarmText: '${n?['text'] ?? ''}', nextAlarmLabel: '${n?['label'] ?? ''}', display: '${j['display'] ?? ''}');
  }
}

class EchoStateFeed {
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  bool _on = false;

  /// how long a request's words stay after it ended (the reply spoken): hassmic keeps them for its own screen's
  /// "Words stay for" (20 s by default, a clock to read them beside); over a screen of the owner's they are in the
  /// way, so the app lets them go this long after the speech
  Duration linger = const Duration(seconds: 1);
  EchoState? _last;
  DateTime? _ended;                             // when the last run ended (null: one runs, or none was seen)
  Timer? _hide;

  /// the state as the app shows it: the words only while a run goes and a linger after it
  EchoState shown(EchoState s) {
    final prev = _last;
    _last = s;
    if (s.running) { _ended = null; _hide?.cancel(); return s; }
    // ended now; or words that came without a run (an answer outside one): from now on too
    if ((prev?.running ?? false) || (s.words && (prev == null || s.heard != prev.heard || s.reply != prev.reply))) {
      _ended = DateTime.now();
    }
    final e = _ended;
    return s.withWords(s.words && e != null && DateTime.now().difference(e) < linger);
  }

  /// calls on() with every new state until stop(); hassmic not answering: tries again every 5 s
  void start(void Function(EchoState) on) {
    if (_on) return;
    _on = true;
    void emit(EchoState s) {
      final shown = this.shown(s);
      on(shown);
      if (shown.words && !s.running) {          // the words go a linger after the run's end, by themselves
        _hide?.cancel();
        _hide = Timer(linger - DateTime.now().difference(_ended!), () { if (_on && identical(_last, s)) on(s.withWords(false)); });
      }
    }
    () async {
      var v = -1;
      while (_on) {
        try {
          final req = await _client.getUrl(Uri.parse('http://127.0.0.1:28931/kiosk/state${v < 0 ? '' : '/$v'}'));
          final res = await req.close().timeout(const Duration(seconds: 35));
          final body = await res.transform(utf8.decoder).join();
          if (res.statusCode != 200) throw 'refused';
          final s = EchoState.parse(body);
          if (s.v != v) { v = s.v; if (_on) emit(s); }
        } catch (_) {
          v = -1;
          await Future.delayed(const Duration(seconds: 5));
        }
      }
    }();
  }

  void stop() { _on = false; _hide?.cancel(); }
}
