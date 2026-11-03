// Echo-Wall: Home Assistant on an Echo Show as Apple's HomeView shows a home (lib/home/), on Echo-Screen
// (the template this is a fork of: the contract with hassmic, the web screens, the keyboard, hassmic's pictures).
// The WallView is the first screen; the integration's screens follow it in the switcher and as tiles on Home.
//
// Echo-Screen: a screen app for an Echo Show running hassmic (echo-dot-assist docs/screen-apps.md), in Flutter.
// It does what hassmic's own Java kiosk does, as a template to build on: the screens Home Assistant's hassmic
// integration chose (Home Assistant's dashboards, Music Assistant, any page) in a WebView, logged into Home Assistant
// with the Echo's own token, a swipe down from the top edge to switch, back to the start screen after a while untouched, and
// a keyboard of its own (the Echo has none).  Fork it and replace the WebView with widgets of your own: the config
// (lib/hassmic.dart) gives Home Assistant's address and a token for its websocket API too.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'hassmic.dart';
import 'echo_ui.dart';
import 'apps.dart';
import 'ha.dart';
import 'home/wall_view.dart';
import 'home/layout.dart';
import 'home/layout_sync.dart';
import 'device.dart';
import 'keyboard.dart';
import 'login.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);   // no system UI on the Echo, none to show
  // Inter: the open face nearest Apple's San Francisco; Apple's page transitions and scrolling everywhere
  runApp(MaterialApp(debugShowCheckedModeBanner: false, home: const ScreenApp(), theme: ThemeData(
    fontFamily: 'Inter', brightness: Brightness.dark, splashFactory: NoSplash.splashFactory, highlightColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: CupertinoPageTransitionsBuilder()}),
  )));
}

class ScreenApp extends StatefulWidget {
  const ScreenApp({super.key});
  @override
  State<ScreenApp> createState() => _ScreenAppState();
}

/// put into every page: tells the app (channel HassmicKiosk) whether a text field has the focus, through shadow roots
/// (Home Assistant's fields are in them); kind 1 a password, 2 numbers
const _focusJs = '''(function(){if(window.__hmk)return;window.__hmk=1;
function deep(){var a=document.activeElement;while(a&&a.shadowRoot&&a.shadowRoot.activeElement)a=a.shadowRoot.activeElement;return a}
function ed(e){if(!e)return false;if(e.isContentEditable)return true;var t=(e.tagName||'').toLowerCase();if(t==='textarea')return true;
if(t!=='input')return false;var y=(e.type||'text').toLowerCase();
return['button','checkbox','radio','range','submit','reset','file','color','image','hidden'].indexOf(y)<0}
function tell(){try{var e=deep(),k=e&&e.type==='password'?1:e&&(e.type==='number'||e.inputMode==='numeric'||e.inputMode==='decimal')?2:0;
HassmicKiosk.postMessage(JSON.stringify({typing:ed(e),kind:k}))}catch(x){}}
document.addEventListener('focusin',function(){setTimeout(tell,0)},true);
document.addEventListener('focusout',function(){setTimeout(tell,60)},true);tell()})()''';

class _ScreenAppState extends State<ScreenApp> with WidgetsBindingObserver {
  final hassmic = Hassmic();
  final feed = EchoStateFeed();
  EchoState echo = const EchoState();
  final ha = Ha();
  final apps = Apps();                          // the owner's other apps: the switcher's and Home's (apps.dart)
  Layout? layout;
  static const home = -2;                       // `current` while the WallView shows
  ScreenConfig? cfg;
  bool reached = false, front = true;
  WebViewController? web;
  int current = -1;
  String injectedFor = '';
  String loaded = '';                           // the page the WebView has (under the clock too)
  DateTime touched = DateTime.now();
  bool bar = false, typing = false, numbers = false;
  bool ownKeyboard = true;                      // false where the device has an input method of its own (not an Echo)
  bool round = false;                           // a round screen (Echo Spot): nothing near its corners
  Timer? poller, hideBar;
  // without hassmic (a tablet): the app's own login to Home Assistant (lib/login.dart)
  HaLogin? login;
  int _misses = 0;                              // hassmic's config asked for and not had, since the start
  bool standalone = false, needLogin = false;
  String? loginError;
  Timer? _renewer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    apps.addListener(() { if (mounted) setState(() {}); });
    const MethodChannel('echo_screen/keys').invokeMethod<bool>('hasInputMethod').then((has) {
      if (mounted && has == true) setState(() => ownKeyboard = false);
    }).catchError((_) {});
    const MethodChannel('echo_screen/keys').invokeMethod<bool>('isRound').then((r) {
      if (mounted && r == true) setState(() => round = true);
    }).catchError((_) {});
    HaLogin.load().then((l) => login = l);
    Future.wait([Layout.load(), Device.load()]).then((r) {
      final l = r[0] as Layout, d = r[1] as Device;
      if (mounted) setState(() => layout = l);
      final sync = LayoutSync(ha, l, device: d.id, info: () {
        final v = WidgetsBinding.instance.platformDispatcher.views.first;
        final c = cfg;
        return {'name': d.name, 'model': d.model, 'version': appVersion,
            'screen': [(v.physicalSize.width / v.devicePixelRatio).round(), (v.physicalSize.height / v.devicePixelRatio).round()],
            'screens': [if (c != null) for (final s in c.screens) if (_offered(s)) s.name]};
      });
      sync.publishApps(apps.list);
      apps.addListener(() => sync.publishApps(apps.list));
    });
    _schedule(Duration.zero);
    feed.start((s) {                            // the words, a ring, the clock's next alarm, the screen's mode
      if (!mounted) return;
      final keep = s.display == 'always' || s.display == 'always_dim';
      if (keep != (echo.display == 'always' || echo.display == 'always_dim') || echo.v == 0) {
        // "always on": the window keeps the screen on too, whatever the screen timeout says (hassmic sets that, but
        // a tool that sets it after hassmic would put the screen to sleep, and a sleeping panel takes no touch)
        const MethodChannel('echo_screen/keys').invokeMethod('keepOn', keep).catchError((_) => null);
      }
      setState(() => echo = s);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    poller?.cancel();
    _renewer?.cancel();
    feed.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------- hassmic's contract: the polls

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final now = s == AppLifecycleState.resumed;
    if (now == front) return;
    front = now;
    if (now) apps.lent = false;                 // back from the app it started (Back there, or the app bar's Home)
    _schedule(Duration.zero);                   // /front or /back at once: hassmic takes or gives the screen by them
  }

  void _schedule(Duration d) {
    poller?.cancel();
    poller = Timer(d, () async {
      // paused for an app it started: the app bar's process polls /lent meanwhile; a /back here would end that
      if (!front && apps.lent) { _schedule(const Duration(seconds: 30)); return; }
      final c = await hassmic.poll(front: front);
      if (!mounted) return;
      if (c == null && !reached && ++_misses >= 2) _standalone();   // no hassmic here: the app's own login
      if (front) _apply(c);
      _schedule(Duration(seconds: front ? 5 : 30));
    });
  }

  /// a device without hassmic: Home Assistant with the app's own login, or its login screen
  Future<void> _standalone() async {
    final l = login ?? await HaLogin.load();
    login = l;
    if (reached || !mounted) return;
    final t = l.has ? await l.fresh() : null;
    if (!mounted || reached) return;
    if (t == null) { setState(() { needLogin = true; loginError = l.has ? 'Home Assistant did not take the saved login: log in again' : null; }); return; }
    standalone = true;
    ha.renew = l.fresh;
    _renewer?.cancel();                         // access tokens last 30 minutes: the cameras' requests use one too
    _renewer = Timer.periodic(const Duration(minutes: 20), (_) async { final t = await l.fresh(); if (t != null) ha.freshToken(t); });
    setState(() => needLogin = false);
    _apply(ScreenConfig.standalone(l.url, t));
  }

  void _apply(ScreenConfig? c) {
    if (c == null) return;                      // hassmic restarting: keep what shows
    if (standalone && !c.raw.startsWith('standalone ')) {   // hassmic came after all (it started late): its login wins
      standalone = false; ha.renew = null; _renewer?.cancel();
    }
    final old = cfg;
    if (!reached || old == null || c.raw != old.raw) {
      final newLogin = old == null || c.token != old.token;
      final sameScreens = old != null && _urls(old) == _urls(c);
      setState(() { cfg = c; reached = true; });
      if (newLogin) injectedFor = '';
      ha.configure(c.enabled ? c.ha : '', c.token);   // the WallView's own connection, with the Echo's login
      if (!c.enabled) { _stop(); return; }
      _start();
      if (!sameScreens || newLogin || current == -1 || current >= c.screens.length) _home();
      return;
    }
    // untouched long enough on another screen: back to the WallView
    if (c.enabled && web != null && c.returnSeconds > 0 && current != home &&
        DateTime.now().difference(touched).inSeconds > c.returnSeconds) {
      _home();
    }
  }

  static String _urls(ScreenConfig c) => c.screens.map((s) => s.url).join('\n');

  /// a screen offered here: the WallView replaces the template's clock (hassmic:clock; its lock screen is the clock
  /// here) and the old web wall panel (hassmic's wall.html), which an integration set up before may still list
  static bool _offered(Screen s) => !s.url.startsWith('hassmic:') && !s.url.contains('/echo_local/wall.html');

  // ---------------------------------------------------------------- the WebView

  void _start() {
    if (web != null) return;
    final w = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('HassmicKiosk', onMessageReceived: (m) {
        try {
          final j = jsonDecode(m.message) as Map<String, dynamic>;
          setState(() { typing = j['typing'] == true; numbers = j['kind'] == 2; });
        } catch (_) {}
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => typing = false),
        onPageFinished: (_) => web?.runJavaScript(_focusJs),
        onWebResourceError: (e) {
          if (e.isForMainFrame != true) return;
          final at = current;                   // Home Assistant restarting, Wi-Fi back later: the screen again
          Timer(const Duration(seconds: 15), () { if (mounted && current == at) { loaded = ''; _show(at); } });
        },
      ));
    if (w.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);          // adb is root's on the Echo already
      (w.platform as AndroidWebViewController).setMediaPlaybackRequiresUserGesture(false);
    }
    setState(() => web = w);
  }

  void _stop() {
    loaded = '';
    setState(() { web = null; current = -1; typing = false; bar = false; });    // the WebView goes with its widget
  }

  static String _origin(String u) {
    final x = Uri.tryParse(u);
    if (x == null || !x.hasScheme || x.host.isEmpty) return '';
    return '${x.scheme}://${x.host}${x.hasPort ? ':${x.port}' : ''}';
  }

  void _home() {
    setState(() { current = home; bar = false; typing = false; });
    touched = DateTime.now();
  }

  /// a dashboard's view in Home Assistant's own UI, from one of its cards the WallView cannot draw (a HACS card);
  /// not one of the screens (Home, the bar, or the return to the start screen leave it)
  static const dashView = -3;
  void _openPath(String path) {
    final c = cfg, w = web;
    if (c == null || w == null || c.ha.isEmpty) return;
    setState(() { current = dashView; bar = false; typing = false; });
    touched = DateTime.now();
    final url = '${c.ha}$path';
    if (url != loaded) _load(c, w, url);
  }

  void _show(int i) {
    final c = cfg, w = web;
    if (c == null || w == null || i < 0 || i >= c.screens.length) return;
    setState(() { current = i; bar = false; typing = false; });
    touched = DateTime.now();
    final url = c.screens[i].url;
    if (!_offered(c.screens[i])) { _home(); return; }   // the clock, the old wall: the WallView instead
    if (url == loaded) return;                  // there already
    _load(c, w, url);
  }

  void _load(ScreenConfig c, WebViewController w, String url) {
    final hao = _origin(c.ha);
    loaded = url;
    if (c.token.isNotEmpty && hao.isNotEmpty && _origin(url) == hao && injectedFor != hao) {
      // the login: the token into Home Assistant's origin as its frontend keeps its own, before its first page
      injectedFor = hao;
      final tokens = jsonEncode({
        'access_token': c.token, 'token_type': 'Bearer', 'expires_in': 315360000, 'hassUrl': hao,
        'clientId': '$hao/', 'expires': 4102444800000, 'refresh_token': '',
      });
      w.loadHtmlString(
          '<!doctype html><script>try{localStorage.setItem("hassTokens",${jsonEncode(tokens)})}catch(e){}'
          'location.replace(${jsonEncode(url)})</script>',
          baseUrl: '$hao/hassmic-kiosk-login');
    } else {
      w.loadRequest(Uri.parse(url));
    }
  }

  // ---------------------------------------------------------------- what is on the screen

  @override
  Widget build(BuildContext context) {
    final c = cfg, w = web;
    Widget body;
    if (!reached && needLogin && login != null) {
      return LoginScreen(login: login!, error: loginError, onDone: () { setState(() => needLogin = false); _standalone(); });
    }
    if (!reached) {
      body = const Center(child: Text('Connecting…', style: TextStyle(color: Color(0xff8a8a8a), fontSize: 18)));
    } else if (c == null || w == null) {
      body = const SizedBox.expand();                       // the screen off: black
    } else {
      body = Column(children: [
        Expanded(child: Stack(children: [
          // the page; the WebView stays (its page kept) under the WallView
          WebViewWidget(controller: w),
          // the WallView, the same way: faded out into a web screen (its tile), back in after idle
          if (layout != null)
            Positioned.fill(child: IgnorePointer(ignoring: current != home, child: AnimatedOpacity(
              opacity: current == home ? 1 : 0, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut,
              child: WallView(ha: ha, layout: layout!, h24: echo.h24,
                  screens: [for (final s in c.screens) if (_offered(s)) s.name],
                  onScreen: (i) => _show(c.screens.indexOf([for (final s in c.screens) if (_offered(s)) s][i])),
                  apps: apps.list, onApp: _launch, onDashboard: _openPath,
                  settings: layout!.settingsOver(c.settings), nextAlarm: echo.nextAlarmText, round: round, echo: echo),
            ))),
          // open: a touch anywhere else, or a swipe up, puts it away (the touch goes no further: it was for the bar)
          if (bar) Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _hideBar,
              onVerticalDragUpdate: (d) { if (d.delta.dy < -2) _hideBar(); })),
          _handle(),
          if (bar) _switcher(c),
        ])),
        if (typing && ownKeyboard && current != home)
          Keyboard(
            round: round,
            numbers: numbers,
            fallback: (s) => w.runJavaScript('document.execCommand("insertText",false,${jsonEncode(s)})'),
            onHide: () => setState(() => typing = false),
          ),
      ]);
    }
    // over everything: a ring, then a request's words (hassmic leaves the screen to this app for them: front/draws)
    if (reached && c != null && c.enabled) {
      body = Stack(children: [
        body,
        // on the WallView, its own glass draws these (home/voice.dart); on a web screen, the template's
        if (current != home) ...[
          if (echo.ringing.isNotEmpty) RingOverlay(s: echo, round: round) else if (echo.words) WordsOverlay(s: echo, round: round),
        ],
      ]);
    }
    // never left by Back (a remote, a keyboard's Escape): the screen app is all there is; its sheets still close by it
    return PopScope(canPop: false, child: Scaffold(
      backgroundColor: Colors.black,
      body: Listener(onPointerDown: (_) => touched = DateTime.now(), child: body),
    ));
  }

  // pulled down from the top edge, as the app bar over the other apps (AppBarService.kt) opens: nothing drawn there
  // (the owner's choice: no pill over the pages), and a tap does nothing, so only a swipe down opens it
  Widget _handle() => Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(widthFactor: .4, child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (d) { if (!bar && d.delta.dy > 2) _showBar(); },
          child: const SizedBox(height: 24),
        )),
      );

  void _showBar() {
    setState(() => bar = true);
    hideBar?.cancel();
    hideBar = Timer(const Duration(seconds: 8), _hideBar);
  }

  void _hideBar() { hideBar?.cancel(); if (mounted) setState(() => bar = false); }

  // the switcher: the same bar as the one over the other apps (AppBarService.kt), so that it is one bar wherever one is:
  // dropped from the top edge, dark glass, a column of icon and name per place (Home first, then the integration's
  // screens, then the owner's apps), the one shown lit; scrolled sideways where it does not fit (a Spot's 320 dp), on a
  // round screen lower (the circle's chord at the top is short)
  Widget _switcher(ScreenConfig c) => LayoutBuilder(builder: (context, box) => Align(
        alignment: Alignment.topCenter,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: -120, end: 0), duration: const Duration(milliseconds: 180), curve: Curves.easeOut,
          builder: (_, y, child) => Transform.translate(offset: Offset(0, y), child: child),
          child: GestureDetector(
           onVerticalDragUpdate: (d) { if (d.delta.dy < -2) _hideBar(); },       // swiped back up
           child: Container(
            margin: EdgeInsets.only(top: round ? box.maxHeight * .2 : 12, left: 16, right: 16),
            constraints: BoxConstraints(maxWidth: box.maxWidth * (round ? .86 : 1) - 32),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xe6202124), borderRadius: BorderRadius.circular(22)),
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: [
              _item('Home', current == home, _home, icon: Icons.home_rounded),
              for (var i = 0; i < c.screens.length; i++)
                if (_offered(c.screens[i])) _item(c.screens[i].name, i == current, () => _show(i), icon: _screenIcon(c.screens[i].name)),
              for (final a in apps.list) _item(a.label, false, () => _launch(a.package), png: a.icon),
              if (current != home) _item('Reload', false, () { _hideBar(); web?.reload(); }, icon: Icons.refresh_rounded),
            ])),
          )),
        ),
      ));

  static IconData _screenIcon(String name) => RegExp('music', caseSensitive: false).hasMatch(name) ? Icons.music_note_rounded
      : RegExp('clock', caseSensitive: false).hasMatch(name) ? Icons.schedule_rounded
      : RegExp('assistant|home', caseSensitive: false).hasMatch(name) ? Icons.dashboard_rounded : Icons.public_rounded;

  /// one place in the bar, as AppBarService.item draws it: 84 dp wide, a 48 dp icon, the name under it, lit when shown
  Widget _item(String label, bool current, VoidCallback onTap, {IconData? icon, Uint8List? png}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 84, margin: const EdgeInsets.symmetric(horizontal: 2), padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          decoration: current ? BoxDecoration(color: const Color(0x33ffffff), borderRadius: BorderRadius.circular(14)) : null,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 48, height: 48, child: png != null
                ? Image.memory(png, gaplessPlayback: true, filterQuality: FilterQuality.medium)
                : DecoratedBox(decoration: BoxDecoration(color: const Color(0x2effffff), borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: Colors.white, size: 28))),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ),
      );

  /// another app of the owner's, with the app bar over it (apps.dart); Home's cards and the switcher's pills
  void _launch(String package) {
    _hideBar();
    apps.launch(package);
  }
}
