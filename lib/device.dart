// This install of the app, as the Echo-Wall integration knows it (custom_components/echo_wall home.py): an id made
// here once and kept in the app's files (a reinstall is a new device), and what it says of itself at every login.
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'io/io.dart';

/// the app's version, as the integration's panel shows it
const appVersion = '2026.11.1';

class Device {
  final String id;
  final String name, model;
  const Device(this.id, this.name, this.model);

  static Future<Device> load() async {
    var id = '';
    try {
      final f = File('${(await getApplicationSupportDirectory()).path}/device_id');
      if (await f.exists()) id = (await f.readAsString()).trim();
      if (!RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(id)) {
        final r = Random.secure();
        const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
        id = List.generate(20, (_) => abc[r.nextInt(abc.length)]).join();
        await f.writeAsString(id);
      }
    } catch (_) {
      id = 'unsaved${DateTime.now().millisecondsSinceEpoch}';   // no files (tests): a new one each start
    }
    var model = '', name = 'Echo-Wall';
    try {
      final m = await const MethodChannel('echo_screen/keys').invokeMapMethod<String, String>('device') ?? const {};
      final maker = m['manufacturer'] ?? '', mod = m['model'] ?? '';
      model = mod.toLowerCase().startsWith(maker.toLowerCase()) || maker.isEmpty ? mod : '$maker $mod';
      if (model.isNotEmpty) name = model;
    } catch (_) {}
    return Device(id, name, model);
  }
}
