// The layout in Home Assistant too: the Echo-Wall integration (custom_components/echo_wall, home.py) keeps each
// device's Home, edits it in its sidebar panel, exports it to a file and imports it again.  This install is a device
// there (lib/device.dart): it says who it is at every login (echo_wall/register: the first one binds the device to the
// login it uses, an Echo's own kiosk user or a tablet's), then follows its layout.
//
//   - at each login: register, then subscribe.  Its first answer is what Home Assistant has: nothing yet -> ours is
//     sent (so the layout of before, kept in the app's file, comes with it); something else than ours -> theirs is
//     taken (the panel saved while the app was not running), unless ours was changed since this start and never sent
//     (then ours goes, the last change wins as everywhere else)
//   - every save of ours (layout.dart's, half a second after the last change) is sent, unless it is what came in
//   - every change from there (the panel's Save, an import, a copy from another device) is taken and drawn
//
// Without the integration (not installed, or Home Assistant still loading it) or without Home Assistant, the app keeps
// its file as before, and asks again every 15 s.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../apps.dart' show AndroidApp;
import '../ha.dart';
import 'layout.dart';

/// what the device says of itself at a login: its name, model, the app's version, its screen in logical pixels, its
/// other screens' names (their tiles on Home: the preview draws them too)
typedef DeviceInfo = Map<String, dynamic> Function();

class LayoutSync {
  final Ha ha;
  final Layout layout;
  String device;                                // (the old id meanwhile where the integration cannot move it yet)
  final DeviceInfo info;
  String _agreed = '';                          // the last layout both sides had, as JSON
  bool _changed = false;                        // ours changed since this start and not sent yet

  /// the id this install had before (lib/device.dart): told at the login until Home Assistant moved it to [device]
  String? replaces;
  /// called once a login was taken (the id may be kept now)
  final void Function()? onRegistered;
  bool _noReplace = false;                      // an integration of before "replaces": the move waits for its update

  LayoutSync(this.ha, this.layout, {required this.device, required this.info, this.replaces, this.onRegistered}) {
    layout.onSaved = _saved;
    ha.onConnected.add(_follow);
    if (ha.connected) _follow();
  }

  String _json(Map<String, dynamic> j) => jsonEncode(j);

  // Home Assistant answers the websocket's login before it has loaded custom integrations: just after its restart (a
  // HACS update) echo_wall/register is still an unknown command.  Asked again every 15 s while the link holds
  // (seen on the Echo Show 5: refused at the reconnect, and the panel's saves never arrived until the app restarted)
  Timer? _again;
  static Duration retry = const Duration(seconds: 15);
  int _link = 0;                                // which login a retry belongs to

  void _follow() {
    _again?.cancel();
    final link = ++_link;
    _appsSent = '';                             // a new login: Home Assistant may have restarted without them
    var first = true;
    debugPrint('layout sync: registering $device');
    Null again(Object e) {
      debugPrint('layout sync: not followed ($e)');      // not loaded yet, or no Echo-Wall integration: the file meanwhile
      if (link == _link && ha.connected) _again = Timer(retry, () { if (link == _link && ha.connected) _follow(); });
    }
    final rep = _noReplace ? null : replaces;
    ha.send({'type': 'echo_wall/register', 'device': device, ...info(), 'replaces': ?rep}).then((_) {
      if (link != _link) return;
      if (rep != null) { debugPrint('layout sync: $rep moved to $device'); replaces = null; }
      if (replaces == null) onRegistered?.call();
      ha.subscribe({'type': 'echo_wall/subscribe', 'device': device}, (ev) {
        final theirs = ((ev as Map)['layout'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final mine = layout.toJson();
        if (first) {
          first = false;
          debugPrint('layout sync: Home Assistant has ${theirs.isEmpty ? 'none' : 'one'}${_changed ? ', ours changed' : ''}');
          if (theirs.isEmpty || (_changed && _json(mine) != _agreed)) { _send(mine); return; }
        }
        if (_json(theirs) == _json(mine)) { _agreed = _json(mine); return; }
        _agreed = _json(theirs);
        debugPrint('layout sync: taken from Home Assistant');
        layout.apply(theirs);
        _agreed = _json(layout.toJson());         // as this version of the app reads it back
      }).then((_) {
        debugPrint('layout sync: subscribed');
        _sendApps();
      }).catchError(again);
    }).catchError((Object e) {
      // an integration that does not know "replaces" refuses the whole message: the old id goes on until it is
      // updated (the new one registered now could never take the old one's place: a move needs it unknown)
      if (rep != null && link == _link && e is Map && e['code'] == 'invalid_format') {
        debugPrint('layout sync: the integration moves no device yet ($e): $rep goes on');
        _noReplace = true;
        device = rep;
        _follow();
        return null;
      }
      return again(e);
    });
  }

  void _saved() {
    final mine = layout.toJson();
    if (_json(mine) == _agreed) return;         // what came in, written to the file
    _changed = true;
    if (ha.connected) _send(mine);
  }

  // the device's Android apps (apps.dart) for the integration's panel: its preview draws their tiles.  Sent at each
  // login and when the list changes.
  List<AndroidApp> _apps = const [];
  String _appsSent = '';
  void publishApps(List<AndroidApp> apps) { _apps = apps; _sendApps(); }

  void _sendApps() {
    if (!ha.connected || _apps.isEmpty) return;
    final list = [for (final a in _apps) {'package': a.package, 'label': a.label, 'icon': base64Encode(a.icon)}];
    final j = jsonEncode(list);
    if (j == _appsSent) return;
    _appsSent = j;
    ha.send({'type': 'echo_wall/apps/set', 'device': device, 'apps': list}).then((_) => debugPrint('layout sync: ${list.length} apps sent'))
        .catchError((e) { _appsSent = ''; debugPrint('layout sync: apps not sent ($e)'); });
  }

  void _send(Map<String, dynamic> mine) {
    ha.send({'type': 'echo_wall/set', 'device': device, 'layout': mine}).then((_) {
      _agreed = _json(mine); _changed = false;
      debugPrint('layout sync: sent');
    }).catchError((e) { debugPrint('layout sync: not sent ($e)'); });                      // refused or not connected: sent at the next save or login
  }
}
