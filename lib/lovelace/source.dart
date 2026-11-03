// The dashboard the WallView draws after Home (Layout.dashboard): its config read from Home Assistant over the app's
// websocket (lovelace/config, the Echo's own login reads any dashboard that is not for administrators only) and read
// again when Home Assistant says it was saved (the event lovelace_updated, which the editor fires on every save).  A
// dashboard of a strategy (Overview untouched: Home Assistant makes it up as it draws it) has no views to read: the
// WallView then has its own room pages.
import 'package:flutter/foundation.dart';

import '../ha.dart';
import 'lovelace.dart';

class LovelaceSource extends ChangeNotifier {
  final Ha ha;
  String path = '';
  List<LView> views = const [];
  String? error;
  bool _subscribed = false;
  int _asked = 0;

  LovelaceSource(this.ha) : _fixed = false {
    ha.onConnected.add(() { _subscribed = false; _load(); });
  }

  /// a dashboard's views given, nothing asked of Home Assistant (tests, the previews)
  LovelaceSource.fixed(this.ha, this.path, this.views) : _fixed = true;
  final bool _fixed;

  /// the dashboard to follow ("" none)
  void use(String p) {
    if (p == path || _fixed) return;
    path = p;
    views = const [];
    error = null;
    _load();
  }

  // called from the WallView's build (use): told after it, never during it
  Future<void> _load() async {
    await Future<void>.delayed(Duration.zero);
    if (path.isEmpty || !ha.connected) { notifyListeners(); return; }
    final ask = ++_asked, want = path;
    if (!_subscribed) {
      _subscribed = true;
      ha.subscribe({'type': 'subscribe_events', 'event_type': 'lovelace_updated'}, (ev) {
        final p = ((ev as Map)['data'] as Map?)?['url_path'];
        if ((p ?? 'lovelace') == (path == 'lovelace' ? 'lovelace' : path)) _load();
      }).catchError((_) {});
    }
    try {
      final cfg = await ha.send({'type': 'lovelace/config', if (want != 'lovelace') 'url_path': want});
      if (ask != _asked) return;                // another dashboard asked for meanwhile
      final vs = cfg is Map ? cfg['views'] as List? : null;
      views = [for (final v in vs ?? const []) if (v is Map) LView.parse(Map<String, dynamic>.from(v))];
      error = vs == null ? 'made by a strategy: no views of its own' : null;
    } catch (e) {
      if (ask != _asked) return;
      views = const [];
      error = '$e';
      debugPrint('lovelace $want: $e');
    }
    notifyListeners();
  }
}
