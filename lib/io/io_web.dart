// io.dart on the web: just enough of dart:io for the WallView in a browser (the Echo Local panel's preview).  Home
// Assistant is the page's own origin there, so its websocket, camera stills and the like work as on the Echo; other
// origins (Immich) answer only if they allow it (CORS), and the app falls back as it does when they are unreachable.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class HttpException implements Exception {
  final String message;
  const HttpException(this.message);
  @override
  String toString() => 'HttpException: $message';
}

class ContentType {
  final String value;
  const ContentType._(this.value);
  static const json = ContentType._('application/json; charset=utf-8');
}

class HttpHeaders {
  final _h = <String, String>{};
  void set(String name, Object value) => _h[name] = '$value';
  set contentType(ContentType? t) { if (t != null) _h['content-type'] = t.value; }
}

class HttpClient {
  Duration? connectionTimeout;
  Future<HttpClientRequest> getUrl(Uri u) async => HttpClientRequest._('GET', u);
  Future<HttpClientRequest> openUrl(String method, Uri u) async => HttpClientRequest._(method, u);
  void close({bool force = false}) {}
}

class HttpClientRequest {
  final String method;
  final Uri uri;
  final headers = HttpHeaders();
  final _body = StringBuffer();
  HttpClientRequest._(this.method, this.uri);
  void write(Object? o) => _body.write(o);

  Future<HttpClientResponse> close() async {
    final h = web.Headers();
    headers._h.forEach((k, v) => h.set(k, v));
    final init = web.RequestInit(method: method, headers: h);
    if (_body.isNotEmpty) init.body = _body.toString().toJS;
    try {
      final r = await web.window.fetch(uri.toString().toJS, init).toDart;
      final buf = (await r.arrayBuffer().toDart).toDart.asUint8List();
      return HttpClientResponse._(r.status, buf);
    } catch (e) {
      throw HttpException('$uri: $e');
    }
  }
}

class HttpClientResponse extends Stream<List<int>> {
  final int statusCode;
  final Uint8List _bytes;
  HttpClientResponse._(this.statusCode, this._bytes);
  int get contentLength => _bytes.length;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(_bytes).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
}

Future<Uint8List> consolidateBytes(HttpClientResponse r) async => r._bytes;

/// nothing is kept in files on the web: the layout comes from the panel
class File {
  final String path;
  File(this.path);
  Future<bool> exists() async => false;
  Future<String> readAsString() async => throw HttpException('no files here: $path');
  Future<File> writeAsString(String s) async => this;
}

class WebSocket {
  final web.WebSocket _ws;
  final _in = StreamController<dynamic>();
  WebSocket._(this._ws) {
    _ws.onmessage = ((web.MessageEvent e) => _in.add((e.data as JSString).toDart)).toJS;
    _ws.onclose = ((web.Event _) { if (!_in.isClosed) _in.close(); }).toJS;
    _ws.onerror = ((web.Event _) { if (!_in.isClosed) { _in.addError('websocket error'); _in.close(); } }).toJS;
  }

  static Future<WebSocket> connect(String url) {
    final ws = web.WebSocket(url);
    final c = Completer<WebSocket>();
    ws.onopen = ((web.Event _) { if (!c.isCompleted) c.complete(WebSocket._(ws)); }).toJS;
    ws.onerror = ((web.Event _) { if (!c.isCompleted) c.completeError(HttpException('$url not reached')); }).toJS;
    return c.future;
  }

  StreamSubscription<dynamic> listen(void Function(dynamic) onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _in.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  void add(Object? data) => _ws.send((data is String ? data : jsonEncode(data)).toJS);
  Future<void> close([int? code, String? reason]) async => _ws.close();
}
