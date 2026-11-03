// An app of the owner's on Home (a YouTube client, a music app: ../apps.dart): its own icon on the glass, as a screen's
// tile is drawn, and a tap starts it (hassmic's bar, pulled down from the top edge, comes back here).
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'sizes.dart';
import 'widgets.dart';

class AppTile extends StatelessWidget {
  final Palette p;
  final String name;
  final Uint8List icon;
  final double cell;
  final VoidCallback onTap;
  final CardSize size;                          // s, or m: the icon beside the name
  const AppTile({super.key, required this.p, required this.name, required this.icon, required this.cell, required this.onTap, this.size = CardSize.s});
  @override
  Widget build(BuildContext context) {
    final u = cell / 100, side = 34 * u;
    if (size != CardSize.s) {
      return GestureDetector(onTap: onTap, child: Glass(p: p, cell: cell, padding: EdgeInsets.all(12 * u), child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(side * 1.4 * .22),
            child: Image.memory(icon, width: side * 1.4, height: side * 1.4, fit: BoxFit.contain, gaplessPlayback: true, filterQuality: FilterQuality.medium)),
        SizedBox(width: 10 * u),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: max(13.0, 10 * u))),
          Text('Open', style: TextStyle(color: p.dim, fontSize: max(11.0, 7.8 * u), fontWeight: FontWeight.w500)),
        ])),
      ])));
    }
    return GestureDetector(onTap: onTap, child: Glass(p: p, cell: cell, padding: EdgeInsets.all(10 * u), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(borderRadius: BorderRadius.circular(side * .22),
          child: Image.memory(icon, width: side, height: side, fit: BoxFit.contain, gaplessPlayback: true, filterQuality: FilterQuality.medium)),
      const Spacer(),
      Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: max(12.0, 9 * u))),
      SizedBox(height: 1.5 * u),
      Row(children: [
        Text('Open', style: TextStyle(color: p.dim, fontSize: max(11.0, 7.8 * u), fontWeight: FontWeight.w500)),
        Icon(Icons.chevron_right, size: max(12.0, 8 * u), color: p.dim),
      ]),
    ])));
  }
}
