// The on-screen keyboard: the Echo has no input method.  Keys go to the WebView as real key events
// (MainActivity.kt, channel "hassmic/keys"); a character the key map lacks is inserted by script.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef InsertText = Future<void> Function(String text);

class Keyboard extends StatefulWidget {
  final bool numbers;                   // a number field: the digits first
  final bool round;                     // a round screen: the keys kept off the circle's edge
  final InsertText? fallback;
  final VoidCallback onHide;
  // typing into the app's own field (the HomeView's search) instead of the WebView: each character, ⌫, ⏎
  final void Function(String)? onText;
  final VoidCallback? onBackspace, onEnter;
  const Keyboard({super.key, required this.numbers, this.fallback, required this.onHide, this.round = false,
      this.onText, this.onBackspace, this.onEnter});
  @override
  State<Keyboard> createState() => _KeyboardState();
}

const _letters = [
  ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
  ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
  ['⇧', 'z', 'x', 'c', 'v', 'b', 'n', 'm', '⌫'],
  ['?123', '@', ' ', '.', '⏎', '⌄'],
];
const _symbols = [
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
  ['@', '#', r'$', '%', '&', '*', '-', '+', '(', ')'],
  ['=', '!', '"', "'", ':', ';', '/', '?', '⌫'],
  ['ABC', ',', ' ', '.', '⏎', '⌄'],
];
const _special = {'⇧', '⌫', '?123', 'ABC', '⏎', '⌄'};

class _KeyboardState extends State<Keyboard> {
  static const _keys = MethodChannel('hassmic/keys');
  late bool symbols = widget.numbers;
  bool shift = false;
  Timer? _repeat;

  @override
  void didUpdateWidget(Keyboard old) {
    super.didUpdateWidget(old);
    if (old.numbers != widget.numbers) symbols = widget.numbers;
  }

  Future<void> _key(String code) async {
    if (code == 'backspace' && widget.onBackspace != null) return widget.onBackspace!();
    if (code == 'enter' && widget.onEnter != null) return widget.onEnter!();
    await _keys.invokeMethod('key', code);
  }
  Future<void> _text(String s) async {
    if (widget.onText != null) return widget.onText!(s);
    final ok = await _keys.invokeMethod<bool>('text', s) ?? false;
    if (!ok) await widget.fallback?.call(s);
  }

  void _down(String k) {
    if (k == '⌫') {
      _key('backspace');
      _repeat = Timer(const Duration(milliseconds: 450), () {
        _repeat = Timer.periodic(const Duration(milliseconds: 70), (_) => _key('backspace'));
      });
    }
  }

  void _up(String k) {
    _repeat?.cancel();
    switch (k) {
      case '⌫':
        break;
      case '⇧':
        setState(() => shift = !shift);
      case '?123':
        setState(() => symbols = true);
      case 'ABC':
        setState(() => symbols = false);
      case '⏎':
        _key('enter');
      case '⌄':
        widget.onHide();
      default:
        _text(shift ? k.toUpperCase() : k);
        if (shift) setState(() => shift = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // as wide as a tablet's keyboard at most (a Show 15's 1920 px of keys would be a reach), centred; on a round screen
    // inset so that the outer keys stay inside the circle
    final size = MediaQuery.sizeOf(context);
    var rows = symbols ? _symbols : _letters;
    // round: the bottom row where the circle is narrow keeps its four keys that matter (@ . , are under ?123)
    if (widget.round) rows = [...rows.take(3), symbols ? const ['ABC', ' ', '⏎', '⌄'] : const ['?123', ' ', '⏎', '⌄']];
    // a round screen: each row as wide as the circle is at its height (a 52 px row, counted from the bottom), less a margin
    double inset(int i) {
      if (!widget.round) return 0;
      final r = min(size.width, size.height) / 2, fromBottom = 30 + 26 + 52.0 * (rows.length - 1 - i);
      final d = (size.height / 2 - fromBottom).abs() + 26;            // the row's far edge from the centre
      final half = d >= r ? 0.0 : sqrt(r * r - d * d);
      return max(0.0, size.width / 2 - half * .94);
    }
    return Container(
      color: const Color(0xff1c1c1e),
      padding: EdgeInsets.fromLTRB(4, 5, 4, widget.round ? 30 : 5),
      alignment: Alignment.center,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (i, row) in rows.indexed)
          Padding(padding: EdgeInsets.symmetric(horizontal: inset(i)), child: Row(children: [
            for (final k in row)
              Expanded(
                flex: k == ' ' ? 46 : _special.contains(k) ? 15 : 10,
                child: _Key(
                  label: k == ' ' ? 'space' : (shift && k.length == 1 ? k.toUpperCase() : k),
                  dark: _special.contains(k),
                  lit: k == '⇧' && shift,
                  onDown: () => _down(k),
                  onUp: () => _up(k),
                  onCancel: () => _repeat?.cancel(),
                ),
              ),
          ])),
      ])),
    );
  }
}

class _Key extends StatefulWidget {
  final String label;
  final bool dark, lit;
  final VoidCallback onDown, onUp, onCancel;
  const _Key({required this.label, required this.dark, required this.lit, required this.onDown, required this.onUp, required this.onCancel});
  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) {
    final bg = widget.lit ? const Color(0xffe5e5ea) : widget.dark ? const Color(0xff2c2c2e) : const Color(0xff48484a);
    return Listener(
      onPointerDown: (_) { setState(() => pressed = true); widget.onDown(); },
      onPointerUp: (_) { setState(() => pressed = false); widget.onUp(); },
      onPointerCancel: (_) { setState(() => pressed = false); widget.onCancel(); },
      child: Container(
        height: 46,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: pressed ? bg.withValues(alpha: .6) : bg, borderRadius: BorderRadius.circular(7)),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(widget.label, maxLines: 1,
            style: TextStyle(color: widget.lit ? Colors.black : Colors.white, fontSize: widget.label.length == 1 ? 20 : 15))),
      ),
    );
  }
}
