import 'dart:ui';

import 'package:flutter/services.dart';

int _immersiveSessionDepth = 0;

bool get juicrImmersiveSessionActive => _immersiveSessionDepth > 0;

void beginJuicrImmersiveSession() {
  _immersiveSessionDepth += 1;
}

void endJuicrImmersiveSession() {
  if (_immersiveSessionDepth > 0) {
    _immersiveSessionDepth -= 1;
  }
}

Future<void> restoreJuicrSystemUi({bool force = false}) {
  if (!force && juicrImmersiveSessionActive) {
    return Future<void>.value();
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      systemNavigationBarColor: Color(0xFF000000),
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  return SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
}

void scheduleJuicrSystemUiRestore() {
  if (juicrImmersiveSessionActive) return;
  restoreJuicrSystemUi();
  Future<void>.delayed(const Duration(milliseconds: 120), () {
    restoreJuicrSystemUi();
  });
  Future<void>.delayed(const Duration(milliseconds: 450), () {
    restoreJuicrSystemUi();
  });
}
