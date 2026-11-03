// AirPlay through Music Assistant: the Echo's pause mutes it (MA can neither pause nor resume the phone's stream),
// the button shows play while muted so; another player's pause is a pause
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_screen/ha.dart';

void main() {
  test('AirPlay: pause holds by muting, shown as paused; play releases', () async {
    final ha = Ha();
    ha.states['media_player.echo'] = EntityState('playing', {'source': 'AirPlay Receiver (Echo)', 'app_id': 'airplay_receiver://audio_source/x'});
    expect(Ha.airPlay(ha.states['media_player.echo']), isTrue);
    expect(ha.sounding('media_player.echo'), isTrue);
    await ha.playPause('media_player.echo');          // muted (the call fails here: no Home Assistant)
    ha.states['media_player.echo']!.attr['is_volume_muted'] = true;
    expect(ha.sounding('media_player.echo'), isFalse);
    await ha.playPause('media_player.echo');          // unmuted
    expect(ha.sounding('media_player.echo'), isTrue);
  });

  test('a queue of Music Assistant: not AirPlay', () {
    expect(Ha.airPlay(EntityState('playing', {'source': 'Music Assistant Queue', 'app_id': 'music_assistant'})), isFalse);
  });
}
