import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'account_auth_sheet.dart';
import 'app_state.dart';
import 'diagnostic_log.dart';
import 'juicr_bottom_sheet.dart';
import 'stream_api.dart';
import 'visual_style.dart';

const List<String> _accountEmojiOptions = [
  '🍋',
  '🎬',
  '🍿',
  '⭐',
  '🔥',
  '⚡',
  '🌙',
  '🚀',
  '🎭',
  '🏆',
  '💚',
  '😎',
  '🧃',
  '🎧',
  '📺',
  '✨',
  '🎞️',
  '🎟️',
  '🎥',
  '📽️',
  '🍫',
  '🍕',
  '🍜',
  '☕',
  '🧋',
  '🍩',
  '🍓',
  '🥭',
  '🌶️',
  '🧊',
  '🪩',
  '🎤',
  '🎹',
  '🎮',
  '🕹️',
  '🎲',
  '🧩',
  '📚',
  '📝',
  '🔍',
  '💡',
  '🛸',
  '🌌',
  '🌊',
  '🌴',
  '🌈',
  '🦾',
  '🤖',
  '👾',
  '🧠',
  '🫶',
  '😂',
  '🥹',
  '🤩',
  '🥳',
  '🤠',
  '🫡',
  '😈',
  '👻',
  '💀',
  '🍋',
  '🎬',
  '🍿',
  '⭐',
  '🔥',
  '⚡',
  '🌙',
  '🚀',
  '🎭',
  '🏆',
  '💚',
  '😎',
  '🧃',
  '🎧',
  '📺',
  '✨',
  '🇦🇫',
  '🇦🇽',
  '🇦🇱',
  '🇩🇿',
  '🇦🇸',
  '🇦🇩',
  '🇦🇴',
  '🇦🇮',
  '🇦🇶',
  '🇦🇬',
  '🇦🇷',
  '🇦🇲',
  '🇦🇼',
  '🇦🇺',
  '🇦🇹',
  '🇦🇿',
  '🇧🇸',
  '🇧🇭',
  '🇧🇩',
  '🇧🇧',
  '🇧🇾',
  '🇧🇪',
  '🇧🇿',
  '🇧🇯',
  '🇧🇲',
  '🇧🇹',
  '🇧🇴',
  '🇧🇦',
  '🇧🇼',
  '🇧🇷',
  '🇮🇴',
  '🇻🇬',
  '🇧🇳',
  '🇧🇬',
  '🇧🇫',
  '🇧🇮',
  '🇰🇭',
  '🇨🇲',
  '🇨🇦',
  '🇨🇻',
  '🇧🇶',
  '🇰🇾',
  '🇨🇫',
  '🇹🇩',
  '🇨🇱',
  '🇨🇳',
  '🇨🇽',
  '🇨🇨',
  '🇨🇴',
  '🇰🇲',
  '🇨🇬',
  '🇨🇩',
  '🇨🇰',
  '🇨🇷',
  '🇨🇮',
  '🇭🇷',
  '🇨🇺',
  '🇨🇼',
  '🇨🇾',
  '🇨🇿',
  '🇩🇰',
  '🇩🇯',
  '🇩🇲',
  '🇩🇴',
  '🇪🇨',
  '🇪🇬',
  '🇸🇻',
  '🇬🇶',
  '🇪🇷',
  '🇪🇪',
  '🇸🇿',
  '🇪🇹',
  '🇫🇰',
  '🇫🇴',
  '🇫🇯',
  '🇫🇮',
  '🇫🇷',
  '🇬🇫',
  '🇵🇫',
  '🇹🇫',
  '🇬🇦',
  '🇬🇲',
  '🇬🇪',
  '🇩🇪',
  '🇬🇭',
  '🇬🇮',
  '🇬🇷',
  '🇬🇱',
  '🇬🇩',
  '🇬🇵',
  '🇬🇺',
  '🇬🇹',
  '🇬🇬',
  '🇬🇳',
  '🇬🇼',
  '🇬🇾',
  '🇭🇹',
  '🇭🇳',
  '🇭🇰',
  '🇭🇺',
  '🇮🇸',
  '🇮🇳',
  '🇮🇩',
  '🇮🇷',
  '🇮🇶',
  '🇮🇪',
  '🇮🇲',
  '🇮🇱',
  '🇮🇹',
  '🇯🇲',
  '🇯🇵',
  '🇯🇪',
  '🇯🇴',
  '🇰🇿',
  '🇰🇪',
  '🇰🇮',
  '🇽🇰',
  '🇰🇼',
  '🇰🇬',
  '🇱🇦',
  '🇱🇻',
  '🇱🇧',
  '🇱🇸',
  '🇱🇷',
  '🇱🇾',
  '🇱🇮',
  '🇱🇹',
  '🇱🇺',
  '🇲🇴',
  '🇲🇬',
  '🇲🇼',
  '🇲🇾',
  '🇲🇻',
  '🇲🇱',
  '🇲🇹',
  '🇲🇭',
  '🇲🇶',
  '🇲🇷',
  '🇲🇺',
  '🇾🇹',
  '🇲🇽',
  '🇫🇲',
  '🇲🇩',
  '🇲🇨',
  '🇲🇳',
  '🇲🇪',
  '🇲🇸',
  '🇲🇦',
  '🇲🇿',
  '🇲🇲',
  '🇳🇦',
  '🇳🇷',
  '🇳🇵',
  '🇳🇱',
  '🇳🇨',
  '🇳🇿',
  '🇳🇮',
  '🇳🇪',
  '🇳🇬',
  '🇳🇺',
  '🇳🇫',
  '🇰🇵',
  '🇲🇰',
  '🇲🇵',
  '🇳🇴',
  '🇴🇲',
  '🇵🇰',
  '🇵🇼',
  '🇵🇸',
  '🇵🇦',
  '🇵🇬',
  '🇵🇾',
  '🇵🇪',
  '🇵🇭',
  '🇵🇳',
  '🇵🇱',
  '🇵🇹',
  '🇵🇷',
  '🇶🇦',
  '🇷🇪',
  '🇷🇴',
  '🇷🇺',
  '🇷🇼',
  '🇼🇸',
  '🇸🇲',
  '🇸🇹',
  '🇸🇦',
  '🇸🇳',
  '🇷🇸',
  '🇸🇨',
  '🇸🇱',
  '🇸🇬',
  '🇸🇽',
  '🇸🇰',
  '🇸🇮',
  '🇸🇧',
  '🇸🇴',
  '🇿🇦',
  '🇰🇷',
  '🇸🇸',
  '🇪🇸',
  '🇱🇰',
  '🇧🇱',
  '🇸🇭',
  '🇰🇳',
  '🇱🇨',
  '🇲🇫',
  '🇵🇲',
  '🇻🇨',
  '🇸🇩',
  '🇸🇷',
  '🇸🇯',
  '🇸🇪',
  '🇨🇭',
  '🇸🇾',
  '🇹🇼',
  '🇹🇯',
  '🇹🇿',
  '🇹🇭',
  '🇹🇱',
  '🇹🇬',
  '🇹🇰',
  '🇹🇴',
  '🇹🇹',
  '🇹🇳',
  '🇹🇷',
  '🇹🇲',
  '🇹🇨',
  '🇹🇻',
  '🇺🇬',
  '🇺🇦',
  '🇦🇪',
  '🇬🇧',
  '🇺🇸',
  '🇺🇾',
  '🇺🇿',
  '🇻🇺',
  '🇻🇦',
  '🇻🇪',
  '🇻🇳',
  '🇻🇮',
  '🇼🇫',
  '🇪🇭',
  '🇾🇪',
  '🇿🇲',
  '🇿🇼',
];

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _signingOut = false;
  bool _deletingAccount = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    final token = AppState.accountSession.value?.token ?? '';
    try {
      if (token.isNotEmpty) await StreamApi().signOutAuthSession(token);
    } catch (_) {
      // Local sign-out still clears the session if the network is unavailable.
    }
    final messenger = ScaffoldMessenger.of(context);
    await AppState.clearAccountSession();
    DiagnosticLog.add('account sign out cleared local session');
    AppState.shellTab.value = 3;
    if (!mounted) return;
    setState(() => _signingOut = false);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    messenger
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Signed out.')));
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        var deleteHistory = false;
        var deleteSaved = false;
        var deleteLeaderboard = false;
        var deleteAccountData = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final allChecked =
                deleteHistory &&
                deleteSaved &&
                deleteLeaderboard &&
                deleteAccountData;

            return AlertDialog(
              title: const Text('Delete your Juicr account?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This removes account-held data and signs this device out. Confirm each item before deleting.',
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: deleteAccountData,
                    onChanged: (value) =>
                        setDialogState(() => deleteAccountData = value == true),
                    title: const Text('Delete sign-in and account data'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: deleteLeaderboard,
                    onChanged: (value) =>
                        setDialogState(() => deleteLeaderboard = value == true),
                    title: const Text(
                      'Delete leaderboard profile and watch time',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: deleteSaved,
                    onChanged: (value) =>
                        setDialogState(() => deleteSaved = value == true),
                    title: const Text('Clear saved movies on this device'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: deleteHistory,
                    onChanged: (value) =>
                        setDialogState(() => deleteHistory = value == true),
                    title: const Text('Clear local history on this device'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: allChecked
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: const Text('Delete account'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final token = AppState.accountSession.value?.token ?? '';
    setState(() => _deletingAccount = true);
    try {
      await StreamApi().deleteAccount(token);
      final messenger = ScaffoldMessenger.of(context);
      AppState.clearLibrary();
      AppState.clearSearchHistory();
      AppState.clearContinueWatchingForAccountDeletion();
      AppState.clearCompletedWatchingForAccountDeletion();
      AppState.clearRetainedActiveWatchTime();
      await AppState.clearAccountSession();
      AppState.shellTab.value = 3;
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Account deleted.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not delete the account. Try again.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  Future<bool?> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearContinueWatching() async {
    final confirmed = await _confirmAction(
      title: 'Clear continue watching?',
      message:
          'This removes saved playback progress for movies, series, and animation. Active watch time stays.',
      confirmLabel: 'Clear',
    );
    if (confirmed != true) return;
    DiagnosticLog.add('account action clear continue watching pressed');
    AppState.clearContinueWatching();
    _snack('Clearing playback history...');
    await AppState.pushSignedInLibrarySnapshot(
      reason: 'clear_continue_watching',
    );

    await Future.wait<void>([
      _ignoreWebViewStorageError(CookieManager.instance().deleteAllCookies()),
      _ignoreWebViewStorageError(WebStorageManager.instance().deleteAllData()),
      _ignoreWebViewStorageError(
        InAppWebViewController.clearAllCache(includeDiskFiles: true),
      ),
    ]);

    if (!mounted) return;
    _snack('Continue watching cleared.');
  }

  Future<void> _clearFavorites() async {
    final confirmed = await _confirmAction(
      title: 'Remove all favorites?',
      message:
          'This removes every saved movie, series, animation, and channel from your Library favorites.',
      confirmLabel: 'Remove',
    );
    if (confirmed != true) return;
    DiagnosticLog.add('account action clear favorites pressed');
    AppState.clearSavedLibraryFavorites();
    await AppState.pushSignedInLibrarySnapshot(reason: 'clear_favorites');
    _snack('Favorites removed.');
  }

  Future<void> _clearLibraryLists() async {
    final confirmed = await _confirmAction(
      title: 'Clear all lists?',
      message:
          'This removes every custom Library list while keeping saved titles.',
      confirmLabel: 'Clear',
    );
    if (confirmed != true) return;
    DiagnosticLog.add('account action clear library lists pressed');
    AppState.clearLibraryLists();
    await AppState.pushSignedInLibrarySnapshot(reason: 'clear_library_lists');
    _snack('Library lists cleared.');
  }

  Future<void> _clearSearchHistory() async {
    final confirmed = await _confirmAction(
      title: 'Clear search history?',
      message: 'This removes all saved search suggestions.',
      confirmLabel: 'Clear',
    );
    if (confirmed != true) return;
    DiagnosticLog.add('account action clear search history pressed');
    AppState.clearSearchHistory();
    _snack('Search history cleared.');
  }

  Future<void> _clearCompletedWatching() async {
    final confirmed = await _confirmAction(
      title: 'Clear completed history?',
      message:
          'This removes finished-watch records while keeping current Continue Watching progress. Active watch time stays.',
      confirmLabel: 'Clear',
    );
    if (confirmed != true) return;
    DiagnosticLog.add('account action clear completed history pressed');
    AppState.clearCompletedWatching();
    await AppState.pushSignedInLibrarySnapshot(
      reason: 'clear_completed_history',
    );
    _snack('Completed history cleared.');
  }

  Future<void> _ignoreWebViewStorageError(Future<dynamic> action) async {
    try {
      await action;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 4,
        toolbarHeight: JuicrVisual.topLevelToolbarHeight,
        title: const Text('Account'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: ValueListenableBuilder<AccountSession?>(
          valueListenable: AppState.accountSession,
          builder: (context, session, _) {
            return ValueListenableBuilder<AccountProfile?>(
              valueListenable: AppState.accountProfile,
              builder: (context, profile, __) {
                final signedIn = session?.isValid == true && profile != null;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  children: [
                    if (signedIn)
                      _AccountHero(profile: profile)
                    else
                      _GuestHero(onSignIn: () => showAccountAuthSheet(context)),
                    const SizedBox(height: 12),
                    const _AccountInfoCard(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy & account data',
                      children: [
                        'Email is saved only for sign-in and account recovery.',
                        'Email is never shown on leaderboards.',
                        'Only your username, emoji, and active watch time can appear publicly after opt-in.',
                        'Saved titles, Lists, continue watching, and completed history sync after sign-in.',
                        'Search history stays on this device.',
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (signedIn) ...[
                      const _AccountLibrarySyncStatusCard(),
                      const SizedBox(height: 12),
                    ],
                    if (signedIn) ...[
                      _AccountProfileSection(profile: profile),
                      const SizedBox(height: 12),
                    ],
                    if (signedIn) ...[
                      const _AccountNotificationsSection(),
                      const SizedBox(height: 12),
                    ],
                    _AccountDataActionsSection(
                      onClearContinueWatching: _clearContinueWatching,
                      onClearFavorites: _clearFavorites,
                      onClearLibraryLists: _clearLibraryLists,
                      onClearSearchHistory: _clearSearchHistory,
                      onClearCompletedWatching: _clearCompletedWatching,
                    ),
                    if (signedIn) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _signingOut ? null : _signOut,
                        icon: _signingOut
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.logout_rounded),
                        label: const Text('Sign out'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _deletingAccount ? null : _deleteAccount,
                        icon: _deletingAccount
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete account'),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AccountProfileSection extends StatefulWidget {
  const _AccountProfileSection({required this.profile});

  final AccountProfile profile;

  @override
  State<_AccountProfileSection> createState() => _AccountProfileSectionState();
}

class _AccountProfileSectionState extends State<_AccountProfileSection> {
  late final TextEditingController _usernameController;
  late String _emoji;
  late bool _leaderboardOptIn;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.profile.username);
    _emoji = widget.profile.emoji;
    _leaderboardOptIn =
        widget.profile.leaderboardOptIn || widget.profile.username.isEmpty;
  }

  @override
  void didUpdateWidget(covariant _AccountProfileSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id ||
        oldWidget.profile.username != widget.profile.username) {
      _usernameController.text = widget.profile.username;
    }
    if (oldWidget.profile.id != widget.profile.id ||
        oldWidget.profile.emoji != widget.profile.emoji) {
      _emoji = widget.profile.emoji;
    }
    if (oldWidget.profile.leaderboardOptIn != widget.profile.leaderboardOptIn) {
      _leaderboardOptIn =
          widget.profile.leaderboardOptIn || widget.profile.username.isEmpty;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _showEmojiPicker() async {
    if (_saving) return;
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                child: Text(
                  'Choose emoji',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    18,
                    0,
                    18,
                    JuicrVisual.bottomSheetBottomBreathingRoom,
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 58,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: _accountEmojiOptions.length,
                  itemBuilder: (context, index) {
                    final option = _accountEmojiOptions[index];
                    return _EmojiChoice(
                      emoji: option,
                      selected: option == _emoji,
                      onTap: () => Navigator.of(sheetContext).pop(option),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() => _emoji = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    final token = AppState.accountSession.value?.token ?? '';
    setState(() => _saving = true);
    final api = StreamApi();
    try {
      final profile = await api.updateAccountProfile(
        token: token,
        username: _usernameController.text,
        emoji: _emoji,
        leaderboardOptIn: _leaderboardOptIn,
      );
      await AppState.updateAccountProfileCache(profile);
      await AppState.syncSignedInWatchMetrics(
        (token, activeWatchSeconds) => api.syncAccountWatchMetrics(
          token: token,
          activeWatchSeconds: activeWatchSeconds,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              profile.username.isNotEmpty && profile.emoji.isNotEmpty
                  ? 'Profile saved as ${profile.emoji} ${profile.username}.'
                  : 'Profile saved.',
            ),
          ),
        );
    } on StreamApiException catch (error) {
      if (!mounted) return;
      final message = error.message.contains('already taken')
          ? 'That username is already taken.'
          : error.message;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      api.close();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final usernameLocked = widget.profile.usernameLocked;
    return DecoratedBox(
      decoration: JuicrVisual.softPanel(colorScheme),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.badge_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Public profile',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Only your username, emoji, and active watch time can appear publicly after you join.',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.74),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    enabled: !usernameLocked && !_saving,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_]')),
                      LengthLimitingTextInputFormatter(20),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Username',
                      helperText: usernameLocked
                          ? 'Username can only be set once.'
                          : 'Username can only be set once. Juicr checks if it is already taken.',
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _EmojiPickerButton(
                  emoji: _emoji,
                  enabled: !_saving,
                  onTap: _showEmojiPicker,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'You will choose a username and emoji before joining.',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.62),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                Icons.emoji_events_outlined,
                color: colorScheme.primary,
              ),
              title: const Text('Join leaderboard'),
              subtitle: const Text(
                'On by default after sign-in. Turn this off to opt out.',
              ),
              value: _leaderboardOptIn,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _leaderboardOptIn = value),
            ),
            Padding(
              padding: EdgeInsets.zero,
              child: Text(
                'Only active watch time can become public after opt-in. Suspicious watch-time jumps are quarantined and excluded.',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.68),
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Save profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiPickerButton extends StatelessWidget {
  const _EmojiPickerButton({
    required this.emoji,
    required this.enabled,
    required this.onTap,
  });

  final String emoji;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Emoji',
      value: emoji.isEmpty ? 'Not selected' : emoji,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 72,
          height: 64,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Center(
            child: Text(
              emoji.isEmpty ? '🙂' : emoji,
              style: const TextStyle(fontSize: 28),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmojiChoice extends StatelessWidget {
  const _EmojiChoice({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 25))),
      ),
    );
  }
}

class _AccountNotificationsSection extends StatelessWidget {
  const _AccountNotificationsSection();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppState.notificationsEnabled,
        AppState.notificationDialogsEnabled,
      ]),
      builder: (context, _) {
        return _AccountSwitchCard(
          icon: Icons.notifications_active_outlined,
          title: 'Notifications',
          subtitle:
              'Choose what can appear on this device. These settings stay local for now.',
          switches: [
            _AccountSwitchItem(
              icon: Icons.notifications_active_outlined,
              title: 'Push notifications',
              subtitle:
                  'Occasional picks, episode reminders, and continue-watching prompts.',
              value: AppState.notificationsEnabled.value,
              onChanged: (enabled) {
                DiagnosticLog.add(
                  'account notifications ${enabled ? 'enabled' : 'disabled'}',
                );
                AppState.setNotificationsEnabled(enabled);
              },
            ),
            _AccountSwitchItem(
              icon: Icons.dashboard_customize_outlined,
              title: 'In-app cards',
              subtitle:
                  'Daily curation, release notes, and occasional cards while Juicr is open.',
              value: AppState.notificationDialogsEnabled.value,
              onChanged: (enabled) {
                DiagnosticLog.add(
                  'account notification in-app cards ${enabled ? 'enabled' : 'disabled'}',
                );
                AppState.setNotificationDialogsEnabled(enabled);
                AppState.setNotificationInterstitialsEnabled(enabled);
              },
            ),
          ],
        );
      },
    );
  }
}

class _AccountDataActionsSection extends StatelessWidget {
  const _AccountDataActionsSection({
    required this.onClearContinueWatching,
    required this.onClearFavorites,
    required this.onClearLibraryLists,
    required this.onClearSearchHistory,
    required this.onClearCompletedWatching,
  });

  final VoidCallback onClearContinueWatching;
  final VoidCallback onClearFavorites;
  final VoidCallback onClearLibraryLists;
  final VoidCallback onClearSearchHistory;
  final VoidCallback onClearCompletedWatching;

  @override
  Widget build(BuildContext context) {
    return _AccountActionCard(
      icon: Icons.folder_delete_outlined,
      title: 'Personal data',
      subtitle:
          'Clear saved activity from this device. Signed-in library changes also sync to your account.',
      actions: [
        _AccountActionItem(
          icon: Icons.history_rounded,
          title: 'Clear continue watching',
          subtitle: 'Remove saved playback progress. Active watch time stays.',
          onTap: onClearContinueWatching,
        ),
        _AccountActionItem(
          icon: Icons.favorite_border_rounded,
          title: 'Remove all favorites',
          subtitle: 'Remove every saved Library favorite.',
          onTap: onClearFavorites,
        ),
        _AccountActionItem(
          icon: Icons.bookmarks_outlined,
          title: 'Clear all lists',
          subtitle: 'Remove every custom Library list.',
          onTap: onClearLibraryLists,
        ),
        _AccountActionItem(
          icon: Icons.manage_search_rounded,
          title: 'Clear search history',
          subtitle: 'Remove previous searches and suggestions.',
          onTap: onClearSearchHistory,
        ),
        _AccountActionItem(
          icon: Icons.done_all_rounded,
          title: 'Clear completed history',
          subtitle:
              'Remove finished-watch records only. Active watch time stays.',
          onTap: onClearCompletedWatching,
        ),
      ],
    );
  }
}

class _AccountActionCard extends StatelessWidget {
  const _AccountActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<_AccountActionItem> actions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: JuicrVisual.softPanel(colorScheme),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.70),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < actions.length; index += 1) ...[
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              leading: Icon(actions[index].icon),
              title: Text(actions[index].title),
              subtitle: Text(actions[index].subtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: actions[index].onTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountActionItem {
  const _AccountActionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _AccountSwitchCard extends StatelessWidget {
  const _AccountSwitchCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.switches,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<_AccountSwitchItem> switches;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: JuicrVisual.softPanel(colorScheme),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.70),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < switches.length; index += 1) ...[
            const Divider(height: 1),
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              secondary: Icon(switches[index].icon),
              title: Text(switches[index].title),
              subtitle: Text(switches[index].subtitle),
              value: switches[index].value,
              onChanged: switches[index].onChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountSwitchItem {
  const _AccountSwitchItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
}

class _GuestHero extends StatelessWidget {
  const _GuestHero({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: JuicrVisual.elevatedCardDecoration(colorScheme),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            JuicrVisual.iconBadge(context, icon: Icons.person_outline_rounded),
            const SizedBox(height: 14),
            const Text(
              'Continue as guest',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Juicr stays free. Sign in only when you want account sync, Lists, and future leaderboard opt-in.',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onSignIn,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountHero extends StatelessWidget {
  const _AccountHero({required this.profile});

  final AccountProfile profile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: JuicrVisual.elevatedCardDecoration(colorScheme),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            JuicrVisual.iconBadge(context, icon: Icons.verified_user_rounded),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Signed in',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountLibrarySyncStatusCard extends StatelessWidget {
  const _AccountLibrarySyncStatusCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<AccountLibrarySyncStatus>(
      valueListenable: AppState.accountLibrarySyncStatus,
      builder: (context, status, _) {
        return DecoratedBox(
          decoration: JuicrVisual.softPanel(colorScheme),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.sync_rounded, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.safeLabel,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.74),
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AccountInfoCard extends StatelessWidget {
  const _AccountInfoCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<String> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: JuicrVisual.softPanel(colorScheme),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final child in children) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      child,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.74),
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              if (child != children.last) const SizedBox(height: 7),
            ],
          ],
        ),
      ),
    );
  }
}
