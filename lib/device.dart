// This install of the app, as the Echo-Wall integration knows it (custom_components/echo_wall home.py): an id, and what
// it says of itself at every login.
//
// The id is one a reinstall gives again, so the device keeps its layout in Home Assistant: on an Echo, hassmic's node
// name ("echo-" + the node of GET /api/hello, which the Echo makes from its Wi-Fi MAC), else Android's id for this app
// ("android-" + ANDROID_ID), else a random one kept in the app's files.  An install that had another id (a random one
// of before, kept in its files) says so at its next login ("replaces"), and the integration moves that device, layout
// and all, to the new id; the file holds the new one once Home Assistant took it (commit()).
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'io/io.dart';

/// the app's version, as the integration's panel shows it
const appVersion = '2026.11.2';

final _idOk = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

class Device {
  final String id;
  final String name, model;
  final String? replaces;                       // the id this install had before (moved to this one at the login)
  final File? _file;
  const Device(this.id, this.name, this.model, {this.replaces, File? file}) : _file = file;

  /// the stable id from what the Echo or Android say: on an Echo hassmic's node, else Android's id
  @visibleForTesting
  static String? stableId({String? node, String? androidId}) {
    String clean(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '-');
    if (node != null && node.isNotEmpty) { final id = 'echo-${clean(node)}'; if (_idOk.hasMatch(id)) return id; }
    if (androidId != null && androidId.length >= 8 && androidId != '9774d56d682e549c') {   // (an emulator's known one)
      final id = 'android-${clean(androidId)}'; if (_idOk.hasMatch(id)) return id;
    }
    return null;
  }

  /// hassmic's node on this Echo (GET /api/hello: unsigned, the page's own first call), none elsewhere
  static Future<String?> _hassmicNode() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final rq = await c.getUrl(Uri.parse('http://127.0.0.1:28931/api/hello'));
      final rs = await rq.close().timeout(const Duration(seconds: 3));
      if (rs.statusCode != 200) return null;
      final j = jsonDecode(await rs.transform(utf8.decoder).join()) as Map;
      return j['node'] as String?;
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  static Future<Device> load() async {
    var model = '', name = 'Echo-Wall', androidId = '';
    try {
      final m = await const MethodChannel('echo_screen/keys').invokeMapMethod<String, String>('device') ?? const {};
      final maker = m['manufacturer'] ?? '', mod = m['model'] ?? '';
      model = mod.toLowerCase().startsWith(maker.toLowerCase()) || maker.isEmpty ? mod : '$maker $mod';
      if (model.isNotEmpty) name = model;
      androidId = m['android_id'] ?? '';
    } catch (_) {}
    File? f;
    var kept = '';
    try {
      f = File('${(await getApplicationSupportDirectory()).path}/device_id');
      if (await f.exists()) kept = (await f.readAsString()).trim();
    } catch (_) {
      f = null;                                 // no files (tests)
    }
    final stable = stableId(node: await _hassmicNode(), androidId: androidId);
    if (stable != null) {
      return Device(stable, name, model, replaces: _idOk.hasMatch(kept) && kept != stable ? kept : null, file: f);
    }
    if (_idOk.hasMatch(kept)) return Device(kept, name, model, file: f);
    final r = Random.secure();
    const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final id = f == null ? 'unsaved${DateTime.now().millisecondsSinceEpoch}' : List.generate(20, (_) => abc[r.nextInt(abc.length)]).join();
    final d = Device(id, name, model, file: f);
    await d.commit();
    return d;
  }

  /// the id kept in the app's files, once Home Assistant took it (a move of the old one done, or no old one)
  Future<void> commit() async {
    try { await _file?.writeAsString(id); } catch (_) {}
  }
}
