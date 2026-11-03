// What hassmic would otherwise draw over the app (docs/screen-apps.md "Drawing the clock, the words and the alarms
// itself"), drawn here in the app's own look: the clock as an idle screen ("hassmic:clock"), a request's words, a
// ringing alarm or timer.  The look follows hassmic's: black, the time big and light, the attention colour cyan.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'hassmic.dart';

const cyan = Color(0xff00caff);
const grey = Color(0xff9aa0a6);
const _family = 'sans-serif-light';

String clockText(DateTime t, bool h24) =>
    h24 ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}' : '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')}';
String ampm(DateTime t, bool h24) => h24 ? '' : (t.hour < 12 ? 'AM' : 'PM');
const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
String dateText(DateTime t) => '${_days[t.weekday - 1]}, ${_months[t.month - 1]} ${t.day}';

/// a hundredth of the size text is measured in: the height, or three quarters of the width where that is less (a screen hung
/// upright), inside the square a round screen has room for
double unit(BoxConstraints box) => min(box.maxHeight, box.maxWidth * .75) / 100;

/// a round screen (Echo Spot): what is drawn kept within the square that fits in the circle
Widget roundInset(bool round, Widget child) => round
    ? LayoutBuilder(builder: (_, b) => Padding(padding: EdgeInsets.all(min(b.maxWidth, b.maxHeight) * .146), child: child))
    : child;

/// a widget that builds again on every minute's turn (a second's, with seconds)
class Ticker extends StatefulWidget {
  final Widget Function(BuildContext, DateTime) builder;
  final bool seconds;
  const Ticker({super.key, required this.builder, this.seconds = false});
  @override
  State<Ticker> createState() => _TickerState();
}

class _TickerState extends State<Ticker> {
  Timer? _t;
  @override
  void initState() { super.initState(); _arm(); }
  void _arm() {
    final now = DateTime.now();
    final next = widget.seconds ? const Duration(seconds: 1) - Duration(milliseconds: now.millisecond)
        : Duration(seconds: 60 - now.second) - Duration(milliseconds: now.millisecond);
    _t = Timer(next, () { if (mounted) { setState(() {}); _arm(); } });
  }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}

/// the idle screen "hassmic:clock": the time, the date, the next alarm
class ClockScreen extends StatelessWidget {
  final EchoState s;
  final bool round;
  const ClockScreen({super.key, required this.s, this.round = false});
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black,
        child: roundInset(round, LayoutBuilder(builder: (context, box) {
          final u = unit(box);
          if (!s.clockSet) {
            return Center(child: Text('Waiting for Home Assistant to set the clock', style: TextStyle(color: grey, fontSize: 8 * u)));
          }
          return Ticker(builder: (context, now) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic, children: [
                  Text(clockText(now, s.h24), style: TextStyle(color: Colors.white, fontSize: 46 * u, fontFamily: _family, height: 1)),
                  if (!s.h24) Padding(padding: EdgeInsets.only(left: 2 * u),
                      child: Text(ampm(now, s.h24), style: TextStyle(color: grey, fontSize: 11 * u))),
                ])),
                SizedBox(height: 4 * u),
                Text(dateText(now), style: TextStyle(color: grey, fontSize: 8 * u)),
                if (s.nextAlarmText.isNotEmpty) ...[
                  SizedBox(height: 6 * u),
                  Text(s.nextAlarmText + (s.nextAlarmLabel.isNotEmpty ? '  ·  ${s.nextAlarmLabel}' : ''), textAlign: TextAlign.center,
                      style: TextStyle(color: cyan, fontSize: 6.5 * u)),
                ],
              ]));
        })),
      );
}

/// a request: what speech to text heard (grey), what the assistant answered (white), the clock small above
class WordsOverlay extends StatelessWidget {
  final EchoState s;
  final bool round;
  const WordsOverlay({super.key, required this.s, this.round = false});
  @override
  Widget build(BuildContext context) => _Opaque(child: roundInset(round, LayoutBuilder(builder: (context, box) {
        final u = unit(box), m = round ? 0.0 : box.maxWidth * .06;
        return Padding(
          padding: EdgeInsets.fromLTRB(m, 6 * u, m, 4 * u),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Ticker(builder: (_, now) => Text(clockText(now, s.h24), style: TextStyle(color: grey, fontSize: 8 * u))),
            SizedBox(height: 8 * u),
            if (s.heard.isNotEmpty)
              Text(s.heard, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: grey, fontSize: 8 * u))
            else if (s.running)
              Text('Listening…', style: TextStyle(color: cyan, fontSize: 8 * u)),
            SizedBox(height: 4 * u),
            if (s.reply.isNotEmpty)
              Expanded(child: Text(s.reply, overflow: TextOverflow.fade, style: TextStyle(color: Colors.white, fontSize: 10 * u, height: 1.25))),
          ]),
        );
      })));
}

/// an alarm or timer ringing: what rings, big, and what stops it (a tap snoozes, a hold stops: told to hassmic)
class RingOverlay extends StatelessWidget {
  final EchoState s;
  final bool round;
  const RingOverlay({super.key, required this.s, this.round = false});
  @override
  Widget build(BuildContext context) => _Opaque(onTap: () => Hassmic.ring(stop: false), onLongPress: () => Hassmic.ring(stop: true),
      child: LayoutBuilder(builder: (context, outer) {
        return Stack(children: [
          Container(height: 1.2 * unit(outer), color: cyan),
          roundInset(round, LayoutBuilder(builder: (context, box) { final u = unit(box); return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Ticker(builder: (_, now) => Text(clockText(now, s.h24), style: TextStyle(color: grey, fontSize: 9 * u))),
            SizedBox(height: 6 * u),
            Padding(padding: EdgeInsets.symmetric(horizontal: box.maxWidth * .06),
                child: Text(s.ringing, textAlign: TextAlign.center, maxLines: 2,
                    style: TextStyle(color: Colors.white, fontSize: 15 * u, fontWeight: FontWeight.bold))),
            SizedBox(height: 10 * u),
            Text(s.ringingAlarm ? 'Tap to snooze  ·  hold or say “stop”' : 'Tap or say “stop”', textAlign: TextAlign.center,
                style: TextStyle(color: grey, fontSize: 7 * u)),
          ])); })),
        ]);
      }));
}

/// black over everything, every touch kept from what is under it
class _Opaque extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap, onLongPress;
  const _Opaque({required this.child, this.onTap, this.onLongPress});
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onTap ?? () {}, onLongPress: onLongPress ?? () {},
        child: Container(color: Colors.black, child: SafeArea(child: child)));
}
