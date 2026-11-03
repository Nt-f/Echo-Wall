import 'package:flutter_test/flutter_test.dart';
import 'package:echo_screen/home/sizes.dart';
import 'package:echo_screen/home/wall_view.dart';

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

  // Home on an Echo Show 5 (4 x 2): two pages of tiles, every one where it was put
  Map<String, Spot> two() => {for (var i = 0; i < 12; i++) 't$i': (i ~/ 8, i % 4, (i % 8) ~/ 4)};
  List<Item> tiles(int n) => [for (var i = 0; i < n; i++) Item(Kind.tile, id: 't$i')];
  Spot? where(List<PageSpec> ps, String key) {
    for (final p in ps) { for (final (it, c, r) in p.placed) { if (it.key == key) return (p.index, c, r); } }
    return null;
  }

  test('pushed aside by a resize: the neighbours stay on their page, next to where they were', () {
    // t1 (1,0) grown to large (2 x 2): it takes 1-2 x 0-1, so t2, t5, t6 are pushed; page 0 had t0..t7, t3 and t4 stay
    final items = [for (final it in tiles(12)) it.id == 't1' ? it.withSize(CardSize.l) : it];
    final ps = pack('Home', '', null, items, 4, 2, fixed: two(), first: 't1');
    expect(where(ps, 't1'), (0, 1, 0));
    expect(where(ps, 't0'), (0, 0, 0));
    expect(where(ps, 't3'), (0, 3, 0));
    expect(where(ps, 't4'), (0, 0, 1));
    expect(where(ps, 't7'), (0, 3, 1));
    // the three pushed: no room left on page 0, so onto page 1 (after t8..t11), never back to a gap somewhere else
    for (final k in ['t2', 't5', 't6']) { expect(where(ps, k)!.$1, 1, reason: k); }
    for (var i = 8; i < 12; i++) { expect(where(ps, 't$i'), two()['t$i']); }
  });

  test('dragged onto a full page: the one under it takes its old place, the rest do not move', () {
    final fixed = {...two(), 't9': (0, 2, 1)};                     // t9 from page 1 dropped on t6
    final ps = pack('Home', '', null, tiles(12), 4, 2, fixed: fixed, first: 't9', swapTo: (1, 1, 0));
    expect(where(ps, 't9'), (0, 2, 1));
    expect(where(ps, 't6'), (1, 1, 0));
    for (final k in ['t0', 't1', 't2', 't3', 't4', 't5', 't7', 't8', 't10', 't11']) { expect(where(ps, k), two()[k], reason: k); }
  });

  test('pushed aside with room on its own page: the nearest free place there, not the first page', () {
    // page 1 has t8..t11 in its first row; t8 grown wide (2 x 1) pushes t9 to the second row under where it was
    final items = [for (final it in tiles(12)) it.id == 't8' ? it.withSize(CardSize.m) : it];
    final ps = pack('Home', '', null, items, 4, 2, fixed: {...two(), 't0': (0, 0, 0)}..remove('t3'), first: 't8');
    expect(where(ps, 't8'), (1, 0, 0));
    expect(where(ps, 't9'), (1, 1, 1));
    expect(where(ps, 't3'), (0, 3, 0));                            // a card without a place: the first gap
  });
}
