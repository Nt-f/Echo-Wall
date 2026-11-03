// The apps the owner installed beside this one (a YouTube client, a music app; echo-dot-assist docs/screen-apps.md
// "Other apps"): listed by the Android side (Launchable.kt) for the switcher and Home's cards, and started there with
// the app bar over them (AppBarService.kt: pulled down from the top edge, Home first).  While one has the screen this
// app is paused, and it does not poll /back then: the bar's process polls /lent/<package> instead, so that hassmic keeps
// its own layer off the other app.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidApp {
  final String package, label;
  final Uint8List icon;                         // PNG, 64 dp
  const AndroidApp(this.package, this.label, this.icon);
  /// its key among Home's widgets (homeOrder, places) and in the hidden set: never an entity id or a screen's name
  String get key => 'app:$package';
}

class Apps extends ChangeNotifier {
  static const _ch = MethodChannel('echo_screen/apps');
  List<AndroidApp> list = const [];
  /// this app started one and is not in front since: the screen is lent to it
  bool lent = false;

  Apps() {
    _ch.setMethodCallHandler((c) async { if (c.method == 'changed') refresh(); });
    refresh();
  }

  Future<void> refresh() async {
    try {
      final r = await _ch.invokeListMethod<Map<dynamic, dynamic>>('list') ?? const [];
      list = [for (final m in r) AndroidApp('${m['package']}', '${m['label']}', m['icon'] as Uint8List)];
      notifyListeners();
    } catch (_) {}                              // not on Android (tests): none
  }

  Future<bool> launch(String package) async {
    lent = true;                                // before the pause it causes: no /back poll in between
    try {
      if (await _ch.invokeMethod<bool>('launch', package) == true) return true;
    } catch (_) {}
    lent = false;
    return false;
  }
}
