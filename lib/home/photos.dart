// The lock screen's photos: the owner's Immich library (the integration's screen app settings: immich.url, immich.key,
// immich.album optional), else the nature photos that come with the app (assets/photos, CC0, from Wikimedia Commons).
// The Echo's firewall lets the app reach local addresses only: an Immich on the LAN, never a photo service on the
// internet, hence the photos in the app.
//
// Immich (its API since 1.118): POST /api/search/random for a batch of photos (of an album, when one is named), the
// preview size of each (/api/assets/<id>/thumbnail?size=preview, ~1440 px), and the faces Immich found in it
// (/api/faces?id=<id>: their boxes), which the clock keeps clear of (placement.dart).
import 'dart:convert';
import 'dart:typed_data';
import '../io/io.dart';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

class Photo {
  final String key;
  final Uint8List bytes;
  final List<Rect> faces;                       // in the photo, 0..1 on each side
  final String credit;
  const Photo(this.key, this.bytes, this.faces, this.credit);
}

class PhotoLibrary {
  String _url = '', _key = '', _album = '';
  final _rand = Random();
  final _queue = <Map<String, dynamic>>[];      // Immich's assets not shown yet
  List<Map<String, dynamic>>? _bundled;
  int _bi = -1;
  bool immichFailed = false;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  void configure(Map<String, String> settings) {
    final u = (settings['immich.url'] ?? '').replaceAll(RegExp(r'/+$'), ''), k = settings['immich.key'] ?? '', a = settings['immich.album'] ?? '';
    if (u == _url && k == _key && a == _album) return;
    _url = u; _key = k; _album = a;
    _queue.clear(); immichFailed = false;
  }

  bool get usesImmich => _url.isNotEmpty && _key.isNotEmpty && !immichFailed;

  /// the next photo: Immich's, or (it not set up or not answering) one of the app's
  Future<Photo> next({required bool wide}) async {
    if (usesImmich) {
      try {
        return await _immich(wide);
      } catch (_) {
        immichFailed = true;                    // tried again at the next configure (the options saved again)
      }
    }
    return _bundle();
  }

  Future<Photo> _bundle() async {
    _bundled ??= (jsonDecode(await rootBundle.loadString('assets/photos/credits.json')) as List).cast<Map<String, dynamic>>();
    final list = _bundled!;
    var i = _rand.nextInt(list.length);
    if (list.length > 1 && i == _bi) i = (i + 1) % list.length;
    _bi = i;
    final c = list[i];
    final bytes = (await rootBundle.load('assets/photos/${c['file']}')).buffer.asUint8List();
    return Photo('bundled:${c['file']}', bytes, const [], 'Photo: ${c['author']} (CC0)');
  }

  Future<dynamic> _json(String method, String path, [Object? body]) async {
    final req = await _client.openUrl(method, Uri.parse('$_url$path'));
    req.headers.set('x-api-key', _key);
    req.headers.set('Accept', 'application/json');
    if (body != null) { req.headers.contentType = ContentType.json; req.write(jsonEncode(body)); }
    final res = await req.close().timeout(const Duration(seconds: 10));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) throw HttpException('$path: ${res.statusCode}');
    return jsonDecode(text);
  }

  Future<Uint8List> _bytes(String path) async {
    final req = await _client.getUrl(Uri.parse('$_url$path'));
    req.headers.set('x-api-key', _key);
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) throw HttpException('$path: ${res.statusCode}');
    final b = BytesBuilder(copy: false);
    await for (final chunk in res) { b.add(chunk); }
    return b.takeBytes();
  }

  Future<Photo> _immich(bool wide) async {
    if (_queue.isEmpty) {
      final batch = await _json('POST', '/api/search/random', {
        'size': 40, 'type': 'IMAGE', 'withExif': true,
        if (_album.isNotEmpty) 'albumIds': [_album],
      }) as List;
      // the screen's own shape first (a landscape on a Show 5, an upright photo on a Show 15 hung upright)
      final assets = batch.cast<Map<String, dynamic>>();
      bool fits(Map<String, dynamic> a) {
        final e = a['exifInfo'] as Map<String, dynamic>?;
        final w = (e?['exifImageWidth'] as num?)?.toDouble(), h = (e?['exifImageHeight'] as num?)?.toDouble();
        final o = '${e?['orientation'] ?? ''}';
        if (w == null || h == null) return true;
        final turned = o == '6' || o == '8' || o == '5' || o == '7';
        final landscape = turned ? h > w : w > h;
        return landscape == wide;
      }
      _queue.addAll([...assets.where(fits), ...assets.where((a) => !fits(a))]);
      if (_queue.isEmpty) throw const HttpException('no photos');
    }
    final a = _queue.removeAt(0);
    final id = '${a['id']}';
    final bytes = await _bytes('/api/assets/$id/thumbnail?size=preview');
    var faces = <Rect>[];
    try {
      final fs = await _json('GET', '/api/faces?id=$id') as List;
      faces = [
        for (final f in fs.cast<Map<String, dynamic>>())
          if ((f['imageWidth'] as num? ?? 0) > 0 && (f['imageHeight'] as num? ?? 0) > 0)
            Rect.fromLTRB((f['boundingBoxX1'] as num) / (f['imageWidth'] as num), (f['boundingBoxY1'] as num) / (f['imageHeight'] as num),
                (f['boundingBoxX2'] as num) / (f['imageWidth'] as num), (f['boundingBoxY2'] as num) / (f['imageHeight'] as num)),
      ];
    } catch (_) {}                               // a key without face access: the clock by the picture alone
    final when = (a['localDateTime'] ?? a['fileCreatedAt'] ?? '') as String;
    final year = when.length >= 4 ? when.substring(0, 4) : '';
    return Photo('immich:$id', bytes, faces, year);
  }
}
