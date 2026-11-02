import 'package:flutter_test/flutter_test.dart';
import 'package:hassmic_screen/home/home_view.dart';

void main() {
  test('packing: big ones where they fit, the small ones fill around them, a full page starts the next', () {
    const big = Item(Kind.thermo, id: 'climate.a');
    final items = [
      const Item(Kind.analog), const Item(Kind.digital), big,
      for (var i = 0; i < 12; i++) Item(Kind.tile, id: 'light.l$i'),
    ];
    final pages = pack('Home', '', null, items, 6, 3);   // the Echo Show 5: 6 x 3 cells
    expect(pages.length, 2);                       // 1 + 2 + 4 + 12 = 19 cells: the first page full, one tile over
    final first = pages.first.placed;
    // the analog clock at 0,0; the digital one (2 wide) at 1,0; the thermostat (2 x 2) at 3,0
    expect(first[0].$2, 0);
    expect((first[1].$2, first[1].$3), (1, 0));
    expect((first[2].$2, first[2].$3), (3, 0));
    // every cell of the first page taken: 1 + 2 + 4 + 11 tiles = 18 = 6 x 3
    final cells = first.fold<int>(0, (n, e) => n + e.$1.w * e.$1.h);
    expect(cells, 18);
    expect(first.length, 14);
    expect(pages[1].placed.length, 1);
  });

  test('a big one that does not fit where it comes: the small ones after it fill the gap', () {
    // 4 x 2: the clocks and the date fill the first row; the thermostat (2 x 2) cannot go under them
    final items = [const Item(Kind.analog), const Item(Kind.digital), const Item(Kind.date), const Item(Kind.thermo, id: 'climate.a'),
        for (var i = 0; i < 4; i++) Item(Kind.tile, id: 'lock.l$i')];
    final pages = pack('Home', '', null, items, 4, 2);
    expect(pages.length, 2);
    expect(pages[0].placed.where((e) => e.$1.kind == Kind.tile).length, 4);     // the second row: the four locks
    expect(pages[1].placed.single.$1.kind, Kind.thermo);
  });

  test('a widget bigger than the page is left out, not looped on', () {
    final pages = pack('Spot', '', null, const [Item(Kind.thermo, id: 'climate.a'), Item(Kind.tile, id: 'light.a')], 1, 3);
    expect(pages.length, 1);
    expect(pages.first.placed.map((e) => e.$1.id), ['light.a']);
  });
}
