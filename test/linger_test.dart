import 'package:flutter_test/flutter_test.dart';
import 'package:echo_screen/hassmic.dart';

void main() {
  test('words while a run goes, then a linger after it ends', () async {
    final f = EchoStateFeed()..linger = const Duration(milliseconds: 200);
    expect(f.shown(const EchoState(running: true, words: true, heard: 'lights on')).words, isTrue);
    expect(f.shown(const EchoState(running: true, words: true, heard: 'lights on', reply: 'Done')).words, isTrue);
    // the reply spoken, the run over: hassmic keeps the words (its own screen's 20 s); the app shows them a linger
    const after = EchoState(words: true, heard: 'lights on', reply: 'Done');
    expect(f.shown(after).words, isTrue);
    await Future.delayed(const Duration(milliseconds: 250));
    expect(f.shown(after).words, isFalse);
  });

  test('an answer outside a run: shown a linger from when it came', () async {
    final f = EchoStateFeed()..linger = const Duration(milliseconds: 200);
    expect(f.shown(const EchoState()).words, isFalse);
    expect(f.shown(const EchoState(words: true, reply: 'Alarm set for 7')).words, isTrue);
    await Future.delayed(const Duration(milliseconds: 250));
    expect(f.shown(const EchoState(words: true, reply: 'Alarm set for 7')).words, isFalse);
  });
}
