import 'package:flutter/services.dart';

import 'diagnostic_log.dart';

class LocalNotificationBridge {
  const LocalNotificationBridge._();

  static const MethodChannel _channel = MethodChannel(
    'app.juicr.flutter/local_notifications',
  );

  static Future<bool> areEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('areEnabled') ?? false;
    } catch (error) {
      DiagnosticLog.add('local notification enabled check failed error=$error');
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (error) {
      DiagnosticLog.add('local notification permission failed error=$error');
      return false;
    }
  }

  static Future<bool> show({
    required int id,
    required String title,
    required String message,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('show', {
            'id': id,
            'title': title,
            'message': message,
          }) ??
          false;
    } catch (error) {
      DiagnosticLog.add('local notification show failed error=$error');
      return false;
    }
  }

  static Future<bool> syncSettings({
    required bool notificationsEnabled,
    required bool metricsEnabled,
    required bool dialogsEnabled,
    required bool interstitialsEnabled,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('syncSettings', {
            'notificationsEnabled': notificationsEnabled,
            'metricsEnabled': metricsEnabled,
            'dialogsEnabled': dialogsEnabled,
            'interstitialsEnabled': interstitialsEnabled,
          }) ??
          false;
    } catch (error) {
      DiagnosticLog.add('local notification settings sync failed error=$error');
      return false;
    }
  }
}
