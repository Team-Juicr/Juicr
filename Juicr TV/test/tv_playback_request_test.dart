import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/tv_playback_request.dart';

void main() {
  test('maps TV catalog item types to safe playback request kinds', () {
    expect(tvPlaybackRequestKindForItemType('movie'), TvPlaybackRequestKind.movie);
    expect(tvPlaybackRequestKindForItemType('series'), TvPlaybackRequestKind.tv);
    expect(tvPlaybackRequestKindForItemType('animation'), TvPlaybackRequestKind.tv);
    expect(tvPlaybackRequestKindForItemType('live'), TvPlaybackRequestKind.live);
    expect(tvPlaybackRequestKindForItemType('livetv'), TvPlaybackRequestKind.live);
    expect(tvPlaybackRequestKindForItemType('channel'), TvPlaybackRequestKind.live);
  });

  test('only episodic request kinds include season and episode values', () {
    expect(TvPlaybackRequestKind.tv.includesEpisode, isTrue);
    expect(TvPlaybackRequestKind.movie.includesEpisode, isFalse);
    expect(TvPlaybackRequestKind.live.includesEpisode, isFalse);
  });
}
