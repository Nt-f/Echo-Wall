// The HomeView's backdrop and its glass, as Apple's materials work: a card shows what is behind it, blurred, its colour
// lifted (vibrancy), lightened or darkened by the material's tint.  A live blur of the screen behind every card costs
// a Mali-T720 half its frames (25-43 fps measured); but what is behind the cards is the wallpaper, which does not move,
// so it is blurred once (per photo and screen size) and every card draws its own piece of that blurred image, found
// from where the card is on the screen at each frame (a swipe, a press, a card flying into its detail): frosted glass
// for the price of copying a picture.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class Backdrop extends ChangeNotifier {
  ui.Image? sharp, blurred;
  Size size = Size.zero;                        // logical, the screen's
  Uint8List? _bytes;
  Alignment _crop = Alignment.center;
  int _gen = 0;

  /// a photo for wallpaper, cropped to the screen around `crop`
  Future<void> photo(Uint8List bytes, {Alignment crop = Alignment.center}) async {
    _bytes = bytes; _crop = crop;
    await _make();
  }

  /// a gradient wallpaper (widgets.dart): painted at the screen's size, then blurred the same way
  Future<void> painted(CustomPainter painter) async {
    if (size.isEmpty) { _painter = painter; return; }
    final rec = ui.PictureRecorder();
    painter.paint(Canvas(rec), size);
    final img = await rec.endRecording().toImage(size.width.round(), size.height.round());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    _painter = painter;
    if (png != null) await photo(png.buffer.asUint8List());
  }
  CustomPainter? _painter;

  Future<void> resize(Size s) async {
    if (s == size || s.isEmpty) return;
    size = s;
    if (_bytes == null && _painter != null) { await painted(_painter!); return; }
    await _make();
  }

  Future<void> _make() async {
    final bytes = _bytes, s = size;
    if (bytes == null || s.isEmpty) return;
    final gen = ++_gen;
    // the sharp one at the screen's size (logical px: the photo's preview is ~1440 px wide anyway)
    final codec = await ui.instantiateImageCodec(bytes);
    final src = (await codec.getNextFrame()).image;
    final w = s.width.round(), h = s.height.round();
    final fitted = applyBoxFit(BoxFit.cover, Size(src.width.toDouble(), src.height.toDouble()), s);
    final from = _crop.inscribe(fitted.source, Offset.zero & Size(src.width.toDouble(), src.height.toDouble()));
    var rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(src, from, Offset.zero & s, Paint()..filterQuality = FilterQuality.medium);
    final sharpImg = await rec.endRecording().toImage(w, h);
    src.dispose();
    // the blurred one: a quarter of the size (the blur hides it), its colour lifted and a little darker, as Apple's
    // "regular" material under white text
    const q = 4.0;
    rec = ui.PictureRecorder();
    final small = Size(s.width / q, s.height / q);
    Canvas(rec).drawImageRect(sharpImg, Offset.zero & s, Offset.zero & small, Paint()
      ..filterQuality = FilterQuality.medium
      ..imageFilter = ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7, tileMode: TileMode.clamp)
      ..colorFilter = const ColorFilter.matrix(_vibrancy));
    final blurImg = await rec.endRecording().toImage(small.width.ceil(), small.height.ceil());
    if (gen != _gen) { sharpImg.dispose(); blurImg.dispose(); return; }
    final oldS = sharp, oldB = blurred;
    sharp = sharpImg; blurred = blurImg;
    notifyListeners();
    // the old ones after this frame: a card may still be painting with them
    WidgetsBinding.instance.addPostFrameCallback((_) { oldS?.dispose(); oldB?.dispose(); });
  }
}

/// saturation 1.6, brightness .88: the colours behind glass glow through it, the white on it stays readable
const _vibrancy = <double>[
  1.3276 * .88, -.2862 * .88, -.0414 * .88, 0, 0,
  -.0846 * .88, 1.3138 * .88, -.0414 * .88, 0, 0,
  -.0846 * .88, -.2862 * .88, 1.3586 * .88, 0, 0,
  0, 0, 0, 1, 0,
];

class BackdropScope extends InheritedNotifier<Backdrop> {
  const BackdropScope({super.key, required Backdrop backdrop, required super.child}) : super(notifier: backdrop);
  static Backdrop? of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<BackdropScope>()?.notifier;
}

/// the wallpaper: the sharp photo, a breath darker for the white on the glass; the palette's gradient before it is
/// ready (or for the gradient wallpapers)
class BackdropView extends StatelessWidget {
  final Gradient fallback;
  const BackdropView({super.key, required this.fallback});
  @override
  Widget build(BuildContext context) {
    final b = BackdropScope.of(context);
    return RepaintBoundary(child: Stack(fit: StackFit.expand, children: [
      DecoratedBox(decoration: BoxDecoration(gradient: fallback)),
      if (b?.sharp != null) AnimatedSwitcher(duration: const Duration(milliseconds: 900),
          child: RawImage(key: ValueKey(b!.sharp), image: b.sharp, fit: BoxFit.fill)),
      const ColoredBox(color: Color(0x14000000)),
    ]));
  }
}

/// a card of frosted glass: its piece of the blurred backdrop, the material's tint, the continuous corners Apple's
/// cards have (a superellipse, not a circle's quarter), a light edge at the top
class Frosted extends SingleChildRenderObjectWidget {
  final ui.Image? blurred;
  final Size screen;
  final BorderRadius radius;
  final Color tint;
  final Color edgeTop, edgeBottom;
  const Frosted({super.key, required this.blurred, required this.screen, required this.radius, required this.tint,
      this.edgeTop = const Color(0x66ffffff), this.edgeBottom = const Color(0x14ffffff), super.child});

  @override
  RenderFrosted createRenderObject(BuildContext context) =>
      RenderFrosted(blurred, screen, radius, tint, edgeTop, edgeBottom);

  @override
  void updateRenderObject(BuildContext context, RenderFrosted renderObject) {
    renderObject..blurred = blurred..screen = screen..radius = radius..tint = tint..edgeTop = edgeTop..edgeBottom = edgeBottom;
  }
}

class RenderFrosted extends RenderProxyBox {
  RenderFrosted(this._blurred, this._screen, this._radius, this._tint, this._edgeTop, this._edgeBottom);
  ui.Image? _blurred;
  Size _screen;
  BorderRadius _radius;
  Color _tint, _edgeTop, _edgeBottom;
  set blurred(ui.Image? v) { if (v != _blurred) { _blurred = v; markNeedsPaint(); } }
  set screen(Size v) { if (v != _screen) { _screen = v; markNeedsPaint(); } }
  set radius(BorderRadius v) { if (v != _radius) { _radius = v; markNeedsPaint(); } }
  set tint(Color v) { if (v != _tint) { _tint = v; markNeedsPaint(); } }
  set edgeTop(Color v) { if (v != _edgeTop) { _edgeTop = v; markNeedsPaint(); } }
  set edgeBottom(Color v) { if (v != _edgeBottom) { _edgeBottom = v; markNeedsPaint(); } }

  @override
  bool get alwaysNeedsCompositing => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas, box = offset & size;
    final shape = _radius.toRSuperellipse(box);
    canvas.save();
    canvas.clipRSuperellipse(shape);
    final img = _blurred;
    if (img != null && !_screen.isEmpty && attached) {
      // where this card is on the screen now (transforms included: a press, a wobble, a flight)
      final onScreen = MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);
      final k = img.width / _screen.width;
      final src = Rect.fromLTWH(onScreen.left * k, onScreen.top * k, onScreen.width * k, onScreen.height * k);
      canvas.drawImageRect(img, src, box, Paint()..filterQuality = FilterQuality.low);
    }
    canvas.drawRect(box, Paint()..color = _tint);
    canvas.restore();
    // the edge: the light catches the top
    canvas.drawRSuperellipse(_radius.toRSuperellipse(box.deflate(.5)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_edgeTop, _edgeBottom]).createShader(box));
    if (child != null) {
      context.pushClipRSuperellipse(needsCompositing, offset, Offset.zero & size, _radius.toRSuperellipse(Offset.zero & size),
          (c, o) => c.paintChild(child!, o));
    }
  }
}
