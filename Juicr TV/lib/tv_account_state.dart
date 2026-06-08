import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String tvAccountProfilePrefsKey = 'juicr_tv_account_profile_v1';
const String tvAccountSessionTokenKey = 'juicr_tv_account_session_token_v1';
const String tvAccountSessionExpiresAtKey = 'juicr_tv_account_session_expires_at_v1';
const String unsupportedTvAccountEmailMessage =
    'Use a supported personal email provider to sign in.';

const Set<String> _supportedTvAccountEmailDomains = {
  'gmail.com',
  'googlemail.com',
  'yahoo.com',
  'ymail.com',
  'rocketmail.com',
  'outlook.com',
  'hotmail.com',
  'live.com',
  'msn.com',
  'icloud.com',
  'me.com',
  'mac.com',
  'proton.me',
  'protonmail.com',
  'aol.com',
  'zoho.com',
  'fastmail.com',
};

bool isSupportedTvAccountEmail(String email) {
  final parts = email.trim().toLowerCase().split('@');
  if (parts.length != 2 || parts.first.isEmpty || parts.last.isEmpty) {
    return false;
  }
  return _supportedTvAccountEmailDomains.contains(parts.last);
}

class TvAccountSession {
  const TvAccountSession({required this.token, required this.expiresAt});

  factory TvAccountSession.fromJson(Map<String, Object?> json) {
    return TvAccountSession(
      token: (json['token'] ?? '').toString().trim(),
      expiresAt: DateTime.tryParse((json['expiresAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String token;
  final DateTime expiresAt;

  bool get isValid => token.isNotEmpty && expiresAt.isAfter(DateTime.now());

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'token': token,
      'expiresAt': expiresAt.toIso8601String(),
    };
  }
}

class TvAccountAdPreferences {
  const TvAccountAdPreferences({
    required this.adsEnabled,
    this.resetGuestOnSignOut = true,
  });

  factory TvAccountAdPreferences.fromJson(Object? value) {
    final json = value is Map ? Map<String, Object?>.from(value) : const <String, Object?>{};
    return TvAccountAdPreferences(
      adsEnabled: _boolFromAccountValue(json['adsEnabled'], fallback: true),
      resetGuestOnSignOut: json['resetGuestOnSignOut'] != false,
    );
  }

  final bool adsEnabled;
  final bool resetGuestOnSignOut;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'adsEnabled': adsEnabled,
      'source': 'account',
      'resetGuestOnSignOut': resetGuestOnSignOut,
    };
  }
}

class TvAccountProfile {
  const TvAccountProfile({
    required this.id,
    required this.email,
    this.username = '',
    this.emoji = '',
    this.leaderboardOptIn = false,
    this.usernameLocked = false,
    this.adPreferences = const TvAccountAdPreferences(adsEnabled: true),
    this.createdAt,
    this.lastLoginAt,
  });

  factory TvAccountProfile.fromJson(Map<String, Object?> json) {
    return TvAccountProfile(
      id: (json['id'] ?? '').toString().trim(),
      email: (json['email'] ?? '').toString().trim(),
      username: (json['username'] ?? '').toString().trim(),
      emoji: (json['emoji'] ?? '').toString().trim(),
      leaderboardOptIn: json['leaderboardOptIn'] == true,
      usernameLocked: json['usernameLocked'] == true,
      adPreferences: TvAccountAdPreferences.fromJson(json['adPreferences']),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      lastLoginAt: DateTime.tryParse((json['lastLoginAt'] ?? '').toString()),
    );
  }

  final String id;
  final String email;
  final String username;
  final String emoji;
  final bool leaderboardOptIn;
  final bool usernameLocked;
  final TvAccountAdPreferences adPreferences;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  bool get isUsable => id.isNotEmpty && email.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'email': email,
      if (username.isNotEmpty) 'username': username,
      if (emoji.isNotEmpty) 'emoji': emoji,
      'leaderboardOptIn': leaderboardOptIn,
      'usernameLocked': usernameLocked,
      'adPreferences': adPreferences.toJson(),
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (lastLoginAt != null) 'lastLoginAt': lastLoginAt!.toIso8601String(),
    };
  }
}

class TvAccountStateStore {
  const TvAccountStateStore({
    this.secureStorage = const FlutterSecureStorage(),
  });

  final FlutterSecureStorage secureStorage;

  Future<({TvAccountSession? session, TvAccountProfile? profile})> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final profile = _profileFromEncoded(prefs.getString(tvAccountProfilePrefsKey));
    final token = (await secureStorage.read(key: tvAccountSessionTokenKey))?.trim() ?? '';
    final expiresAtRaw = await secureStorage.read(key: tvAccountSessionExpiresAtKey);
    final expiresAt = DateTime.tryParse(expiresAtRaw ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    final session = TvAccountSession(token: token, expiresAt: expiresAt);
    return (session: session.isValid ? session : null, profile: profile?.isUsable == true ? profile : null);
  }

  Future<void> save({
    required TvAccountSession session,
    required TvAccountProfile profile,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(tvAccountProfilePrefsKey, jsonEncode(profile.toJson()));
    await secureStorage.write(key: tvAccountSessionTokenKey, value: session.token);
    await secureStorage.write(
      key: tvAccountSessionExpiresAtKey,
      value: session.expiresAt.toIso8601String(),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tvAccountProfilePrefsKey);
    await secureStorage.delete(key: tvAccountSessionTokenKey);
    await secureStorage.delete(key: tvAccountSessionExpiresAtKey);
  }
}

TvAccountProfile? _profileFromEncoded(String? encoded) {
  if (encoded == null || encoded.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) return null;
    return TvAccountProfile.fromJson(Map<String, Object?>.from(decoded));
  } catch (_) {
    return null;
  }
}

bool _boolFromAccountValue(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return fallback;
}
