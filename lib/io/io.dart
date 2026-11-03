// What the app takes of dart:io, for both its builds: on the Echo dart:io itself; on the web (the Echo Local panel's
// preview, lib/preview.dart) stand-ins over the browser's fetch and WebSocket with the same names and the few members
// the app uses (HttpClient getUrl/openUrl, headers, close, the response as a byte stream; WebSocket.connect, listen,
// add, close; File that never exists).  The app's files import this instead of dart:io.
export 'io_native.dart' if (dart.library.js_interop) 'io_web.dart';
