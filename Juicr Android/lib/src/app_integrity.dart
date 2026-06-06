import 'dart:async';

import 'package:flutter/services.dart';

import 'diagnostic_log.dart';

class AppIntegrityService {
  AppIntegrityService._();

  static final AppIntegrityService instance = AppIntegrityService._();
  static const MethodChannel _channel =
      MethodChannel('app.juicr.flutter/integrity');

  Future<void> observeBoot() async {
    try {
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('status')
          .timeout(const Duration(seconds: 2));
      final mode = result?['mode']?.toString() ?? 'unknown';
      final available = result?['available'] == true;
      final configured = result?['configured'] == true;
      final appTrusted = result?['appTrusted'] != false;
      final packageTrusted = result?['packageTrusted'] != false;
      final signatureConfigured = result?['signatureConfigured'] == true;
      final signatureTrusted = result?['signatureTrusted'] != false;
      final blockUntrustedApp = result?['blockUntrustedApp'] == true;
      DiagnosticLog.add(
        'app integrity observe mode=$mode '
        'available=$available configured=$configured '
        'appTrusted=$appTrusted packageTrusted=$packageTrusted '
        'signatureConfigured=$signatureConfigured '
        'signatureTrusted=$signatureTrusted',
      );
      if (!appTrusted && blockUntrustedApp) {
        DiagnosticLog.add('app integrity blocked untrusted app build');
        await SystemNavigator.pop();
      }
    } on MissingPluginException {
      DiagnosticLog.add(
        'app integrity observe mode=unsupported '
        'available=false configured=false',
      );
    } on TimeoutException {
      DiagnosticLog.add('app integrity observe failed reason=timeout');
    } catch (error) {
      DiagnosticLog.add('app integrity observe failed error=$error');
    }
  }
}
