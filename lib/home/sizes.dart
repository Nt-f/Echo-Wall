// A card's size on the WallView's grid, as Apple's widgets have them: small (a cell), wide (two side by side), large (two
// by two), extra large (four by two: on the Echo Show 5 a whole page).  Which sizes a card has is wall_view.dart's
// `sizesOf`; how each card draws itself at each is in its widget, and test/gallery_test.dart draws every one.
enum CardSize {
  s(1, 1, '1x1', 'Small'),
  m(2, 1, '2x1', 'Wide'),
  l(2, 2, '2x2', 'Large'),
  xl(4, 2, '4x2', 'Extra large');

  final int w, h;
  final String code, label;
  const CardSize(this.w, this.h, this.code, this.label);

  static CardSize? of(String? code) => CardSize.values.where((s) => s.code == code).firstOrNull;
}
