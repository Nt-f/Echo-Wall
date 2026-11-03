// Home Assistant over its websocket API, with the token hassmic hands the screen app (lib/hassmic.dart): the states
// (subscribe_entities, the compressed form Home Assistant's own frontend gets), the area, device and entity
// registries for display, and actions.  One connection, opened again 5 s after it drops; listeners are told after
// every change (a ChangeNotifier), the widgets ask for what they show.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class EntityState {
  String state;
  Map<String, dynamic> attr;
  EntityState(this.state, this.attr);
  String get name => (attr['friendly_name'] as String?) ?? '';
  num? numAttr(String k) => attr[k] is num ? attr[k] as num : null;
}

class Area {
  final String id, name;
  const Area(this.id, this.name);
}

class Ha extends ChangeNotifier {
  String _url = '', _token = '';
  WebSocket? _ws;
  int _id = 1;
  final _pending = <int, Completer<dynamic>>{};
  final _subs = <int, void Function(dynamic)>{};
  Timer? _retry;
  bool connected = false;
  String? error;

  final states = <String, EntityState>{};
  var areas = <Area>[];
  final _entityArea = <String, String>{}, _deviceArea = <String, String>{}, _entityDevice = <String, String>{};
  final hiddenByHa = <String>{};               // hidden in Home Assistant, or a config/diagnostic entity
  int version = 0;                             // bumps on every change: what changed is not tracked per entity

  String get url => _url;
  String get token => _token;

  /// (re)connects when the address or the token changed
  void configure(String url, String token) {
    if (url == _url && token == _token) return;
    _url = url; _token = token;
    _close();
    if (url.isNotEmpty && token.isNotEmpty) _connect();
  }

  void _close() {
    _retry?.cancel();
    _ws?.close();
    _ws = null;
    connected = false;
  }

  Future<void> _connect() async {
    final u = Uri.parse(_url);
    final ws = '${u.scheme == 'https' ? 'wss' : 'ws'}://${u.host}${u.hasPort ? ':${u.port}' : ''}/api/websocket';
    try {
      final s = await WebSocket.connect(ws).timeout(const Duration(seconds: 10));
      _ws = s;
      s.listen(_message, onDone: _dropped, onError: (_) => _dropped(), cancelOnError: true);
    } catch (e) {
      error = 'Home Assistant not reached ($e)';
      notifyListeners();
      _later();
    }
  }

  void _dropped() {
    connected = false;
    for (final c in _pending.values) { if (!c.isCompleted) c.completeError('closed'); }
    _pending.clear(); _subs.clear();
    notifyListeners();
    _later();
  }

  void _later() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 5), () { if (_ws == null || !connected) { _ws = null; _connect(); } });
  }

  void _message(dynamic raw) {
    final m = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (m['type']) {
      case 'auth_required':
        _ws?.add(jsonEncode({'type': 'auth', 'access_token': _token}));
      case 'auth_invalid':
        error = 'Home Assistant refused the login: set the screen up again from the hassmic integration';
        notifyListeners();
      case 'auth_ok':
        connected = true; error = null;
        _started();
      case 'result':
        final c = _pending.remove(m['id']);
        if (c == null) return;
        if (m['success'] == true) { c.complete(m['result']); } else { c.completeError(m['error'] ?? 'failed'); }
      case 'event':
        _subs[m['id']]?.call(m['event']);
    }
  }

  Future<dynamic> send(Map<String, dynamic> msg) {
    final ws = _ws;
    if (ws == null || !connected) return Future.error('not connected');
    final id = _id++, c = Completer<dynamic>();
    _pending[id] = c;
    ws.add(jsonEncode({...msg, 'id': id}));
    return c.future;
  }

  Future<dynamic> subscribe(Map<String, dynamic> msg, void Function(dynamic) on) {
    final ws = _ws;
    if (ws == null) return Future.error('not connected');
    final id = _id++, c = Completer<dynamic>();
    _pending[id] = c; _subs[id] = on;
    ws.add(jsonEncode({...msg, 'id': id}));
    return c.future;
  }

  Future<void> _started() async {
    subscribe({'type': 'subscribe_entities'}, _entities).catchError((_) {});
    await _registries().catchError((_) {});
    for (final t in ['area_registry_updated', 'entity_registry_updated', 'device_registry_updated']) {
      Timer? t2;
      subscribe({'type': 'subscribe_events', 'event_type': t}, (_) {
        t2?.cancel(); t2 = Timer(const Duration(milliseconds: 1500), () => _registries().catchError((_) {}));
      }).catchError((_) {});
    }
    notifyListeners();
  }

  /// the compressed states: a = whole states, c = changes ("+" set, "-" removed attributes), r = removed entities
  void _entities(dynamic ev) {
    final e = ev as Map<String, dynamic>;
    (e['a'] as Map<String, dynamic>?)?.forEach((id, v) {
      states[id] = EntityState('${v['s']}', Map<String, dynamic>.from(v['a'] as Map? ?? {}));
    });
    (e['c'] as Map<String, dynamic>?)?.forEach((id, d) {
      final st = states[id];
      if (st == null) return;
      final plus = d['+'] as Map<String, dynamic>?, minus = d['-'] as Map<String, dynamic>?;
      if (plus != null) {
        if (plus.containsKey('s')) st.state = '${plus['s']}';
        (plus['a'] as Map<String, dynamic>?)?.forEach((k, v) => st.attr[k] = v);
      }
      for (final k in (minus?['a'] as List? ?? const [])) { st.attr.remove(k); }
    });
    for (final id in (e['r'] as List? ?? const [])) { states.remove(id); }
    version++;
    notifyListeners();
  }

  Future<void> _registries() async {
    final res = await Future.wait([
      send({'type': 'config/area_registry/list'}),
      send({'type': 'config/device_registry/list'}).catchError((_) => <dynamic>[]),
      send({'type': 'config/entity_registry/list_for_display'}),
    ]);
    areas = [for (final a in res[0] as List) Area('${a['area_id']}', '${a['name']}')]..sort((x, y) => x.name.compareTo(y.name));
    _deviceArea.clear(); _entityArea.clear(); _entityDevice.clear(); hiddenByHa.clear();
    for (final d in res[1] as List) { if (d['area_id'] != null) _deviceArea['${d['id']}'] = '${d['area_id']}'; }
    for (final e in (res[2] as Map<String, dynamic>)['entities'] as List) {
      final id = '${e['ei']}';
      if (e['ai'] != null) _entityArea[id] = '${e['ai']}';
      if (e['di'] != null) _entityDevice[id] = '${e['di']}';
      if (e['hb'] == true || e['ec'] != null) hiddenByHa.add(id);
    }
    version++;
    notifyListeners();
  }

  /// the other entities of an entity's device (a camera's other streams: an ONVIF camera has one entity per profile)
  List<String> sameDevice(String id) {
    final d = _entityDevice[id];
    return d == null ? const [] : [for (final e in _entityDevice.entries) if (e.value == d && e.key != id) e.key];
  }

  String? areaOf(String id) => _entityArea[id] ?? _deviceArea[_entityDevice[id] ?? ''];
  String areaName(String? id) => areas.firstWhere((a) => a.id == id, orElse: () => const Area('', '')).name;

  Future<void> call(String domain, String service, String entity, [Map<String, dynamic> data = const {}]) =>
      send({'type': 'call_service', 'domain': domain, 'service': service, 'service_data': data, 'target': {'entity_id': entity}})
          .catchError((e) { debugPrint('ha: $domain.$service $entity: $e'); return null; });

  /// play or pause a player.  Paused where it can pause; where it cannot, or the pause fails, stopped: Music
  /// Assistant playing an AirPlay stream from a phone (its AirPlay receiver plugin) took media_play_pause and did
  /// nothing, the button looked dead
  Future<void> playPause(String id) async {
    final st = states[id];
    final f = (st?.numAttr('supported_features') ?? 0).toInt();
    debugPrint('ha: play/pause $id: ${st?.state}, features $f, source ${st?.attr['source']}, app ${st?.attr['app_id'] ?? st?.attr['app_name']}');
    if (st?.state != 'playing') return call('media_player', 'media_play', id);
    Future<dynamic> svc(String s) => send({'type': 'call_service', 'domain': 'media_player', 'service': s, 'target': {'entity_id': id}});
    try {
      if (f & 1 != 0) return await svc('media_pause');
    } catch (e) {
      debugPrint('ha: media_pause $id: $e; stopping instead');
    }
    try {
      await svc('media_stop');
    } catch (e) {
      debugPrint('ha: media_stop $id: $e');
    }
  }

  /// an image of Home Assistant's (a camera, a cover): the address, with the login as a header for Image.network
  Uri image(String path) => Uri.parse(_url).resolve(path);
  /// a camera's live stream (HLS, the camera's own codec, so no transcoding on Home Assistant): its address, which
  /// carries its own token; null where the camera has none or Home Assistant's stream integration failed
  Future<Uri?> cameraStream(String id) async {
    try {
      final r = await send({'type': 'camera/stream', 'entity_id': id});
      final url = (r as Map?)?['url'] as String?;
      return url == null ? null : image(url);
    } catch (_) {
      return null;
    }
  }

  Map<String, String> get authHeader => {'Authorization': 'Bearer $_token'};
}

String domainOf(String id) => id.substring(0, id.indexOf('.'));
