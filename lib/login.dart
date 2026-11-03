// Echo-Wall's own login to Home Assistant, for a device without hassmic (a tablet; docs/integration.md "Devices"):
// Home Assistant's login page in a WebView, as its own apps do it (IndieAuth with the client id on Home Assistant's
// own origin, so no app registration: client_id = <ha>/, redirect_uri = <ha>/?auth_callback=1), the authorization code
// taken off the redirect, exchanged for tokens at /auth/token.  The refresh token is kept in the app's files; access
// tokens last 30 minutes and are renewed from it (Ha.renew, and every 20 minutes for the camera's requests).
//
// On an Echo Show hassmic gives the address and a token (lib/hassmic.dart): this is not used there.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'io/io.dart';

class HaLogin {
  String url = '', refresh = '', access = '';
  DateTime expires = DateTime.fromMillisecondsSinceEpoch(0);
  File? _file;

  bool get has => url.isNotEmpty && refresh.isNotEmpty;

  static Future<HaLogin> load() async {
    final l = HaLogin();
    try {
      l._file = File('${(await getApplicationSupportDirectory()).path}/login.json');
      if (await l._file!.exists()) {
        final j = jsonDecode(await l._file!.readAsString()) as Map<String, dynamic>;
        l.url = '${j['url'] ?? ''}'; l.refresh = '${j['refresh'] ?? ''}';
      }
    } catch (_) {}                              // none yet, or not readable: log in again
    return l;
  }

  Future<void> _save() async => _file?.writeAsString(jsonEncode({'url': url, 'refresh': refresh}));

  Future<void> forget() async { url = refresh = access = ''; try { await _file?.delete(); } catch (_) {} }

  static String clientId(String ha) => '$ha/';
  static String redirect(String ha) => '$ha/?auth_callback=1';

  /// Home Assistant's login page for this app
  static Uri authorize(String ha) => Uri.parse('$ha/auth/authorize').replace(queryParameters: {
        'response_type': 'code', 'client_id': clientId(ha), 'redirect_uri': redirect(ha), 'state': 'echo-wall'});

  /// the code the login page sent to the redirect, for tokens
  Future<bool> exchange(String ha, String code) => _token(ha, {'grant_type': 'authorization_code', 'code': code, 'client_id': clientId(ha)});

  /// a fresh access token from the refresh token (null: refused, log in again)
  Future<String?> fresh() async {
    if (!has) return null;
    if (access.isNotEmpty && DateTime.now().isBefore(expires.subtract(const Duration(minutes: 5)))) return access;
    return await _token(url, {'grant_type': 'refresh_token', 'refresh_token': refresh, 'client_id': clientId(url)}) ? access : null;
  }

  Future<bool> _token(String ha, Map<String, String> form) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final rq = await c.postUrl(Uri.parse('$ha/auth/token'));
      rq.headers.set('content-type', 'application/x-www-form-urlencoded');
      rq.write(form.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'));
      final rs = await rq.close().timeout(const Duration(seconds: 15));
      final body = await rs.transform(utf8.decoder).join();
      if (rs.statusCode != 200) return false;
      final j = jsonDecode(body) as Map<String, dynamic>;
      access = '${j['access_token'] ?? ''}';
      if (j['refresh_token'] != null) refresh = '${j['refresh_token']}';
      expires = DateTime.now().add(Duration(seconds: (j['expires_in'] as num? ?? 1800).toInt()));
      url = ha;
      await _save();
      return access.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      c.close(force: true);
    }
  }
}

/// Home Assistant's address, then its own login page; done: the login kept, `onDone` called
class LoginScreen extends StatefulWidget {
  final HaLogin login;
  final VoidCallback onDone;
  final String? error;
  const LoginScreen({super.key, required this.login, required this.onDone, this.error});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final text = TextEditingController(text: widget.login.url.isEmpty ? 'http://homeassistant.local:8123' : widget.login.url);
  WebViewController? web;
  String? error;

  @override
  void initState() { super.initState(); error = widget.error; }

  String _base() {
    var u = text.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    return u;
  }

  void _open() {
    final ha = _base();
    final w = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          final u = Uri.tryParse(r.url);
          if (u != null && r.url.startsWith(HaLogin.redirect(ha)) && u.queryParameters['code'] != null) {
            _done(ha, u.queryParameters['code']!);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onWebResourceError: (e) { if (e.isForMainFrame ?? true) setState(() { web = null; error = 'Home Assistant not reached at $ha (${e.description})'; }); },
      ))
      ..loadRequest(HaLogin.authorize(ha));
    setState(() { web = w; error = null; });
  }

  Future<void> _done(String ha, String code) async {
    final ok = await widget.login.exchange(ha, code);
    if (!mounted) return;
    if (ok) { widget.onDone(); } else { setState(() { web = null; error = 'Home Assistant did not give this app a login'; }); }
  }

  // Back never leaves the app (it is the device's home screen): in the login page it goes back a page, then to the address
  @override
  Widget build(BuildContext context) => PopScope(canPop: false, onPopInvokedWithResult: (popped, _) async {
        final w = web;
        if (popped || w == null) return;
        if (await w.canGoBack()) { await w.goBack(); } else if (mounted) { setState(() => web = null); }
      }, child: _page());

  Widget _page() {
    final w = web;
    if (w != null) {
      return Scaffold(backgroundColor: Colors.white, body: SafeArea(child: Column(children: [
        Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => setState(() => web = null), child: const Text('‹ Address'))),
        Expanded(child: WebViewWidget(controller: w)),
      ])));
    }
    return Scaffold(backgroundColor: Colors.black, body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Echo-Wall', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Log in to your Home Assistant. Add the Echo-Wall integration there (HACS) to arrange this screen from its sidebar.',
            style: TextStyle(color: Color(0xffb0b0b0), fontSize: 15)),
        const SizedBox(height: 20),
        TextField(controller: text, keyboardType: TextInputType.url, autocorrect: false, style: const TextStyle(color: Colors.white, fontSize: 17),
            decoration: const InputDecoration(labelText: "Home Assistant's address", labelStyle: TextStyle(color: Color(0xffb0b0b0)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xff606060)))),
            onSubmitted: (_) => _open()),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Color(0xffff6b5e), fontSize: 14))),
        const SizedBox(height: 20),
        FilledButton(onPressed: _open, child: const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text('Log in', style: TextStyle(fontSize: 16)))),
      ]),
    ))));
  }
}
