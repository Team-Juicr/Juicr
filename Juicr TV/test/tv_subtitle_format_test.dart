import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/main.dart';

void main() {
  test('specific SRT label wins over contradictory generic VTT metadata', () {
    expect(
      tvSubtitleFormatFromJson(
        const <String, dynamic>{'format': 'vtt'},
        label: 'English - Open subtitles - [SRT] - release.srt',
        url: 'https://example.invalid/subtitle',
      ),
      'srt',
    );
  });

  test('URL extension remains a safe format signal', () {
    expect(
      tvSubtitleFormatFromJson(
        const <String, dynamic>{},
        label: 'English',
        url: 'https://example.invalid/subtitle.vtt',
      ),
      'vtt',
    );
  });
}
