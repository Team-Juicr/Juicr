import 'dart:async';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'diagnostic_log.dart';
import 'stream_api.dart';
import 'visual_style.dart';

const Set<String> _supportedAuthEmailDomains = {
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

const String _unsupportedAuthEmailMessage =
    'Use a supported personal email provider to sign in.';

bool _isSupportedAuthEmail(String email) {
  final parts = email.trim().toLowerCase().split('@');
  if (parts.length != 2 || parts.first.isEmpty || parts.last.isEmpty) {
    return false;
  }
  return _supportedAuthEmailDomains.contains(parts.last);
}

Future<void> showAccountAuthSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const AccountAuthSheet(),
  );
}

class AccountAuthSheet extends StatefulWidget {
  const AccountAuthSheet({super.key});

  @override
  State<AccountAuthSheet> createState() => _AccountAuthSheetState();
}

class _AccountAuthSheetState extends State<AccountAuthSheet> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final StreamApi _api = StreamApi();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  int _resendCooldownSeconds = 0;

  @override
  void dispose() {
    _api.close();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _busy) return;
    if (!_isSupportedAuthEmail(email)) {
      DiagnosticLog.add(
        'account sign-in code request blocked reason=unsupported_email_domain',
      );
      setState(() => _error = _unsupportedAuthEmailMessage);
      return;
    }
    DiagnosticLog.add('account sign-in code request started');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.sendAuthCode(email);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _resendCooldownSeconds = result.resendCooldownSeconds;
      });
      DiagnosticLog.add('account sign-in code request ok');
    } on StreamApiException catch (error) {
      final bucket = _authFailureBucket(error);
      DiagnosticLog.add('account sign-in code request failed bucket=$bucket');
      if (mounted) setState(() => _error = _friendlyAuthError(error.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    if (email.isEmpty || code.length < 6 || _busy) return;
    if (!_isSupportedAuthEmail(email)) {
      setState(() => _error = _unsupportedAuthEmailMessage);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.verifyAuthCode(email: email, code: code);
      await AppState.saveAccountSession(
        session: result.session,
        profile: result.profile,
      );
      unawaited(
        AppState.syncSignedInLibrary(
          fetch: _api.fetchAccountLibrarySnapshot,
          push: (token, snapshot, baseRevision) =>
              _api.pushAccountLibrarySnapshot(
                token: token,
                snapshot: snapshot,
                baseRevision: baseRevision,
              ),
        ),
      );
      unawaited(
        AppState.syncSignedInWatchMetrics(
          (token, activeWatchSeconds) => _api.syncAccountWatchMetrics(
            token: token,
            activeWatchSeconds: activeWatchSeconds,
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      final profile = result.profile;
      final signedInLabel =
          profile.username.isNotEmpty && profile.emoji.isNotEmpty
          ? '${profile.emoji} ${profile.username}'
          : profile.email;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('Signed in to Juicr as $signedInLabel.')),
        );
    } on StreamApiException catch (error) {
      if (mounted) setState(() => _error = _friendlyAuthError(error.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyAuthError(String message) {
    final text = message.trim();
    if (text.isEmpty) {
      return 'Sign-in is having trouble right now. Please try again.';
    }
    final lower = text.toLowerCase();
    if (lower.contains('request failed') ||
        lower.contains('server error') ||
        lower.contains('500') ||
        lower.contains('503')) {
      return 'Sign-in is having trouble right now. Please try again.';
    }
    return text;
  }

  String _authFailureBucket(StreamApiException error) {
    final lower = error.message.toLowerCase();
    if (lower.contains('too many') || lower.contains('wait before')) {
      return 'rate_limited';
    }
    if (lower.contains("couldn't send") ||
        lower.contains('503') ||
        lower.contains('server error')) {
      return 'delivery_unavailable';
    }
    if (lower.contains('valid email') ||
        lower.contains('supported personal email')) {
      return 'validation';
    }
    if (lower.contains('connection') ||
        lower.contains('timeout') ||
        lower.contains('network')) {
      return 'network';
    }
    return error is StreamApiTemporaryBlockException
        ? 'temporary_unavailable'
        : 'other';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: DecoratedBox(
          decoration: JuicrVisual.elevatedCardDecoration(
            colorScheme,
            color: colorScheme.surface,
            radius: JuicrVisual.bottomSheetTopRadius,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              20,
              14,
              20,
              JuicrVisual.bottomSheetBottomBreathingRoom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    JuicrVisual.iconBadge(
                      context,
                      icon: Icons.person_rounded,
                      boxSize: 42,
                      iconSize: 20,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Sign in to Juicr',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Your email is used for sign-in and account recovery. Use a supported personal email provider.',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _emailController,
                  enabled: !_busy && !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  onSubmitted: (_) => unawaited(_sendCode()),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codeController,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '6-digit code',
                      counterText: '',
                      prefixIcon: Icon(Icons.pin_rounded),
                    ),
                    onSubmitted: (_) => unawaited(_verifyCode()),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : _codeSent
                      ? _verifyCode
                      : _sendCode,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _codeSent
                              ? Icons.verified_rounded
                              : Icons.send_rounded,
                        ),
                  label: Text(_codeSent ? 'Verify code' : 'Send code'),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _sendCode,
                    child: Text(
                      _resendCooldownSeconds > 0
                          ? 'Send another code'
                          : 'Resend code',
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Continue as guest'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
