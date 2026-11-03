// The WallView in a browser: the Echo-Wall integration's panel preview of a device's Home (custom_components/echo_wall/
// frontend/panel.js; docs/integration.md).  Built for the web (`flutter build web -t lib/preview.dart`, tools/preview.sh)
// and served by the integration at /echo_wall/preview/, it runs in a same-origin iframe of the panel and takes
// everything from it:
//
//   parent.echoWallPreview.token()   Home Assistant's access token (the panel's own login), asked again when refused
//   parent.echoWallPreview.layout()  the draft to draw at the start
//   parent.echoWallPreview.info()    {h24, screens: [names], settings: {key: value}, apps: [{package, label, icon}]}:
//                                     what the Echo's app would get (apps: the Echo's Android apps as this app sent
//                                     them, LayoutSync.publishApps, their icons base64 PNG)
//   message 'echo-wall-layout'       a new draft (the panel's form changed)
//   message 'echo-wall-apps'         those apps, when the panel has them after the start
//   message 'echo-wall-editmode'     the edit mode on or off (the panel's switch)
//   message 'echo-wall-gallery'      every card at every size (home/gallery.dart) instead of the Home, with this Home
//                                     Assistant's own devices: how each would look before it is picked
//   posts   'echo-wall-pages'        the pages after Home ({group, title, kind own|room|dashboard, hidden}): the panel's
//                                     Pages list, which adds, deletes, orders and takes them off through the draft
//   posts   'echo-wall-edit'         the edit mode changed the layout (a drag, ★, −): the panel's draft; the panel saves
//
// The same WallView as on the Echo, on the same Home Assistant: what the owner arranges here is what the Echo shows.
// Nothing of the Echo's own (hassmic's requests and rings, the lock screen) is drawn; its Android apps' tiles are, as
// the Echo last sent them (a tap starts nothing here).
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsBinding;
import 'package:web/web.dart' as web;

import 'apps.dart' show AndroidApp;

import 'ha.dart';
import 'home/gallery.dart';
import 'home/layout.dart';
import 'home/widgets.dart' show Palette;
import 'home/wall_view.dart';

JSObject? get _host {
  try {
    final p = web.window.parent;
    final h = p == null ? null : (p as JSObject)['echoWallPreview'];
    // not isA<JSObject>(): that is instanceof this frame's Object, and the panel's object is of its own frame
    return h == null || h.isUndefinedOrNull ? null : h as JSObject;
  } catch (_) {
    return null;                                // not the panel's frame (another origin, or opened alone)
  }
}

Future<String> _token() async {
  final h = _host;
  if (h == null) return '';
  final p = h.callMethod<JSPromise<JSString>>('token'.toJS);
  return (await p.toDart).toDart;
}

/// a JS value as JSON's map: through JSON.stringify, which takes objects of the panel's frame too (dartify() does not:
/// it knows this frame's Object only)
Map<String, dynamic> _map(JSAny? v) {
  if (v == null || v.isUndefinedOrNull) return <String, dynamic>{};
  try {
    final j = (globalContext['JSON'] as JSObject).callMethod<JSString?>('stringify'.toJS, v)?.toDart;
    final d = j == null ? null : jsonDecode(j);
    return d is Map<String, dynamic> ? d : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}

void main() {
  runApp(const PreviewApp());
  // the tree as the browser's accessibility nodes: a screen reader reads the preview, and tests find tiles by name
  SemanticsBinding.instance.ensureSemantics();
}

class PreviewApp extends StatefulWidget {
  const PreviewApp({super.key});
  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  final ha = Ha();
  final layout = Layout();
  final editMode = ValueNotifier(false);
  final gallery = ValueNotifier(false);
  bool h24 = true;
  List<String> screens = const [];
  Map<String, String> settings = const {};
  List<AndroidApp> apps = const [];
  String _sent = '';
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    final h = _host;
    if (h != null) {
      layout.apply(_map(h.callMethod<JSAny?>('layout'.toJS)));
      final info = _map(h.callMethod<JSAny?>('info'.toJS));
      h24 = info['h24'] != false;
      screens = [for (final s in (info['screens'] as List? ?? const [])) '$s'];
      settings = {for (final e in (info['settings'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'};
      apps = _apps(info['apps']);
      editMode.value = info['editing'] == true;     // the panel's switch, set before this frame listened
      gallery.value = info['gallery'] == true;
    }
    _sent = jsonEncode(layout.toJson());
    // the WallView's own edits (layout.dart saves 500 ms after the last change): to the panel, not to Home Assistant
    layout.onSaved = () {
      final j = jsonEncode(layout.toJson());
      if (j == _sent) return;
      // only the media card's player remembered (the WallView keeps the last that played): not an edit of the draft
      Map<String, dynamic> but(String x) => (jsonDecode(x) as Map<String, dynamic>)..remove('player');
      final quiet = jsonEncode(but(j)) == jsonEncode(but(_sent));
      _sent = j;
      if (quiet) return;
      web.window.parent?.postMessage({'type': 'echo-wall-edit', 'layout': layout.toJson()}.jsify(), web.window.location.origin.toJS);
    };
    web.window.addEventListener('message', ((web.MessageEvent e) {
      if (e.origin != web.window.location.origin) return;
      final m = _map(e.data);
      if (m['type'] == 'echo-wall-layout') {
        final l = (m['layout'] as Map?)?.cast<String, dynamic>() ?? {};
        _sent = jsonEncode(l);
        layout.apply(l);
        _sent = jsonEncode(layout.toJson());
      } else if (m['type'] == 'echo-wall-apps') {
        setState(() => apps = _apps(m['apps']));
      } else if (m['type'] == 'echo-wall-gallery') {
        gallery.value = m['on'] == true;
      } else if (m['type'] == 'echo-wall-editmode') {
        editMode.value = m['on'] == true;
      }
    }).toJS);
    // a login the panel renews: Home Assistant's access tokens last 30 minutes; refused, ask the panel again
    ha.addListener(() {
      if (ha.error != null && ha.error!.contains('refused') && !_refreshing) {
        _refreshing = true;
        _token().then((t) => ha.configure(web.window.location.origin, t)).whenComplete(() => _refreshing = false);
      }
    });
    _token().then((t) => ha.configure(web.window.location.origin, t));
  }

  static List<AndroidApp> _apps(Object? v) => [
        for (final a in (v is List ? v : const []))
          if (a is Map)
            AndroidApp('${a['package']}', '${a['label']}', (() { try { return base64Decode('${a['icon'] ?? ''}'); } catch (_) { return Uint8List(0); } })()),
      ];

  @override
  Widget build(BuildContext context) => MaterialApp(
        // the pages swiped with a mouse or a trackpad too, not only by touch (Flutter's default on the web: touch only)
        scrollBehavior: const MaterialScrollBehavior().copyWith(dragDevices: {
          PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus}),
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Inter', brightness: Brightness.dark, splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ValueListenableBuilder(valueListenable: gallery, builder: (_, on, _) => on
              ? ListenableBuilder(listenable: Listenable.merge([ha, layout]), builder: (_, _) => SizedBox.expand(child: DecoratedBox(
                  decoration: BoxDecoration(gradient: Palette.of(layout.wallpaper == Wallpaper.photo ? Wallpaper.dusk : layout.wallpaper).wall),
                  child: SingleChildScrollView(child: CardGallery(ha: ha, h24: h24,
                      p: Palette.of(layout.wallpaper == Wallpaper.photo ? Wallpaper.dusk : layout.wallpaper))))))
              : WallView(ha: ha, layout: layout, h24: h24, screens: screens, onScreen: (_) {}, settings: settings, apps: apps,
                  onPages: (l) => web.window.parent?.postMessage({'type': 'echo-wall-pages', 'pages': l}.jsify(), web.window.location.origin.toJS),
                  editMode: editMode, preview: true)),
        ),
      );
}
