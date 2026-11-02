// hassmic HomeView: Home Assistant on an Echo Show as Apple's HomeView shows a home (lib/home/), on hassmic-screen
// (the template this is a fork of: the contract with hassmic, the web screens, the keyboard, hassmic's pictures).
// The HomeView is the first screen; the integration's screens follow it in the switcher and as tiles on Home.
//
// hassmic-screen: a screen app for an Echo Show running hassmic (echo-dot-assist docs/screen-apps.md), in Flutter.
// It does what hassmic's own Java kiosk does, as a template to build on: the screens Home Assistant's hassmic
// integration chose (Home Assistant's dashboards, Music Assistant, any page) in a WebView, logged into Home Assistant
// with the Echo's own token, a handle at the top edge to switch, back to the start screen after a while untouched, and
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
import 'ha.dart';
import 'home/home_view.dart';
import 'home/layout.dart';
import 'keyboard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);   // no system UI on the Echo, none to show
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: ScreenApp()));
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
  Layout? layout;
  static const home = -2;                       // `current` while the HomeView shows
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    const MethodChannel('hassmic/keys').invokeMethod<bool>('hasInputMethod').then((has) {
      if (mounted && has == true) setState(() => ownKeyboard = false);
    }).catchError((_) {});
    const MethodChannel('hassmic/keys').invokeMethod<bool>('isRound').then((r) {
      if (mounted && r == true) setState(() => round = true);
    }).catchError((_) {});
    Layout.load().then((l) { if (mounted) setState(() => layout = l); });
    _schedule(Duration.zero);
    feed.start((s) { if (mounted) setState(() => echo = s); });      // the words, a ring, the clock's next alarm
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    poller?.cancel();
    feed.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------- hassmic's contract: the polls

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final now = s == AppLifecycleState.resumed;
    if (now == front) return;
    front = now;
    _schedule(Duration.zero);                   // /front or /back at once: hassmic takes or gives the screen by them
  }

  void _schedule(Duration d) {
    poller?.cancel();
    poller = Timer(d, () async {
      final c = await hassmic.poll(front: front);
      if (!mounted) return;
      if (front) _apply(c);
      _schedule(Duration(seconds: front ? 5 : 30));
    });
  }

  void _apply(ScreenConfig? c) {
    if (c == null) return;                      // hassmic restarting: keep what shows
    final old = cfg;
    if (!reached || old == null || c.raw != old.raw) {
      final newLogin = old == null || c.token != old.token;
      final sameScreens = old != null && _urls(old) == _urls(c);
      setState(() { cfg = c; reached = true; });
      if (newLogin) injectedFor = '';
      ha.configure(c.enabled ? c.ha : '', c.token);   // the HomeView's own connection, with the Echo's login
      if (!c.enabled) { _stop(); return; }
      _start();
      if (!sameScreens || newLogin || current == -1 || current >= c.screens.length) _home();
      return;
    }
    // untouched long enough on another screen: back to the HomeView
    if (c.enabled && web != null && c.returnSeconds > 0 && current != home &&
        DateTime.now().difference(touched).inSeconds > c.returnSeconds) {
      _home();
    }
  }

  static String _urls(ScreenConfig c) => c.screens.map((s) => s.url).join('\n');

  /// the first web page among the screens (where a tap on the clock goes), the current one where there is none
  int _firstPage(ScreenConfig c) {
    final i = c.screens.indexWhere((s) => !s.url.startsWith('hassmic:'));
    return i < 0 ? current : i;
  }

  /// the screen shown is one this app draws (hassmic:clock), not a page
  bool ownScreen(ScreenConfig c) => current >= 0 && current < c.screens.length && c.screens[current].url == 'hassmic:clock';

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

  void _show(int i) {
    final c = cfg, w = web;
    if (c == null || w == null || i < 0 || i >= c.screens.length) return;
    setState(() { current = i; bar = false; typing = false; });
    touched = DateTime.now();
    var url = c.screens[i].url;
    if (url.startsWith('hassmic:')) {           // drawn here (build); the page a tap fades into loads under it meanwhile
      final f = _firstPage(c);
      if (f < 0 || f == i || c.screens[f].url == loaded) return;
      url = c.screens[f].url;
    } else if (url == loaded) {
      return;                                   // there already (it loaded under the clock)
    }
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
    if (!reached) {
      body = const Center(child: Text('Waiting for hassmic…', style: TextStyle(color: Color(0xff8a8a8a), fontSize: 18)));
    } else if (c == null || w == null) {
      body = const SizedBox.expand();                       // the screen off: black
    } else {
      body = Column(children: [
        Expanded(child: Stack(children: [
          // a screen of hassmic's this app draws, else the page; the WebView stays (its page kept) under the clock
          WebViewWidget(controller: w),
          // the clock fades in over the page (back after idle) and out into it (a tap: the first web screen)
          Positioned.fill(child: IgnorePointer(ignoring: !ownScreen(c), child: AnimatedOpacity(
            opacity: ownScreen(c) ? 1 : 0, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut,
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _show(_firstPage(c)),
                child: ClockScreen(s: echo, round: round)),
          ))),
          // the HomeView, the same way: faded out into a web screen (its tile), back in after idle
          if (layout != null)
            Positioned.fill(child: IgnorePointer(ignoring: current != home, child: AnimatedOpacity(
              opacity: current == home ? 1 : 0, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut,
              child: HomeView(ha: ha, layout: layout!, h24: echo.h24, screens: [for (final s in c.screens) s.name], onScreen: _show),
            ))),
          _handle(),
          if (bar) _switcher(c),
        ])),
        if (typing && ownKeyboard && !ownScreen(c) && current != home)
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
        if (echo.ringing.isNotEmpty) RingOverlay(s: echo, round: round) else if (echo.words) WordsOverlay(s: echo, round: round),
      ]);
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(onPointerDown: (_) => touched = DateTime.now(), child: body),
    );
  }

  Widget _handle() => Align(
        alignment: Alignment.topCenter,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => bar ? _hideBar() : _showBar(),
          child: SizedBox(
            width: 120, height: 24,
            child: Center(child: Container(width: 56, height: 5, decoration: BoxDecoration(
                color: const Color(0x99a0a0a0), border: Border.all(color: const Color(0x55000000)), borderRadius: BorderRadius.circular(3)))),
          ),
        ),
      );

  void _showBar() {
    setState(() => bar = true);
    hideBar?.cancel();
    hideBar = Timer(const Duration(seconds: 8), _hideBar);
  }

  void _hideBar() { hideBar?.cancel(); if (mounted) setState(() => bar = false); }

  // the screens' pills: scrolled sideways where they do not fit (a Spot's 320 dp), on a round screen lower and narrower
  // (the circle's chord at the top is short)
  Widget _switcher(ScreenConfig c) => LayoutBuilder(builder: (context, box) => Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: EdgeInsets.only(top: round ? box.maxHeight * .2 : 28),
          constraints: BoxConstraints(maxWidth: box.maxWidth * (round ? .86 : 1) - 16),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xe6202124), borderRadius: BorderRadius.circular(18)),
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _pill('Home', current == home ? 0x55ffffff : 0x33ffffff, _home)),
            for (var i = 0; i < c.screens.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _pill(c.screens[i].name, i == current ? 0x55ffffff : 0x33ffffff, () => _show(i)),
              ),
            _pill('↻', 0x22ffffff, () { _hideBar(); web?.reload(); }),
          ])),
        ),
      ));

  Widget _pill(String text, int color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Color(color), borderRadius: BorderRadius.circular(14)),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ),
      );
}
