// Where the lock screen's clock goes on a photo, and in what colour: where it covers no one and nothing much.
//
// The photo is shrunk to a 64-wide grid of luminance; for each of nine places (left, centre, right; top, middle,
// bottom) the clock's block would take, a score of
//   - faces under it (Immich's boxes, a fifth larger all round): by far the most
//   - how busy the picture is there (the mean luminance gradient: edges, leaves, text) and how uneven (its spread)
//   - a little for the middle row (the subject is most often there) and the centre column
// and the lowest wins.  The clock is dark where the place is bright (snow, sky), white with a soft shadow elsewhere.
// The photo itself is cropped to the screen (cover) around its faces, when it has any, else around its centre.
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

class Placement {
  final Alignment clock;                        // where the clock's block sits on the screen
  final Alignment crop;                         // how the photo is cropped to the screen
  final bool dark;                              // dark digits (a bright place)
  const Placement(this.clock, this.crop, this.dark);
  static const fallback = Placement(Alignment(-.85, -.75), Alignment.center, false);
}

/// the clock's block on the screen, as a fraction of its width and height
const blockW = .46, blockH = .4;

Future<Placement> place(Uint8List bytes, List<Rect> faces, Size screen, {bool round = false}) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final w = img.width, h = img.height;
    final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    img.dispose();
    final lum = Float64List(w * h);
    for (var i = 0; i < w * h; i++) {
      lum[i] = (.2126 * data.getUint8(i * 4) + .7152 * data.getUint8(i * 4 + 1) + .0722 * data.getUint8(i * 4 + 2)) / 255;
    }
    final grad = Float64List(w * h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final gx = lum[y * w + x + 1] - lum[y * w + x - 1], gy = lum[(y + 1) * w + x] - lum[(y - 1) * w + x];
        grad[y * w + x] = sqrt(gx * gx + gy * gy);
      }
    }
    return choose(lum, grad, w, h, faces, screen, round: round);
  } catch (_) {
    return Placement.fallback;
  }
}

/// the part of the photo the screen shows (cover), 0..1 of the photo, for a crop alignment
Rect visible(double imgAspect, double screenAspect, Alignment crop) {
  if (imgAspect > screenAspect) {               // wider: the sides cut
    final f = screenAspect / imgAspect, x0 = (1 - f) * (crop.x + 1) / 2;
    return Rect.fromLTWH(x0, 0, f, 1);
  }
  final f = imgAspect / screenAspect, y0 = (1 - f) * (crop.y + 1) / 2;
  return Rect.fromLTWH(0, y0, 1, f);
}

/// round: a round screen (an Echo Spot) has room for the clock in the middle column only, above or below the centre
Placement choose(Float64List lum, Float64List grad, int w, int h, List<Rect> faces, Size screen, {bool round = false}) {
  final ia = w / h, sa = screen.width / screen.height;
  // the crop: around the faces' middle, else the centre
  var crop = Alignment.center;
  if (faces.isNotEmpty) {
    final cx = faces.map((f) => f.center.dx).reduce((a, b) => a + b) / faces.length;
    final cy = faces.map((f) => f.center.dy).reduce((a, b) => a + b) / faces.length;
    crop = Alignment((cx * 2 - 1).clamp(-1.0, 1.0), (cy * 2 - 1).clamp(-1.0, 1.0));
  }
  final v = visible(ia, sa, crop);
  final grown = [for (final f in faces) f.inflate(max(f.width, f.height) * .2)];

  double? best;
  var at = const Alignment(-.85, -.75);
  var dark = false;
  for (final ax in round ? const [0.0] : const [-1.0, 0.0, 1.0]) {
    for (final ay in round ? const [-1.0, 1.0] : const [-1.0, 0.0, 1.0]) {
      // the block on the screen (8 % margins), then in the photo
      final sx = .04 + (1 - blockW - .08) * (ax + 1) / 2, sy = .06 + (1 - blockH - .14) * (ay + 1) / 2;
      final r = Rect.fromLTWH(v.left + sx * v.width, v.top + sy * v.height, blockW * v.width, blockH * v.height);
      var n = 0;
      double g = 0, l = 0, l2 = 0;
      for (var y = (r.top * h).floor(); y < min(h, (r.bottom * h).ceil()); y++) {
        for (var x = (r.left * w).floor(); x < min(w, (r.right * w).ceil()); x++) {
          final i = y * w + x;
          g += grad[i]; l += lum[i]; l2 += lum[i] * lum[i]; n++;
        }
      }
      if (n == 0) continue;
      g /= n; l /= n;
      final spread = sqrt(max(0.0, l2 / n - l * l));
      var face = 0.0;
      for (final f in grown) {
        final o = f.intersect(r);
        if (o.width > 0 && o.height > 0) face += o.width * o.height / (r.width * r.height);
      }
      final score = face * 8 + g * 4 + spread * 1.5 + (ay == 0 ? .06 : 0) + (ax == 0 ? .02 : 0);
      if (best == null || score < best) {
        best = score; at = Alignment(ax * .92, ay * (round ? .5 : .86)); dark = l > .62;
      }
    }
  }
  return Placement(at, crop, dark);
}
