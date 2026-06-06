import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account_auth_sheet.dart';
import 'account_page.dart';
import 'app_state.dart';

class AccountActionButton extends StatelessWidget {
  const AccountActionButton({super.key});

  static const double iconSize = 24;

  void _open(BuildContext context) {
    AppState.markUserInteraction('account');
    if (AppState.hapticsEnabled.value) {
      HapticFeedback.selectionClick();
    }
    if (AppState.accountSession.value?.isValid == true) {
      unawaited(
        Navigator.of(context).push(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 320),
            reverseTransitionDuration: const Duration(milliseconds: 320),
            pageBuilder: (context, animation, secondaryAnimation) =>
                const AccountPage(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, child) {
                  final value = Curves.easeOutCubic.transform(animation.value);
                  final offset = Offset(1 - value, 0);
                  final scale = 0.985 + (0.015 * value);

                  return Transform.translate(
                    offset: Offset(
                      offset.dx * MediaQuery.sizeOf(context).width,
                      offset.dy * MediaQuery.sizeOf(context).height,
                    ),
                    child: Transform.scale(
                      alignment: Alignment.bottomCenter,
                      scale: scale,
                      child: child,
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
      return;
    }
    unawaited(showAccountAuthSheet(context));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AccountSession?>(
      valueListenable: AppState.accountSession,
      builder: (context, session, _) {
        final signedIn = session?.isValid == true;
        return IconButton(
          tooltip: signedIn ? 'Account' : 'Sign in',
          iconSize: iconSize,
          onPressed: () => _open(context),
          icon: Icon(
            signedIn
                ? Icons.account_circle_rounded
                : Icons.account_circle_outlined,
          ),
        );
      },
    );
  }
}
