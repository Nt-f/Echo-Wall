import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hassmic_screen/home/placement.dart';

/// a 64 x 32 picture: the left half busy (noise), the right half a calm sky, bright above and dark below
(Float64List, Float64List) picture() {
  const w = 64, h = 32;
  final r = Random(1), lum = Float64List(w * h), grad = Float64List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      lum[y * w + x] = x < w / 2 ? r.nextDouble() : (y < h / 2 ? .85 : .25);
    }
  }
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final gx = lum[y * w + x + 1] - lum[y * w + x - 1], gy = lum[(y + 1) * w + x] - lum[(y - 1) * w + x];
      grad[y * w + x] = sqrt(gx * gx + gy * gy);
    }
  }
  return (lum, grad);
}

void main() {
  test('the clock goes where the picture is calm, dark on a bright sky', () {
    final (lum, grad) = picture();
    final p = choose(lum, grad, 64, 32, const [], const Size(960, 480));
    expect(p.clock.x, greaterThan(0));            // the calm right half
    expect(p.clock.y, lessThan(0));               // the bright top: ...
    expect(p.dark, isTrue);                       // ... dark digits there
  });

  test('a face keeps the clock away', () {
    final (lum, grad) = picture();
    // a face right where the clock would go (top right)
    final p = choose(lum, grad, 64, 32, const [Rect.fromLTRB(.62, .05, .95, .45)], const Size(960, 480));
    expect(p.clock.y, greaterThan(0));            // below it instead
    expect(p.clock.x, greaterThan(0));
  });

  test('round: the middle column only, above or below the centre', () {
    final (lum, grad) = picture();
    final p = choose(lum, grad, 64, 32, const [], const Size(480, 480), round: true);
    expect(p.clock.x, 0);
    expect(p.clock.y.abs(), closeTo(.5, 1e-9));
  });

  test('cropped to the screen around the faces', () {
    final v = visible(2.0, 1.0, const Alignment(1, 0));   // a wide photo on a square screen, faces to the right
    expect(v.left, closeTo(.5, 1e-9));
    expect(v.width, closeTo(.5, 1e-9));
  });
}
