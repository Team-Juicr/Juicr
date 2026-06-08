import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/tv_account_state.dart';

void main() {
  test('parses valid account session and profile responses', () {
    final session = TvAccountSession.fromJson({
      'token': ' token-1 ',
      'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    });
    final profile = TvAccountProfile.fromJson({
      'id': 'user-1',
      'email': 'user@example.com',
      'username': 'JuicrUser',
      'emoji': 'leaf',
      'leaderboardOptIn': true,
      'usernameLocked': true,
      'adPreferences': {'adsEnabled': false, 'resetGuestOnSignOut': false},
    });

    expect(session.token, 'token-1');
    expect(session.isValid, isTrue);
    expect(profile.isUsable, isTrue);
    expect(profile.leaderboardOptIn, isTrue);
    expect(profile.adPreferences.adsEnabled, isFalse);
    expect(profile.toJson()['email'], 'user@example.com');
  });

  test('accepts only supported personal sign-in email domains', () {
    expect(isSupportedTvAccountEmail('user@gmail.com'), isTrue);
    expect(isSupportedTvAccountEmail('user@proton.me'), isTrue);
    expect(isSupportedTvAccountEmail('user@work.example'), isFalse);
    expect(isSupportedTvAccountEmail('missing-at'), isFalse);
  });
}
