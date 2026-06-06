import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'account_action_button.dart';
import 'app_state.dart';
import 'catalog_item.dart';
import 'diagnostic_log.dart';
import 'juicr_bottom_sheet.dart';
import 'motion.dart';
import 'p2p_indexer_connectors.dart';
import 'p2p_stream_bridge.dart';
import 'playback_provider.dart';
import 'source_ranking.dart';
import 'stream_api.dart';
import 'visual_style.dart';

const MethodChannel _externalPlayerChannel = MethodChannel(
  'app.juicr.flutter/external_player',
);
const MethodChannel _catalogBuilderPickerChannel = MethodChannel(
  'app.juicr.flutter/catalog_builder_picker',
);

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final StreamApi _api = StreamApi();
  late Future<StreamConfig> _configFuture;
  late final Future<Map<String, Object?>> _installInfoFuture;
  String _providerHealthSampleId = '';
  bool _checkingProviders = false;
  List<String> _providerHealthLogs = const [];
  static const ApiProvider _autoNativeProvider = ApiProvider(
    id: AppState.autoNativeProviderId,
    name: 'Auto',
  );
  final ValueNotifier<bool> _checkingProvidersNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _addonSelectionModeNotifier = ValueNotifier(false);
  final ValueNotifier<Set<String>> _selectedAddonIdsNotifier =
      ValueNotifier<Set<String>>(const <String>{});
  final ValueNotifier<List<String>> _providerHealthLogsNotifier = ValueNotifier(
    const [],
  );
  final ValueNotifier<_ProviderHealthSummaryResult?>
  _providerHealthSummaryNotifier = ValueNotifier(null);
  final Map<String, Future<AddonCapabilities>> _addonCapabilityFutures =
      <String, Future<AddonCapabilities>>{};
  final List<ApiProvider> _nativeProviders = const [
    ApiProvider(id: 'vidlink', name: 'Alpha'),
    ApiProvider(id: 'vidsrc', name: 'Beta'),
    ApiProvider(id: 'icefy', name: 'Delta'),
    ApiProvider(id: 'vidnest', name: 'Epsilon'),
    ApiProvider(id: 'xpass', name: 'Zeta'),
    ApiProvider(id: 'moviesapi', name: 'Eta'),
    ApiProvider(id: 'vidking', name: 'Nu'),
    ApiProvider(id: 'popr', name: 'Theta'),
    ApiProvider(id: 'cinesu', name: 'Rho'),
    ApiProvider(id: 'rgshows', name: 'Iota'),
    ApiProvider(id: 'vixsrc', name: 'Kappa'),
    ApiProvider(id: 'vidrock', name: 'Lambda'),
    ApiProvider(id: 'vidzee', name: 'Mu'),
    ApiProvider(id: 'vidapi', name: 'Sigma'),
    ApiProvider(id: 'videasy', name: 'Tau'),
    ApiProvider(id: 'vidfun', name: 'Upsilon'),
    ApiProvider(id: 'flixhq', name: 'Phi'),
    ApiProvider(id: 'flixer', name: 'Xi'),
    ApiProvider(id: '7xstream', name: 'Omicron'),
    ApiProvider(id: 'meowtv', name: 'Pi'),
  ];

  @override
  void initState() {
    super.initState();
    _configFuture = StreamApi.cachedConfig == null
        ? Future<StreamConfig>.delayed(
            const Duration(milliseconds: 800),
            _api.config,
          )
        : Future<StreamConfig>.value(StreamApi.cachedConfig!);
    _installInfoFuture = Future<Map<String, Object?>>.delayed(
      const Duration(milliseconds: 1200),
      DiagnosticLog.installInfo,
    );
    AppState.settingsIntent.addListener(_handleSettingsIntent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) _scheduleLazyProviderHealthRefresh();
      });
      _handleSettingsIntent();
    });
  }

  @override
  void dispose() {
    AppState.settingsIntent.removeListener(_handleSettingsIntent);
    _checkingProvidersNotifier.dispose();
    _addonSelectionModeNotifier.dispose();
    _selectedAddonIdsNotifier.dispose();
    _providerHealthLogsNotifier.dispose();
    _providerHealthSummaryNotifier.dispose();
    _api.close();
    super.dispose();
  }

  void _handleSettingsIntent() {
    if (!mounted || AppState.settingsIntent.value != 'addons') return;
    AppState.settingsIntent.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openAddOnsSection();
    });
  }

  String _addonCapabilityCacheKey(UserAddon addon) {
    return '${addon.id}|${addon.name}|${addon.manifestUrl}';
  }

  Future<AddonCapabilities> _addonCapabilityFuture(UserAddon addon) {
    final key = _addonCapabilityCacheKey(addon);
    return _addonCapabilityFutures.putIfAbsent(
      key,
      () => _api.addonCapabilities(addon),
    );
  }

  void _forgetAddonCapability(UserAddon addon) {
    final prefix = '${addon.id}|';
    _addonCapabilityFutures.removeWhere((key, _) => key.startsWith(prefix));
  }

  void _pruneAddonCapabilityFutures(List<UserAddon> addons) {
    final activeKeys = {
      for (final addon in addons) _addonCapabilityCacheKey(addon),
    };
    _addonCapabilityFutures.removeWhere((key, _) => !activeKeys.contains(key));
  }

  Future<void> _openAddOnsSection() {
    return _openSettingsSection(
      title: 'Add-ons',
      child: _buildAddOnsSettingsContent(),
      framed: false,
      actions: [
        IconButton(
          tooltip: 'Add-ons guide',
          onPressed: _showAddOnsHelpSheet,
          icon: const Icon(Icons.menu_book_outlined),
        ),
        IconButton(
          tooltip: 'Manage add-ons',
          onPressed: _showAddOnsManagerSheet,
          icon: const Icon(Icons.settings_rounded),
        ),
      ],
    );
  }

  Future<void> _openPersonalServersSection() {
    return _openSettingsSection(
      title: 'Personal servers',
      child: _buildPersonalServersSettingsContent(),
      framed: false,
      actions: [
        IconButton(
          tooltip: 'Personal servers guide',
          onPressed: _showPersonalServersHelpSheet,
          icon: const Icon(Icons.menu_book_outlined),
        ),
      ],
      titleBadgeLabel: 'Beta',
      titleBadgeHint:
          'Personal servers are functional, but still being validated against real home server setups.',
    );
  }

  void _reload() {
    setState(() {
      _configFuture = _api.config();
    });
  }

  void _snack(String message) {
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _copyDiagnosticReport() async {
    DiagnosticLog.add('Diagnostic report copied from Settings.');
    await DiagnosticLog.refreshBatteryEvidenceForReport('copy_report');
    await Clipboard.setData(ClipboardData(text: DiagnosticLog.report()));
    _snack('Diagnostic report copied.');
  }

  Future<void> _sendDiagnosticReport() async {
    final accepted = await _confirmDiagnosticReportPrivacy();
    if (accepted != true) return;
    await DiagnosticLog.refreshBatteryEvidenceForReport('send_report');
    final report = DiagnosticLog.uploadReport();
    DiagnosticLog.add('Diagnostic report submitted from Settings.');
    try {
      final ticketId = await _api.sendDiagnosticReport(report);
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: ticketId));
      await _showDiagnosticTicketCreated(ticketId);
    } catch (error) {
      DiagnosticLog.add('Diagnostic report submit failed error=$error');
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: report));
      await _showDiagnosticUploadFallback(error);
    }
  }

  Future<void> _copyAppVersion() async {
    final installInfo = await _installInfoFuture;
    final versionName = _stringValue(installInfo['versionName']);
    final versionCode = _stringValue(installInfo['versionCode']);
    final packageName = _stringValue(installInfo['packageName']);
    final parts = <String>[
      if (versionName.isNotEmpty) versionName else 'unknown',
      if (versionCode.isNotEmpty && versionCode != '0') '($versionCode)',
      if (packageName.isNotEmpty) packageName,
    ];
    DiagnosticLog.add('settings app version copied');
    await Clipboard.setData(ClipboardData(text: parts.join(' ')));
    if (!mounted) return;
    _snack('App version copied.');
  }

  Future<bool?> _confirmDiagnosticReportPrivacy() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send diagnostic report?'),
        content: const SingleChildScrollView(
          child: Text(
            'Juicr will send a private diagnostic ticket so we can investigate issues.\n\n'
            'What is included:\n'
            '- Recent app events and errors\n'
            '- Playback and add-on state summaries\n'
            '- App settings needed for troubleshooting\n'
            '- Performance timing clues when available\n\n'
            'What is not included:\n'
            '- Passwords or account tokens\n'
            '- Playable stream links\n'
            '- Local file names, paths, or picked-file handles\n'
            '- Private manifest URLs\n'
            '- Email addresses or long secret-looking values\n\n'
            'Juicr does not sell diagnostic data, use it for advertising, or use it to track you across apps or services.\n\n'
            'The report is redacted before sending and the server redacts it again. Tickets are kept temporarily so fixes can be tracked in release notes and changelogs.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('I agree, send'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDiagnosticTicketCreated(String ticketId) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Diagnostic ticket sent'),
        content: Text(
          'Your ticket number is $ticketId.\n\n'
          'It was copied to your clipboard. Keep this number if you want to reference the fix later.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: ticketId));
              Navigator.of(context).pop();
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDiagnosticUploadFallback(Object error) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Diagnostic report copied'),
        content: Text(
          'Juicr could not create the online ticket right now, so the report was copied to your clipboard instead.\n\n'
          'Reason: ${_diagnosticUploadErrorLabel(error)}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String _diagnosticUploadErrorLabel(Object error) {
    final raw = error.toString();
    if (raw.contains('Diagnostic report is too large')) {
      return 'The report was larger than the upload limit.';
    }
    if (raw.contains('timed out') || raw.contains('TimeoutException')) {
      return 'The network request timed out.';
    }
    if (raw.contains('Failed host lookup') || raw.contains('SocketException')) {
      return 'The device could not reach the diagnostics service.';
    }
    if (raw.contains('Diagnostic inbox is not configured')) {
      return 'The diagnostics inbox is not available on the server.';
    }
    if (raw.contains('429') || raw.contains('Rate limit')) {
      return 'Too many reports were sent recently. Please try again later.';
    }
    return 'The diagnostics service was unavailable.';
  }

  Future<void> _clearVerifiedSourceCache() async {
    final confirmed = await _confirmAction(
      title: 'Clear playback shortcuts?',
      message:
          'This forgets last-working playback shortcuts. Juicr will check again next time.',
      confirmLabel: 'Clear',
    );
    if (confirmed != true) return;
    DiagnosticLog.add('settings action clear verified source cache pressed');
    AppState.clearVerifiedPlaybackSources();
    _snack('Playback shortcuts cleared.');
  }

  Future<void> _clearAddonRouteEvidence() async {
    final confirmed = await _confirmAction(
      title: 'Clear add-on route evidence?',
      message:
          'This removes recent add-on route-attempt diagnostics. It does not remove add-ons.',
      confirmLabel: 'Clear',
    );
    if (confirmed != true) return;
    DiagnosticLog.add('settings action clear addon route evidence pressed');
    AppState.clearAddonRouteAttemptHistory();
    _snack('Add-on route evidence cleared.');
  }

  Future<void> _clearProviderCheckSamples() async {
    final confirmed = await _confirmAction(
      title: 'Clear playback health samples?',
      message:
          'This removes stale sample-only playback checks. Your playback choice stays untouched.',
      confirmLabel: 'Clear',
    );
    if (confirmed != true) return;
    DiagnosticLog.add('settings action clear provider check samples pressed');
    AppState.clearSampleOnlyNativeProviderHealth();
    _snack('Playback health samples cleared.');
  }

  void _scheduleLazyProviderHealthRefresh() {
    if (!mounted || !AppState.defaultProvidersEnabled.value) {
      return;
    }
    final quietRemaining = AppState.interactionQuietRemaining();
    if (quietRemaining > Duration.zero) {
      Future<void>.delayed(quietRemaining, () {
        if (mounted) _scheduleLazyProviderHealthRefresh();
      });
      return;
    }
    unawaited(_syncProviderHealthFromResolver());
  }

  bool _providerHealthLooksStale() {
    final health = AppState.nativeProviderHealth.value;
    if (health.isEmpty) return true;
    final now = DateTime.now();
    for (final provider in _nativeProviders) {
      final details = health[provider.id];
      if (details == null ||
          details.status == NativeProviderHealthStatus.untested ||
          details.status == NativeProviderHealthStatus.checkedNoSample) {
        return true;
      }
      if (now.difference(details.updatedAt) > const Duration(minutes: 45)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _syncProviderHealthFromResolver() async {
    await _api.refreshNativeProviderServerHealth();
    if (!mounted || !_providerHealthLooksStale()) return;
    DiagnosticLog.add(
      'settings playback availability cache unavailable; keeping local playback state',
    );
  }

  Future<void> _refreshProviderHealth({bool silent = false}) async {
    if (_checkingProviders) return;
    final remaining = AppState.providerHealthRefreshRemaining();
    if (remaining > Duration.zero) {
      if (!silent) {
        _snack(
          'Please wait ${remaining.inSeconds + 1}s before checking again.',
        );
      }
      return;
    }

    DiagnosticLog.add(
      silent
          ? 'settings playback availability lazy refresh started'
          : 'settings playback availability refresh started',
    );
    await AppState.markProviderHealthRefreshStarted();
    if (!mounted) return;
    final initialLogs = const [
      'Preparing built-in playback routes',
      'Starting playback availability check',
    ];
    var sampleReadyCount = 0;
    void publishLogs(List<String> logs) {
      if (silent || !mounted) return;
      _providerHealthLogsNotifier.value = logs;
      setState(() {
        _providerHealthLogs = logs;
      });
    }

    if (!silent) {
      _checkingProvidersNotifier.value = true;
      _providerHealthLogsNotifier.value = initialLogs;
      _providerHealthSummaryNotifier.value = null;
    }
    setState(() {
      _checkingProviders = true;
      if (!silent) _providerHealthLogs = initialLogs;
    });
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    try {
      var nextLogs = [
        ..._providerHealthLogs,
        'Resolving shared availability sample',
      ];
      publishLogs(nextLogs);

      final customId = _providerHealthSampleId.trim();
      final check = await _api.checkNativeProviderHealthSample(
        customId: customId.isEmpty ? null : customId,
      );
      if (!mounted) return;
      final sampleLabel = _providerHealthSampleCheckLabel(check.sample);

      nextLogs = [
        ..._providerHealthLogs,
        'Checking built-in availability for $sampleLabel',
      ];
      publishLogs(nextLogs);

      final providerCounts = check.providerCounts;
      if (!check.timedOut || providerCounts.isNotEmpty) {
        for (final provider in _nativeProviders) {
          if (!mounted) return;
          final count = providerCounts[provider.id] ?? 0;
          if (count > 0) {
            sampleReadyCount += 1;
          }
          AppState.recordNativeProviderResolve(
            providerId: provider.id,
            sourceCount: count,
            elapsed: Duration.zero,
          );
        }
      }

      nextLogs = [
        ..._providerHealthLogs,
        check.timedOut
            ? 'Sample timed out; keeping the last playback status.'
            : 'Checked ${_nativeProviders.length} built-in playback options. $sampleReadyCount available.',
      ];
      publishLogs(nextLogs);

      DiagnosticLog.add(
        silent
            ? 'settings playback availability lazy refresh finished'
            : 'settings playback availability refresh finished',
      );
      if (!mounted) return;
      nextLogs = [..._providerHealthLogs, 'Playback status refreshed'];
      publishLogs(nextLogs);
      if (!silent) _snack('Playback check updated.');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      final summary = _providerHealthSummaryFromSample(
        sampleReadyCount: sampleReadyCount,
        sampleLabel: sampleLabel,
        sourceClassCounts: check.sourceClassCounts,
      );
      if (!silent) _providerHealthSummaryNotifier.value = summary;
    } catch (error) {
      DiagnosticLog.add('settings playback availability refresh failed: $error');
      if (!mounted) return;
      final temporarilyBlocked = error is StreamApiTemporaryBlockException;
      if (!silent) {
        _snack(
          temporarilyBlocked
              ? 'Playback check is busy right now.'
              : 'Playback check failed. Try again later.',
        );
      }
      final summary = temporarilyBlocked
          ? _providerHealthSummaryFromCurrentState(blocked: true)
          : const _ProviderHealthSummaryResult(
              total: 0,
              ready: 0,
              noSource: 0,
              noSample: 0,
              issue: 1,
              untested: 0,
              failed: true,
            );
      if (!silent) _providerHealthSummaryNotifier.value = summary;
    } finally {
      if (!silent) _checkingProvidersNotifier.value = false;
      if (mounted) setState(() => _checkingProviders = false);
    }
  }

  Future<void> _configureProviderHealthSample() async {
    final result = await showJuicrBottomSheet<_ProviderHealthSampleConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) {
        return _ProviderHealthSampleSheet(initialId: _providerHealthSampleId);
      },
    );
    if (result == null) return;
    setState(() {
      _providerHealthSampleId = result.id.trim();
    });
    DiagnosticLog.add(
      'settings playback health sample configured id=${_providerHealthSampleId.isEmpty ? 'playback-random' : _providerHealthSampleId}',
    );
  }

  String get _providerHealthSampleLabel {
    final id = _providerHealthSampleId.trim();
    if (id.isEmpty) return 'Juicr chooses a fresh sample each check';
    return 'Catalog ID $id';
  }

  String _providerHealthSampleCheckLabel(ProviderHealthSample sample) {
    final title = sample.title?.trim();
    final hasTitle = title != null && title.isNotEmpty;
    final name = hasTitle ? title : '${sample.type.label} ID ${sample.id}';
    if (sample.type == MediaType.movie) {
      return hasTitle ? '$name (${sample.type.label} ${sample.id})' : name;
    }
    return hasTitle
        ? '$name (${sample.type.label} ${sample.id} S${sample.season} E${sample.episode})'
        : '$name S${sample.season} E${sample.episode}';
  }

  CatalogItem _providerHealthCatalogItem(ProviderHealthSample sample) {
    final title = sample.title?.trim();
    return CatalogItem(
      type: sample.type,
      id: sample.id,
      name: title == null || title.isEmpty
          ? '${sample.type.label} ID ${sample.id}'
          : title,
      year: sample.year,
    );
  }

  Future<List<PlaybackSource>> _resolveProviderHealthSampleSources(
    CatalogItem item,
    ProviderHealthSample sample,
    String providerId,
  ) {
    if (sample.type == MediaType.movie) {
      return _api.resolveMovieNativeSources(item, providerId: providerId);
    }
    return _api.resolveEpisodeNativeSources(
      item,
      season: sample.season,
      episode: sample.episode,
      providerId: providerId,
    );
  }

  _ProviderHealthSummaryResult _providerHealthSummaryFromCurrentState({
    int? sampleReadyCount,
    String? sampleLabel,
    bool blocked = false,
  }) {
    var readyCount = 0;
    var noSourceCount = 0;
    var noSampleCount = 0;
    var issueCount = 0;
    var untestedCount = 0;
    final healthByProvider = AppState.nativeProviderHealth.value;
    for (final provider in _nativeProviders) {
      final health =
          healthByProvider[provider.id] ??
          AppState.nativeProviderHealthDetailsFor(provider.id);
      switch (health.status) {
        case NativeProviderHealthStatus.ready:
          readyCount += 1;
        case NativeProviderHealthStatus.limited:
        case NativeProviderHealthStatus.noSource:
          noSourceCount += 1;
        case NativeProviderHealthStatus.checkedNoSample:
        case NativeProviderHealthStatus.protected:
          noSampleCount += 1;
        case NativeProviderHealthStatus.slow:
        case NativeProviderHealthStatus.failing:
          issueCount += 1;
        case NativeProviderHealthStatus.untested:
          untestedCount += 1;
          break;
      }
    }
    return _ProviderHealthSummaryResult(
      total: _nativeProviders.length,
      ready: readyCount,
      noSource: noSourceCount,
      noSample: noSampleCount,
      issue: issueCount,
      untested: untestedCount,
      sampleReadyCount: sampleReadyCount,
      sampleLabel: sampleLabel,
      historical: true,
      blocked: blocked,
    );
  }

  _ProviderHealthSummaryResult _providerHealthSummaryFromSample({
    required int sampleReadyCount,
    required String sampleLabel,
    required Map<String, int> sourceClassCounts,
  }) {
    var readyCount = 0;
    var noSourceCount = 0;
    var noSampleCount = 0;
    var issueCount = 0;
    var untestedCount = 0;
    final healthByProvider = AppState.nativeProviderHealth.value;
    for (final provider in _nativeProviders) {
      final health =
          healthByProvider[provider.id] ??
          AppState.nativeProviderHealthDetailsFor(provider.id);
      switch (health.status) {
        case NativeProviderHealthStatus.ready:
          readyCount += 1;
        case NativeProviderHealthStatus.limited:
        case NativeProviderHealthStatus.noSource:
          noSourceCount += 1;
        case NativeProviderHealthStatus.checkedNoSample:
        case NativeProviderHealthStatus.protected:
          noSampleCount += 1;
        case NativeProviderHealthStatus.slow:
        case NativeProviderHealthStatus.failing:
          issueCount += 1;
        case NativeProviderHealthStatus.untested:
          untestedCount += 1;
          break;
      }
    }
    return _ProviderHealthSummaryResult(
      total: _nativeProviders.length,
      ready: readyCount,
      noSource: noSourceCount,
      noSample: noSampleCount,
      issue: issueCount,
      untested: untestedCount,
      sampleReadyCount: sampleReadyCount,
      sampleLabel: sampleLabel,
      sourceClassSummary: _providerHealthSourceClassSummary(sourceClassCounts),
      historical: false,
    );
  }

  String? _providerHealthSourceClassSummary(Map<String, int> counts) {
    if (counts.isEmpty) return null;
    const labels = <String, String>{
      'direct': 'direct',
      'debrid': 'cached',
      'external': 'external',
      'p2p': 'P2P',
      'unsupported': 'unsupported',
      'unknown': 'unknown',
    };
    final parts = <String>[];
    for (final sourceClass in labels.keys) {
      final count = counts[sourceClass] ?? 0;
      if (count <= 0) continue;
      final routeLabel = count == 1 ? 'route' : 'routes';
      parts.add('$count ${labels[sourceClass]} $routeLabel');
    }
    if (parts.isEmpty) return null;
    return 'Source mix: ${parts.join(', ')}.';
  }

  void _updateNativeOverrides(NativePlaybackOverrides next) {
    AppState.updateNativePlaybackOverrides(next);
  }

  void _updatePlayerBehavior(PlayerBehaviorSettings next) {
    AppState.updatePlayerBehaviorSettings(next);
  }

  void _updateBatteryData(BatteryDataSettings next) {
    AppState.updateBatteryDataSettings(next);
  }

  Future<void> _setExperimentalControlsEnabled(
    PlayerBehaviorSettings behavior,
    bool enabled,
  ) async {
    if (enabled && !await _confirmExperimentalControlsEnable()) return;
    _updatePlayerBehavior(
      behavior.copyWith(experimentalControlsEnabled: enabled),
    );
  }

  Future<void> _resetPlaybackOverrides() async {
    final confirmed = await _confirmAction(
      title: 'Reset overwrite settings?',
      message: 'This restores the global native player defaults.',
      confirmLabel: 'Reset',
    );
    if (confirmed != true) return;
    AppState.updateNativePlaybackOverrides(const NativePlaybackOverrides());
    AppState.setNativePlaybackOverridesEnabled(false);
    _snack('Playback overwrite settings reset.');
  }

  Future<void> _clearSavedNativePlayerSettings() async {
    final confirmed = await _confirmAction(
      title: 'Clear saved player settings?',
      message:
          'This clears per-title quality, speed, subtitle, and sizing choices while keeping watch progress.',
      confirmLabel: 'Clear',
    );
    if (confirmed != true) return;
    AppState.clearSavedNativePlayerSettings();
    _snack('Saved player settings cleared.');
  }

  Future<void> _resetPlayerBehaviorSettings() async {
    final confirmed = await _confirmAction(
      title: 'Reset player behavior?',
      message:
          'This restores playback behavior, retry, subtitle selection, and control defaults.',
      confirmLabel: 'Reset',
    );
    if (confirmed != true) return;
    AppState.updatePlayerBehaviorSettings(const PlayerBehaviorSettings());
    _snack('Player behavior reset.');
  }

  Future<void> _resetExperimentalControls(
    PlayerBehaviorSettings behavior,
  ) async {
    final confirmed = await _confirmAction(
      title: 'Reset advanced playback?',
      message:
          'This restores the stable Media3, libVLC, retry, and progress timing defaults.',
      confirmLabel: 'Reset',
    );
    if (confirmed != true) return;
    const defaults = PlayerBehaviorSettings();
    _updatePlayerBehavior(
      behavior.copyWith(
        failureReadSeconds: defaults.failureReadSeconds,
        providerWarmupCount: defaults.providerWarmupCount,
        providerResolveTimeoutSeconds: defaults.providerResolveTimeoutSeconds,
        progressFallbackClockEnabled: defaults.progressFallbackClockEnabled,
        resumeSeekRetrySeconds: defaults.resumeSeekRetrySeconds,
        blackVideoWatchdogSeconds: defaults.blackVideoWatchdogSeconds,
        autoProviderMemory: defaults.autoProviderMemory,
        libVlcWarmupSeconds: defaults.libVlcWarmupSeconds,
        libVlcReleaseSettleMs: defaults.libVlcReleaseSettleMs,
        stallWatchdogSeconds: defaults.stallWatchdogSeconds,
        libVlcOpenTimeoutSeconds: defaults.libVlcOpenTimeoutSeconds,
        libVlcContinuousTsVisualGraceSeconds:
            defaults.libVlcContinuousTsVisualGraceSeconds,
        zeroClockSkipEnabled: defaults.zeroClockSkipEnabled,
        exoPlayerOpenTimeoutSeconds: defaults.exoPlayerOpenTimeoutSeconds,
        media3NativeExoEnabled: defaults.media3NativeExoEnabled,
      ),
    );
    _snack('Advanced playback settings reset.');
  }

  double _autoProviderMemoryValue(String memory) {
    return switch (memory) {
      'fresh' => 0,
      'sticky' => 2,
      _ => 1,
    };
  }

  String _autoProviderMemoryFromValue(double value) {
    final rounded = value.round();
    return switch (rounded) {
      0 => 'fresh',
      2 => 'sticky',
      _ => 'balanced',
    };
  }

  String _autoProviderMemoryLabel(String memory) {
    return switch (memory) {
      'fresh' => 'Fresh',
      'sticky' => 'Sticky',
      _ => 'Balanced',
    };
  }

  Future<bool?> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    final normalizedLabel = confirmLabel.trim().toLowerCase();
    final looksDestructive =
        destructive ||
        normalizedLabel == 'clear' ||
        normalizedLabel == 'remove' ||
        normalizedLabel == 'reset' ||
        normalizedLabel.startsWith('delete');
    if (looksDestructive && !AppState.confirmDestructiveActions.value) {
      return Future<bool?>.value(true);
    }
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  }

  void _maybeSelectionHaptic() {
    if (!AppState.hapticsEnabled.value) return;
    HapticFeedback.selectionClick();
  }

  String _qualityModeLabel(NativePlaybackOverrides value) {
    return switch (value.qualityMode) {
      'higher' => 'Higher picture quality',
      'dataSaver' => 'Data saver',
      'advanced' => 'Advanced',
      _ => 'Auto (recommended)',
    };
  }

  String _fitModeLabel(String value) {
    return switch (value) {
      'fill' => 'Fill',
      'wide' => '16:9',
      'stretch' => 'Stretch',
      _ => 'Fit',
    };
  }

  String _startBehaviorLabel(String value) {
    return switch (value) {
      'resume' => 'Resume automatically',
      'restart' => 'Start from beginning',
      _ => 'Ask when available',
    };
  }

  String _playbackEngineLabel(String value) {
    return switch (value) {
      'exoplayer' => 'Media3',
      'libvlc' => 'libVLC',
      'ksplayer' => 'KSPlayer',
      _ => 'Auto',
    };
  }

  bool get _supportsKsPlayerEngine {
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  String _playerModeLabel(PlayerBehaviorSettings settings) {
    if (settings.useNativePlayer) {
      return 'In-app - ${_playbackEngineLabel(settings.playbackEngine)}';
    }
    return settings.externalPlayerLabel ?? 'External player';
  }

  Future<List<_ExternalPlayerApp>> _loadExternalPlayers() async {
    try {
      final raw =
          await _externalPlayerChannel.invokeMethod<List<dynamic>>('list') ??
          const <dynamic>[];
      final players = <_ExternalPlayerApp>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final packageName = item['packageName']?.toString().trim() ?? '';
        final activityName = item['activityName']?.toString().trim() ?? '';
        final label = item['label']?.toString().trim() ?? '';
        if (packageName.isEmpty || label.isEmpty) continue;
        players.add(
          _ExternalPlayerApp(
            packageName: packageName,
            activityName: activityName,
            label: label,
          ),
        );
      }
      DiagnosticLog.add('external players detected count=${players.length}');
      return players;
    } catch (error) {
      DiagnosticLog.add('external players list failed: $error');
      return const <_ExternalPlayerApp>[];
    }
  }

  String _retryStyleLabel(String value) {
    return switch (value) {
      'fast' => 'Fast failover',
      'patient' => 'Patient',
      _ => 'Balanced',
    };
  }

  String _subtitleAutoLabel(String value) {
    return switch (value) {
      'off' => 'Off',
      'last' => 'Last used',
      'forced' => 'Forced only',
      _ => 'Default language',
    };
  }

  String _subtitleLanguageLabel(String value) {
    return switch (value) {
      'auto' => 'Auto',
      'en' => 'English',
      'ja' => 'Japanese',
      'ko' => 'Korean',
      'es' => 'Spanish',
      'fr' => 'French',
      'de' => 'German',
      'pt' => 'Portuguese',
      'fil' || 'tl' => 'Filipino',
      _ => value.toUpperCase(),
    };
  }

  String _audioLanguageLabel(String value) {
    return switch (value) {
      'original' => 'Original audio',
      _ => _subtitleLanguageLabel(value),
    };
  }

  String _p2pPriorityModeLabel(String mode) {
    return switch (mode) {
      p2pPriorityModeQualityFirst => 'Quality first',
      p2pPriorityModeAvailabilityFirst => 'Availability first',
      p2pPriorityModeSmallerFasterFiles => 'Smaller, faster files',
      p2pPriorityModeBalancedQualityAvailability =>
        'Balanced quality and availability',
      _ => 'Smart start',
    };
  }

  String _p2pPriorityModeSubtitle(String mode) {
    return switch (mode) {
      p2pPriorityModeQualityFirst =>
        'Prefer sharper results when several playable choices are available.',
      p2pPriorityModeAvailabilityFirst =>
        'Prefer choices that are more likely to start reliably.',
      p2pPriorityModeSmallerFasterFiles =>
        'Prefer lighter files that can begin faster on constrained networks.',
      p2pPriorityModeBalancedQualityAvailability =>
        'Balance picture quality with a stronger chance of smooth startup.',
      _ => 'Balance fast startup, quality, and source health automatically.',
    };
  }

  String _p2pSizeLimitLabel(int value) {
    return value <= 0 ? 'No limit' : '${value} MB';
  }

  String _startupTabLabel(String value) {
    return switch (value) {
      'home' => 'Home',
      'discovery' => 'Discovery',
      'library' => 'Library',
      'settings' => 'Settings',
      _ => 'Last used',
    };
  }

  String _textSizeLabel(String value) {
    return switch (value) {
      'small' => 'Small',
      'large' => 'Large',
      _ => 'Default',
    };
  }

  String _navigationStyleLabel(String value) {
    return switch (value) {
      'selected' => 'Selected label only',
      'hidden' => 'Icons only',
      _ => 'Always show labels',
    };
  }

  String _homeDensityLabel(String value) {
    return switch (value) {
      'compact' => 'Compact',
      'large' => 'Large posters',
      _ => 'Comfortable',
    };
  }

  String _statusMessageStyleLabel(String value) {
    return switch (value) {
      'bottom' => 'Bottom bar',
      'quiet' => 'Quiet floating',
      _ => 'Floating',
    };
  }

  String _posterImageIntensityLabel(String value) {
    return switch (value) {
      'soft' => 'Soft',
      'bold' => 'Bold',
      _ => 'Normal',
    };
  }

  String _loadingBackdropStyleLabel(String value) {
    return switch (value) {
      'none' => 'Off',
      'artworkBlur' => 'Artwork blur',
      _ => 'Scan pulse',
    };
  }

  String _systemBarStyleLabel(String value) {
    return switch (value) {
      'black' => 'Black',
      'transparent' => 'Transparent',
      _ => 'Match theme',
    };
  }

  Future<void> _showStartupTabSheet() async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'App start page',
        options: const [
          _OptionItem(value: 'home', label: 'Home'),
          _OptionItem(value: 'discovery', label: 'Discovery'),
          _OptionItem(value: 'library', label: 'Library'),
          _OptionItem(value: 'settings', label: 'Settings'),
          _OptionItem(value: 'last', label: 'Last used'),
        ],
        selected: AppState.startupTabMode.value,
      ),
    );
    if (selected == null) return;
    DiagnosticLog.add('settings startup tab selected $selected');
    AppState.setStartupTabMode(selected);
    if (mounted) setState(() {});
  }

  Future<void> _showTextSizeSheet() async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Text size',
        options: const [
          _OptionItem(value: 'small', label: 'Small'),
          _OptionItem(value: 'default', label: 'Default'),
          _OptionItem(value: 'large', label: 'Large'),
        ],
        selected: AppState.textSize.value,
      ),
    );
    if (selected == null) return;
    DiagnosticLog.add('settings text size selected $selected');
    AppState.setTextSize(selected);
    if (mounted) setState(() {});
  }

  Future<void> _showNavigationStyleSheet() async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Navigation style',
        options: const [
          _OptionItem(value: 'always', label: 'Always show labels'),
          _OptionItem(value: 'selected', label: 'Selected label only'),
          _OptionItem(value: 'hidden', label: 'Icons only'),
        ],
        selected: AppState.navigationStyle.value,
      ),
    );
    if (selected == null) return;
    DiagnosticLog.add('settings navigation style selected $selected');
    AppState.setNavigationStyle(selected);
    if (mounted) setState(() {});
  }

  Future<void> _showHomeDensitySheet() async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Home density',
        options: const [
          _OptionItem(value: 'compact', label: 'Compact'),
          _OptionItem(value: 'comfortable', label: 'Comfortable'),
          _OptionItem(value: 'large', label: 'Large posters'),
        ],
        selected: AppState.homeDensity.value,
      ),
    );
    if (selected == null) return;
    DiagnosticLog.add('settings home density selected $selected');
    AppState.setHomeDensity(selected);
    if (mounted) setState(() {});
  }

  Future<void> _showStatusMessageStyleSheet() async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Status message style',
        options: const [
          _OptionItem(value: 'floating', label: 'Floating'),
          _OptionItem(value: 'quiet', label: 'Quiet floating'),
          _OptionItem(value: 'bottom', label: 'Bottom bar'),
        ],
        selected: AppState.statusMessageStyle.value,
      ),
    );
    if (selected == null) return;
    DiagnosticLog.add('settings status message style selected $selected');
    AppState.setStatusMessageStyle(selected);
    if (mounted) setState(() {});
  }

  Future<void> _showPosterImageIntensitySheet() async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Poster image intensity',
        options: const [
          _OptionItem(value: 'soft', label: 'Soft'),
          _OptionItem(value: 'normal', label: 'Normal'),
          _OptionItem(value: 'bold', label: 'Bold'),
        ],
        selected: AppState.posterImageIntensity.value,
      ),
    );
    if (selected == null) return;
    DiagnosticLog.add('settings poster intensity selected $selected');
    AppState.setPosterImageIntensity(selected);
    if (mounted) setState(() {});
  }

  Future<void> _showLoadingBackdropStyleSheet(
    PlayerBehaviorSettings settings,
  ) async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Player loading backdrop',
        options: const [
          _OptionItem(value: 'none', label: 'Off'),
          _OptionItem(value: 'scan', label: 'Scan pulse'),
          _OptionItem(value: 'artworkBlur', label: 'Artwork blur'),
        ],
        selected: settings.loadingBackdropStyle,
      ),
    );
    if (selected == null) return;
    DiagnosticLog.add('settings loading backdrop selected $selected');
    _updatePlayerBehavior(settings.copyWith(loadingBackdropStyle: selected));
    if (mounted) setState(() {});
  }

  Future<void> _showSystemBarStyleSheet() async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Status/navigation bars',
        options: const [
          _OptionItem(value: 'match', label: 'Match theme'),
          _OptionItem(value: 'black', label: 'Black'),
          _OptionItem(value: 'transparent', label: 'Transparent'),
        ],
        selected: AppState.systemBarStyle.value,
      ),
    );
    if (selected == null) return;
    DiagnosticLog.add('settings system bars selected $selected');
    AppState.setSystemBarStyle(selected);
    if (mounted) setState(() {});
  }

  void _resetAppearanceSettings() {
    DiagnosticLog.add('settings appearance reset');
    AppState.setThemeMode(ThemeMode.system);
    AppState.setPureBlackTheme(false);
    AppState.setUseDeviceAccent(false);
    AppState.setAccentTheme(AppState.accentGreen);
    AppState.setStartupTabMode('home');
    AppState.setStartupBehavior('normal');
    AppState.setCompactLayout(false);
    AppState.setReduceMotion(false);
    AppState.setTextSize('default');
    AppState.setNavigationStyle('always');
    AppState.setHomeDensity('comfortable');
    AppState.setArtworkMotion(true);
    AppState.setConfirmDestructiveActions(true);
    AppState.setHapticsEnabled(true);
    AppState.setStatusMessageStyle('floating');
    AppState.setPosterImageIntensity('normal');
    AppState.setSystemBarStyle('match');
    _snack('Appearance reset.');
  }

  Future<void> _showQualityModeSheet(NativePlaybackOverrides overrides) async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Preferred quality',
        options: const [
          _OptionItem(value: 'recommended', label: 'Auto (recommended)'),
          _OptionItem(value: 'higher', label: 'Higher picture quality'),
          _OptionItem(value: 'dataSaver', label: 'Data saver'),
          _OptionItem(value: 'advanced', label: 'Advanced'),
        ],
        selected: overrides.qualityMode,
      ),
    );
    if (selected == null) return;
    _updateNativeOverrides(overrides.copyWith(qualityMode: selected));
  }

  Future<void> _showAdvancedQualitySheet(
    NativePlaybackOverrides overrides,
  ) async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Advanced quality',
        options: const [
          _OptionItem(value: '4320P', label: '4320P (8K)'),
          _OptionItem(value: '2160P', label: '2160P (4K)'),
          _OptionItem(value: '1440P', label: '1440P (QHD)'),
          _OptionItem(value: '1080P', label: '1080P (Full HD)'),
          _OptionItem(value: '800P', label: '800P'),
          _OptionItem(value: '720P', label: '720P (HD)'),
          _OptionItem(value: '674P', label: '674P'),
          _OptionItem(value: '534P', label: '534P'),
          _OptionItem(value: '480P', label: '480P'),
          _OptionItem(value: '452P', label: '452P'),
          _OptionItem(value: '360P', label: '360P'),
          _OptionItem(value: '336P', label: '336P'),
          _OptionItem(value: '266P', label: '266P'),
          _OptionItem(value: '240P', label: '240P'),
        ],
        selected: overrides.advancedQuality == '4K'
            ? '2160P'
            : overrides.advancedQuality,
      ),
    );
    if (selected == null) return;
    _updateNativeOverrides(
      overrides.copyWith(qualityMode: 'advanced', advancedQuality: selected),
    );
  }

  Future<void> _showFitModeSheet(NativePlaybackOverrides overrides) async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Video size',
        options: const [
          _OptionItem(value: 'fit', label: 'Fit'),
          _OptionItem(value: 'fill', label: 'Fill'),
          _OptionItem(value: 'wide', label: '16:9'),
          _OptionItem(value: 'stretch', label: 'Stretch'),
        ],
        selected: overrides.videoFitMode,
      ),
    );
    if (selected == null) return;
    _updateNativeOverrides(overrides.copyWith(videoFitMode: selected));
  }

  Future<void> _showStartBehaviorSheet(PlayerBehaviorSettings settings) async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Start behavior',
        options: const [
          _OptionItem(value: 'ask', label: 'Ask when available'),
          _OptionItem(value: 'resume', label: 'Resume automatically'),
          _OptionItem(value: 'restart', label: 'Start from beginning'),
        ],
        selected: settings.startBehavior,
      ),
    );
    if (selected == null) return;
    _updatePlayerBehavior(settings.copyWith(startBehavior: selected));
  }

  Future<void> _showPlaybackEngineSheet(PlayerBehaviorSettings settings) async {
    final supportsKsPlayer = _supportsKsPlayerEngine;
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Native player',
        options: [
          const _OptionItem(
            value: 'auto',
            label: 'Auto',
            subtitle:
                'Automatically chooses the best compatible in-app engine for the stream format and device.',
          ),
          const _OptionItem(
            value: 'exoplayer',
            label: 'Media3',
            subtitle: 'Fast Android-native path for direct and cached streams.',
          ),
          const _OptionItem(
            value: 'libvlc',
            label: 'libVLC',
            subtitle:
                'Independent in-app engine with broad format support and its own buffering behavior.',
          ),
          if (supportsKsPlayer)
            const _OptionItem(
              value: 'ksplayer',
              label: 'KSPlayer',
              subtitle:
                  'Apple-side candidate only; Android does not route to it.',
            ),
        ],
        selected: supportsKsPlayer || settings.playbackEngine != 'ksplayer'
            ? settings.playbackEngine
            : 'auto',
      ),
    );
    if (selected == null) return;
    DiagnosticLog.add('settings playback engine selected $selected');
    _updatePlayerBehavior(settings.copyWith(playbackEngine: selected));
  }

  Future<void> _showRetryStyleSheet(PlayerBehaviorSettings settings) async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Retry style',
        options: const [
          _OptionItem(value: 'fast', label: 'Fast failover'),
          _OptionItem(value: 'balanced', label: 'Balanced'),
          _OptionItem(value: 'patient', label: 'Patient'),
        ],
        selected: settings.retryStyle,
      ),
    );
    if (selected == null) return;
    _updatePlayerBehavior(settings.copyWith(retryStyle: selected));
  }

  Future<void> _showSubtitleAutoSheet(PlayerBehaviorSettings settings) async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Subtitle auto-select',
        options: const [
          _OptionItem(value: 'off', label: 'Off'),
          _OptionItem(value: 'default', label: 'Default language'),
          _OptionItem(value: 'last', label: 'Last used'),
          _OptionItem(value: 'forced', label: 'Forced only'),
        ],
        selected: settings.subtitleAutoSelect,
      ),
    );
    if (selected == null) return;
    _updatePlayerBehavior(settings.copyWith(subtitleAutoSelect: selected));
  }

  Future<void> _showSubtitleLanguageSheet(
    PlayerBehaviorSettings settings,
  ) async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Preferred subtitles',
        options: const [
          _OptionItem(value: 'auto', label: 'Auto'),
          _OptionItem(value: 'en', label: 'English'),
          _OptionItem(value: 'ja', label: 'Japanese'),
          _OptionItem(value: 'ko', label: 'Korean'),
          _OptionItem(value: 'es', label: 'Spanish'),
          _OptionItem(value: 'fr', label: 'French'),
          _OptionItem(value: 'de', label: 'German'),
          _OptionItem(value: 'pt', label: 'Portuguese'),
          _OptionItem(value: 'fil', label: 'Filipino'),
        ],
        selected: settings.subtitleLanguage,
      ),
    );
    if (selected == null) return;
    _updatePlayerBehavior(settings.copyWith(subtitleLanguage: selected));
  }

  Future<void> _showAudioLanguageSheet(PlayerBehaviorSettings settings) async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Preferred audio',
        options: const [
          _OptionItem(value: 'auto', label: 'Auto'),
          _OptionItem(value: 'original', label: 'Original audio'),
          _OptionItem(value: 'en', label: 'English'),
          _OptionItem(value: 'ja', label: 'Japanese'),
          _OptionItem(value: 'ko', label: 'Korean'),
          _OptionItem(value: 'es', label: 'Spanish'),
          _OptionItem(value: 'fr', label: 'French'),
          _OptionItem(value: 'de', label: 'German'),
          _OptionItem(value: 'pt', label: 'Portuguese'),
          _OptionItem(value: 'fil', label: 'Filipino'),
        ],
        selected: settings.preferredAudioLanguage,
      ),
    );
    if (selected == null) return;
    _updatePlayerBehavior(settings.copyWith(preferredAudioLanguage: selected));
  }

  Future<void> _showP2pPriorityModeSheet(
    PlayerBehaviorSettings settings,
  ) async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<String>(
        title: 'Source priority',
        options: [
          for (final mode in const [
            p2pPriorityModeSmartStart,
            p2pPriorityModeQualityFirst,
            p2pPriorityModeAvailabilityFirst,
            p2pPriorityModeSmallerFasterFiles,
            p2pPriorityModeBalancedQualityAvailability,
          ])
            _OptionItem(
              value: mode,
              label: _p2pPriorityModeLabel(mode),
              subtitle: _p2pPriorityModeSubtitle(mode),
            ),
        ],
        selected: settings.p2pPriorityMode,
      ),
    );
    if (selected == null) return;
    _updatePlayerBehavior(settings.copyWith(p2pPriorityMode: selected));
  }

  Future<void> _showP2pSizeLimitSheet(PlayerBehaviorSettings settings) async {
    final selected = await showJuicrBottomSheet<int>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => _OptionSheet<int>(
        title: 'Source size limit',
        options: [
          for (final value in const [0, 2048, 4096, 8192, 16384, 32768, 65536])
            _OptionItem(
              value: value,
              label: _p2pSizeLimitLabel(value),
              subtitle: value <= 0
                  ? 'Let Juicr consider all eligible source sizes.'
                  : 'Prefer sources up to ${_p2pSizeLimitLabel(value)}.',
            ),
        ],
        selected: settings.p2pSizeLimitMb,
      ),
    );
    if (selected == null) return;
    _updatePlayerBehavior(settings.copyWith(p2pSizeLimitMb: selected));
  }

  Future<void> _showPlaybackHelpSheet() async {
    await showJuicrBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => const _PlaybackHelpSheet(),
    );
  }

  Future<void> _showBatteryDataHelpSheet() async {
    await showJuicrBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => const _BatteryDataHelpSheet(),
    );
  }

  Future<void> _showGeneralHelpSheet() async {
    await showJuicrBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => const _GeneralHelpSheet(),
    );
  }

  Future<void> _showDefaultSourceHelpSheet() async {
    await showJuicrBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => const _DefaultSourceHelpSheet(),
    );
  }

  Future<void> _showAddOnsHelpSheet() async {
    await showJuicrBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => const _AddOnsHelpSheet(),
    );
  }

  Future<void> _showPersonalServersHelpSheet() async {
    await showJuicrBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => const _PersonalServersHelpSheet(),
    );
  }

  Future<void> _showAdvanceHelpSheet() async {
    await showJuicrBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => const _AdvanceHelpSheet(),
    );
  }

  Future<void> _openSettingsSection({
    required String title,
    required Widget child,
    bool framed = true,
    List<Widget>? actions,
    BuildContext? sourceContext,
    String? titleBadgeLabel,
    String? titleBadgeHint,
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _SettingsSectionPage(
              title: title,
              child: child,
              framed: framed,
              actions: actions,
              titleBadgeLabel: titleBadgeLabel,
              titleBadgeHint: titleBadgeHint,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
    );
  }

  Future<void> _showAddOnDialog({UserAddon? existing}) async {
    if (!await _confirmAddOnDisclaimer()) return;
    final result = await showDialog<_AddonDialogResult>(
      context: context,
      builder: (context) => _AddonEditorDialog(existing: existing),
    );

    if (result == null) return;
    final editing = existing != null;
    final candidate = UserAddon(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: result.name,
      manifestUrl: result.manifestUrl,
      active: result.active,
    );
    var active = result.active;
    if (active) {
      try {
        final capabilities = await _api.addonCapabilities(candidate);
        final conflictLane = await _firstAddonActivationConflict(
          candidate,
          capabilities,
        );
        if (conflictLane != null) {
          await _showAddonLaneConflictDialog(conflictLane);
          active = false;
        }
      } catch (error) {
        DiagnosticLog.add(
          'settings addon ${candidate.id} save active check failed error=$error',
        );
        _snack('Could not check this add-on yet. Saved off for now.');
        active = false;
      }
    }
    if (editing) {
      AppState.updateUserAddon(
        existing.copyWith(
          name: result.name,
          manifestUrl: result.manifestUrl,
          active: active,
        ),
      );
    } else {
      AppState.addUserAddon(
        name: result.name,
        manifestUrl: result.manifestUrl,
        active: active,
      );
    }
    if (mounted) {
      _snack(
        active
            ? (editing ? 'Add-on updated.' : 'Add-on saved.')
            : (editing ? 'Add-on updated, but left off.' : 'Add-on saved off.'),
      );
    }
  }

  Future<void> _showPersonalServerSheet(PersonalServerType type) async {
    final existing = AppState.personalServerConnection(type);
    final result = await showJuicrBottomSheet<_PersonalServerEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) =>
          _PersonalServerEditorSheet(type: type, existing: existing),
    );
    if (!mounted || result == null) return;
    if (result.remove) {
      AppState.removePersonalServerConnection(type);
      DiagnosticLog.add('settings personal server removed type=${type.id}');
      _snack('${type.label} removed.');
      return;
    }
    AppState.upsertPersonalServerConnection(
      PersonalServerConnection(
        type: type,
        serverUrl: result.serverUrl,
        username: result.username,
        token: result.token,
        password: result.password,
        userId: result.userId,
        active: result.active,
        updatedAt: DateTime.now(),
      ),
    );
    DiagnosticLog.add('settings personal server saved type=${type.id}');
    _snack('${type.label} saved.');
  }

  String _personalServerSubtitle(
    PersonalServerConnection? connection, {
    required String fallback,
  }) {
    if (connection == null) return fallback;
    final server = Uri.tryParse(connection.serverUrl)?.host;
    final serverLabel = server == null || server.isEmpty
        ? 'saved server'
        : server;
    final activeLabel = connection.active ? 'Ready to sync later' : 'Saved off';
    return '$serverLabel - $activeLabel. Catalog and playback stay in the personal server lane.';
  }

  Widget _buildGeneralSettingsContent() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppState.themeMode,
        AppState.pureBlackTheme,
        AppState.accentThemeId,
        AppState.customAccentColor,
        AppState.useDeviceAccent,
        AppState.compactLayout,
        AppState.reduceMotion,
        AppState.startupTabMode,
        AppState.posterImageIntensity,
        AppState.systemBarStyle,
        AppState.showMatureContent,
        AppState.artworkMotion,
        AppState.confirmDestructiveActions,
        AppState.hapticsEnabled,
        AppState.playerBehaviorSettings,
        AppState.textSize,
        AppState.navigationStyle,
        AppState.homeDensity,
        AppState.statusMessageStyle,
      ]),
      builder: (context, _) {
        final mode = AppState.themeMode.value;
        final pureBlack = AppState.pureBlackTheme.value;
        final accentId = AppState.accentThemeId.value;
        final customAccent = AppState.customAccentColor.value;
        final useDeviceAccent = AppState.useDeviceAccent.value;
        final textSize = AppState.textSize.value;
        final navigationStyle = AppState.navigationStyle.value;
        final homeDensity = AppState.homeDensity.value;
        final startupTabMode = AppState.startupTabMode.value;
        final showMatureContent = AppState.showMatureContent.value;
        final compactLayout = AppState.compactLayout.value;
        final reduceMotion = AppState.reduceMotion.value;
        final artworkMotion = AppState.artworkMotion.value;
        final confirmDestructiveActions =
            AppState.confirmDestructiveActions.value;
        final hapticsEnabled = AppState.hapticsEnabled.value;
        final posterIntensity = AppState.posterImageIntensity.value;
        final behavior = AppState.playerBehaviorSettings.value;
        final statusMessageStyle = AppState.statusMessageStyle.value;
        final systemBarStyle = AppState.systemBarStyle.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ThemeOption(
                            label: 'System',
                            icon: Icons.contrast_rounded,
                            selected: mode == ThemeMode.system,
                            onTap: () {
                              DiagnosticLog.add(
                                'settings theme selected system',
                              );
                              AppState.setThemeMode(ThemeMode.system);
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _ThemeOption(
                            label: 'Light',
                            icon: Icons.light_mode_outlined,
                            selected: mode == ThemeMode.light,
                            onTap: () {
                              DiagnosticLog.add(
                                'settings theme selected light',
                              );
                              AppState.setThemeMode(ThemeMode.light);
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _ThemeOption(
                            label: 'Dark',
                            icon: Icons.dark_mode_rounded,
                            selected: mode == ThemeMode.dark,
                            onTap: () {
                              DiagnosticLog.add('settings theme selected dark');
                              AppState.setThemeMode(ThemeMode.dark);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  _GeneralSwitchTile(
                    title: 'Pure black theme',
                    subtitle: 'Use AMOLED black surfaces in dark mode',
                    value: pureBlack,
                    onChanged: (enabled) {
                      DiagnosticLog.add(
                        'settings pure black theme ${enabled ? 'enabled' : 'disabled'}',
                      );
                      AppState.setPureBlackTheme(enabled);
                      if (enabled &&
                          AppState.themeMode.value != ThemeMode.dark) {
                        DiagnosticLog.add(
                          'settings pure black theme forced dark mode',
                        );
                        AppState.setThemeMode(ThemeMode.dark);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GeneralSwitchTile(
                    title: 'Use device accent',
                    subtitle: 'Let Juicr follow your device highlight color',
                    value: useDeviceAccent,
                    onChanged: (enabled) {
                      DiagnosticLog.add(
                        'settings device accent ${enabled ? 'enabled' : 'disabled'}',
                      );
                      AppState.setUseDeviceAccent(enabled);
                    },
                  ),
                  const Divider(height: 1),
                  _AccentThemeCard(
                    selectedId: accentId,
                    customColor: customAccent,
                    enabled: !useDeviceAccent,
                    onSelected: (id) {
                      DiagnosticLog.add('settings accent selected $id');
                      AppState.setAccentTheme(id);
                    },
                    onCustomSelected: () async {
                      final selected = await showDialog<Color>(
                        context: context,
                        builder: (context) => _ColorPickerDialog(
                          title: 'Custom accent',
                          initialColor: customAccent,
                        ),
                      );
                      if (selected == null) return;
                      DiagnosticLog.add('settings accent selected custom');
                      AppState.setCustomAccentColor(selected);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GeneralLanguageTile(
                    onTap: () {
                      _snack(
                        'Language settings are reserved for a future update.',
                      );
                    },
                  ),
                  const Divider(height: 1),
                  _GeneralValueTile(
                    title: 'Text size',
                    subtitle: 'Scale app text for readability',
                    value: _textSizeLabel(textSize),
                    onTap: _showTextSizeSheet,
                  ),
                  const Divider(height: 1),
                  _GeneralValueTile(
                    title: 'Navigation style',
                    subtitle: 'Choose bottom tab labels',
                    value: _navigationStyleLabel(navigationStyle),
                    onTap: _showNavigationStyleSheet,
                  ),
                  const Divider(height: 1),
                  _GeneralValueTile(
                    title: 'Home density',
                    subtitle: 'Adjust poster grid spacing',
                    value: _homeDensityLabel(homeDensity),
                    onTap: _showHomeDensitySheet,
                  ),
                  const Divider(height: 1),
                  _GeneralValueTile(
                    title: 'App start page',
                    subtitle: 'Choose where Juicr opens',
                    value: _startupTabLabel(startupTabMode),
                    onTap: _showStartupTabSheet,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _ExperimentalInfoTile(
                    icon: Icons.visibility_off_outlined,
                    title: 'Adult title visibility',
                    subtitle:
                        'Adult flags are imperfect. Some mature or erotic films may still appear because catalog labels can differ by title, cut, or region.',
                  ),
                  const Divider(height: 1),
                  _GeneralSwitchTile(
                    title: 'Show Adult Titles',
                    badgeText: '+18',
                    subtitle: 'Include titles hidden by default',
                    value: showMatureContent,
                    onChanged: (enabled) {
                      _maybeSelectionHaptic();
                      DiagnosticLog.add(
                        'settings mature content ${enabled ? 'enabled' : 'disabled'}',
                      );
                      AppState.setShowMatureContent(enabled);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GeneralSwitchTile(
                    title: 'Compact layout',
                    subtitle: 'Tighten spacing across controls',
                    value: compactLayout,
                    onChanged: (enabled) {
                      DiagnosticLog.add(
                        'settings compact layout ${enabled ? 'enabled' : 'disabled'}',
                      );
                      AppState.setCompactLayout(enabled);
                      setState(() {});
                    },
                  ),
                  const Divider(height: 1),
                  _GeneralSwitchTile(
                    title: 'Reduce motion',
                    subtitle: 'Remove page transition animations',
                    value: reduceMotion,
                    onChanged: (enabled) {
                      DiagnosticLog.add(
                        'settings reduce motion ${enabled ? 'enabled' : 'disabled'}',
                      );
                      AppState.setReduceMotion(enabled);
                      setState(() {});
                    },
                  ),
                  const Divider(height: 1),
                  _GeneralSwitchTile(
                    title: 'Artwork motion',
                    subtitle: 'Animate poster and artwork UI changes',
                    value: artworkMotion,
                    onChanged: (enabled) {
                      _maybeSelectionHaptic();
                      DiagnosticLog.add(
                        'settings artwork motion ${enabled ? 'enabled' : 'disabled'}',
                      );
                      AppState.setArtworkMotion(enabled);
                    },
                  ),
                  const Divider(height: 1),
                  _GeneralSwitchTile(
                    title: 'Confirm destructive actions',
                    subtitle: 'Ask before clearing or resetting data',
                    value: confirmDestructiveActions,
                    onChanged: (enabled) {
                      _maybeSelectionHaptic();
                      DiagnosticLog.add(
                        'settings destructive confirmations ${enabled ? 'enabled' : 'disabled'}',
                      );
                      AppState.setConfirmDestructiveActions(enabled);
                    },
                  ),
                  const Divider(height: 1),
                  _GeneralSwitchTile(
                    title: 'Haptics',
                    subtitle: 'Use vibration feedback on key taps',
                    value: hapticsEnabled,
                    onChanged: (enabled) {
                      _maybeSelectionHaptic();
                      DiagnosticLog.add(
                        'settings haptics ${enabled ? 'enabled' : 'disabled'}',
                      );
                      AppState.setHapticsEnabled(enabled);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GeneralValueTile(
                    title: 'Poster image intensity',
                    subtitle: 'Tune poster contrast preference',
                    value: _posterImageIntensityLabel(posterIntensity),
                    onTap: _showPosterImageIntensitySheet,
                  ),
                  const Divider(height: 1),
                  _GeneralValueTile(
                    title: 'Player loading backdrop',
                    subtitle: 'Choose what shows while Juicr checks sources',
                    value: _loadingBackdropStyleLabel(
                      behavior.loadingBackdropStyle,
                    ),
                    onTap: () => _showLoadingBackdropStyleSheet(behavior),
                  ),
                  const Divider(height: 1),
                  _GeneralValueTile(
                    title: 'Status message style',
                    subtitle: 'Choose snackbar placement',
                    value: _statusMessageStyleLabel(statusMessageStyle),
                    onTap: _showStatusMessageStyleSheet,
                  ),
                  const Divider(height: 1),
                  _GeneralValueTile(
                    title: 'Status/navigation bars',
                    subtitle: 'Choose how system bars blend',
                    value: _systemBarStyleLabel(systemBarStyle),
                    onTap: _showSystemBarStyleSheet,
                  ),
                  const Divider(height: 1),
                  _GeneralValueTile(
                    title: 'Reset appearance',
                    subtitle: 'Return theme and display settings to defaults',
                    value: 'Reset',
                    onTap: _resetAppearanceSettings,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlaybackSettingsContent() {
    return ValueListenableBuilder<bool>(
      valueListenable: AppState.nativePlaybackOverridesEnabled,
      builder: (context, enabled, __) {
        return ValueListenableBuilder<NativePlaybackOverrides>(
          valueListenable: AppState.nativePlaybackOverrides,
          builder: (context, overrides, ___) {
            return ValueListenableBuilder<PlayerBehaviorSettings>(
              valueListenable: AppState.playerBehaviorSettings,
              builder: (context, behavior, ____) {
                return Column(
                  children: [
                    _SettingsCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 4,
                            ),
                            secondary: const Icon(
                              Icons.play_circle_outline_rounded,
                            ),
                            title: const Text('Native player'),
                            subtitle: Text(_playerModeLabel(behavior)),
                            value: behavior.useNativePlayer,
                            onChanged: (value) {
                              DiagnosticLog.add(
                                'settings native player enabled=$value',
                              );
                              _updatePlayerBehavior(
                                behavior.copyWith(useNativePlayer: value),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          if (behavior.useNativePlayer)
                            _SettingsValueTile(
                              icon: Icons.memory_rounded,
                              title: 'Playback engine',
                              value: _playbackEngineLabel(
                                behavior.playbackEngine,
                              ),
                              onTap: () => _showPlaybackEngineSheet(behavior),
                            )
                          else
                            _ExternalPlayersSection(
                              selectedPackage: behavior.externalPlayerPackage,
                              loadPlayers: _loadExternalPlayers,
                              onSelected: (player) {
                                DiagnosticLog.add(
                                  'settings external player selected ${player.packageName}',
                                );
                                _updatePlayerBehavior(
                                  behavior.copyWith(
                                    externalPlayerPackage: player.packageName,
                                    externalPlayerActivity: player.activityName,
                                    externalPlayerLabel: player.label,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SettingsCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 4,
                            ),
                            secondary: const Icon(Icons.tune_rounded),
                            title: const Text('Overwrite settings'),
                            subtitle: const Text(
                              'Force native player defaults for movies, episodes, and animation.',
                            ),
                            value: enabled,
                            onChanged:
                                AppState.setNativePlaybackOverridesEnabled,
                          ),
                          const Divider(height: 1),
                          _OverrideSettingsSection(
                            enabled: enabled,
                            children: [
                              _SettingsValueTile(
                                icon: Icons.high_quality_rounded,
                                title: 'Preferred quality',
                                value: _qualityModeLabel(overrides),
                                showValue: false,
                                onTap: () => _showQualityModeSheet(overrides),
                              ),
                              if (overrides.qualityMode != 'advanced')
                                _SettingsValueTile(
                                  icon: Icons.aspect_ratio_rounded,
                                  title: 'Video size',
                                  value: _fitModeLabel(overrides.videoFitMode),
                                  showValue: false,
                                  onTap: () => _showFitModeSheet(overrides),
                                ),
                              if (overrides.qualityMode == 'advanced')
                                Column(
                                  children: [
                                    _SettingsValueTile(
                                      icon: Icons.tune_rounded,
                                      title: 'Advanced quality',
                                      value: overrides.advancedQuality,
                                      showValue: false,
                                      onTap: () =>
                                          _showAdvancedQualitySheet(overrides),
                                    ),
                                    _SettingsValueTile(
                                      icon: Icons.aspect_ratio_rounded,
                                      title: 'Video size',
                                      value: _fitModeLabel(
                                        overrides.videoFitMode,
                                      ),
                                      showValue: false,
                                      onTap: () => _showFitModeSheet(overrides),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 8),
                              _SettingsSliderTile(
                                icon: Icons.replay_10_rounded,
                                title: 'Skip time',
                                value: overrides.seekStepSeconds,
                                min: 5,
                                max: 60,
                                divisions: 11,
                                labelBuilder: (value) =>
                                    '${value.round()} seconds',
                                onChanged: (value) => _updateNativeOverrides(
                                  overrides.copyWith(seekStepSeconds: value),
                                ),
                              ),
                              _SettingsSliderTile(
                                icon: Icons.speed_rounded,
                                title: 'Playback speed',
                                value: overrides.speed,
                                min: 0.5,
                                max: 2.0,
                                divisions: 6,
                                labelBuilder: (value) =>
                                    '${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}x',
                                onChanged: (value) => _updateNativeOverrides(
                                  overrides.copyWith(speed: value),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _SettingsSliderTile(
                                icon: Icons.text_fields_rounded,
                                title: 'Subtitle size',
                                value: overrides.subtitleFontSize,
                                min: 12,
                                max: 28,
                                divisions: 8,
                                labelBuilder: (value) => '${value.round()}',
                                onChanged: (value) => _updateNativeOverrides(
                                  overrides.copyWith(subtitleFontSize: value),
                                ),
                              ),
                              _SettingsSliderTile(
                                icon: Icons.swap_vert_rounded,
                                title: 'Subtitle position',
                                value: overrides.subtitleBottomOffset,
                                min: 18,
                                max: 80,
                                divisions: 31,
                                labelBuilder: (value) => '${value.round()}',
                                onChanged: (value) => _updateNativeOverrides(
                                  overrides.copyWith(
                                    subtitleBottomOffset: value,
                                  ),
                                ),
                              ),
                              _SettingsSliderTile(
                                icon: Icons.timer_outlined,
                                title: 'Subtitle sync',
                                value: overrides.subtitleDelaySeconds,
                                min: -10,
                                max: 10,
                                divisions: 40,
                                labelBuilder: (value) =>
                                    '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}s',
                                onChanged: (value) => _updateNativeOverrides(
                                  overrides.copyWith(
                                    subtitleDelaySeconds: value,
                                  ),
                                ),
                              ),
                              _SettingsSliderTile(
                                icon: Icons.opacity_rounded,
                                title: 'Subtitle background opacity',
                                value: overrides.subtitleBackgroundOpacity,
                                min: 0,
                                max: 1,
                                divisions: 10,
                                labelBuilder: (value) =>
                                    '${(value * 100).round()}%',
                                onChanged: (value) => _updateNativeOverrides(
                                  overrides.copyWith(
                                    subtitleBackgroundOpacity: value,
                                  ),
                                ),
                              ),
                              _SettingsSliderTile(
                                icon: Icons.rounded_corner_rounded,
                                title: 'Subtitle background radius',
                                value: overrides.subtitleBackgroundRadius >= 999
                                    ? 32
                                    : overrides.subtitleBackgroundRadius,
                                min: 0,
                                max: 32,
                                divisions: 8,
                                labelBuilder: (value) =>
                                    value >= 32 ? 'Pill' : '${value.round()}',
                                onChanged: (value) => _updateNativeOverrides(
                                  overrides.copyWith(
                                    subtitleBackgroundRadius: value >= 32
                                        ? 999
                                        : value,
                                  ),
                                ),
                              ),
                              _SettingsColorTile(
                                icon: Icons.format_color_text_rounded,
                                title: 'Subtitle text color',
                                selectedColor: Color(
                                  overrides.subtitleTextColor,
                                ),
                                colors: const [
                                  Colors.white,
                                  Color(0xFFFFF59D),
                                  Color(0xFFB3E5FC),
                                  Color(0xFFFFCCBC),
                                ],
                                onSelected: (value) => _updateNativeOverrides(
                                  overrides.copyWith(
                                    subtitleTextColor: value.value,
                                  ),
                                ),
                              ),
                              _SettingsColorTile(
                                icon: Icons.format_color_fill_rounded,
                                title: 'Subtitle background color',
                                selectedColor: Color(
                                  overrides.subtitleBackgroundColor,
                                ),
                                colors: const [
                                  Colors.black,
                                  Color(0xFF1C1C1C),
                                  Color(0xFF311B92),
                                  Color(0xFF0D47A1),
                                ],
                                onSelected: (value) => _updateNativeOverrides(
                                  overrides.copyWith(
                                    subtitleBackgroundColor: value.value,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SettingsCard(
                      child: Column(
                        children: [
                          _SettingsValueTile(
                            icon: Icons.play_circle_outline_rounded,
                            title: 'Start behavior',
                            value: _startBehaviorLabel(behavior.startBehavior),
                            onTap: () => _showStartBehaviorSheet(behavior),
                          ),
                          _SettingsValueTile(
                            icon: Icons.sync_rounded,
                            title: 'Retry style',
                            value: _retryStyleLabel(behavior.retryStyle),
                            onTap: () => _showRetryStyleSheet(behavior),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            secondary: const Icon(Icons.route_rounded),
                            title: const Text('Prefer last working playback'),
                            subtitle: const Text(
                              'Auto can reuse the last option that played well for this title.',
                            ),
                            value: behavior.preferLastWorkingSource,
                            onChanged: (value) => _updatePlayerBehavior(
                              behavior.copyWith(preferLastWorkingSource: value),
                            ),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            secondary: const Icon(Icons.swap_horiz_rounded),
                            title: const Text('Auto-switch on stall'),
                            subtitle: const Text(
                              'Try the next playback option if video gets stuck.',
                            ),
                            value: behavior.autoSwitchOnStall,
                            onChanged: (value) => _updatePlayerBehavior(
                              behavior.copyWith(autoSwitchOnStall: value),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SettingsCard(
                      child: Column(
                        children: [
                          const _StaticSettingsValueTile(
                            icon: Icons.translate_rounded,
                            title: 'Language defaults',
                            value:
                                'These are preferences. The native player still shows what the current stream actually supports.',
                          ),
                          const Divider(height: 1),
                          _SettingsValueTile(
                            icon: Icons.closed_caption_outlined,
                            title: 'Subtitle mode',
                            value: _subtitleAutoLabel(
                              behavior.subtitleAutoSelect,
                            ),
                            onTap: () => _showSubtitleAutoSheet(behavior),
                          ),
                          _SettingsValueTile(
                            icon: Icons.language_rounded,
                            title: 'Preferred subtitles',
                            value: _subtitleLanguageLabel(
                              behavior.subtitleLanguage,
                            ),
                            onTap: () => _showSubtitleLanguageSheet(behavior),
                          ),
                          _SettingsValueTile(
                            icon: Icons.record_voice_over_rounded,
                            title: 'Preferred audio',
                            value: _audioLanguageLabel(
                              behavior.preferredAudioLanguage,
                            ),
                            onTap: () => _showAudioLanguageSheet(behavior),
                          ),
                          const _StaticSettingsValueTile(
                            icon: Icons.info_outline_rounded,
                            title: 'Audio support',
                            value:
                                'Audio language can be preferred now. True in-stream audio track switching depends on stream and engine support.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SettingsCard(
                      child: Column(
                        children: [
                          _SettingsSliderTile(
                            icon: Icons.timer_rounded,
                            title: 'Controls timeout',
                            value: behavior.controlsTimeoutSeconds.toDouble(),
                            min: 2,
                            max: 10,
                            divisions: 8,
                            labelBuilder: (value) => '${value.round()} seconds',
                            onChanged: (value) => _updatePlayerBehavior(
                              behavior.copyWith(
                                controlsTimeoutSeconds: value.round(),
                              ),
                            ),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            secondary: const Icon(Icons.skip_next_rounded),
                            title: const Text('Autoplay next episode'),
                            value: behavior.autoplayNextEpisode,
                            onChanged: (value) => _updatePlayerBehavior(
                              behavior.copyWith(autoplayNextEpisode: value),
                            ),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            secondary: const Icon(
                              Icons.picture_in_picture_alt_rounded,
                            ),
                            title: const Text('Picture-in-picture'),
                            subtitle: const Text(
                              'Let Android keep playback floating when you leave the app.',
                            ),
                            value: behavior.pipOnBackground,
                            onChanged: (value) => _updatePlayerBehavior(
                              behavior.copyWith(pipOnBackground: value),
                            ),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            secondary: const Icon(Icons.logout_rounded),
                            title: const Text('Confirm before leaving'),
                            value: behavior.confirmBeforeLeaving,
                            onChanged: (value) => _updatePlayerBehavior(
                              behavior.copyWith(confirmBeforeLeaving: value),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SettingsCard(
                      child: Column(
                        children: [
                          _ActionTile(
                            icon: Icons.restart_alt_rounded,
                            title: 'Reset overwrite settings',
                            subtitle: 'Restore global native player defaults.',
                            onTap: _resetPlaybackOverrides,
                          ),
                          const Divider(height: 1),
                          _ActionTile(
                            icon: Icons.settings_backup_restore_rounded,
                            title: 'Reset player behavior',
                            subtitle:
                                'Restore retry, subtitle, and control behavior.',
                            onTap: _resetPlayerBehaviorSettings,
                          ),
                          const Divider(height: 1),
                          _ActionTile(
                            icon: Icons.cleaning_services_outlined,
                            title: 'Clear saved player settings',
                            subtitle: 'Remove per-title native player choices.',
                            onTap: _clearSavedNativePlayerSettings,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBatteryDataSettingsContent() {
    return ValueListenableBuilder<BatteryDataSettings>(
      valueListenable: AppState.batteryDataSettings,
      builder: (context, settings, _) {
        return Column(
          children: [
            _SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.battery_saver_rounded),
                    title: const Text('Battery saver playback'),
                    subtitle: const Text(
                      'Prefers Data saver quality, reduces artwork motion, and skips discovery prefetch.',
                    ),
                    value: settings.batterySaverPlayback,
                    onChanged: (value) {
                      DiagnosticLog.add(
                        'settings battery saver playback enabled=$value',
                      );
                      _updateBatteryData(
                        settings.copyWith(batterySaverPlayback: value),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    secondary: const Icon(Icons.wifi_rounded),
                    title: const Text('Wi-Fi only for Advanced P2P'),
                    subtitle: const Text(
                      'Uses Android network state to block P2P startup on mobile data or unknown networks.',
                    ),
                    value: settings.wifiOnlyAdvancedP2p,
                    onChanged: (value) {
                      DiagnosticLog.add(
                        'settings p2p wifi only enabled=$value',
                      );
                      _updateBatteryData(
                        settings.copyWith(wifiOnlyAdvancedP2p: value),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    secondary: const Icon(Icons.pause_circle_outline_rounded),
                    title: const Text('Pause P2P in background'),
                    subtitle: const Text(
                      'Stops Advanced P2P playback when the player leaves the foreground.',
                    ),
                    value: settings.pauseP2pWhenBackgrounded,
                    onChanged: (value) {
                      DiagnosticLog.add(
                        'settings p2p background pause enabled=$value',
                      );
                      _updateBatteryData(
                        settings.copyWith(pauseP2pWhenBackgrounded: value),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    secondary: const Icon(Icons.battery_alert_outlined),
                    title: const Text('Stop P2P on low battery'),
                    subtitle: const Text(
                      'Uses Android battery evidence to block P2P startup below the selected floor unless charging.',
                    ),
                    value: settings.stopP2pOnLowBattery,
                    onChanged: (value) {
                      DiagnosticLog.add(
                        'settings p2p low battery guard enabled=$value',
                      );
                      _updateBatteryData(
                        settings.copyWith(stopP2pOnLowBattery: value),
                      );
                    },
                  ),
                  _OverrideSettingsSection(
                    enabled: settings.stopP2pOnLowBattery,
                    children: [
                      _SettingsSliderTile(
                        icon: Icons.battery_2_bar_rounded,
                        title: 'Battery floor',
                        value: settings.lowBatteryThresholdPercent.toDouble(),
                        min: 10,
                        max: 40,
                        divisions: 6,
                        labelBuilder: (value) => '${value.round()}%',
                        onChanged: (value) => _updateBatteryData(
                          settings.copyWith(
                            lowBatteryThresholdPercent: value.round(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StaticSettingsValueTile(
                    icon: Icons.fact_check_outlined,
                    title: 'What is enforced',
                    value:
                        'Playback quality, discovery prefetch, artwork motion, P2P network bucket, P2P battery floor, and P2P background cleanup are wired to runtime checks.',
                  ),
                  Divider(height: 1),
                  _StaticSettingsValueTile(
                    icon: Icons.privacy_tip_outlined,
                    title: 'What stays private',
                    value:
                        'Network checks store only safe buckets like Wi-Fi, mobile data, offline, or unavailable. No network names, addresses, peers, URLs, tokens, or stream identities are shown.',
                  ),
                  Divider(height: 1),
                  _StaticSettingsValueTile(
                    icon: Icons.shield_outlined,
                    title: 'Still automatic',
                    value:
                        'Screen awake remains tied to active playback, P2P preflight keeps a startup cap, and route close cleanup stops stale playback work.',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAdvanceSettingsContent() {
    return Column(
      children: [
        ValueListenableBuilder<PlayerBehaviorSettings>(
          valueListenable: AppState.playerBehaviorSettings,
          builder: (context, behavior, _) {
            return _SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.tune_rounded),
                    title: const Text('Advanced playback'),
                    subtitle: const Text(
                      'Fine-tune Media3, libVLC, retry timing, and progress behavior.',
                    ),
                    value: behavior.experimentalControlsEnabled,
                    onChanged: (value) =>
                        _setExperimentalControlsEnabled(behavior, value),
                  ),
                  _OverrideSettingsSection(
                    enabled: behavior.experimentalControlsEnabled,
                    children: [
                      const Divider(height: 1),
                      const _ExperimentalWarning(),
                      const _AdvancedPlaybackSectionHeader(
                        icon: Icons.route_rounded,
                        title: 'Native playback baseline',
                        subtitle:
                            'Controls how Juicr waits, retries, and remembers working playback choices.',
                      ),
                      _SettingsSliderTile(
                        icon: Icons.hourglass_bottom_rounded,
                        title: 'Failure read time',
                        value: behavior.failureReadSeconds.toDouble(),
                        min: 2,
                        max: 10,
                        divisions: 8,
                        labelBuilder: (value) => '${value.round()} seconds',
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(failureReadSeconds: value.round()),
                        ),
                      ),
                      _SettingsSliderTile(
                        icon: Icons.route_rounded,
                        title: 'Playback warmup',
                        value: behavior.providerWarmupCount.toDouble(),
                        min: 0,
                        max: 3,
                        divisions: 3,
                        labelBuilder: (value) {
                          final count = value.round();
                          return count == 1 ? '1 option' : '$count options';
                        },
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(providerWarmupCount: value.round()),
                        ),
                      ),
                      _SettingsSliderTile(
                        icon: Icons.network_check_rounded,
                        title: 'Playback timeout',
                        value: behavior.providerResolveTimeoutSeconds
                            .toDouble(),
                        min: 8,
                        max: 30,
                        divisions: 22,
                        labelBuilder: (value) => '${value.round()} seconds',
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(
                            providerResolveTimeoutSeconds: value.round(),
                          ),
                        ),
                      ),
                      _SettingsSliderTile(
                        icon: Icons.memory_rounded,
                        title: 'Auto playback memory',
                        value: _autoProviderMemoryValue(
                          behavior.autoProviderMemory,
                        ),
                        min: 0,
                        max: 2,
                        divisions: 2,
                        labelBuilder: (value) => _autoProviderMemoryLabel(
                          _autoProviderMemoryFromValue(value),
                        ),
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(
                            autoProviderMemory: _autoProviderMemoryFromValue(
                              value,
                            ),
                          ),
                        ),
                      ),
                      const _AdvancedPlaybackSectionHeader(
                        icon: Icons.more_time_rounded,
                        title: 'Progress and resume',
                        subtitle:
                            'Keeps watch progress honest when a stream reports incomplete timing.',
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        secondary: const Icon(Icons.more_time_rounded),
                        title: const Text('Fallback progress clock'),
                        subtitle: const Text(
                          'Save progress from wall time when player metadata is broken.',
                        ),
                        value: behavior.progressFallbackClockEnabled,
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(
                            progressFallbackClockEnabled: value,
                          ),
                        ),
                      ),
                      _SettingsSliderTile(
                        icon: Icons.restore_rounded,
                        title: 'Resume seek retry',
                        value: behavior.resumeSeekRetrySeconds.toDouble(),
                        min: 4,
                        max: 20,
                        divisions: 16,
                        labelBuilder: (value) => '${value.round()} seconds',
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(
                            resumeSeekRetrySeconds: value.round(),
                          ),
                        ),
                      ),
                      _SettingsSliderTile(
                        icon: Icons.visibility_off_rounded,
                        title: 'Black video watchdog',
                        value: behavior.blackVideoWatchdogSeconds.toDouble(),
                        min: 4,
                        max: 20,
                        divisions: 16,
                        labelBuilder: (value) => '${value.round()} seconds',
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(
                            blackVideoWatchdogSeconds: value.round(),
                          ),
                        ),
                      ),
                      const _AdvancedPlaybackSectionHeader(
                        icon: Icons.video_settings_rounded,
                        title: 'libVLC baseline',
                        subtitle:
                            'Startup, HLS relay patience, stall checks, and handoff behavior for the libVLC engine.',
                      ),
                      _SettingsSliderTile(
                        icon: Icons.health_and_safety_outlined,
                        title: 'libVLC startup grace',
                        value: behavior.libVlcWarmupSeconds.toDouble(),
                        min: 4,
                        max: 24,
                        divisions: 20,
                        labelBuilder: (value) => '${value.round()} seconds',
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(libVlcWarmupSeconds: value.round()),
                        ),
                      ),
                      _SettingsSliderTile(
                        icon: Icons.speed_rounded,
                        title: 'Stall watchdog',
                        value: behavior.stallWatchdogSeconds.toDouble(),
                        min: 2,
                        max: 10,
                        divisions: 8,
                        labelBuilder: (value) => '${value.round()} seconds',
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(
                            stallWatchdogSeconds: value.round(),
                          ),
                        ),
                      ),
                      _SettingsSliderTile(
                        icon: Icons.hourglass_empty_rounded,
                        title: 'libVLC handoff pause',
                        value: behavior.libVlcReleaseSettleMs.toDouble(),
                        min: 0,
                        max: 2000,
                        divisions: 8,
                        labelBuilder: (value) => '${value.round()} ms',
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(
                            libVlcReleaseSettleMs: value.round(),
                          ),
                        ),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        secondary: const Icon(Icons.not_interested_rounded),
                        title: const Text('Skip zero-clock source'),
                        subtitle: const Text(
                          'Move to the next option when libVLC opens but never reports playback progress.',
                        ),
                        value: behavior.zeroClockSkipEnabled,
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(zeroClockSkipEnabled: value),
                        ),
                      ),
                      _SettingsSliderTile(
                        icon: Icons.timer_outlined,
                        title: 'libVLC open timeout',
                        value: behavior.libVlcOpenTimeoutSeconds.toDouble(),
                        min: 4,
                        max: 18,
                        divisions: 14,
                        labelBuilder: (value) => '${value.round()} seconds',
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(
                            libVlcOpenTimeoutSeconds: value.round(),
                          ),
                        ),
                      ),
                      _SettingsSliderTile(
                        icon: Icons.slow_motion_video_rounded,
                        title: 'HLS relay visual grace',
                        value: behavior.libVlcContinuousTsVisualGraceSeconds
                            .toDouble(),
                        min: 12,
                        max: 90,
                        divisions: 13,
                        labelBuilder: (value) => '${value.round()} seconds',
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(
                            libVlcContinuousTsVisualGraceSeconds: value.round(),
                          ),
                        ),
                      ),
                      const _AdvancedPlaybackSectionHeader(
                        icon: Icons.smart_display_rounded,
                        title: 'Media3 baseline',
                        subtitle:
                            'Android-native playback surface and open timing for the Media3 engine.',
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        secondary: const Icon(Icons.smart_display_rounded),
                        title: const Text('Native Media3 surface'),
                        subtitle: const Text(
                          'Use Android Media3 directly when the Media3 engine is selected.',
                        ),
                        value: behavior.media3NativeExoEnabled,
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(media3NativeExoEnabled: value),
                        ),
                      ),
                      _SettingsSliderTile(
                        icon: Icons.smart_display_rounded,
                        title: 'Media3 open timeout',
                        value: behavior.exoPlayerOpenTimeoutSeconds.toDouble(),
                        min: 4,
                        max: 18,
                        divisions: 14,
                        labelBuilder: (value) => '${value.round()} seconds',
                        onChanged: (value) => _updatePlayerBehavior(
                          behavior.copyWith(
                            exoPlayerOpenTimeoutSeconds: value.round(),
                          ),
                        ),
                      ),
                      const _ExperimentalInfoTile(
                        icon: Icons.pending_actions_rounded,
                        title: 'Future playback proof',
                        subtitle:
                            'Planning only for now. New engines stay hidden until dependency, license, rollback, and real-device proof are accepted.',
                      ),
                      _ActionTile(
                        icon: Icons.restart_alt_rounded,
                        title: 'Reset advanced controls',
                        subtitle: 'Restore the default timing values.',
                        onTap: () => _resetExperimentalControls(behavior),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<PlayerBehaviorSettings>(
          valueListenable: AppState.playerBehaviorSettings,
          builder: (context, behavior, _) {
            return _buildAdvancedRuntimeControlsCard(behavior);
          },
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<PlayerBehaviorSettings>(
          valueListenable: AppState.playerBehaviorSettings,
          builder: (context, behavior, _) {
            return _buildP2pSourcePrioritiesCard(behavior);
          },
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<PlayerBehaviorSettings>(
          valueListenable: AppState.playerBehaviorSettings,
          builder: (context, behavior, _) {
            return _buildP2pIndexerConnectorsCard(behavior);
          },
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionTile(
                icon: Icons.verified_user_outlined,
                title: 'Clear playback shortcuts',
                subtitle: 'Forget last-working playback options.',
                onTap: _clearVerifiedSourceCache,
              ),
              const Divider(height: 1),
              _ActionTile(
                icon: Icons.route_outlined,
                title: 'Clear add-on route evidence',
                subtitle: 'Remove recent add-on route diagnostics.',
                onTap: _clearAddonRouteEvidence,
              ),
              const Divider(height: 1),
              _ActionTile(
                icon: Icons.health_and_safety_outlined,
                title: 'Clear playback health samples',
                subtitle: 'Remove stale sample-only playback checks.',
                onTap: _clearProviderCheckSamples,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _setAdvancedRuntimeControlsExpanded(
    PlayerBehaviorSettings behavior,
    bool expanded,
  ) async {
    if (!expanded) {
      _updatePlayerBehavior(
        behavior.copyWith(advancedRuntimeControlsExpanded: false),
      );
      return;
    }
    if (!behavior.p2pPlaybackConsentAccepted) {
      final accepted = await _reviewP2pPlaybackConsent(
        behavior,
        expandRuntimeControls: true,
      );
      if (!accepted) return;
      return;
    }
    _updatePlayerBehavior(
      behavior.copyWith(advancedRuntimeControlsExpanded: true),
    );
  }

  Widget _buildAdvancedRuntimeControlsCard(PlayerBehaviorSettings behavior) {
    final p2pBridgeAvailable = P2pLocalStreamBridge.instance.isAvailable;
    final expanded = behavior.advancedRuntimeControlsExpanded;
    return _SettingsCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            secondary: const Icon(Icons.tune_rounded),
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text('Advanced P2P playback')),
                SizedBox(width: 8),
                _SettingsBetaPill(),
              ],
            ),
            subtitle: Text(
              expanded
                  ? p2pBridgeAvailable
                        ? 'Advanced P2P controls are visible. Source health can vary.'
                        : 'Controls are visible, but this build does not include the required playback support.'
                  : 'Hidden by default. Turning this on opens P2P consent first.',
            ),
            value: expanded,
            onChanged: (value) =>
                _setAdvancedRuntimeControlsExpanded(behavior, value),
          ),
          if (!expanded)
            const SizedBox.shrink()
          else ...[
            const Divider(height: 1),
            const _ExperimentalInfoTile(
              icon: Icons.tune_rounded,
                title: 'Advanced P2P playback',
              subtitle:
                  'Use this only for sources you are allowed to access. Source health and bandwidth can vary.',
            ),
            if (!behavior.p2pPlaybackConsentAccepted) ...[
              const Divider(height: 1),
              _ActionTile(
                icon: Icons.hub_outlined,
                title: 'Review P2P consent',
                subtitle:
                    'Read the obligations before enabling Advanced P2P playback.',
                onTap: () {
                  unawaited(_reviewP2pPlaybackConsent(behavior));
                },
              ),
            ],
            const Divider(height: 1),
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              secondary: Icon(
                p2pBridgeAvailable
                    ? Icons.hub_outlined
                    : Icons.lock_outline_rounded,
              ),
              title: const Text('P2P playback'),
              subtitle: Text(
                p2pBridgeAvailable
                    ? 'Allows Juicr to try recognized P2P sources after consent.'
                    : 'Unavailable in this build because required playback support is missing.',
              ),
              value: behavior.p2pPlaybackEnabled,
              onChanged: p2pBridgeAvailable
                  ? (value) {
                      _updatePlayerBehavior(
                        behavior.copyWith(p2pPlaybackEnabled: value),
                      );
                      DiagnosticLog.add(
                        'settings p2p playback ${value ? 'enabled' : 'disabled'} bridgeAvailable=true mode=controlled_beta',
                      );
                    }
                  : null,
            ),
            const Divider(height: 1),
            _ExperimentalInfoTile(
              icon: Icons.router_outlined,
              title: 'Playback support',
              subtitle: p2pBridgeAvailable
                  ? 'Available on this device. Diagnostics can explain stream health and startup readiness.'
                  : 'Not installed in this build. Advanced P2P playback stays unavailable.',
            ),
            if (p2pBridgeAvailable) ...[
              const Divider(height: 1),
              const _ExperimentalInfoTile(
                icon: Icons.lightbulb_outline_rounded,
                title: 'Startup tip',
                subtitle:
                    'If a P2P stream starts slowly, Auto or Data saver quality can help weaker sources begin faster.',
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildP2pSourcePrioritiesCard(PlayerBehaviorSettings behavior) {
    final p2pReady =
        behavior.p2pPlaybackConsentAccepted && behavior.p2pPlaybackEnabled;
    final enabled = p2pReady && behavior.p2pSourcePrioritiesEnabled;
    return _SettingsCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            secondary: Icon(
              p2pReady
                  ? Icons.low_priority_rounded
                  : Icons.lock_outline_rounded,
            ),
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text('Advanced source priorities')),
                SizedBox(width: 8),
                _SettingsBetaPill(),
              ],
            ),
            subtitle: Text(
              p2pReady
                  ? 'Direct and account-backed streams still stay first.'
                  : 'Turn on Advanced P2P playback to tune source choice.',
            ),
            value: enabled,
            onChanged: p2pReady
                ? (value) {
                    _updatePlayerBehavior(
                      behavior.copyWith(p2pSourcePrioritiesEnabled: value),
                    );
                    DiagnosticLog.add(
                      'settings p2p priority ${value ? 'enabled' : 'disabled'}',
                    );
                  }
                : null,
          ),
          if (enabled) ...[
            const Divider(height: 1),
            _ActionTile(
              icon: Icons.swap_vert_rounded,
              title: 'Priority mode',
              subtitle:
                  '${_p2pPriorityModeLabel(behavior.p2pPriorityMode)}: '
                  '${_p2pPriorityModeSubtitle(behavior.p2pPriorityMode)}',
              onTap: () => _showP2pPriorityModeSheet(behavior),
            ),
            const Divider(height: 1),
            _SettingsSliderTile(
              icon: Icons.playlist_add_check_rounded,
              title: 'Results per quality',
              value: behavior.p2pResultsPerQuality.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              labelBuilder: (value) => '${value.round()}',
              onChanged: (value) => _updatePlayerBehavior(
                behavior.copyWith(p2pResultsPerQuality: value.round()),
              ),
            ),
            const Divider(height: 1),
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              secondary: const Icon(Icons.health_and_safety_outlined),
              title: const Text('Avoid risky formats'),
              subtitle: const Text(
                'Prefer safer formats first on this device.',
              ),
              value: behavior.p2pAvoidRiskyFormats,
              onChanged: (value) => _updatePlayerBehavior(
                behavior.copyWith(p2pAvoidRiskyFormats: value),
              ),
            ),
            const Divider(height: 1),
            _ActionTile(
              icon: Icons.sd_storage_outlined,
              title: 'Size limit',
              subtitle: _p2pSizeLimitLabel(behavior.p2pSizeLimitMb),
              onTap: () => _showP2pSizeLimitSheet(behavior),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildP2pIndexerConnectorsCard(PlayerBehaviorSettings behavior) {
    final p2pReady =
        behavior.p2pPlaybackConsentAccepted && behavior.p2pPlaybackEnabled;
    return ValueListenableBuilder<bool>(
      valueListenable: AppState.p2pIndexerConnectorsEnabled,
      builder: (context, connectorsEnabled, _) {
        return ValueListenableBuilder<List<P2pIndexerConnector>>(
          valueListenable: AppState.p2pIndexerConnectors,
          builder: (context, connectors, _) {
            return _SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    secondary: Icon(
                      p2pReady
                          ? Icons.travel_explore_rounded
                          : Icons.lock_outline_rounded,
                    ),
                    title: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: Text('Indexer Connectors')),
                        SizedBox(width: 8),
                        _SettingsBetaPill(),
                      ],
                    ),
                    subtitle: Text(
                      p2pReady
                          ? 'Use your own indexer server for fallback P2P sources.'
                          : 'Turn on Advanced P2P playback to add indexer connectors.',
                    ),
                    value: p2pReady && connectorsEnabled,
                    onChanged: p2pReady
                        ? (value) {
                            AppState.setP2pIndexerConnectorsEnabled(value);
                            DiagnosticLog.add(
                              'settings p2p indexer connectors ${value ? 'enabled' : 'disabled'}',
                            );
                          }
                        : null,
                  ),
                  const Divider(height: 1),
                  const _ExperimentalInfoTile(
                    icon: Icons.travel_explore_rounded,
                    title: 'Use indexer connectors',
                    subtitle:
                        'Normal direct and account-backed playback stays first. Indexers are searched only when playback needs help.',
                  ),
                  if (connectors.isEmpty) ...[
                    const Divider(height: 1),
                    _ActionTile(
                      icon: Icons.add_link_rounded,
                      title: 'Add connector',
                      subtitle: 'Add an indexer server URL and API key.',
                      onTap: p2pReady
                          ? _showAddP2pIndexerConnectorSheet
                          : _showP2pIndexerConnectorsLockedSnack,
                    ),
                  ] else ...[
                    for (final connector in connectors) ...[
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        leading: Icon(
                          connector.enabled
                              ? Icons.hub_outlined
                              : Icons.pause_circle_outline_rounded,
                        ),
                        title: Text(connector.displayLabel),
                        subtitle: Text(
                          '${connector.type.label} · ${connector.lastStatusBucket}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove connector',
                          onPressed: () {
                            AppState.removeP2pIndexerConnector(connector.id);
                            DiagnosticLog.add(
                              'settings p2p indexer connector removed type=${connector.type.wireName}',
                            );
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ),
                    ],
                    const Divider(height: 1),
                    _ActionTile(
                      icon: Icons.add_link_rounded,
                      title: 'Add connector',
                      subtitle: 'Add another indexer server.',
                      onTap: p2pReady
                          ? _showAddP2pIndexerConnectorSheet
                          : _showP2pIndexerConnectorsLockedSnack,
                    ),
                    const Divider(height: 1),
                    _ActionTile(
                      icon: Icons.network_check_rounded,
                      title: 'Test connection',
                      subtitle:
                          'Check configured connectors without exposing URLs or API keys in diagnostics.',
                      onTap: p2pReady
                          ? _testP2pIndexerConnectors
                          : _showP2pIndexerConnectorsLockedSnack,
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddP2pIndexerConnectorSheet() async {
    if (!AppState.p2pIndexerConnectorsAcknowledged.value) {
      final accepted = await _confirmP2pIndexerConnectorAcknowledgement();
      if (accepted != true) return;
      AppState.markP2pIndexerConnectorsAcknowledged();
    }
    if (!mounted) return;
    final labelController = TextEditingController();
    final urlController = TextEditingController();
    final apiKeyController = TextEditingController();
    var type = P2pIndexerConnectorType.prowlarr;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Add connector'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<P2pIndexerConnectorType>(
                      value: type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(
                          value: P2pIndexerConnectorType.prowlarr,
                          child: Text('Prowlarr'),
                        ),
                        DropdownMenuItem(
                          value: P2pIndexerConnectorType.jackett,
                          child: Text('Jackett'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setLocalState(() => type = value);
                      },
                    ),
                    TextField(
                      controller: labelController,
                      decoration: const InputDecoration(
                        labelText: 'Label',
                        hintText: 'Home indexer',
                      ),
                    ),
                    TextField(
                      controller: urlController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Server URL',
                        hintText: 'http://192.168.1.20:9696',
                      ),
                    ),
                    TextField(
                      controller: apiKeyController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'API key'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved != true) return;
    AppState.upsertP2pIndexerConnector(
      P2pIndexerConnector(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: type,
        label: labelController.text,
        baseUrl: urlController.text,
        apiKey: apiKeyController.text,
        enabled: true,
      ),
    );
    AppState.setP2pIndexerConnectorsEnabled(true);
    DiagnosticLog.add(
      'settings p2p indexer connector saved type=${type.wireName}',
    );
    _snack('Connector saved.');
  }

  void _showP2pIndexerConnectorsLockedSnack() {
    _snack('Turn on Advanced P2P playback first.');
  }

  Future<bool?> _confirmP2pIndexerConnectorAcknowledgement() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use your own indexer?'),
        content: const SingleChildScrollView(
          child: Text(
            'Juicr will connect to the server URL you add and store the API key locally.\n\n'
            'Indexer results can include P2P sources. Juicr does not provide or manage connector servers or their indexers.\n\n'
            'Normal direct and account-backed playback stays first. Diagnostics hide URLs, API keys, result links, magnets, and hashes.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
  }

  Future<void> _testP2pIndexerConnectors() async {
    final connectors = AppState.enabledP2pIndexerConnectors();
    if (connectors.isEmpty) {
      _snack('No enabled connectors.');
      return;
    }
    DiagnosticLog.add(
      'settings p2p indexer test requested connectors=${connectors.length} uri=[hidden]',
    );
    _snack('Testing connectors...');
    const client = P2pIndexerConnectorClient();
    var okCount = 0;
    for (final connector in connectors) {
      final status = await client.testConnection(connector);
      if (status == 'ok') okCount += 1;
      AppState.updateP2pIndexerConnector(
        connector.copyWith(
          lastStatusBucket: status,
          lastCheckedAt: DateTime.now().toUtc(),
        ),
      );
    }
    if (!mounted) return;
    _snack(okCount > 0 ? 'Connector reachable.' : 'Connector needs attention.');
  }

  Widget _buildAboutDiagnosticsContent() {
    return Column(
      children: [
        FutureBuilder<Map<String, Object?>>(
          future: _installInfoFuture,
          builder: (context, snapshot) {
            final installInfo = snapshot.data ?? const <String, Object?>{};
            final versionName = _stringValue(installInfo['versionName']);
            final versionCode = _stringValue(installInfo['versionCode']);
            final packageName = _stringValue(installInfo['packageName']);
            final firstInstalled = _formatInstallTimestamp(
              installInfo['firstInstallTime'],
            );
            final lastUpdated = _formatInstallTimestamp(
              installInfo['lastUpdateTime'],
            );
            final versionLabel = [
              if (versionName.isNotEmpty) versionName else 'Unknown',
              if (versionCode.isNotEmpty && versionCode != '0')
                '($versionCode)',
            ].join(' ');
            return _SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _SettingsCardSection(
                    title: 'App',
                    child: SizedBox.shrink(),
                  ),
                  _StaticSettingsValueTile(
                    icon: Icons.movie_filter_outlined,
                    title: 'App name',
                    value: 'Juicr',
                  ),
                  const Divider(height: 1),
                  _StaticSettingsValueTile(
                    icon: Icons.verified_outlined,
                    title: 'App version',
                    value: versionLabel.trim().isEmpty
                        ? 'Unknown'
                        : versionLabel.trim(),
                  ),
                  const Divider(height: 1),
                  _StaticSettingsValueTile(
                    icon: Icons.inventory_2_outlined,
                    title: 'Package name',
                    value: packageName.isEmpty ? 'Unknown' : packageName,
                  ),
                  const Divider(height: 1),
                  _StaticSettingsValueTile(
                    icon: Icons.download_done_outlined,
                    title: 'First installed',
                    value: firstInstalled,
                  ),
                  const Divider(height: 1),
                  _StaticSettingsValueTile(
                    icon: Icons.system_update_alt_outlined,
                    title: 'Last updated',
                    value: lastUpdated,
                  ),
                  const Divider(height: 1),
                  _ActionTile(
                    icon: Icons.copy_all_rounded,
                    title: 'Copy app version',
                    subtitle: 'Copy version and package details for support.',
                    onTap: _copyAppVersion,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    Text(
                      'Diagnostics',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              _StaticSettingsValueTile(
                icon: Icons.badge_outlined,
                title: 'Current session',
                value: DiagnosticLog.sessionId,
              ),
              const Divider(height: 1),
              _StaticSettingsValueTile(
                icon: Icons.restore_rounded,
                title: 'Previous session exit',
                value: DiagnosticLog.previousSessionExit,
              ),
              const Divider(height: 1),
              _StaticSettingsValueTile(
                icon: Icons.android_rounded,
                title: 'Previous Android exit reason',
                value: DiagnosticLog.previousAndroidExitReason,
              ),
              const Divider(height: 1),
              _StaticSettingsValueTile(
                icon: Icons.update_rounded,
                title: 'Install changed before launch',
                value: DiagnosticLog.previousInstallChanged ? 'Yes' : 'No',
              ),
              const Divider(height: 1),
              const _ExperimentalInfoTile(
                icon: Icons.privacy_tip_outlined,
                title:
                    'Recent diagnostics stay on this device until you copy or send a report.',
                subtitle:
                    'Juicr hides stream URLs, manifest URLs, and long secret-looking values before reports leave the app.',
              ),
              const Divider(height: 1),
              _ActionTile(
                icon: Icons.bug_report_outlined,
                title: 'Copy diagnostic report',
                subtitle: 'Copy temporary playback logs for troubleshooting.',
                onTap: _copyDiagnosticReport,
              ),
              const Divider(height: 1),
              _ActionTile(
                icon: Icons.cloud_upload_outlined,
                title: 'Send diagnostic report',
                subtitle: 'Create a private support ticket for this device.',
                onTap: _sendDiagnosticReport,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<bool> _confirmDefaultSourceEnable() async {
    if (AppState.defaultSourceDisclaimerAccepted.value) return true;
    final acknowledgements = <_SourceConsentAcknowledgement>[
      const _SourceConsentAcknowledgement(
        title: 'Juicr does not provide media',
        text:
            'Built-in sources are optional tools for catalog items, subtitles, trailers, and playback lookups.',
      ),
      const _SourceConsentAcknowledgement(
        title: 'Use only allowed content',
        text:
            'You are responsible for subscriptions, permissions, local laws, and what you choose to access.',
      ),
      const _SourceConsentAcknowledgement(
        title: 'No bypassing access controls',
        text:
            'Juicr does not bypass DRM, paywalls, site protections, geoblocks, subscriptions, or other controls.',
      ),
    ];
    final acceptedIndexes = <int>{};
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final allAccepted =
                acceptedIndexes.length == acknowledgements.length;
            void toggleAcknowledgement(int index, bool? value) {
              setDialogState(() {
                if (value == true) {
                  acceptedIndexes.add(index);
                } else {
                  acceptedIndexes.remove(index);
                }
              });
            }

            return AlertDialog(
              title: const Text('Enable built-in sources?'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Before Juicr turns these tools on, check each acknowledgement. This keeps source choices deliberate instead of a quick tap-through.',
                    ),
                    const SizedBox(height: 12),
                    for (
                      var index = 0;
                      index < acknowledgements.length;
                      index++
                    )
                      _SourceConsentAcknowledgementTile(
                        acknowledgement: acknowledgements[index],
                        value: acceptedIndexes.contains(index),
                        onChanged: (value) =>
                            toggleAcknowledgement(index, value),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      allAccepted
                          ? 'Thanks. Built-in sources can be enabled now.'
                          : 'Check every acknowledgement to enable sources.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: allAccepted
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: allAccepted
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: const Text('Enable sources'),
                ),
              ],
            );
          },
        );
      },
    );
    if (accepted == true) {
      AppState.acceptDefaultSourceDisclaimer();
      return true;
    }
    return false;
  }

  Future<bool> _confirmAddOnDisclaimer() async {
    if (AppState.addonDisclaimerAccepted.value) return true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add third-party add-on?'),
        content: const Text(
          'Add-ons are third-party manifests that may provide catalogs, subtitles, streams, or other sources outside Juicr. Juicr does not review, control, or endorse third-party add-ons.\n\n'
          'Catalog/details and subtitle add-ons are kept to one active source at a time so browse results and captions stay predictable. Streams, Live TV, account-backed routes, and P2P can coexist as playback fallback paths.\n\n'
          'Only add sources you trust. Add-ons may contact outside services, and those services may see network information such as your IP address. '
          'Only use add-ons for content you are legally allowed to access in your region.\n\n'
          'You are responsible for any add-on you add, enable, or use. Do not use add-ons to bypass DRM, paywalls, site protections, geoblocks, subscriptions, or other access controls. '
          'Do not use add-ons for torrenting, piracy, or content you do not have permission to access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      AppState.acceptAddonDisclaimer();
      return true;
    }
    return false;
  }

  Future<bool> _confirmExperimentalControlsEnable() async {
    if (AppState.experimentalDisclaimerAccepted.value) return true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable advanced playback?'),
        content: const Text(
          'Advanced playback is meant for power users. It changes native player timing such as failure delays, stall detection, Media3 opening, and libVLC startup behavior.\n\n'
          'Incorrect values can make playback feel slower, skip sources too early, leave the player waiting too long, or make native playback unstable. Only change these settings if you understand what each control does.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enable controls'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      AppState.acceptExperimentalDisclaimer();
      return true;
    }
    return false;
  }

  Future<void> _showCatalogBuilderHelpSheet() async {
    await showJuicrBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _CatalogBuilderHelpSheet(),
    );
  }

  Future<void> _showCreateLocalCatalogDialog() async {
    final result = await showDialog<_LocalCatalogDialogResult>(
      context: context,
      builder: (context) => const _LocalCatalogDialog(),
    );
    if (result == null) return;
    AppState.addLocalCatalog(
      name: result.name,
      description: result.description,
    );
    DiagnosticLog.add('local catalog created itemCount=0');
    _snack('${result.name} catalog created.');
  }

  Future<void> _showEditLocalCatalogDialog(LocalCatalog catalog) async {
    final result = await showDialog<_LocalCatalogDialogResult>(
      context: context,
      builder: (context) => _LocalCatalogDialog(initialCatalog: catalog),
    );
    if (result == null) return;
    AppState.updateLocalCatalogMetadata(
      id: catalog.id,
      name: result.name,
      description: result.description,
    );
    DiagnosticLog.add(
      'local catalog metadata updated itemCount=${AppState.localCatalogItemCount(catalog.id)} '
      'containsMediaRef=false containsPath=false',
    );
    _snack('${result.name} shelf details updated.');
  }

  Future<void> _showCreateLocalCatalogItemDialog(LocalCatalog catalog) async {
    final result = await showDialog<_LocalCatalogItemDialogResult>(
      context: context,
      builder: (context) => _LocalCatalogItemDialog(catalogName: catalog.name),
    );
    if (result == null) return;
    AppState.addLocalCatalogItem(
      catalogId: catalog.id,
      title: result.title,
      description: result.description,
      mediaKind: result.mediaKind,
      tags: result.tags,
      releaseYear: result.releaseYear,
      runtimeSeconds: result.runtimeSeconds,
    );
    DiagnosticLog.add('local catalog item created hasMediaRef=false');
    _snack('${result.title} added to ${catalog.name}.');
  }

  Future<void> _showEditLocalCatalogItemDialog(
    LocalCatalog catalog,
    LocalCatalogItem item,
  ) async {
    final result = await showDialog<_LocalCatalogItemDialogResult>(
      context: context,
      builder: (context) =>
          _LocalCatalogItemDialog(catalogName: catalog.name, initialItem: item),
    );
    if (result == null) return;
    AppState.updateLocalCatalogItemMetadata(
      id: item.id,
      title: result.title,
      description: result.description,
      mediaKind: result.mediaKind,
      tags: result.tags,
      releaseYear: result.releaseYear,
      runtimeSeconds: result.runtimeSeconds,
    );
    DiagnosticLog.add('local catalog item updated hasMediaRef=false');
    _snack('${result.title} updated in ${catalog.name}.');
  }

  Future<void> _showManageLocalCatalogItemsSheet(LocalCatalog catalog) async {
    final items = AppState.localCatalogItemsFor(catalog.id);
    if (items.isEmpty) {
      _snack('${catalog.name} has no local item metadata yet.');
      return;
    }
    await showJuicrBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manage ${catalog.name} items',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose videos through the system picker. Juicr records only relink-needed local references, not files, paths, picker handles, or playback state.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final pickedRefCount = AppState.localPickedAssetRefsFor(
                      item.id,
                    ).length;
                    return _SettingsCard(
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                        title: Text(item.title),
                        subtitle: Text(_localCatalogItemSheetSubtitle(item)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Copy item metadata',
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                _copyLocalCatalogItemMetadataExport(
                                  catalog,
                                  item,
                                );
                              },
                              icon: const Icon(Icons.copy_all_rounded),
                            ),
                            IconButton(
                              tooltip: 'Edit item metadata',
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                _showEditLocalCatalogItemDialog(catalog, item);
                              },
                              icon: const Icon(Icons.edit_note_rounded),
                            ),
                            IconButton(
                              tooltip: 'Choose video with system picker',
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                _chooseLocalCatalogItemVideo(catalog, item);
                              },
                              icon: const Icon(Icons.video_file_rounded),
                            ),
                            if (pickedRefCount > 0)
                              IconButton(
                                tooltip: 'Clear local video reference',
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();
                                  _clearLocalCatalogItemVideoReference(
                                    catalog,
                                    item,
                                    pickedRefCount,
                                  );
                                },
                                icon: const Icon(Icons.link_off_rounded),
                              ),
                            IconButton(
                              tooltip: 'Remove item metadata',
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                _removeLocalCatalogItemMetadata(catalog, item);
                              },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _localCatalogItemSheetSubtitle(LocalCatalogItem item) {
    final pickedRefCount = AppState.localPickedAssetRefsFor(item.id).length;
    final details = [
      item.mediaKind,
      if (item.releaseYear != null) '${item.releaseYear}',
      if (item.runtimeSeconds != null && item.runtimeSeconds! > 0)
        '${(item.runtimeSeconds! / 60).round()} min',
      if (pickedRefCount > 0)
        pickedRefCount == 1
            ? '1 local video reference needs relink; reselect with the system picker, no path saved'
            : '$pickedRefCount local video references need relink; reselect with the system picker, no path saved',
      if (item.tags.isNotEmpty) item.tags.join(', '),
    ].where((value) => value.trim().isNotEmpty).join(' - ');
    return details.isEmpty ? 'Private metadata item' : details;
  }

  Future<void> _chooseLocalCatalogItemVideo(
    LocalCatalog catalog,
    LocalCatalogItem item,
  ) async {
    try {
      final selected =
          await _catalogBuilderPickerChannel.invokeMethod<bool>('openVideo') ??
          false;
      if (!selected) {
        DiagnosticLog.add('local catalog picker cancelled containsPath=false');
        _snack('No video selected for ${item.title}.');
        return;
      }
      AppState.registerLocalPickedAssetRef(
        catalogId: catalog.id,
        itemId: item.id,
        mediaKind: item.mediaKind,
      );
      DiagnosticLog.add(
        'local catalog picker selected pickedAssetRef=true '
        'containsPath=false containsUri=false containsHandle=false',
      );
      _snack('${item.title} now has a relink-needed local video reference.');
    } on PlatformException {
      DiagnosticLog.add('local catalog picker unavailable containsPath=false');
      _snack('System picker is not available on this device.');
    }
  }

  Future<void> _clearLocalCatalogItemVideoReference(
    LocalCatalog catalog,
    LocalCatalogItem item,
    int pickedRefCount,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear local video reference for ${item.title}?'),
        content: const Text(
          'This removes only Juicr\'s relink-needed local video reference. It does not delete media files, file handles, paths, or anything outside Juicr.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear reference'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    AppState.clearLocalPickedAssetRefsForItem(item.id);
    DiagnosticLog.add(
      'local catalog picked reference cleared '
      'pickedAssetRefCount=$pickedRefCount '
      'containsPath=false containsUri=false containsHandle=false',
    );
    _snack('${item.title} local video reference cleared from ${catalog.name}.');
  }

  Future<void> _removeLocalCatalogItemMetadata(
    LocalCatalog catalog,
    LocalCatalogItem item,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${item.title}?'),
        content: const Text(
          'This removes only this local item from Juicr. It does not delete media files, file handles, paths, or anything outside the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove item'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    AppState.removeLocalCatalogItem(item.id);
    DiagnosticLog.add(
      'local catalog item metadata removed hasMediaRef=false containsPath=false',
    );
    _snack('${item.title} removed from ${catalog.name}.');
  }

  Future<void> _copyLocalCatalogMetadataExport(LocalCatalog catalog) async {
    final encoded = AppState.exportLocalCatalogMetadata(catalog);
    await Clipboard.setData(ClipboardData(text: encoded));
    DiagnosticLog.add(
      'local catalog metadata export copied '
      'itemCount=${AppState.localCatalogItemCount(catalog.id)} '
      'containsMediaRef=false containsPath=false',
    );
    _snack('${catalog.name} export copied.');
  }

  Future<void> _copyLocalCatalogItemMetadataExport(
    LocalCatalog catalog,
    LocalCatalogItem item,
  ) async {
    final encoded = AppState.exportLocalCatalogItemMetadata(
      catalog: catalog,
      item: item,
    );
    await Clipboard.setData(ClipboardData(text: encoded));
    DiagnosticLog.add(
      'local catalog item metadata export copied '
      'containsMediaRef=false containsPath=false',
    );
    _snack('${item.title} export copied.');
  }

  Future<void> _importLocalCatalogItemMetadataFromClipboard(
    LocalCatalog catalog,
  ) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _snack('No Catalog Builder item export found on clipboard.');
      return;
    }
    try {
      final result = AppState.importLocalCatalogItemMetadata(
        text,
        catalogId: catalog.id,
      );
      if (result == null) {
        DiagnosticLog.add(
          'local catalog item metadata import rejected reason=invalid_schema',
        );
        _snack('That clipboard text is not a safe item export.');
        return;
      }
      DiagnosticLog.add(
        'local catalog item metadata import accepted '
        'itemCount=${result.itemCount} '
        'containsMediaRef=false containsPath=false',
      );
      _snack('Item details imported into ${result.catalogName}.');
    } catch (_) {
      DiagnosticLog.add(
        'local catalog item metadata import rejected reason=parse_error',
      );
      _snack('That clipboard text is not a safe item export.');
    }
  }

  Future<void> _importLocalCatalogMetadataFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _snack('No Catalog Builder export found on clipboard.');
      return;
    }
    try {
      final result = AppState.importLocalCatalogMetadata(text);
      if (result == null) {
        DiagnosticLog.add(
          'local catalog metadata import rejected reason=invalid_schema',
        );
        _snack('That clipboard text is not a safe Catalog Builder export.');
        return;
      }
      DiagnosticLog.add(
        'local catalog metadata import accepted '
        'itemCount=${result.itemCount} '
        'containsMediaRef=false containsPath=false',
      );
      _snack('${result.catalogName} imported with ${result.itemCount} items.');
    } catch (_) {
      DiagnosticLog.add(
        'local catalog metadata import rejected reason=parse_error',
      );
      _snack('That clipboard text is not a safe Catalog Builder export.');
    }
  }

  Future<void> _clearLocalCatalogItems(LocalCatalog catalog) async {
    final itemCount = AppState.localCatalogItemCount(catalog.id);
    if (itemCount == 0) {
      _snack('${catalog.name} has no local items to clear.');
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear items in ${catalog.name}?'),
        content: Text(
          'This removes $itemCount local items from this shelf. It does not delete media files, file handles, paths, or anything outside Juicr.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear local items'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    AppState.clearLocalCatalogItems(catalog.id);
    DiagnosticLog.add(
      'local catalog item metadata cleared '
      'itemCount=$itemCount containsMediaRef=false containsPath=false',
    );
    _snack('Local items cleared from ${catalog.name}.');
  }

  Future<void> _deleteLocalCatalog(LocalCatalog catalog) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${catalog.name}?'),
        content: const Text(
          'This removes only Juicr\'s local shelf details. It does not delete media files, file handles, paths, or anything outside the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete catalog'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    AppState.removeLocalCatalog(catalog.id);
    DiagnosticLog.add(
      'local catalog removed itemCount=${catalog.itemCount} '
      'containsMediaRef=false containsPath=false containsHandle=false',
    );
    _snack('${catalog.name} removed from Catalog Builder.');
  }

  Future<bool> _confirmP2pPlaybackConsent() async {
    final acknowledgements = List<bool>.filled(5, false);
    var typedPhrase = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canAccept =
                acknowledgements.every((accepted) => accepted) &&
                typedPhrase.trim().toUpperCase() == kP2pHeavyConsentPhrase;
            Widget acknowledgement(int index, String title) {
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: acknowledgements[index],
                onChanged: (value) {
                  setDialogState(() {
                    acknowledgements[index] = value == true;
                  });
                },
                title: Text(title),
              );
            }

            return AlertDialog(
              title: const Text('Heavy P2P consent'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 460,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Advanced P2P playback is a user-controlled mode. Juicr does not provide content or legal permission. Only continue if you understand the risks and will use sources you are allowed to access.',
                      ),
                      const SizedBox(height: 12),
                      acknowledgement(
                        0,
                        'Juicr does not provide, host, promote, or endorse torrent content, trackers, media goods, or legal permission.',
                      ),
                      acknowledgement(
                        1,
                        'I am responsible for the add-ons, sources, and media I choose to use.',
                      ),
                      acknowledgement(
                        2,
                        'P2P can expose my IP address to peers and may be visible to my network provider.',
                      ),
                      acknowledgement(
                        3,
                        'P2P depends on seeders and can use more bandwidth, battery, and storage.',
                      ),
                      acknowledgement(
                        4,
                        P2pLocalStreamBridge.instance.isAvailable
                            ? 'Advanced P2P playback can be enabled on this build, but stream health can still vary.'
                            : 'Playback remains unavailable until Juicr has a build with Advanced P2P support.',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Type I UNDERSTAND',
                          helperText:
                              'Required before this consent can be saved.',
                        ),
                        onChanged: (value) {
                          typedPhrase = value;
                          setDialogState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: canAccept
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  child: const Text('Save P2P consent'),
                ),
              ],
            );
          },
        );
      },
    );
    return accepted == true;
  }

  Future<bool> _reviewP2pPlaybackConsent(
    PlayerBehaviorSettings behavior, {
    bool expandRuntimeControls = false,
  }) async {
    if (!await _confirmP2pPlaybackConsent()) return false;
    DiagnosticLog.add(
      'settings p2p heavy consent accepted version=$kP2pHeavyConsentVersion bridgeAvailable=${P2pLocalStreamBridge.instance.isAvailable}',
    );
    _updatePlayerBehavior(
      behavior.copyWith(
        p2pPlaybackConsentAccepted: true,
        p2pPlaybackConsentVersion: kP2pHeavyConsentVersion,
        p2pPlaybackConsentAcceptedAt: DateTime.now().toUtc().toIso8601String(),
        p2pPlaybackEnabled: P2pLocalStreamBridge.instance.isAvailable,
        advancedRuntimeControlsExpanded:
            expandRuntimeControls || behavior.advancedRuntimeControlsExpanded,
      ),
    );
    _snack(
      P2pLocalStreamBridge.instance.isAvailable
          ? 'P2P consent saved. Advanced P2P playback is enabled.'
          : 'P2P consent saved. Playback needs a build with Advanced P2P support.',
    );
    return true;
  }

  Future<void> _setDefaultCatalogEnabled(bool enabled) async {
    if (enabled && !await _confirmDefaultSourceEnable()) return;
    if (enabled && await _hasActiveAddonLaneConflict(_AddonLane.catalog)) {
      await _showAddonLaneConflictDialog(_AddonLane.catalog);
      return;
    }
    AppState.setDefaultCatalogEnabled(enabled);
  }

  Future<void> _setDefaultProvidersEnabled(bool enabled) async {
    if (enabled && !await _confirmDefaultSourceEnable()) return;
    AppState.setDefaultProvidersEnabled(enabled);
    if (enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleLazyProviderHealthRefresh();
      });
    }
  }

  Future<void> _setDefaultSubtitlesEnabled(bool enabled) async {
    if (enabled && !await _confirmDefaultSourceEnable()) return;
    if (enabled && await _hasActiveAddonLaneConflict(_AddonLane.subtitles)) {
      await _showAddonLaneConflictDialog(_AddonLane.subtitles);
      return;
    }
    AppState.setDefaultSubtitlesEnabled(enabled);
  }

  Future<void> _setDefaultTrailersEnabled(bool enabled) async {
    if (enabled && !await _confirmDefaultSourceEnable()) return;
    AppState.setDefaultTrailersEnabled(enabled);
  }

  Future<void> _setLiveTvDirectoryEnabled(bool enabled) async {
    if (enabled && !await _confirmDefaultSourceEnable()) return;
    if (enabled) {
      AppState.setPublicIptvEnabled(true);
    } else {
      AppState.setPublicIptvEnabled(false);
      AppState.setTvSourcesEnabled(false);
    }
    StreamApi.clearAddonManifestCache();
  }

  Future<void> _openDefaultSourceSettingsSection() async {
    if (!await _confirmDefaultSourceEnable()) return;
    _openSettingsSection(
      title: 'Default',
      child: _buildDefaultSourceSettingsContent(),
      actions: [
        IconButton(
          tooltip: 'Built-in sources guide',
          onPressed: _showDefaultSourceHelpSheet,
          icon: const Icon(Icons.menu_book_outlined),
        ),
      ],
    );
  }

  Widget _buildDefaultSourceSettingsContent() {
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: AppState.defaultCatalogEnabled,
          builder: (context, enabled, _) {
            return SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 4,
              ),
              secondary: const Icon(Icons.grid_view_rounded),
              title: const Text('Built-in catalog'),
              subtitle: const Text(
                'Use optional Juicr catalog results on Home and Discovery.',
              ),
              value: enabled,
              onChanged: (value) => _setDefaultCatalogEnabled(value),
            );
          },
        ),
        const Divider(height: 1),
        ValueListenableBuilder<bool>(
          valueListenable: AppState.defaultSubtitlesEnabled,
          builder: (context, enabled, _) {
            return SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 4,
              ),
              secondary: const Icon(Icons.closed_caption_outlined),
              title: const Text('Built-in subtitles'),
              subtitle: const Text(
                'Look up optional default subtitles in the native player.',
              ),
              value: enabled,
              onChanged: (value) => _setDefaultSubtitlesEnabled(value),
            );
          },
        ),
        const Divider(height: 1),
        ValueListenableBuilder<bool>(
          valueListenable: AppState.defaultTrailersEnabled,
          builder: (context, enabled, _) {
            return SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 4,
              ),
              secondary: const Icon(Icons.movie_filter_outlined),
              title: const Text('Built-in trailers'),
              subtitle: const Text(
                'Show optional external trailer links on details pages.',
              ),
              value: enabled,
              onChanged: (value) => _setDefaultTrailersEnabled(value),
            );
          },
        ),
        const Divider(height: 1),
        ValueListenableBuilder<bool>(
          valueListenable: AppState.tvSourcesEnabled,
          builder: (context, tvEnabled, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: AppState.publicIptvEnabled,
              builder: (context, enabled, __) {
                return SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  secondary: const Icon(Icons.live_tv_rounded),
                  title: const Text('Built-in live TV'),
                  subtitle: const Text(
                    'Show optional public live TV channels. Streams are third-party and may change.',
                  ),
                  value: tvEnabled && enabled,
                  onChanged: _setLiveTvDirectoryEnabled,
                );
              },
            );
          },
        ),
        const Divider(height: 1),
        ValueListenableBuilder<bool>(
          valueListenable: AppState.defaultProvidersEnabled,
          builder: (context, enabled, _) {
            return SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 4,
              ),
              secondary: const Icon(Icons.play_circle_outline_rounded),
              title: const Text('Built-in playback options'),
              subtitle: const Text(
                'Allow optional built-in playback choices after consent.',
              ),
              value: enabled,
              onChanged: (value) => _setDefaultProvidersEnabled(value),
            );
          },
        ),
        const Divider(height: 1),
        ValueListenableBuilder<bool>(
          valueListenable: AppState.defaultProvidersEnabled,
          builder: (context, enabled, _) {
            return _DefaultProviderControls(
              enabled: enabled,
              providers: _nativeProviders,
              sampleLabel: _providerHealthSampleLabel,
              checkingListenable: _checkingProvidersNotifier,
              logsListenable: _providerHealthLogsNotifier,
              summaryListenable: _providerHealthSummaryNotifier,
              onRefresh: _refreshProviderHealth,
              onConfigureSample: _configureProviderHealthSample,
            );
          },
        ),
      ],
    );
  }

  Widget _buildCatalogBuilderContent() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppState.localCatalogs,
        AppState.localCatalogItems,
        AppState.localPickedAssetRefs,
      ]),
      builder: (context, _) {
        final catalogs = AppState.localCatalogs.value;
        final itemCount = AppState.localCatalogItems.value.length;
        final relinkNeededCount = AppState.localPickedAssetRefs.value
            .where((ref) => ref.relinkNeeded)
            .length;
        return Column(
          children: [
            const _CatalogBuilderIntroCard(),
            const SizedBox(height: 12),
            _SettingsCard(
              child: Column(
                children: [
                  _ActionTile(
                    icon: Icons.add_rounded,
                    title: 'Create local catalog',
                    subtitle:
                        'Start a private shelf. File picking comes next, without storage permissions.',
                    onTap: _showCreateLocalCatalogDialog,
                  ),
                  const Divider(height: 1),
                  _ActionTile(
                    icon: Icons.content_paste_go_rounded,
                    title: 'Import shelf details',
                    subtitle:
                        'Paste a Catalog Builder export. No files, paths, or storage permission.',
                    onTap: _importLocalCatalogMetadataFromClipboard,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _CatalogBuilderCountsCard(
              catalogCount: catalogs.length,
              itemCount: itemCount,
              relinkNeededCount: relinkNeededCount,
            ),
            const SizedBox(height: 12),
            if (catalogs.isEmpty)
              const _CatalogBuilderEmptyCard()
            else
              for (final catalog in catalogs) ...[
                _SettingsCard(
                  child: _LocalCatalogTile(
                    catalog: catalog,
                    itemCount: AppState.localCatalogItemCount(catalog.id),
                    relinkNeededPickedRefCount:
                        AppState.localPickedAssetRefsForCatalog(
                          catalog.id,
                        ).where((ref) => ref.relinkNeeded).length,
                    itemPreviews: AppState.localCatalogItemsFor(
                      catalog.id,
                    ).take(2).toList(growable: false),
                    onEditCatalog: () => _showEditLocalCatalogDialog(catalog),
                    onAddItem: () => _showCreateLocalCatalogItemDialog(catalog),
                    onManageItems: () =>
                        _showManageLocalCatalogItemsSheet(catalog),
                    onExport: () => _copyLocalCatalogMetadataExport(catalog),
                    onImportItem: () =>
                        _importLocalCatalogItemMetadataFromClipboard(catalog),
                    onClearItems: () => _clearLocalCatalogItems(catalog),
                    onDelete: () => _deleteLocalCatalog(catalog),
                  ),
                ),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }

  Widget _buildAddOnsSettingsContent() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppState.defaultCatalogEnabled,
        AppState.defaultProvidersEnabled,
        AppState.defaultSubtitlesEnabled,
        AppState.defaultTrailersEnabled,
        AppState.tvSourcesEnabled,
        AppState.publicIptvEnabled,
        AppState.userAddons,
        _addonSelectionModeNotifier,
        _selectedAddonIdsNotifier,
      ]),
      builder: (context, _) {
        final catalogEnabled = AppState.defaultCatalogEnabled.value;
        final providersEnabled = AppState.defaultProvidersEnabled.value;
        final subtitlesEnabled = AppState.defaultSubtitlesEnabled.value;
        final trailersEnabled = AppState.defaultTrailersEnabled.value;
        final tvSourcesEnabled = AppState.tvSourcesEnabled.value;
        final publicIptvEnabled = AppState.publicIptvEnabled.value;
        final addons = AppState.userAddons.value;
        final selecting = _addonSelectionModeNotifier.value;
        final selectedIds = _selectedAddonIdsNotifier.value;

        final enabledDefaults = [
          catalogEnabled,
          providersEnabled,
          subtitlesEnabled,
          trailersEnabled,
          tvSourcesEnabled && publicIptvEnabled,
        ].where((enabled) => enabled).length;
        final defaultStatus = enabledDefaults == 5
            ? _AddonStatus.active
            : enabledDefaults > 0
            ? _AddonStatus.partial
            : _AddonStatus.off;
        final visibleIds = addons.map((addon) => addon.id).toSet();
        final selectedVisibleIds = selectedIds.intersection(visibleIds);
        _pruneAddonCapabilityFutures(addons);

        return Column(
          children: [
            const _AddOnsIntroCard(),
            const SizedBox(height: 12),
            _SettingsCard(
              child: _ActionTile(
                icon: Icons.add_rounded,
                title: 'Add add-on',
                subtitle: 'Name it and paste an add-on manifest URL.',
                onTap: _showAddOnDialog,
              ),
            ),
            if (selecting) ...[
              const SizedBox(height: 12),
              _AddonSelectionToolbar(
                selectedCount: selectedVisibleIds.length,
                totalCount: addons.length,
                onSelectAll: () => _selectAllUserAddons(addons),
                onSelectNone: _clearAddonSelection,
                onInvertSelection: () => _invertAddonSelection(addons),
                onDeleteSelected: _deleteSelectedUserAddOns,
                onCancel: _cancelAddonSelection,
              ),
            ],
            const SizedBox(height: 12),
            _SettingsCard(
              child: _AddonSourceTile(
                name: 'Default',
                subtitle:
                    'Catalog/details and subtitle lanes allow one active source. Playback add-ons can use fallbacks.',
                status: defaultStatus,
                onTap: selecting ? null : _openDefaultSourceSettingsSection,
              ),
            ),
            for (final addon in addons) ...[
              const SizedBox(height: 12),
              FutureBuilder<AddonCapabilities>(
                future: _addonCapabilityFuture(addon),
                builder: (context, capabilitySnapshot) {
                  final capabilities = capabilitySnapshot.data;
                  final capabilityFailed = capabilitySnapshot.hasError;
                  return _SettingsCard(
                    child: _AddonSourceTile(
                      name: addon.name,
                      subtitle: _addonSubtitleForCapabilities(
                        addon,
                        capabilities,
                        failed: capabilityFailed,
                      ),
                      capabilityLabels: _addonCapabilityLabels(
                        capabilities,
                        failed: capabilityFailed,
                      ),
                      compatibilityText: _addonCompatibilityText(
                        capabilities,
                        failed: capabilityFailed,
                      ),
                      compatibilityHint: _addonCompatibilityHint(
                        capabilities,
                        failed: capabilityFailed,
                      ),
                      helperText: _addonHelperText(
                        capabilities,
                        failed: capabilityFailed,
                      ),
                      status: addon.active
                          ? _AddonStatus.active
                          : _AddonStatus.off,
                      selectable: selecting,
                      selected: selectedVisibleIds.contains(addon.id),
                      onSelectedChanged: (value) =>
                          _setAddonSelected(addon.id, value),
                      onLongPress: () => _startAddonSelection(addon),
                      onActiveChanged: selecting
                          ? null
                          : (value) {
                              DiagnosticLog.add(
                                'settings addon ${addon.id} active=$value',
                              );
                              unawaited(
                                _setUserAddonActive(addon, capabilities, value),
                              );
                            },
                      onEdit: selecting
                          ? null
                          : () => _showAddOnDialog(existing: addon),
                      onRemove: selecting
                          ? null
                          : () async {
                              final confirmed = await _confirmAction(
                                title: 'Remove add-on?',
                                message:
                                    'This removes "${addon.name}" from your add-ons list.',
                                confirmLabel: 'Remove',
                              );
                              if (confirmed != true) return;
                              DiagnosticLog.add(
                                'settings addon ${addon.id} removed',
                              );
                              AppState.removeUserAddon(addon.id);
                              _snack('Add-on removed.');
                            },
                    ),
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildPersonalServersSettingsContent() {
    return AnimatedBuilder(
      animation: AppState.personalServerConnections,
      builder: (context, _) {
        final plexConnection = AppState.personalServerConnection(
          PersonalServerType.plex,
        );
        final jellyfinConnection = AppState.personalServerConnection(
          PersonalServerType.jellyfin,
        );
        final embyConnection = AppState.personalServerConnection(
          PersonalServerType.emby,
        );

        return Column(
          children: [
            const _PersonalServersIntroCard(),
            const SizedBox(height: 12),
            _SettingsCard(
              child: Column(
                children: [
                  _AddonSourceTile(
                    name: 'Plex',
                    subtitle: _personalServerSubtitle(
                      plexConnection,
                      fallback:
                          'Connect your Plex library. Catalog sync and playback routing come next.',
                    ),
                    capabilityLabels: const ['Personal library', 'Local only'],
                    compatibilityText: 'Private',
                    compatibilityHint:
                        'Plex stays separate from built-ins and add-ons. Juicr will use your server only after you connect it.',
                    status: plexConnection != null && plexConnection.active
                        ? _AddonStatus.active
                        : _AddonStatus.off,
                    onTap: () =>
                        _showPersonalServerSheet(PersonalServerType.plex),
                  ),
                  const Divider(height: 1),
                  _AddonSourceTile(
                    name: 'Jellyfin',
                    subtitle: _personalServerSubtitle(
                      jellyfinConnection,
                      fallback:
                          'Connect your Jellyfin server. Catalog sync and playback routing come next.',
                    ),
                    capabilityLabels: const ['Personal library', 'Local only'],
                    compatibilityText: 'Private',
                    compatibilityHint:
                        'Jellyfin stays separate from built-ins and add-ons. Juicr will use your server only after you connect it.',
                    status:
                        jellyfinConnection != null && jellyfinConnection.active
                        ? _AddonStatus.active
                        : _AddonStatus.off,
                    onTap: () =>
                        _showPersonalServerSheet(PersonalServerType.jellyfin),
                  ),
                  const Divider(height: 1),
                  _AddonSourceTile(
                    name: 'Emby',
                    subtitle: _personalServerSubtitle(
                      embyConnection,
                      fallback:
                          'Connect your Emby server. Catalog sync and playback routing come next.',
                    ),
                    capabilityLabels: const ['Personal library', 'Local only'],
                    compatibilityText: 'Private',
                    compatibilityHint:
                        'Emby stays separate from built-ins and add-ons. Juicr will use your server only after you connect it.',
                    status: embyConnection != null && embyConnection.active
                        ? _AddonStatus.active
                        : _AddonStatus.off,
                    onTap: () =>
                        _showPersonalServerSheet(PersonalServerType.emby),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildArrangeAddOnsContent() {
    return ValueListenableBuilder<List<UserAddon>>(
      valueListenable: AppState.userAddons,
      builder: (context, addons, _) {
        if (addons.isEmpty) {
          return const _SettingsCard(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('No user add-ons to arrange.'),
            ),
          );
        }
        return _SettingsCard(
          child: ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: addons.length,
            onReorder: AppState.reorderUserAddons,
            itemBuilder: (context, index) {
              final addon = addons[index];
              return ListTile(
                key: ValueKey(addon.id),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                leading: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle_rounded),
                ),
                title: Text(
                  addon.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(_addonSubtitleFallback(addon)),
                trailing: _ActivePill(
                  status: addon.active ? _AddonStatus.active : _AddonStatus.off,
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _openArrangeAddOns() {
    _openSettingsSection(
      title: 'Arrange',
      child: _buildArrangeAddOnsContent(),
      framed: false,
    );
  }

  Future<void> _setUserAddonActive(
    UserAddon addon,
    AddonCapabilities? capabilities,
    bool active,
  ) async {
    try {
      if (active) {
        if (capabilities == null) _forgetAddonCapability(addon);
        final checkedCapabilities =
            capabilities ?? await _addonCapabilityFuture(addon);
        final conflictLane = await _firstAddonActivationConflict(
          addon,
          checkedCapabilities,
        );
        if (conflictLane != null) {
          await _showAddonLaneConflictDialog(conflictLane);
          _snack('Add-on left off.');
          return;
        }
      }
      AppState.updateUserAddon(addon.copyWith(active: active));
    } catch (error) {
      _forgetAddonCapability(addon);
      DiagnosticLog.add(
        'settings addon ${addon.id} active failed error=$error',
      );
      _snack('Could not check this add-on yet. Please try again.');
    }
  }

  Future<_AddonLane?> _firstAddonActivationConflict(
    UserAddon addon,
    AddonCapabilities capabilities,
  ) async {
    for (final lane in _exclusiveAddonLanesForCapabilities(capabilities)) {
      if (_defaultLaneEnabled(lane)) return lane;
      if (await _hasActiveAddonLaneConflict(lane, exceptAddonId: addon.id)) {
        return lane;
      }
    }
    return null;
  }

  Future<bool> _hasActiveAddonLaneConflict(
    _AddonLane lane, {
    String? exceptAddonId,
  }) async {
    final activeAddons = AppState.userAddons.value.where(
      (addon) => addon.active && addon.id != exceptAddonId,
    );
    for (final addon in activeAddons) {
      try {
        final capabilities = await _api.addonCapabilities(addon);
        if (_exclusiveAddonLanesForCapabilities(capabilities).contains(lane)) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  bool _defaultLaneEnabled(_AddonLane lane) {
    return switch (lane) {
      _AddonLane.catalog => AppState.defaultCatalogEnabled.value,
      _AddonLane.subtitles => AppState.defaultSubtitlesEnabled.value,
    };
  }

  Set<_AddonLane> _exclusiveAddonLanesForCapabilities(
    AddonCapabilities capabilities,
  ) {
    final lanes = <_AddonLane>{};
    if (!_catalogDetailsSubtitleSingleActiveByPolicy()) return lanes;
    final streamFallbackCanCoexist =
        capabilities.usesPlaybackFallbackLane &&
        _streamResourcesCanCoexistByPolicy();
    final usesCatalogDetailsLane =
        !streamFallbackCanCoexist &&
        !capabilities.supportsOnlyLiveTvCatalogs &&
        (capabilities.supportsCatalogs || capabilities.supportsMeta);
    if (usesCatalogDetailsLane) lanes.add(_AddonLane.catalog);
    if (capabilities.supportsSubtitles) lanes.add(_AddonLane.subtitles);
    return lanes;
  }

  bool _streamResourcesCanCoexistByPolicy() {
    return AppState.runtimeAppPolicy.value?.streamResourcesCanCoexist ?? true;
  }

  bool _catalogDetailsSubtitleSingleActiveByPolicy() {
    return AppState
            .runtimeAppPolicy
            .value
            ?.catalogDetailsSubtitleSingleActive ??
        true;
  }

  Future<void> _showAddonLaneConflictDialog(_AddonLane lane) async {
    if (!mounted) return;
    final label = _addonLaneLabel(lane);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Similar source already active'),
          content: Text(
            'This add-on includes $label, but another $label source is already active. To keep browse results clean, use one $label source at a time.\n\n'
            'Streams, Live TV, account-backed routes, and P2P can still coexist as playback fallback paths. This add-on will stay off until you disable the current $label source.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Keep off'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Review sources'),
            ),
          ],
        );
      },
    );
  }

  String _addonLaneLabel(_AddonLane lane) {
    return switch (lane) {
      _AddonLane.catalog => 'Catalog/details',
      _AddonLane.subtitles => 'Subtitle',
    };
  }

  void _startAddonSelection([UserAddon? initialAddon]) {
    _addonSelectionModeNotifier.value = true;
    if (initialAddon != null) {
      _selectedAddonIdsNotifier.value = {initialAddon.id};
    }
  }

  void _cancelAddonSelection() {
    _addonSelectionModeNotifier.value = false;
    _selectedAddonIdsNotifier.value = const <String>{};
  }

  void _setAddonSelected(String addonId, bool selected) {
    final next = Set<String>.from(_selectedAddonIdsNotifier.value);
    if (selected) {
      next.add(addonId);
    } else {
      next.remove(addonId);
    }
    _selectedAddonIdsNotifier.value = next;
  }

  void _clearAddonSelection() {
    _selectedAddonIdsNotifier.value = const <String>{};
  }

  void _selectAllUserAddons(List<UserAddon> addons) {
    if (addons.isEmpty) {
      _snack('No user add-ons to select.');
      return;
    }
    _selectedAddonIdsNotifier.value = {for (final addon in addons) addon.id};
  }

  void _invertAddonSelection(List<UserAddon> addons) {
    if (addons.isEmpty) {
      _snack('No user add-ons to select.');
      return;
    }
    final current = _selectedAddonIdsNotifier.value;
    _selectedAddonIdsNotifier.value = {
      for (final addon in addons)
        if (!current.contains(addon.id)) addon.id,
    };
  }

  Future<void> _showAddOnsManagerSheet() async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) => const _AddOnsManagerSheet(),
    );
    if (!mounted || selected == null) return;
    if (selected == 'arrange') {
      _openArrangeAddOns();
    } else if (selected == 'select') {
      _startAddonSelection();
    } else if (selected == 'export') {
      await _exportAddOns();
    } else if (selected == 'import') {
      await _showImportAddOnsDialog();
    } else if (selected == 'delete-all') {
      await _deleteAllUserAddOns();
    }
  }

  Future<void> _deleteSelectedUserAddOns() async {
    final visibleIds = AppState.userAddons.value
        .map((addon) => addon.id)
        .toSet();
    final selectedIds = _selectedAddonIdsNotifier.value.intersection(
      visibleIds,
    );
    final count = selectedIds.length;
    if (count == 0) {
      _snack('Select add-ons to delete first.');
      return;
    }
    final confirmed = await _confirmAction(
      title: count == 1 ? 'Delete selected add-on?' : 'Delete $count add-ons?',
      message:
          'This removes the selected manifests you added. Built-in sources are separate and stay exactly as you left them. This cannot be undone.',
      confirmLabel: count == 1 ? 'Delete' : 'Delete $count',
      destructive: true,
    );
    if (confirmed != true) return;
    DiagnosticLog.add('settings addons delete-selected count=$count');
    AppState.removeUserAddons(selectedIds);
    _cancelAddonSelection();
    _snack(count == 1 ? 'Deleted 1 add-on.' : 'Deleted $count add-ons.');
  }

  Future<void> _deleteAllUserAddOns() async {
    final count = AppState.userAddons.value.length;
    if (count == 0) {
      _snack('No user add-ons to delete.');
      return;
    }
    final confirmed = await _confirmAction(
      title: 'Delete all add-ons?',
      message:
          'This removes all $count manifests you added. Built-in sources are separate and stay exactly as you left them. This cannot be undone.',
      confirmLabel: 'Delete all',
      destructive: true,
    );
    if (confirmed != true) return;
    DiagnosticLog.add('settings addons clear-all count=$count');
    AppState.clearUserAddons();
    _snack('Deleted $count add-ons.');
  }

  Future<void> _exportAddOns() async {
    final addons = AppState.userAddons.value;
    if (addons.isEmpty) {
      _snack('No user add-ons to export.');
      return;
    }
    final accepted = await _confirmAddOnExport();
    if (accepted != true) return;

    final encoded = const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'addons': [
        for (final addon in addons)
          {
            'name': addon.name,
            'manifestUrl': addon.manifestUrl,
            'active': addon.active,
          },
      ],
    });
    await Clipboard.setData(ClipboardData(text: encoded));
    _snack('Add-ons export copied.');
  }

  Future<bool?> _confirmAddOnExport() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export add-ons?'),
        content: const Text(
          'Exported add-ons may include private configuration or account tokens in manifest URLs. Only share this export with people you trust.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Copy export'),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportAddOnsDialog() async {
    final confirmed = await _confirmAction(
      title: 'Import add-ons?',
      message:
          'Only import add-ons from exports you trust. Imports may include private configuration or account tokens in manifest URLs. Imported add-ons will be added to your current list, and existing add-ons with the same manifest URL will be skipped.',
      confirmLabel: 'Continue',
    );
    if (confirmed != true) return;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const _ImportAddOnsDialog(),
    );
    if (result == null || result.trim().isEmpty) return;
    final outcome = _importAddOnsFromText(result);
    _snack(outcome.message);
  }

  _ImportAddOnsOutcome _importAddOnsFromText(String text) {
    try {
      final decoded = jsonDecode(text);
      final rawAddons = decoded is List
          ? decoded
          : decoded is Map<String, dynamic>
          ? decoded['addons']
          : null;
      if (rawAddons is! List) {
        return const _ImportAddOnsOutcome(
          imported: 0,
          skipped: 0,
          reason: _ImportAddOnsReason.noAddons,
        );
      }
      var imported = 0;
      var skipped = 0;
      final existingUrls = AppState.userAddons.value
          .map((addon) => addon.manifestUrl.trim().toLowerCase())
          .toSet();
      for (final raw in rawAddons.whereType<Map<String, dynamic>>()) {
        final name = (raw['name'] ?? 'Imported add-on').toString().trim();
        final manifestUrl = (raw['manifestUrl'] ?? '').toString().trim();
        final uri = Uri.tryParse(manifestUrl);
        final key = manifestUrl.toLowerCase();
        if (name.isEmpty ||
            uri == null ||
            !uri.hasScheme ||
            uri.host.isEmpty ||
            existingUrls.contains(key)) {
          skipped += 1;
          continue;
        }
        AppState.addUserAddon(
          name: name,
          manifestUrl: manifestUrl,
          active: raw.containsKey('active') ? raw['active'] == true : true,
        );
        existingUrls.add(key);
        imported += 1;
      }
      return _ImportAddOnsOutcome(
        imported: imported,
        skipped: skipped,
        reason: imported > 0
            ? _ImportAddOnsReason.ok
            : _ImportAddOnsReason.noneImported,
      );
    } catch (_) {
      return const _ImportAddOnsOutcome(
        imported: 0,
        skipped: 0,
        reason: _ImportAddOnsReason.invalidJson,
      );
    }
  }

  String _addonSubtitleFallback(UserAddon addon) {
    final hint = '${addon.name} ${addon.manifestUrl}'.toLowerCase();
    if (hint.contains('subtitles') ||
        hint.contains('subtitle') ||
        hint.contains('opensubtitles')) {
      return 'Subtitle add-on';
    }
    if (hint.contains('trailer') ||
        hint.contains('trailers') ||
        hint.contains('strailer') ||
        hint.contains('youtube')) {
      return 'Trailer add-on';
    }
    if (hint.contains('nsfw') ||
        hint.contains('adult') ||
        hint.contains('xxx')) {
      return 'NSFW add-on';
    }
    if (hint.contains('music') || hint.contains('audio')) return 'Music add-on';
    if (hint.contains('torrent') ||
        hint.contains('magnet') ||
        hint.contains('stream')) {
      return 'Stream add-on';
    }
    if (hint.contains('tv')) return 'Live TV add-on';
    if (hint.contains('catalog')) return 'Catalog add-on';
    return 'User add-on';
  }

  String _addonSubtitleForCapabilities(
    UserAddon addon,
    AddonCapabilities? capabilities, {
    bool failed = false,
  }) {
    if (failed) return _addonSubtitleFallback(addon);
    if (capabilities == null) return _addonSubtitleFallback(addon);
    if (capabilities.capabilityBundleLabels.isNotEmpty) {
      return capabilities.capabilitySummary;
    }
    if (capabilities.supportsSubtitles) return 'Subtitle add-on';
    if (capabilities.supportsTrailers) return 'Trailer add-on';
    if (capabilities.supportsCatalogType(MediaType.nsfw)) return 'NSFW add-on';
    if (capabilities.supportsCatalogType(MediaType.music))
      return 'Music add-on';
    if (capabilities.supportsCatalogType(MediaType.liveTv))
      return 'Live TV add-on';
    if (capabilities.resources.contains('stream')) return 'Stream add-on';
    if (capabilities.supportsCatalogType(MediaType.movie) ||
        capabilities.supportsCatalogType(MediaType.series) ||
        capabilities.supportsCatalogType(MediaType.animation)) {
      return 'Catalog add-on';
    }
    return _addonSubtitleFallback(addon);
  }

  List<String> _addonCapabilityLabels(
    AddonCapabilities? capabilities, {
    bool failed = false,
  }) {
    if (failed) return const <String>['Needs Check'];
    if (capabilities == null) return const <String>['Checking'];
    final labels = <String>[];
    if (capabilities.supportsCatalogs) labels.add('Catalogs');
    if (capabilities.supportsCatalogType(MediaType.movie)) labels.add('Movies');
    if (capabilities.supportsCatalogType(MediaType.series))
      labels.add('Series');
    if (capabilities.supportsCatalogType(MediaType.animation))
      labels.add('Animation');
    if (capabilities.supportsCatalogType(MediaType.liveTv)) labels.add('TV');
    if (capabilities.supportsCatalogType(MediaType.music)) labels.add('Music');
    if (capabilities.supportsCatalogType(MediaType.nsfw)) labels.add('Adult');
    if (capabilities.supportsStreams) labels.add('Streams');
    if (capabilities.supportsMeta) labels.add('Details');
    if (capabilities.supportsSubtitles) labels.add('Subtitles');
    if (capabilities.supportsTrailers) labels.add('Trailers');
    if (labels.isEmpty) return const <String>['Needs Check'];
    return labels.take(8).toList(growable: false);
  }

  String? _addonHelperText(
    AddonCapabilities? capabilities, {
    bool failed = false,
  }) {
    if (failed) {
      return 'Juicr could not read this add-on yet. Check the add-on address or account setup, then try again.';
    }
    if (capabilities == null) {
      return 'Juicr is reading this manifest to understand what it can do.';
    }
    if (capabilities.isMixedCapabilityBundle &&
        capabilities.usesPlaybackFallbackLane) {
      return 'This add-on can stay active with the built-in catalog as a playback fallback. It advertises ${capabilities.capabilitySummary}, but stream playback stays separate from browse sources.';
    }
    if (capabilities.isMixedCapabilityBundle && capabilities.looksTorrentLike) {
      return P2pLocalStreamBridge.instance.isAvailable
          ? 'This add-on offers ${capabilities.capabilitySummary}. Catalog/details and subtitles should use one active add-on at a time; playback fallbacks stay separate.'
          : 'This add-on offers ${capabilities.capabilitySummary}. Catalogs or subtitles can help browsing, but P2P playback needs a build with Advanced P2P support.';
    }
    if (capabilities.isMixedCapabilityBundle) {
      return 'This add-on offers ${capabilities.capabilitySummary}. Catalog/details and subtitles use one active add-on at a time; streams can still fall back safely.';
    }
    if (capabilities.looksTorrentLike) {
      return P2pLocalStreamBridge.instance.isAvailable
          ? 'P2P streams are recognized. Advanced P2P playback is beta and needs consent plus the playback switch.'
          : 'P2P streams are recognized, but playback needs a build with Advanced P2P support. Direct or account-backed links can play now.';
    }
    if (capabilities.looksTorrentOrDebrid) {
      return capabilities.looksAccountBased
          ? 'This may need account setup before it can return direct streams. Advanced P2P options stay in Advanced P2P playback once proven.'
          : 'This may be an account-backed or P2P add-on. Juicr can play it when it returns direct stream links.';
    }
    if (capabilities.supportsSubtitles &&
        !capabilities.resources.contains('stream') &&
        !capabilities.supportsCatalogType(MediaType.movie) &&
        !capabilities.supportsCatalogType(MediaType.series)) {
      return 'Looks like a subtitle add-on. Keep one subtitle source active at a time so captions stay predictable.';
    }
    if (capabilities.supportsCatalogType(MediaType.liveTv)) {
      return 'Looks like a TV add-on. Live TV stays separate from movie and series playback.';
    }
    if (capabilities.resources.contains('meta') &&
        !capabilities.resources.contains('stream')) {
      return 'Looks like a catalog/details add-on. It may improve browsing, but playback needs a stream source.';
    }
    if (capabilities.supportsStreams) {
      return 'Looks like a stream add-on. Streams can stay active with other playback sources because fallbacks are safe.';
    }
    return null;
  }

  String _addonCompatibilityText(
    AddonCapabilities? capabilities, {
    bool failed = false,
  }) {
    if (failed) return 'Needs check';
    if (capabilities == null) return 'Checking compatibility';
    if (capabilities.looksDebridLike ||
        (capabilities.looksAccountBased && capabilities.supportsStreams)) {
      return 'Direct links if configured';
    }
    if (capabilities.looksTorrentLike) {
      return P2pLocalStreamBridge.instance.isAvailable
          ? 'P2P beta'
          : 'P2P locked';
    }
    if (capabilities.looksAccountBased) return 'Needs account setup';
    if (capabilities.looksTorrentOrDebrid) return 'Direct links if configured';
    if (capabilities.supportsStreams) return 'Stream add-on';
    if (capabilities.supportsSubtitles &&
        !capabilities.supportsCatalogType(MediaType.movie) &&
        !capabilities.supportsCatalogType(MediaType.series) &&
        !capabilities.supportsCatalogType(MediaType.animation)) {
      return 'Captions only';
    }
    if (capabilities.supportsMeta ||
        capabilities.supportsCatalogType(MediaType.movie) ||
        capabilities.supportsCatalogType(MediaType.series) ||
        capabilities.supportsCatalogType(MediaType.animation) ||
        capabilities.supportsCatalogType(MediaType.liveTv)) {
      return 'Browse only';
    }
    return 'Needs check';
  }

  String _addonCompatibilityHint(
    AddonCapabilities? capabilities, {
    bool failed = false,
  }) {
    if (failed) {
      return 'Juicr could not read the add-on manifest. Activation will retry the check and stay off if the add-on is unavailable.';
    }
    if (capabilities == null) {
      return 'Juicr is reading the manifest before making a compatibility call.';
    }
    if (capabilities.looksDebridLike ||
        (capabilities.looksAccountBased && capabilities.supportsStreams)) {
      return 'Configure it if needed; Juicr can play returned direct links. Stream playback stays separate from built-in browsing.';
    }
    if (capabilities.looksTorrentLike) {
      return P2pLocalStreamBridge.instance.isAvailable
          ? 'Advanced P2P is beta. It stays behind consent, the playback switch, and source-health checks.'
          : 'P2P needs a build with Advanced P2P support. Direct or account-backed links can play now.';
    }
    if (capabilities.looksAccountBased) {
      return 'The add-on may need account setup. Advanced P2P options stay in Advanced P2P playback once proven.';
    }
    if (capabilities.looksTorrentOrDebrid) {
      return 'Configure it if needed; Juicr can play returned direct links. P2P-only routes stay in Advanced P2P playback.';
    }
    if (capabilities.supportsStreams) {
      return 'This manifest advertises streams. Playback tests decide which route type is actually returned.';
    }
    if (capabilities.supportsSubtitles &&
        !capabilities.supportsCatalogType(MediaType.movie) &&
        !capabilities.supportsCatalogType(MediaType.series) &&
        !capabilities.supportsCatalogType(MediaType.animation)) {
      return 'This can help captions, but it is not a playback source.';
    }
    if (capabilities.supportsMeta ||
        capabilities.supportsCatalogType(MediaType.movie) ||
        capabilities.supportsCatalogType(MediaType.series) ||
        capabilities.supportsCatalogType(MediaType.animation) ||
        capabilities.supportsCatalogType(MediaType.liveTv)) {
      return 'Good for browsing/details; playback still needs stream routes.';
    }
    return 'Juicr cannot classify this manifest confidently yet.';
  }

  @override
  Widget build(BuildContext context) {
    final compactLandscape = JuicrVisual.compactLandscape(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: JuicrVisual.topLevelTitleSpacingFor(context),
        toolbarHeight: JuicrVisual.topLevelToolbarHeightFor(context),
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: AccountActionButton(),
          ),
        ],
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: AppState.preferencesReady,
        builder: (context, preferencesReady, _) {
          if (!preferencesReady) return const AppSettingsSkeleton();
          return ListView(
            padding: JuicrVisual.topLevelListPaddingFor(
              context,
              bottom: compactLandscape ? 16 : 24,
            ),
            children: [
              AppReveal(
                delay: const Duration(milliseconds: 80),
                child: _SettingsHomeTile(
                  icon: Icons.settings_rounded,
                  title: 'General',
                  subtitle: 'Theme, layout, and app appearance',
                  onTap: (tileContext) => _openSettingsSection(
                    title: 'General',
                    child: _buildGeneralSettingsContent(),
                    framed: false,
                    sourceContext: tileContext,
                    actions: [
                      IconButton(
                        tooltip: 'General guide',
                        onPressed: _showGeneralHelpSheet,
                        icon: const Icon(Icons.menu_book_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: compactLandscape ? 8 : 12),
              AppReveal(
                delay: const Duration(milliseconds: 110),
                child: _SettingsHomeTile(
                  icon: Icons.smart_display_rounded,
                  title: 'Playback',
                  subtitle: 'Player, language, and subtitle defaults',
                  onTap: (tileContext) => _openSettingsSection(
                    title: 'Playback',
                    child: _buildPlaybackSettingsContent(),
                    framed: false,
                    sourceContext: tileContext,
                    actions: [
                      IconButton(
                        tooltip: 'Playback guide',
                        onPressed: _showPlaybackHelpSheet,
                        icon: const Icon(Icons.menu_book_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: compactLandscape ? 8 : 12),
              AppReveal(
                delay: const Duration(milliseconds: 145),
                child: _SettingsHomeTile(
                  icon: Icons.battery_charging_full_rounded,
                  title: 'Battery & data',
                  subtitle: 'Saver mode, P2P limits, and playback safeguards',
                  onTap: (tileContext) => _openSettingsSection(
                    title: 'Battery & data',
                    child: _buildBatteryDataSettingsContent(),
                    framed: false,
                    sourceContext: tileContext,
                    actions: [
                      IconButton(
                        tooltip: 'Battery & data guide',
                        onPressed: _showBatteryDataHelpSheet,
                        icon: const Icon(Icons.menu_book_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: compactLandscape ? 8 : 12),
              AppReveal(
                delay: const Duration(milliseconds: 215),
                child: _SettingsHomeTile(
                  icon: Icons.extension_rounded,
                  title: 'Add-ons',
                  subtitle: 'Catalog, subtitle, stream, and TV sources',
                  onTap: (tileContext) => _openAddOnsSection(),
                ),
              ),
              SizedBox(height: compactLandscape ? 8 : 12),
              AppReveal(
                delay: const Duration(milliseconds: 250),
                child: _SettingsHomeTile(
                  icon: Icons.dns_rounded,
                  title: 'Personal servers',
                  subtitle: 'Personal media servers and your own library',
                  badgeLabel: 'Beta',
                  badgeHint:
                      'Personal servers are functional, but still being validated against real home server setups.',
                  onTap: (tileContext) => _openPersonalServersSection(),
                ),
              ),
              SizedBox(height: compactLandscape ? 8 : 12),
              AppReveal(
                delay: const Duration(milliseconds: 285),
                child: _SettingsHomeTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Advanced',
                  subtitle: 'Runtime controls and playback cleanup',
                  onTap: (tileContext) => _openSettingsSection(
                    title: 'Advanced',
                    child: _buildAdvanceSettingsContent(),
                    framed: false,
                    sourceContext: tileContext,
                    actions: [
                      IconButton(
                        tooltip: 'Advanced guide',
                        onPressed: _showAdvanceHelpSheet,
                        icon: const Icon(Icons.menu_book_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: compactLandscape ? 8 : 12),
              AppReveal(
                delay: const Duration(milliseconds: 320),
                child: _SettingsHomeTile(
                  icon: Icons.info_outline_rounded,
                  title: 'About & diagnostics',
                  subtitle: 'App version and diagnostic reports',
                  onTap: (tileContext) => _openSettingsSection(
                    title: 'About & diagnostics',
                    child: _buildAboutDiagnosticsContent(),
                    framed: false,
                    sourceContext: tileContext,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatInstallTimestamp(Object? rawValue) {
    final millis = _intValue(rawValue);
    if (millis <= 0) return 'Unknown';
    final value = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    final month = _monthName(value.month);
    final hour = value.hour == 0 || value.hour == 12 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$month ${value.day}, ${value.year} $hour:$minute $period';
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _stringValue(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text;
  }

  String _monthName(int month) {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (month < 1 || month > months.length) return 'Unknown';
    return months[month - 1];
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: JuicrVisual.flatCardColor(colorScheme),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JuicrVisual.cardRadius),
        side: BorderSide(color: JuicrVisual.flatCardBorder(colorScheme)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _AddonDialogResult {
  const _AddonDialogResult({
    required this.name,
    required this.manifestUrl,
    required this.active,
  });

  final String name;
  final String manifestUrl;
  final bool active;
}

class _PersonalServerEditorResult {
  const _PersonalServerEditorResult({
    this.serverUrl = '',
    this.username = '',
    this.token = '',
    this.password = '',
    this.userId = '',
    this.active = true,
    this.remove = false,
  });

  final String serverUrl;
  final String username;
  final String token;
  final String password;
  final String userId;
  final bool active;
  final bool remove;
}

class _LocalCatalogDialogResult {
  const _LocalCatalogDialogResult({
    required this.name,
    required this.description,
  });

  final String name;
  final String description;
}

class _LocalCatalogItemDialogResult {
  const _LocalCatalogItemDialogResult({
    required this.title,
    required this.description,
    required this.mediaKind,
    required this.tags,
    required this.releaseYear,
    required this.runtimeSeconds,
  });

  final String title;
  final String description;
  final String mediaKind;
  final List<String> tags;
  final int? releaseYear;
  final int? runtimeSeconds;
}

class _LocalCatalogDialog extends StatefulWidget {
  const _LocalCatalogDialog({this.initialCatalog});

  final LocalCatalog? initialCatalog;

  @override
  State<_LocalCatalogDialog> createState() => _LocalCatalogDialogState();
}

class _LocalCatalogDialogState extends State<_LocalCatalogDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  bool get _isEditing => widget.initialCatalog != null;

  @override
  void initState() {
    super.initState();
    final catalog = widget.initialCatalog;
    if (catalog != null) {
      _nameController.text = catalog.name;
      _descriptionController.text = catalog.description;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      _LocalCatalogDialogResult(
        name: name,
        description: _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit local catalog' : 'Create local catalog'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing
                  ? 'This only updates shelf metadata inside Juicr. It does not touch files, picker handles, paths, or playback state.'
                  : 'This only creates the private shelf. Juicr will add media later through the system picker, without asking for broad storage access.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Catalog name',
                hintText: 'Batman night',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Optional note for this shelf',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _nameController.text.trim().isEmpty ? null : _submit,
          child: Text(_isEditing ? 'Save shelf' : 'Create catalog'),
        ),
      ],
    );
  }
}

class _LocalCatalogItemDialog extends StatefulWidget {
  const _LocalCatalogItemDialog({required this.catalogName, this.initialItem});

  final String catalogName;
  final LocalCatalogItem? initialItem;

  @override
  State<_LocalCatalogItemDialog> createState() =>
      _LocalCatalogItemDialogState();
}

class _LocalCatalogItemDialogState extends State<_LocalCatalogItemDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _releaseYearController = TextEditingController();
  final TextEditingController _runtimeMinutesController =
      TextEditingController();
  String _mediaKind = 'movie';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialItem;
    if (initial == null) return;
    _titleController.text = initial.title;
    _descriptionController.text = initial.description;
    _tagsController.text = initial.tags.join(', ');
    final initialKind = initial.mediaKind.trim().isEmpty
        ? 'movie'
        : initial.mediaKind.trim();
    _mediaKind =
        const <String>{
          'movie',
          'episode',
          'clip',
          'other',
        }.contains(initialKind)
        ? initialKind
        : 'other';
    if (initial.releaseYear != null) {
      _releaseYearController.text = '${initial.releaseYear}';
    }
    final runtimeSeconds = initial.runtimeSeconds;
    if (runtimeSeconds != null && runtimeSeconds > 0) {
      _runtimeMinutesController.text = '${(runtimeSeconds / 60).round()}';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _releaseYearController.dispose();
    _runtimeMinutesController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final releaseYear = int.tryParse(_releaseYearController.text.trim());
    final runtimeMinutes = int.tryParse(_runtimeMinutesController.text.trim());
    Navigator.of(context).pop(
      _LocalCatalogItemDialogResult(
        title: title,
        description: _descriptionController.text.trim(),
        mediaKind: _mediaKind,
        tags: _tagsController.text
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList(growable: false),
        releaseYear: releaseYear != null && releaseYear > 0
            ? releaseYear
            : null,
        runtimeSeconds: runtimeMinutes != null && runtimeMinutes > 0
            ? runtimeMinutes * 60
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialItem != null;
    return AlertDialog(
      title: Text(
        isEditing
            ? 'Edit item in ${widget.catalogName}'
            : 'Add item to ${widget.catalogName}',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This saves private item details. After saving, use Manage local items to choose a video through the system picker.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _titleController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'The Dark Knight',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _mediaKind,
                decoration: const InputDecoration(labelText: 'Kind'),
                items: const [
                  DropdownMenuItem(value: 'movie', child: Text('Movie')),
                  DropdownMenuItem(value: 'episode', child: Text('Episode')),
                  DropdownMenuItem(value: 'clip', child: Text('Clip')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _mediaKind = value);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tagsController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: 'Action, Batman, Favorites',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _releaseYearController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Release year',
                  hintText: 'Optional year, metadata only',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _runtimeMinutesController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Runtime',
                  hintText: 'Optional minutes, metadata only',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Optional note for this local item',
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _titleController.text.trim().isEmpty ? null : _submit,
          child: Text(isEditing ? 'Save item' : 'Add item'),
        ),
      ],
    );
  }
}

enum _AddonStatus { active, partial, off }

enum _AddonLane { catalog, subtitles }

class _CatalogBuilderIntroCard extends StatelessWidget {
  const _CatalogBuilderIntroCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: JuicrVisual.elevatedIconDecoration(
                colorScheme,
                radius: 14,
                color: colorScheme.primary.withValues(alpha: 0.14),
                shadowAlpha: 0.1,
              ),
              child: Icon(
                Icons.video_library_rounded,
                color: colorScheme.primary,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Build private shelves',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Catalog Builder is local-only. Juicr will use the system picker for files you choose, not broad storage permissions, device scanning, or uploads.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.66),
                      fontWeight: FontWeight.w600,
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

class _CatalogBuilderEmptyCard extends StatelessWidget {
  const _CatalogBuilderEmptyCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.folder_open_rounded,
              color: colorScheme.onSurface.withValues(alpha: 0.46),
            ),
            const SizedBox(height: 10),
            Text(
              'No local catalogs yet',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Create a shelf now. Adding picked media files, posters, and Details-style editing comes after this safe local foundation is proven.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.62),
                height: 1.28,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogBuilderCountsCard extends StatelessWidget {
  const _CatalogBuilderCountsCard({
    required this.catalogCount,
    required this.itemCount,
    required this.relinkNeededCount,
  });

  final int catalogCount;
  final int itemCount;
  final int relinkNeededCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: JuicrVisual.elevatedIconDecoration(
                colorScheme,
                radius: 14,
                color: colorScheme.secondaryContainer.withValues(alpha: 0.32),
                shadowAlpha: 0.06,
              ),
              child: Icon(
                Icons.analytics_outlined,
                color: colorScheme.secondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Local catalog overview',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$catalogCount shelves - $itemCount metadata items - '
                    '$relinkNeededCount references need relink',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.66),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Counts only. No files, paths, URIs, or picker handles are shown.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.58),
                      height: 1.25,
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

class _LocalCatalogTile extends StatelessWidget {
  const _LocalCatalogTile({
    required this.catalog,
    required this.itemCount,
    required this.relinkNeededPickedRefCount,
    required this.itemPreviews,
    required this.onEditCatalog,
    required this.onAddItem,
    required this.onManageItems,
    required this.onExport,
    required this.onImportItem,
    required this.onClearItems,
    required this.onDelete,
  });

  final LocalCatalog catalog;
  final int itemCount;
  final int relinkNeededPickedRefCount;
  final List<LocalCatalogItem> itemPreviews;
  final VoidCallback onEditCatalog;
  final VoidCallback onAddItem;
  final VoidCallback onManageItems;
  final VoidCallback onExport;
  final VoidCallback onImportItem;
  final VoidCallback onClearItems;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final itemPreviewText = itemPreviews.isEmpty
        ? '$itemCount local items.'
        : [
            itemPreviews.map(_cleanItemPreviewLabel).join(' / '),
            if (itemCount > itemPreviews.length)
              '+${itemCount - itemPreviews.length} more',
          ].join(' ');
    final relinkSummary = _relinkNeededPickedRefSummary();
    final subtitle = catalog.description.trim().isEmpty
        ? [
            'Private local shelf.',
            itemPreviewText,
            if (relinkSummary != null) relinkSummary,
          ].join(' ')
        : [
            catalog.description.trim(),
            itemPreviewText,
            if (relinkSummary != null) relinkSummary,
          ].join('\n');
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      leading: Container(
        width: 42,
        height: 42,
        decoration: JuicrVisual.elevatedIconDecoration(
          colorScheme,
          radius: 14,
          color: colorScheme.primary.withValues(alpha: 0.12),
          shadowAlpha: 0.08,
        ),
        child: Icon(
          Icons.video_collection_rounded,
          color: colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(catalog.name),
      subtitle: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<String>(
        tooltip: 'Catalog actions',
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (value) {
          switch (value) {
            case 'edit':
              onEditCatalog();
            case 'add':
              onAddItem();
            case 'manage':
              if (itemCount > 0) onManageItems();
            case 'export':
              onExport();
            case 'importItem':
              onImportItem();
            case 'clear':
              if (itemCount > 0) onClearItems();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit shelf details')),
          const PopupMenuItem(value: 'add', child: Text('Add local item')),
          PopupMenuItem(
            value: 'manage',
            enabled: itemCount > 0,
            child: const Text('Manage local items'),
          ),
          const PopupMenuItem(
            value: 'export',
            child: Text('Copy shelf export'),
          ),
          const PopupMenuItem(
            value: 'importItem',
            child: Text('Import item details'),
          ),
          PopupMenuItem(
            value: 'clear',
            enabled: itemCount > 0,
            child: const Text('Clear local items'),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Delete local catalog'),
          ),
        ],
      ),
    );
  }

  String _cleanItemPreviewLabel(LocalCatalogItem item) {
    final runtime = _formatRuntimeLabel(item.runtimeSeconds);
    final details = [
      if (item.releaseYear != null) '${item.releaseYear}',
      if (runtime != null) runtime,
    ];
    if (details.isEmpty) return item.title;
    return '${item.title} (${details.join(' / ')})';
  }

  String _itemPreviewLabel(LocalCatalogItem item) {
    return _cleanItemPreviewLabel(item);
  }

  String? _relinkNeededPickedRefSummary() {
    if (relinkNeededPickedRefCount <= 0) return null;
    return relinkNeededPickedRefCount == 1
        ? '1 local video reference needs relink.'
        : '$relinkNeededPickedRefCount local video references need relink.';
  }

  /*
    // Legacy body kept below only as inert source context for older guards.
    final runtime = _formatRuntimeLabel(item.runtimeSeconds);
    final details = [
      if (item.releaseYear != null) '${item.releaseYear}',
      if (runtime != null) runtime,
    ];
    if (details.isEmpty) return item.title;
    return '${item.title} (${details.join(' • ')})';
  }

  */

  String? _formatRuntimeLabel(int? runtimeSeconds) {
    if (runtimeSeconds == null || runtimeSeconds <= 0) return null;
    final minutes = (runtimeSeconds / 60).round();
    if (minutes <= 0) return null;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remainder = minutes.remainder(60);
    if (remainder == 0) return '${hours}h';
    return '${hours}h ${remainder}m';
  }
}

class _AddOnsIntroCard extends StatelessWidget {
  const _AddOnsIntroCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: JuicrVisual.elevatedIconDecoration(
                colorScheme,
                radius: 14,
                color: colorScheme.primary.withValues(alpha: 0.14),
                shadowAlpha: 0.1,
              ),
              child: Icon(
                Icons.extension_rounded,
                color: colorScheme.primary,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose what Juicr can see',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Catalog/details and subtitle add-ons use one active source at a time. Streams, Live TV, account-backed routes, and P2P can use separate fallback paths.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.66),
                      fontWeight: FontWeight.w600,
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

class _PersonalServersIntroCard extends StatelessWidget {
  const _PersonalServersIntroCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: JuicrVisual.elevatedIconDecoration(
                colorScheme,
                radius: 14,
                color: colorScheme.primary.withValues(alpha: 0.14),
                shadowAlpha: 0.1,
              ),
              child: Icon(
                Icons.dns_rounded,
                color: colorScheme.primary,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bring your own library',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Connect a server you control. Juicr keeps personal media servers separate from built-ins and add-ons, and uses them only after you save one here.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.66),
                      fontWeight: FontWeight.w600,
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

enum _ImportAddOnsReason { ok, invalidJson, noAddons, noneImported }

class _ImportAddOnsOutcome {
  const _ImportAddOnsOutcome({
    required this.imported,
    required this.skipped,
    required this.reason,
  });

  final int imported;
  final int skipped;
  final _ImportAddOnsReason reason;

  String get message {
    return switch (reason) {
      _ImportAddOnsReason.invalidJson =>
        'Import failed. Paste a valid Juicr add-ons JSON export.',
      _ImportAddOnsReason.noAddons =>
        'Import found no add-ons. Paste a Juicr export with an addons list.',
      _ImportAddOnsReason.noneImported when skipped > 0 =>
        'No new add-ons imported. Skipped $skipped duplicate or invalid entries.',
      _ImportAddOnsReason.noneImported => 'No new add-ons imported.',
      _ => 'Imported $imported add-ons. Skipped $skipped.',
    };
  }
}

class _ExternalPlayerApp {
  const _ExternalPlayerApp({
    required this.packageName,
    required this.activityName,
    required this.label,
  });

  final String packageName;
  final String activityName;
  final String label;
}

class _ExternalPlayersSection extends StatefulWidget {
  const _ExternalPlayersSection({
    required this.selectedPackage,
    required this.loadPlayers,
    required this.onSelected,
  });

  final String? selectedPackage;
  final Future<List<_ExternalPlayerApp>> Function() loadPlayers;
  final ValueChanged<_ExternalPlayerApp> onSelected;

  @override
  State<_ExternalPlayersSection> createState() =>
      _ExternalPlayersSectionState();
}

class _ExternalPlayersSectionState extends State<_ExternalPlayersSection> {
  List<_ExternalPlayerApp> _players = const <_ExternalPlayerApp>[];
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadPlayers();
  }

  @override
  void didUpdateWidget(covariant _ExternalPlayersSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPackage != widget.selectedPackage) {
      _ensureSelectedPlayer();
    }
  }

  Future<void> _loadPlayers() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    final players = await widget.loadPlayers();
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _players = players;
      _loading = false;
    });
    _ensureSelectedPlayer();
  }

  void _refresh() {
    _loadPlayers();
  }

  void _ensureSelectedPlayer() {
    if (_players.isEmpty) return;
    final selectedPackage = widget.selectedPackage;
    final hasSelected =
        selectedPackage != null &&
        _players.any((player) => player.packageName == selectedPackage);
    if (hasSelected) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _players.isEmpty) return;
      final currentPackage = widget.selectedPackage;
      final stillMissing =
          currentPackage == null ||
          !_players.any((player) => player.packageName == currentPackage);
      if (!stillMissing) return;
      widget.onSelected(_players.first);
    });
  }

  @override
  Widget build(BuildContext context) {
    final players = _players;
    if (players.isEmpty) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: JuicrVisual.iconBadge(
          context,
          icon: Icons.open_in_new_rounded,
          boxSize: 38,
          iconSize: 18,
          radius: 14,
          shadowAlpha: 0.12,
        ),
        title: const Text('External player'),
        subtitle: Text(
          _loading
              ? 'Checking installed players...'
              : 'No compatible player apps were found.',
        ),
        trailing: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _refresh,
              ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 4,
          ),
          leading: JuicrVisual.iconBadge(
            context,
            icon: Icons.open_in_new_rounded,
            boxSize: 38,
            iconSize: 18,
            radius: 14,
            shadowAlpha: 0.12,
          ),
          title: const Text('External player'),
          subtitle: Text('${players.length} app(s) can receive video links'),
          trailing: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _refresh,
                ),
        ),
        const Divider(height: 1),
        for (var index = 0; index < players.length; index++) ...[
          RadioListTile<String>(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            secondary: const Icon(Icons.play_arrow_rounded),
            title: Text(players[index].label),
            subtitle: Text(
              players[index].packageName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            value: players[index].packageName,
            groupValue: widget.selectedPackage,
            onChanged: (_) => widget.onSelected(players[index]),
          ),
          if (index != players.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }
}

class _AddOnsManagerSheet extends StatelessWidget {
  const _AddOnsManagerSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          18,
          12,
          18,
          JuicrVisual.bottomSheetBottomBreathingRoom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Manage add-ons',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            JuicrSheetOptionTile(
              icon: Icons.swap_vert_rounded,
              label: 'Arrange add-ons',
              subtitle: 'Choose which trusted manifest Juicr tries first.',
              onTap: () => Navigator.of(context).pop('arrange'),
            ),
            JuicrSheetOptionTile(
              icon: Icons.checklist_rounded,
              label: 'Select add-ons',
              subtitle: 'Choose one or more user add-ons to delete.',
              onTap: () => Navigator.of(context).pop('select'),
            ),
            JuicrSheetOptionTile(
              icon: Icons.upload_file_rounded,
              label: 'Export add-ons',
              subtitle: 'Copy your user add-ons as JSON.',
              onTap: () => Navigator.of(context).pop('export'),
            ),
            JuicrSheetOptionTile(
              icon: Icons.download_rounded,
              label: 'Import add-ons',
              subtitle: 'Paste a Juicr add-ons export.',
              onTap: () => Navigator.of(context).pop('import'),
            ),
            JuicrSheetOptionTile(
              icon: Icons.delete_sweep_outlined,
              label: 'Delete all user add-ons',
              subtitle: 'Keep Default, remove added manifests.',
              trailing: Icon(
                Icons.warning_amber_rounded,
                color: colorScheme.error.withValues(alpha: 0.82),
              ),
              onTap: () => Navigator.of(context).pop('delete-all'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportAddOnsDialog extends StatefulWidget {
  const _ImportAddOnsDialog();

  @override
  State<_ImportAddOnsDialog> createState() => _ImportAddOnsDialogState();
}

class _ImportAddOnsDialogState extends State<_ImportAddOnsDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import add-ons'),
      content: TextField(
        controller: _controller,
        minLines: 6,
        maxLines: 10,
        decoration: const InputDecoration(
          labelText: 'Export JSON',
          alignLabelWithHint: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Import'),
        ),
      ],
    );
  }
}

class _DefaultProviderControls extends StatelessWidget {
  const _DefaultProviderControls({
    required this.enabled,
    required this.providers,
    required this.sampleLabel,
    required this.checkingListenable,
    required this.logsListenable,
    required this.summaryListenable,
    required this.onRefresh,
    required this.onConfigureSample,
  });

  final bool enabled;
  final List<ApiProvider> providers;
  final String sampleLabel;
  final ValueListenable<bool> checkingListenable;
  final ValueListenable<List<String>> logsListenable;
  final ValueListenable<_ProviderHealthSummaryResult?> summaryListenable;
  final Future<void> Function({bool silent}) onRefresh;
  final VoidCallback onConfigureSample;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Turn on built-in playback options to configure them.',
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        ValueListenableBuilder<String>(
          valueListenable: AppState.nativeProviderId,
          builder: (context, selectedId, _) {
            final choices = [
              _SettingsPageState._autoNativeProvider,
              ...providers,
            ];
            final selected = choices.firstWhere(
              (provider) => provider.id == selectedId,
              orElse: () => _SettingsPageState._autoNativeProvider,
            );
            if (selected.id != selectedId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                AppState.nativeProviderId.value = selected.id;
              });
            }

            return _ProviderSelector(
              title: 'Default playback option',
              icon: Icons.play_circle_outline_rounded,
              providers: choices,
              selected: selected,
              showNativeHealth: true,
              checking: false,
              onChanged: (provider) {
                DiagnosticLog.add(
                  'settings native provider selected ${provider.id}',
                );
                AppState.nativeProviderId.value = provider.id;
              },
            );
          },
        ),
        const Divider(height: 1),
        ValueListenableBuilder<bool>(
          valueListenable: checkingListenable,
          builder: (context, checking, _) {
            return _ProviderHealthRefreshTile(
              checking: checking,
              sampleLabel: sampleLabel,
              onTap: () => onRefresh(),
              onConfigureSample: onConfigureSample,
            );
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: checkingListenable,
          builder: (context, checking, _) {
            if (checking) {
              return ValueListenableBuilder<List<String>>(
                valueListenable: logsListenable,
                builder: (context, logs, _) => Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: _ProviderHealthCheckingCard(logs: logs),
                ),
              );
            }
            return ValueListenableBuilder<_ProviderHealthSummaryResult?>(
              valueListenable: summaryListenable,
              builder: (context, summary, _) {
                if (summary == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: _ProviderHealthSummaryCard(summary: summary),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _AddonSelectionToolbar extends StatelessWidget {
  const _AddonSelectionToolbar({
    required this.selectedCount,
    required this.totalCount,
    required this.onSelectAll,
    required this.onSelectNone,
    required this.onInvertSelection,
    required this.onDeleteSelected,
    required this.onCancel,
  });

  final int selectedCount;
  final int totalCount;
  final VoidCallback onSelectAll;
  final VoidCallback onSelectNone;
  final VoidCallback onInvertSelection;
  final VoidCallback onDeleteSelected;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final allSelected = totalCount > 0 && selectedCount == totalCount;
    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedCount == 0
                    ? 'Select add-ons'
                    : '$selectedCount of $totalCount selected',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            TextButton(
              onPressed: totalCount == 0 ? null : onInvertSelection,
              child: const Text('Invert'),
            ),
            TextButton(
              onPressed: totalCount == 0
                  ? null
                  : allSelected
                  ? onSelectNone
                  : onSelectAll,
              child: Text(allSelected ? 'None' : 'All'),
            ),
            IconButton(
              tooltip: 'Delete selected',
              onPressed: selectedCount == 0 ? null : onDeleteSelected,
              icon: Icon(
                Icons.delete_outline_rounded,
                color: selectedCount == 0 ? null : colorScheme.error,
              ),
            ),
            IconButton(
              tooltip: 'Cancel selection',
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderHealthSampleConfig {
  const _ProviderHealthSampleConfig({required this.id});

  final String id;
}

class _ProviderHealthSampleSheet extends StatefulWidget {
  const _ProviderHealthSampleSheet({required this.initialId});

  final String initialId;

  @override
  State<_ProviderHealthSampleSheet> createState() =>
      _ProviderHealthSampleSheetState();
}

class _ProviderHealthSampleSheetState
    extends State<_ProviderHealthSampleSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialId,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            18,
            12,
            18,
            JuicrVisual.bottomSheetBottomBreathingRoom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Sample title', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Leave the ID empty and Juicr will choose a fresh title, with a safe fallback if services are busy.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'TMDB numeric ID',
                  hintText: 'Optional. Empty = automatic sample',
                  helperText:
                      'IMDb tt IDs are different. Juicr checks this title safely.',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _ProviderHealthSampleConfig(
                          id: _controller.text.trim(),
                        ),
                      );
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderHealthSummaryResult {
  const _ProviderHealthSummaryResult({
    required this.total,
    required this.ready,
    required this.noSource,
    required this.noSample,
    required this.issue,
    required this.untested,
    this.sampleReadyCount,
    this.sampleLabel,
    this.sourceClassSummary,
    this.historical = false,
    this.blocked = false,
    this.failed = false,
  });

  final int total;
  final int ready;
  final int noSource;
  final int noSample;
  final int issue;
  final int untested;
  final int? sampleReadyCount;
  final String? sampleLabel;
  final String? sourceClassSummary;
  final bool historical;
  final bool blocked;
  final bool failed;

  String get title {
    if (blocked) return 'Playback check paused';
    if (failed) return 'Playback check failed';
    if (total <= 0) return 'Playback check finished';
    if (!historical && sampleLabel != null) {
      if (ready <= 0) return 'No routes ready';
      return '$ready/$total routes ready';
    }
    return '$ready/$total ready';
  }

  String get message {
    if (blocked) {
      final base = historical
          ? 'Playback check paused. Juicr is protecting playback services right now.'
          : 'Juicr paused this check to protect playback services.';
      return '$base Previous statuses unchanged.';
    }
    if (failed) return 'The scan could not finish. Try again later.';
    final parts = <String>[];
    if (ready > 0) parts.add('$ready ready');
    if (noSource > 0) parts.add('$noSource unavailable');
    if (noSample > 0) parts.add('$noSample not checked');
    if (issue > 0) parts.add('$issue needs attention');
    if (sampleReadyCount == 0 && parts.isEmpty) {
      return 'No playback option was ready during this check.';
    }
    if (untested > 0 && parts.isEmpty) {
      return '$untested playback option statuses are not checked yet.';
    }
    if (untested > 0) parts.add('$untested unchanged');
    if (parts.isEmpty) return 'No playback options are ready yet.';
    final status = parts.join(', ');
    if (historical) return '$status. Previous statuses unchanged.';
    final sourceMix = sourceClassSummary;
    final suffix = sourceMix == null ? '' : ' $sourceMix';
    return '$status. Checked built-in playback options safely.$suffix';
  }
}

class _ProviderHealthSummaryCard extends StatelessWidget {
  const _ProviderHealthSummaryCard({required this.summary});

  final _ProviderHealthSummaryResult summary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = summary.failed
        ? colorScheme.error
        : summary.blocked
        ? const Color(0xFFFFB84D)
        : summary.ready > 0
        ? const Color(0xFF36D98B)
        : colorScheme.onSurface.withValues(alpha: 0.58);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: JuicrVisual.softPanel(colorScheme, alpha: 0.34),
      child: Row(
        children: [
          Icon(
            summary.failed
                ? Icons.error_outline_rounded
                : summary.blocked
                ? Icons.schedule_rounded
                : Icons.check_circle_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  summary.message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.62),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderHealthCheckingCard extends StatefulWidget {
  const _ProviderHealthCheckingCard({required this.logs});

  final List<String> logs;

  @override
  State<_ProviderHealthCheckingCard> createState() =>
      _ProviderHealthCheckingCardState();
}

class _ProviderHealthCheckingCardState
    extends State<_ProviderHealthCheckingCard> {
  Timer? _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      if (!mounted) return;
      setState(() {
        _tick += 1;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final logs = widget.logs.isEmpty
        ? const ['Preparing built-in playback routes']
        : widget.logs;
    final visibleLogs = logs.length > 6 ? logs.sublist(logs.length - 6) : logs;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: JuicrVisual.softPanel(colorScheme, alpha: 0.34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Checking availability',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Text(
              'Testing built-in playback routes. This can take a moment.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.62),
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.56),
              borderRadius: BorderRadius.circular(10),
              boxShadow: JuicrVisual.softShadow(
                colorScheme,
                alpha: 0.07,
                blur: 12,
                y: 4,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < visibleLogs.length; index++)
                  _ProviderHealthLogLine(
                    label: visibleLogs[index],
                    active: index == visibleLogs.length - 1,
                    pulse: _tick.isEven,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderHealthLogLine extends StatelessWidget {
  const _ProviderHealthLogLine({
    required this.label,
    required this.active,
    required this.pulse,
  });

  final String label;
  final bool active;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: active
          ? colorScheme.onSurface.withValues(alpha: 0.88)
          : colorScheme.onSurface.withValues(alpha: 0.58),
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.35,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          SizedBox(
            width: 10,
            child: Text(
              active ? '>' : '-',
              style: style?.copyWith(
                color: active
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.44),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            active ? (pulse ? 'running' : 'checking') : 'done',
            style: style?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.48),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddonEditorDialog extends StatefulWidget {
  const _AddonEditorDialog({this.existing});

  final UserAddon? existing;

  @override
  State<_AddonEditorDialog> createState() => _AddonEditorDialogState();
}

class _AddonEditorDialogState extends State<_AddonEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late bool _active;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _urlController = TextEditingController(
      text: widget.existing?.manifestUrl ?? '',
    );
    _active = widget.existing?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    final uri = Uri.tryParse(url);
    if (name.isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() => _error = 'Enter a name and valid manifest URL.');
      return;
    }
    Navigator.of(
      context,
    ).pop(_AddonDialogResult(name: name, manifestUrl: url, active: _active));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Edit add-on' : 'Add add-on'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _AddonEditorNotice(),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Add-on name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Manifest URL',
                hintText: 'https://example.com/manifest.json',
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _AddonEditorNotice extends StatelessWidget {
  const _AddonEditorNotice();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: JuicrVisual.elevatedCardDecoration(
        colorScheme,
        radius: 14,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderAlpha: 0,
        shadowAlpha: 0.04,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Only add manifests you trust. Juicr does not review, host, or provide add-on sources.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.68),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalServerEditorSheet extends StatefulWidget {
  const _PersonalServerEditorSheet({required this.type, this.existing});

  final PersonalServerType type;
  final PersonalServerConnection? existing;

  @override
  State<_PersonalServerEditorSheet> createState() =>
      _PersonalServerEditorSheetState();
}

class _PersonalServerEditorSheetState
    extends State<_PersonalServerEditorSheet> {
  late final TextEditingController _serverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _tokenController;
  late final TextEditingController _passwordController;
  late bool _active;
  bool _obscureSecret = true;
  bool _saving = false;
  String? _error;

  bool get _isPlex => widget.type == PersonalServerType.plex;
  bool get _usesUsernamePassword => !_isPlex;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _serverController = TextEditingController(text: existing?.serverUrl ?? '');
    _usernameController = TextEditingController(text: existing?.username ?? '');
    _tokenController = TextEditingController(text: existing?.token ?? '');
    _passwordController = TextEditingController(text: existing?.password ?? '');
    _active = existing?.active ?? true;
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _tokenController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final serverUrl = _serverController.text.trim();
    final serverUri = Uri.tryParse(serverUrl);
    final validServer =
        serverUri != null &&
        serverUri.hasScheme &&
        (serverUri.scheme == 'http' || serverUri.scheme == 'https') &&
        serverUri.host.isNotEmpty;
    if (!validServer) {
      setState(() => _error = 'Enter a valid http or https server address.');
      return;
    }

    final username = _usernameController.text.trim();
    final token = _tokenController.text.trim();
    final password = _passwordController.text.trim();
    if (_isPlex && token.isEmpty) {
      setState(
        () => _error = 'Enter your Plex access key to save this server.',
      );
      return;
    }
    if (_usesUsernamePassword && (username.isEmpty || password.isEmpty)) {
      setState(
        () => _error =
            'Enter your ${widget.type.label} username and password to save.',
      );
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    late final _PersonalServerVerifiedSession verifiedSession;
    try {
      verifiedSession = await _verifyConnection(
        serverUri,
        username: username,
        secret: _isPlex ? token : password,
      );
    } on _PersonalServerAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _saving = false;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'Juicr could not connect to ${widget.type.label}. Check the address and try again.';
        _saving = false;
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      _PersonalServerEditorResult(
        serverUrl: serverUrl,
        username: username,
        token: verifiedSession.accessKey,
        password: '',
        userId: verifiedSession.userId,
        active: _active,
      ),
    );
  }

  Future<_PersonalServerVerifiedSession> _verifyConnection(
    Uri serverUri, {
    required String username,
    required String secret,
  }) async {
    if (_isPlex) {
      final sectionsUri = _serverEndpoint(
        serverUri,
        '/library/sections',
      ).replace(queryParameters: {'X-Plex-Token': secret});
      final response = await http
          .get(
            sectionsUri,
            headers: {'Accept': 'application/json', 'X-Plex-Token': secret},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _PersonalServerVerifiedSession(accessKey: secret);
      }
      throw _PersonalServerAuthException(
        'Juicr could not reach Plex with that access key.',
      );
    }

    final authUri = _serverEndpoint(serverUri, '/Users/AuthenticateByName');
    final response = await http
        .post(
          authUri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'X-Emby-Authorization': _mediaServerAuthorizationHeader,
            'Authorization': _mediaServerAuthorizationHeader,
          },
          body: jsonEncode({'Username': username, 'Pw': secret}),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _PersonalServerAuthException(
        'Juicr could not sign in to ${widget.type.label}. Check the account and try again.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw _PersonalServerAuthException(
        '${widget.type.label} returned an unexpected sign-in response.',
      );
    }
    final accessKey = (decoded['AccessToken'] ?? '').toString().trim();
    final user = decoded['User'];
    final userId = user is Map<String, dynamic>
        ? (user['Id'] ?? '').toString().trim()
        : '';
    if (accessKey.isEmpty) {
      throw _PersonalServerAuthException(
        '${widget.type.label} did not return an app access key.',
      );
    }
    if (userId.isEmpty) {
      throw _PersonalServerAuthException(
        '${widget.type.label} did not return the signed-in user.',
      );
    }
    return _PersonalServerVerifiedSession(accessKey: accessKey, userId: userId);
  }

  Uri _serverEndpoint(Uri serverUri, String endpointPath) {
    final basePath = serverUri.path.endsWith('/')
        ? serverUri.path.substring(0, serverUri.path.length - 1)
        : serverUri.path;
    return serverUri.replace(
      path: '$basePath$endpointPath',
      queryParameters: const <String, String>{},
      fragment: '',
    );
  }

  static const String _mediaServerAuthorizationHeader =
      'MediaBrowser Client="Juicr", Device="Android", DeviceId="juicr-android", Version="1"';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final title = 'Connect ${widget.type.label}';
    final helper = _isPlex
        ? 'Paste the access key from your own Plex server. Juicr checks the connection before saving it.'
        : 'Sign in to your ${widget.type.label} server once. Juicr checks the connection and saves an app access key on this device.';
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          12,
          18,
          JuicrVisual.bottomSheetBottomBreathingRoom + bottomInset,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                helper,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.68),
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              _PersonalServerPrivacyNotice(type: widget.type),
              const SizedBox(height: 14),
              TextField(
                controller: _serverController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '${widget.type.label} server address',
                  hintText: switch (widget.type) {
                    PersonalServerType.plex => 'http://192.168.1.20:32400',
                    PersonalServerType.jellyfin =>
                      'https://jellyfin.example.com',
                    PersonalServerType.emby => 'https://emby.example.com',
                  },
                ),
              ),
              const SizedBox(height: 12),
              if (_usesUsernamePassword) ...[
                TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _isPlex ? _tokenController : _passwordController,
                obscureText: _obscureSecret,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: _isPlex ? 'Plex access key' : 'Password',
                  suffixIcon: IconButton(
                    tooltip: _obscureSecret ? 'Show' : 'Hide',
                    onPressed: () =>
                        setState(() => _obscureSecret = !_obscureSecret),
                    icon: Icon(
                      _obscureSecret
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                  ),
                ),
                onSubmitted: (_) => _save(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show in personal servers'),
                subtitle: const Text(
                  'Saved off keeps the connection details, but Juicr will not use this server.',
                ),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (widget.existing != null)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(
                              const _PersonalServerEditorResult(remove: true),
                            ),
                      child: const Text('Remove'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Checking...' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonalServerAuthException implements Exception {
  const _PersonalServerAuthException(this.message);

  final String message;
}

class _PersonalServerVerifiedSession {
  const _PersonalServerVerifiedSession({
    required this.accessKey,
    this.userId = '',
  });

  final String accessKey;
  final String userId;
}

class _PersonalServerPrivacyNotice extends StatelessWidget {
  const _PersonalServerPrivacyNotice({required this.type});

  final PersonalServerType type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: JuicrVisual.elevatedCardDecoration(
        colorScheme,
        radius: 14,
        color: colorScheme.primaryContainer.withValues(alpha: 0.16),
        borderAlpha: 0,
        shadowAlpha: 0.04,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${type.label} is treated as your personal server. Juicr keeps this connection local to the app and does not send the server address, password, access key, or media links in diagnostics.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddonSourceTile extends StatelessWidget {
  const _AddonSourceTile({
    required this.name,
    required this.subtitle,
    required this.status,
    this.capabilityLabels = const <String>[],
    this.compatibilityText,
    this.compatibilityHint,
    this.helperText,
    this.selectable = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.onSelectedChanged,
    this.onActiveChanged,
    this.onEdit,
    this.onRemove,
  });

  final String name;
  final String subtitle;
  final List<String> capabilityLabels;
  final String? compatibilityText;
  final String? compatibilityHint;
  final String? helperText;
  final bool selectable;
  final bool selected;
  final _AddonStatus status;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onSelectedChanged;
  final ValueChanged<bool>? onActiveChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  bool get _showAdvancedRuntimeControlsPill {
    return compatibilityText == 'P2P locked' ||
        compatibilityText == 'P2P beta' ||
        compatibilityHint?.contains('Advanced P2P playback') == true;
  }

  String get _advancedRuntimeControlsHint {
    return 'Power users can manage proven Advanced P2P playback here. It stays behind consent, clear limits, and safe diagnostics before Juicr can try it.';
  }

  Future<void> _showActions(BuildContext context) async {
    final selected = await showJuicrBottomSheet<String>(
      context: context,
      showDragHandle: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) {
        final active = status == _AddonStatus.active;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              18,
              12,
              18,
              JuicrVisual.bottomSheetBottomBreathingRoom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                JuicrSheetOptionTile(
                  icon: active
                      ? Icons.pause_circle_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  label: active ? 'Disable' : 'Activate',
                  subtitle: active
                      ? 'Keep it saved, but stop Juicr from using it.'
                      : 'Allow Juicr to read this manifest when needed.',
                  onTap: () => Navigator.of(context).pop('toggle'),
                ),
                if (compatibilityText != null && compatibilityText!.isNotEmpty)
                  JuicrSheetOptionTile(
                    icon: Icons.info_outline_rounded,
                    label: 'Compatibility',
                    subtitle: 'Explain what this add-on status means.',
                    onTap: () => Navigator.of(context).pop('compatibility'),
                  ),
                if (onEdit != null)
                  JuicrSheetOptionTile(
                    icon: Icons.edit_rounded,
                    label: 'Edit',
                    subtitle: 'Rename it or update the manifest URL.',
                    onTap: () => Navigator.of(context).pop('edit'),
                  ),
                JuicrSheetOptionTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove',
                  subtitle: 'Delete this user add-on from Juicr.',
                  trailing: Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.82),
                  ),
                  onTap: () => Navigator.of(context).pop('remove'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == 'toggle') {
      onActiveChanged?.call(status != _AddonStatus.active);
    } else if (selected == 'compatibility') {
      await _showCompatibilityInfo(context);
    } else if (selected == 'edit') {
      onEdit?.call();
    } else if (selected == 'remove') {
      onRemove?.call();
    }
  }

  Future<void> _showCompatibilityInfo(BuildContext context) async {
    final label = compatibilityText;
    if (label == null || label.isEmpty) return;
    await showJuicrBottomSheet<void>(
      context: context,
      showDragHandle: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final hint = compatibilityHint == null || compatibilityHint!.isEmpty
            ? 'Juicr is still learning what this manifest can do.'
            : compatibilityHint!;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              18,
              12,
              18,
              JuicrVisual.bottomSheetBottomBreathingRoom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Compatibility',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (capabilityLabels.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _AddonCapabilityBreakdown(labels: capabilityLabels),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _AddonCompatibilityPill(label: label, hint: hint),
                    if (_showAdvancedRuntimeControlsPill)
                      _AddonCompatibilityPill(
                        label: 'Advanced P2P',
                        hint: _advancedRuntimeControlsHint,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const _AddonRouteEvidenceNotice(),
                const SizedBox(height: 8),
                Text(
                  'Browse success is not playback proof. Juicr keeps locked playback types unavailable until a separate proof path exists.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                    height: 1.28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  hint,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.74),
                    height: 1.32,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'These are manifest capabilities, not playback proof. This is a compatibility hint, not a promise that the add-on provides playable media. Juicr only tries user-chosen manifests and keeps unsupported source classes unavailable.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.58),
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canEdit =
        onActiveChanged != null || onEdit != null || onRemove != null;
    return InkWell(
      onTap: selectable ? () => onSelectedChanged?.call(!selected) : onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (selectable) ...[
                  Checkbox(
                    value: selected,
                    onChanged: (value) =>
                        onSelectedChanged?.call(value ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.58),
                          height: 1.25,
                        ),
                      ),
                      if (capabilityLabels.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final label in capabilityLabels)
                              _CapabilityChip(label: label),
                          ],
                        ),
                      ],
                      if (compatibilityText != null &&
                          compatibilityText!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _AddonCompatibilityPill(
                              label: compatibilityText!,
                              hint: compatibilityHint,
                            ),
                            if (_showAdvancedRuntimeControlsPill)
                              _AddonCompatibilityPill(
                                label: 'Advanced P2P',
                                hint: _advancedRuntimeControlsHint,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (!selectable) _ActivePill(status: status),
                if (!selectable && canEdit) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: 'Add-on actions',
                    onPressed: () => _showActions(context),
                  ),
                ],
              ],
            ),
            if (helperText != null && helperText!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _AddonHelperText(text: helperText!),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddonRouteEvidenceNotice extends StatelessWidget {
  const _AddonRouteEvidenceNotice();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label:
          'Add-on route evidence records only media type, route status, safe counts, and checked time. It does not store URLs, hashes, trackers, headers, tokens, or account details.',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: JuicrVisual.elevatedCardDecoration(
            colorScheme,
            radius: 16,
            color: colorScheme.primaryContainer.withValues(alpha: 0.18),
            borderAlpha: 0,
            shadowAlpha: 0.035,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.analytics_outlined,
                  size: 18,
                  color: colorScheme.primary.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Route evidence',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'After a playback test, Juicr keeps only the route status, media type, safe counts, and checked time. URLs, hashes, trackers, headers, tokens, and account details stay out.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.66),
                          height: 1.28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddonCapabilityBreakdown extends StatelessWidget {
  const _AddonCapabilityBreakdown({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label:
          'Add-on advertised capabilities: ${labels.join(', ')}. These describe what the manifest offers; playback can still vary by title.',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: JuicrVisual.elevatedCardDecoration(
            colorScheme,
            radius: 16,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
            borderAlpha: 0,
            shadowAlpha: 0.035,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What this add-on advertises',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in labels) _CapabilityChip(label: label),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Catalog/details and subtitles use one active source at a time. Streams, Live TV, account-backed routes, and P2P can stay active as fallback paths.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.62),
                    height: 1.28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddonCompatibilityPill extends StatelessWidget {
  const _AddonCompatibilityPill({required this.label, this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final normalized = label.toLowerCase();
    final color = switch (normalized) {
      'direct streams ready' => colorScheme.primary,
      'stream add-on' => colorScheme.primary,
      'direct links if configured' => const Color(0xFF78C7FF),
      'needs account setup' => const Color(0xFFFFB84D),
      'torrent locked' => const Color(0xFFFFB84D),
      'p2p beta' => const Color(0xFF78C7FF),
      'advanced p2p' => const Color(0xFF78C7FF),
      'advanced p2p playback' => const Color(0xFF78C7FF),
      'captions only' => const Color(0xFF78C7FF),
      'browse only' => colorScheme.onSurface,
      _ => colorScheme.onSurface,
    };
    final semanticsLabel = hint == null || hint!.isEmpty
        ? 'Add-on compatibility: $label'
        : 'Add-on compatibility: $label. $hint';
    final child = Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            boxShadow: JuicrVisual.softShadow(
              colorScheme,
              alpha: 0.04,
              blur: 8,
              y: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  normalized.contains('locked')
                      ? Icons.lock_outline_rounded
                      : normalized.contains('p2p')
                      ? Icons.hub_outlined
                      : normalized.contains('runtime')
                      ? Icons.tune_rounded
                      : normalized.contains('account')
                      ? Icons.manage_accounts_outlined
                      : normalized.contains('stream')
                      ? Icons.play_circle_outline_rounded
                      : normalized.contains('caption')
                      ? Icons.closed_caption_outlined
                      : normalized.contains('browse')
                      ? Icons.travel_explore_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 13,
                  color: color.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (hint == null || hint!.isEmpty) return child;
    return Tooltip(message: hint!, child: child);
  }
}

class _AddonHelperText extends StatelessWidget {
  const _AddonHelperText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(12),
        boxShadow: JuicrVisual.softShadow(
          colorScheme,
          alpha: 0.06,
          blur: 10,
          y: 3,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.tips_and_updates_outlined,
              size: 16,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final normalized = label.toLowerCase();
    final activeColor = switch (normalized) {
      'streams' => const Color(0xFF36D98B),
      'subtitles' => const Color(0xFF78C7FF),
      'tv' => const Color(0xFFFFB84D),
      'details' => colorScheme.primary,
      'needs check' => const Color(0xFFFFB84D),
      _ => colorScheme.onSurface,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        boxShadow: JuicrVisual.softShadow(
          colorScheme,
          alpha: 0.04,
          blur: 8,
          y: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: activeColor.withValues(alpha: 0.9),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  const _ActivePill({required this.status});

  final _AddonStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      _AddonStatus.active => colorScheme.primary,
      _AddonStatus.partial => const Color(0xFFFFB84D),
      _AddonStatus.off => colorScheme.onSurface.withValues(alpha: 0.48),
    };
    final label = switch (status) {
      _AddonStatus.active => 'Active',
      _AddonStatus.partial => 'Partial',
      _AddonStatus.off => 'Off',
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: status == _AddonStatus.off
            ? color.withValues(alpha: 0.07)
            : color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        boxShadow: JuicrVisual.softShadow(
          colorScheme,
          alpha: status == _AddonStatus.off ? 0.03 : 0.06,
          blur: 8,
          y: 2,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BetaPill extends StatelessWidget {
  const _BetaPill({required this.label, this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return JuicrBetaPill(label: label, hint: hint);
  }
}

class _SettingsHomeTile extends StatelessWidget {
  const _SettingsHomeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badgeLabel,
    this.badgeHint,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final ValueChanged<BuildContext> onTap;
  final String? badgeLabel;
  final String? badgeHint;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final compactLandscape = JuicrVisual.compactLandscape(context);
    final cardColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.surfaceContainerHigh
        : JuicrVisual.flatCardColor(colorScheme);
    final borderColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.outlineVariant.withValues(alpha: 0.22)
        : JuicrVisual.flatCardBorder(colorScheme);
    return Builder(
      builder: (tileContext) {
        return Semantics(
          button: true,
          label: title,
          value: subtitle,
          hint: 'Open $title settings',
          child: ExcludeSemantics(
            child: Material(
              color: cardColor,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: borderColor,
                  width: JuicrVisual.cardStrokeWidth,
                ),
              ),
              child: InkWell(
                onTap: () => onTap(tileContext),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compactLandscape ? 12 : 16,
                    compactLandscape ? 11 : 16,
                    compactLandscape ? 12 : 16,
                    compactLandscape ? 11 : 16,
                  ),
                  child: Row(
                    children: [
                      JuicrVisual.iconBadge(
                        context,
                        icon: icon,
                        boxSize: compactLandscape ? 36 : 46,
                        iconSize: compactLandscape ? 18 : 20,
                        radius: compactLandscape ? 13 : 16,
                        shadowAlpha: 0.08,
                        glowAlpha: 0,
                      ),
                      SizedBox(width: compactLandscape ? 12 : 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontSize: compactLandscape
                                              ? 15
                                              : null,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.1,
                                        ),
                                  ),
                                ),
                                if (badgeLabel != null &&
                                    badgeLabel!.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  _BetaPill(
                                    label: badgeLabel!,
                                    hint: badgeHint,
                                  ),
                                ],
                              ],
                            ),
                            SizedBox(height: compactLandscape ? 2 : 4),
                            Text(
                              subtitle,
                              maxLines: compactLandscape ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.68,
                                    ),
                                    height: 1.25,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: compactLandscape ? 8 : 12),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.primary,
                        size: compactLandscape ? 22 : 24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsSectionPage extends StatelessWidget {
  const _SettingsSectionPage({
    required this.title,
    required this.child,
    this.framed = true,
    this.actions,
    this.titleBadgeLabel,
    this.titleBadgeHint,
  });

  final String title;
  final Widget child;
  final bool framed;
  final List<Widget>? actions;
  final String? titleBadgeLabel;
  final String? titleBadgeHint;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final compactLandscape = JuicrVisual.compactLandscape(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
            if (titleBadgeLabel != null && titleBadgeLabel!.isNotEmpty) ...[
              const SizedBox(width: 8),
              _BetaPill(label: titleBadgeLabel!, hint: titleBadgeHint),
            ],
          ],
        ),
        titleSpacing: 4,
        toolbarHeight: JuicrVisual.topLevelToolbarHeightFor(context),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: actions,
      ),
      body: ListView(
        padding: JuicrVisual.topLevelListPaddingFor(
          context,
          top: compactLandscape ? 8 : 12,
          bottom: (compactLandscape ? 72 : 112) + bottomInset,
        ),
        children: [if (framed) _SettingsCard(child: child) else child],
      ),
    );
  }
}

class _SettingsCardSection extends StatelessWidget {
  const _SettingsCardSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        child,
      ],
    );
  }
}

class _ProviderSelector extends StatelessWidget {
  const _ProviderSelector({
    required this.title,
    required this.icon,
    required this.providers,
    required this.selected,
    required this.onChanged,
    this.showNativeHealth = false,
    this.checking = false,
  });

  final String title;
  final IconData icon;
  final List<ApiProvider> providers;
  final ApiProvider selected;
  final ValueChanged<ApiProvider> onChanged;
  final bool showNativeHealth;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    Widget tile(NativeProviderHealth? health) {
      final autoSelected = selected.id == AppState.autoNativeProviderId;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: JuicrVisual.iconBadge(
          context,
          icon: icon,
          boxSize: 38,
          iconSize: 18,
          radius: 14,
          shadowAlpha: 0.12,
        ),
        title: Text(title),
        subtitle: showNativeHealth
            ? autoSelected
                  ? const _AutoProviderSummary(prominent: false)
                  : checking
                  ? _ProviderCheckingSummary(provider: selected)
                  : _ProviderHealthSummary(provider: selected, health: health!)
            : Text(selected.name),
        trailing: const Icon(Icons.keyboard_arrow_down_rounded),
        onTap: () => _showProviderSheet(context),
      );
    }

    if (!showNativeHealth) return tile(null);
    if (selected.id == AppState.autoNativeProviderId) return tile(null);

    return ValueListenableBuilder<Map<String, NativeProviderHealth>>(
      valueListenable: AppState.nativeProviderHealth,
      builder: (context, _, __) {
        return tile(AppState.nativeProviderHealthDetailsFor(selected.id));
      },
    );
  }

  Future<void> _showProviderSheet(BuildContext context) async {
    await showJuicrBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: JuicrVisual.bottomSheetShape,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                18,
                12,
                18,
                JuicrVisual.bottomSheetBottomBreathingRoom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Choose playback option',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: showNativeHealth
                        ? ValueListenableBuilder<
                            Map<String, NativeProviderHealth>
                          >(
                            valueListenable: AppState.nativeProviderHealth,
                            builder: (context, _, __) {
                              return _ProviderSheetList(
                                providers: providers,
                                selected: selected,
                                showNativeHealth: showNativeHealth,
                                onChanged: (provider) {
                                  Navigator.of(sheetContext).pop();
                                  onChanged(provider);
                                },
                              );
                            },
                          )
                        : _ProviderSheetList(
                            providers: providers,
                            selected: selected,
                            showNativeHealth: showNativeHealth,
                            onChanged: (provider) {
                              Navigator.of(sheetContext).pop();
                              onChanged(provider);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProviderHealthRefreshTile extends StatefulWidget {
  const _ProviderHealthRefreshTile({
    required this.checking,
    required this.sampleLabel,
    required this.onTap,
    required this.onConfigureSample,
  });

  final bool checking;
  final String sampleLabel;
  final VoidCallback onTap;
  final VoidCallback onConfigureSample;

  @override
  State<_ProviderHealthRefreshTile> createState() =>
      _ProviderHealthRefreshTileState();
}

class _ProviderHealthRefreshTileState extends State<_ProviderHealthRefreshTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _ProviderHealthRefreshTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checking != widget.checking) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.checking) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final checkedAt = AppState.providerHealthLastCheckedAt;
    final remaining = AppState.providerHealthRefreshRemaining();
    final hint = _providerHealthRefreshHint(checkedAt, remaining);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: JuicrVisual.iconBadge(
        context,
        icon: Icons.health_and_safety_outlined,
        boxSize: 38,
        iconSize: 18,
        radius: 14,
        shadowAlpha: 0.12,
      ),
      title: Text(
        widget.checking
            ? 'Checking playback options...'
            : 'Check playback options',
      ),
      subtitle: Text('${widget.sampleLabel}. $hint'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Choose sample title',
            onPressed: widget.checking ? null : widget.onConfigureSample,
            icon: const Icon(Icons.tune_rounded),
          ),
          RotationTransition(
            turns: _controller,
            child: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      onTap: widget.checking ? null : widget.onTap,
    );
  }

  String _providerHealthRefreshHint(DateTime? checkedAt, Duration remaining) {
    final checkedText = checkedAt == null
        ? 'Not checked yet'
        : 'Last checked ${_relativeProviderHealthTime(checkedAt)}';
    if (remaining > Duration.zero) {
      return '$checkedText. Ready again in ${_compactDuration(remaining)}.';
    }
    return '$checkedText. Ready when you need a fresh check.';
  }

  String _relativeProviderHealthTime(DateTime checkedAt) {
    final elapsed = DateTime.now().difference(checkedAt);
    if (elapsed.inSeconds < 45) return 'just now';
    if (elapsed.inMinutes < 60) {
      final minutes = elapsed.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    }
    if (elapsed.inHours < 24) {
      final hours = elapsed.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }
    final days = elapsed.inDays;
    return '$days ${days == 1 ? 'day' : 'days'} ago';
  }

  String _compactDuration(Duration duration) {
    if (duration.inMinutes >= 1) {
      final seconds = duration.inSeconds.remainder(60);
      if (seconds == 0) return '${duration.inMinutes}m';
      return '${duration.inMinutes}m ${seconds}s';
    }
    return '${duration.inSeconds + 1}s';
  }
}

class _OverrideSettingsSection extends StatelessWidget {
  const _OverrideSettingsSection({
    required this.enabled,
    required this.children,
  });

  final bool enabled;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        reverseDuration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
            reverseCurve: Curves.easeIn,
          );
          final slide =
              Tween<Offset>(
                begin: const Offset(0, -0.035),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                ),
              );
          return ClipRect(
            child: FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: slide,
                child: SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: child,
                ),
              ),
            ),
          );
        },
        child: enabled
            ? KeyedSubtree(
                key: const ValueKey('override-settings-open'),
                child: Column(children: children),
              )
            : const SizedBox.shrink(key: ValueKey('override-settings-closed')),
      ),
    );
  }
}

class _OverrideSectionDivider extends StatelessWidget {
  const _OverrideSectionDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.32),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.62),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.32),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedPlaybackSectionHeader extends StatelessWidget {
  const _AdvancedPlaybackSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JuicrVisual.iconBadge(
            context,
            icon: icon,
            boxSize: 36,
            iconSize: 18,
            radius: 13,
            shadowAlpha: 0.08,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.64),
                    fontWeight: FontWeight.w600,
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExperimentalWarning extends StatelessWidget {
  const _ExperimentalWarning();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: colorScheme.tertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'These controls change native player timing. Extreme values can make playback slower, skip working sources, or leave libVLC waiting too long.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
                height: 1.32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExperimentalInfoTile extends StatelessWidget {
  const _ExperimentalInfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Icon(
              icon,
              size: 20,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.62),
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceConsentAcknowledgement {
  const _SourceConsentAcknowledgement({
    required this.title,
    required this.text,
  });

  final String title;
  final String text;
}

class _SourceConsentAcknowledgementTile extends StatelessWidget {
  const _SourceConsentAcknowledgementTile({
    required this.acknowledgement,
    required this.value,
    required this.onChanged,
  });

  final _SourceConsentAcknowledgement acknowledgement;
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      checked: value,
      label: acknowledgement.title,
      hint: value ? 'Acknowledged' : 'Tap to acknowledge',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onChanged(!value),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            acknowledgement.title,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            acknowledgement.text,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.68,
                                  ),
                                  height: 1.28,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Checkbox(
                      value: value,
                      onChanged: onChanged,
                      semanticLabel: acknowledgement.title,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsValueTile extends StatelessWidget {
  const _SettingsValueTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.showValue = true,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      value: showValue ? value : null,
      hint: 'Change $title',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                JuicrVisual.iconBadge(
                  context,
                  icon: icon,
                  boxSize: 38,
                  iconSize: 18,
                  radius: 14,
                  shadowAlpha: 0.12,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title),
                      if (showValue) ...[
                        const SizedBox(height: 2),
                        Text(value),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const SizedBox(
                  width: 24,
                  child: Center(child: Icon(Icons.chevron_right_rounded)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StaticSettingsValueTile extends StatelessWidget {
  const _StaticSettingsValueTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JuicrVisual.iconBadge(
            context,
            icon: icon,
            boxSize: 38,
            iconSize: 18,
            radius: 14,
            shadowAlpha: 0.12,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSliderTile extends StatelessWidget {
  const _SettingsSliderTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelBuilder,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double value) labelBuilder;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              JuicrVisual.iconBadge(
                context,
                icon: icon,
                boxSize: 38,
                iconSize: 18,
                radius: 14,
                shadowAlpha: 0.12,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title)),
              const SizedBox(width: 12),
              Text(labelBuilder(value)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: labelBuilder(value),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingsColorTile extends StatelessWidget {
  const _SettingsColorTile({
    required this.icon,
    required this.title,
    required this.selectedColor,
    required this.colors,
    required this.onSelected,
  });

  final IconData icon;
  final String title;
  final Color selectedColor;
  final List<Color> colors;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final customSelected = !colors.any(
      (color) => color.value == selectedColor.value,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: JuicrVisual.iconBadge(
              context,
              icon: icon,
              boxSize: 38,
              iconSize: 18,
              radius: 14,
              shadowAlpha: 0.12,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final color in colors) ...[
                      Expanded(
                        child: Center(
                          child: _ColorChoiceButton(
                            color: color,
                            selected: color.value == selectedColor.value,
                            onTap: () => onSelected(color),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Center(
                        child: _ColorChoiceButton(
                          color: customSelected
                              ? selectedColor
                              : colorScheme.primary,
                          selected: customSelected,
                          custom: true,
                          customPreviewColor: customSelected
                              ? selectedColor
                              : null,
                          onTap: () async {
                            final selected = await showDialog<Color>(
                              context: context,
                              builder: (context) => _ColorPickerDialog(
                                title: title,
                                initialColor: selectedColor,
                                allowOpacity: false,
                              ),
                            );
                            if (selected != null) onSelected(selected);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorChoiceButton extends StatelessWidget {
  const _ColorChoiceButton({
    required this.color,
    required this.selected,
    required this.onTap,
    this.custom = false,
    this.customPreviewColor,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final bool custom;
  final Color? customPreviewColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleColor = color == Colors.transparent ? Colors.black : color;
    final customFill = custom ? colorScheme.surfaceContainerHighest : null;
    final customBorder = custom
        ? colorScheme.outlineVariant.withValues(alpha: selected ? 0.52 : 0.28)
        : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 38,
        decoration: BoxDecoration(
          color:
              customFill ??
              (selected
                  ? visibleColor.withValues(alpha: 0.2)
                  : colorScheme.surfaceContainerHigh),
          borderRadius: BorderRadius.circular(14),
          boxShadow: custom || selected
              ? [
                  BoxShadow(
                    color: (customBorder ?? visibleColor).withValues(
                      alpha: selected ? 0.16 : 0.08,
                    ),
                    blurRadius: selected ? 12 : 8,
                    offset: Offset(0, selected ? 5 : 3),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: custom
              ? _RgbCustomColorMark(previewColor: customPreviewColor)
              : Container(
                  width: 21,
                  height: 21,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: visibleColor,
                  ),
                ),
        ),
      ),
    );
  }
}

class _RgbCustomColorMark extends StatelessWidget {
  const _RgbCustomColorMark({this.previewColor});

  final Color? previewColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0xFFFF4D8D),
            Color(0xFFFFD166),
            Color(0xFF32D583),
            Color(0xFF38BDF8),
            Color(0xFF8B5CF6),
            Color(0xFFFF4D8D),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: previewColor ?? Colors.white.withValues(alpha: 0.36),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.86),
              width: 1.2,
            ),
          ),
          child: previewColor == null
              ? const Icon(Icons.palette_outlined, size: 8, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.title,
    required this.initialColor,
    this.allowOpacity = true,
  });

  final String title;
  final Color initialColor;
  final bool allowOpacity;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  late double _opacity;
  late final TextEditingController _hexController;

  static const List<double> _saturationStops = [1, 0.82, 0.64, 0.46, 0.28, 0.1];
  static const List<double> _valueStops = [0.95, 0.78, 0.62, 0.46, 0.3];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialColor == Colors.transparent
        ? Colors.white
        : widget.initialColor;
    _hsv = HSVColor.fromColor(initial.withAlpha(255));
    _opacity = widget.allowOpacity
        ? widget.initialColor.opacity.clamp(0.12, 1.0)
        : 1.0;
    _hexController = TextEditingController(text: _hexFor(_color));
  }

  Color get _color =>
      _hsv.toColor().withValues(alpha: widget.allowOpacity ? _opacity : 1.0);

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor value, {double? opacity}) {
    setState(() {
      _hsv = value;
      if (opacity != null && widget.allowOpacity) _opacity = opacity;
      _hexController.text = _hexFor(_color);
    });
  }

  void _applyHex(String value) {
    final parsed = _colorFromHex(value);
    if (parsed == null) return;
    setState(() {
      _hsv = HSVColor.fromColor(parsed.withAlpha(255));
      _opacity = widget.allowOpacity ? parsed.opacity.clamp(0.12, 1.0) : 1.0;
      _hexController.text = _hexFor(_color);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 86,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(14),
                boxShadow: JuicrVisual.softShadow(
                  colorScheme,
                  alpha: 0.1,
                  blur: 14,
                  y: 5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 8,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: _hsv.hue,
                min: 0,
                max: 360,
                divisions: 72,
                label: '${_hsv.hue.round()}',
                onChanged: (value) => _setHsv(_hsv.withHue(value)),
              ),
            ),
            if (widget.allowOpacity) ...[
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 8,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                ),
                child: Slider(
                  value: _opacity,
                  min: 0.12,
                  max: 1,
                  divisions: 22,
                  label: '${(_opacity * 100).round()}%',
                  onChanged: (value) => _setHsv(_hsv, opacity: value),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final saturation in _saturationStops)
                  for (final value in _valueStops)
                    _PickerSwatch(
                      color: _hsv
                          .withSaturation(saturation)
                          .withValue(value)
                          .toColor(),
                      selected: _closeColor(
                        _hsv
                            .withSaturation(saturation)
                            .withValue(value)
                            .toColor(),
                        _hsv.toColor(),
                      ),
                      onTap: () => _setHsv(
                        _hsv.withSaturation(saturation).withValue(value),
                      ),
                    ),
                for (final color in const [
                  Colors.white,
                  Color(0xFFDDDDDD),
                  Color(0xFF999999),
                  Color(0xFF555555),
                  Colors.black,
                ])
                  _PickerSwatch(
                    color: color,
                    selected: _closeColor(color, _hsv.toColor()),
                    onTap: () => _setHsv(HSVColor.fromColor(color)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hexController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: widget.allowOpacity
                    ? 'Hex (AARRGGBB)'
                    : 'Hex (RRGGBB)',
                prefixText: '#',
              ),
              onSubmitted: _applyHex,
              onEditingComplete: () => _applyHex(_hexController.text),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  bool _closeColor(Color a, Color b) {
    return (a.red - b.red).abs() < 4 &&
        (a.green - b.green).abs() < 4 &&
        (a.blue - b.blue).abs() < 4;
  }

  String _hexFor(Color color) {
    if (!widget.allowOpacity) {
      return (color.value & 0x00FFFFFF)
          .toRadixString(16)
          .padLeft(6, '0')
          .toUpperCase();
    }
    return color.value.toRadixString(16).padLeft(8, '0').toUpperCase();
  }

  Color? _colorFromHex(String value) {
    final cleaned = value.replaceAll('#', '').trim();
    if (!RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(cleaned)) {
      return null;
    }
    final hex = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
    final parsed = Color(int.parse(hex, radix: 16));
    if (!widget.allowOpacity) {
      return Color(0xFF000000 | (parsed.value & 0x00FFFFFF));
    }
    return parsed;
  }
}

class _PickerSwatch extends StatelessWidget {
  const _PickerSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: JuicrVisual.elevatedCircleDecoration(
          colorScheme,
          color: color,
          shadowAlpha: selected ? 0.18 : 0.08,
          glowAlpha: selected ? 0.16 : 0.04,
        ),
      ),
    );
  }
}

class _OptionItem<T> {
  const _OptionItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.badge,
  });

  final T value;
  final String label;
  final String? subtitle;
  final String? badge;
}

class _GeneralHelpSheet extends StatelessWidget {
  const _GeneralHelpSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const items = [
      (
        Icons.contrast_rounded,
        'Theme mode',
        'Grouped with color settings. System follows Android, Light keeps things airy, and Dark uses Juicr\'s deeper surfaces.',
      ),
      (
        Icons.nightlight_round,
        'Pure black theme',
        'Switches dark mode to AMOLED black surfaces. If you turn it on from Light, Juicr automatically changes to Dark.',
      ),
      (
        Icons.palette_outlined,
        'Use device accent',
        'Uses Android dynamic color / Monet when available. If the device does not expose Material You colors, Juicr falls back to the selected accent.',
      ),
      (
        Icons.color_lens_outlined,
        'Accent color',
        'Available when device accent is off. It changes highlights, icons, buttons, card tint, and subtle borders.',
      ),
      (
        Icons.translate_rounded,
        'Language',
        'Reserved for the upcoming app-language selector. It sits with display and readability settings because it changes how the app reads.',
      ),
      (
        Icons.format_size_rounded,
        'Text size',
        'Changes Juicr\'s text size without changing your Android system text size.',
      ),
      (
        Icons.space_dashboard_outlined,
        'Navigation style',
        'Chooses how much the bottom navigation explains itself: every label, selected label only, or icons only.',
      ),
      (
        Icons.grid_view_rounded,
        'Home density',
        'Changes Home spacing and poster size. Larger posters feel calmer; compact keeps more titles on screen. Home can restore recent rows first, then refresh quietly when online.',
      ),
      (
        Icons.home_rounded,
        'App start page',
        'Choose where Juicr opens when you launch the app.',
      ),
      (
        Icons.visibility_off_outlined,
        'Adult title visibility',
        'Kept in its own card because catalog flags are imperfect. Juicr hides clear adult signals by default, but this cannot guarantee every sensitive title is removed.',
      ),
      (
        Icons.compress_rounded,
        'Compact layout',
        'Tightens spacing across controls when you want more on smaller screens.',
      ),
      (
        Icons.motion_photos_off_outlined,
        'Reduce motion',
        'Softens page movement for a calmer, faster-feeling app.',
      ),
      (
        Icons.photo_filter_rounded,
        'Artwork motion',
        'Controls poster and artwork UI animation timing on image-heavy screens.',
      ),
      (
        Icons.wallpaper_outlined,
        'Player loading backdrop',
        'Chooses the native player loading background: no artwork, the scan pulse, or a blurred media backdrop while Juicr prepares playback. Dialogs still take priority over player controls.',
      ),
      (
        Icons.warning_amber_rounded,
        'Confirm destructive actions',
        'When enabled, Juicr asks before clear, remove, reset, or delete actions.',
      ),
      (
        Icons.vibration_rounded,
        'Haptics',
        'Adds subtle vibration feedback to important taps such as bottom navigation.',
      ),
      (
        Icons.wallpaper_outlined,
        'Poster image intensity',
        'Changes poster and hero artwork tone. Soft calms images, Normal keeps them natural, and Bold adds punch.',
      ),
      (
        Icons.message_outlined,
        'Status message style',
        'Changes snackbar behavior between Floating, Quiet floating, and Bottom bar.',
      ),
      (
        Icons.restart_alt_rounded,
        'Reset appearance',
        'Restores the visual defaults: system theme, green accent, accent-tinted cards, scan loading backdrop, normal poster tone, matched system bars, and standard layout.',
      ),
      (
        Icons.phone_android_rounded,
        'Status/navigation bars',
        'Controls how Android status and navigation bars blend with Juicr.',
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          18,
          10,
          18,
          JuicrVisual.bottomSheetBottomBreathingRoom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'General guide',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: JuicrVisual.iconBadge(
                      context,
                      icon: item.$1,
                      boxSize: 38,
                      iconSize: 18,
                      radius: 14,
                      shadowAlpha: 0.12,
                    ),
                    title: Text(
                      item.$2,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(item.$3),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackHelpSheet extends StatelessWidget {
  const _PlaybackHelpSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const items = [
      (
        Icons.tune_rounded,
        'Overwrite settings',
        'When enabled, these choices apply to every movie, episode, and animation instead of using per-title saved player settings.',
      ),
      (
        Icons.high_quality_rounded,
        'Preferred quality',
        'Chooses the source preference. Auto uses the recommended option, Higher picture quality starts from the best available quality, Data saver starts low, and Advanced targets the exact quality you pick.',
      ),
      (
        Icons.tune_rounded,
        'Advanced quality',
        'Appears when Preferred quality is set to Advanced. It targets a specific resolution such as 8K, 4K, 1440P, 1080P, or lower.',
      ),
      (
        Icons.aspect_ratio_rounded,
        'Video size',
        'Controls whether video fits inside the screen or fills the screen with cropping.',
      ),
      (
        Icons.replay_10_rounded,
        'Skip time',
        'Sets how many seconds the native player jumps forward or backward. The player places skip controls on the left and right side for easier landscape thumb reach.',
      ),
      (
        Icons.speed_rounded,
        'Playback speed',
        'Sets the default playback speed used by the native player.',
      ),
      (
        Icons.text_fields_rounded,
        'Subtitle size',
        'Changes the default subtitle text size.',
      ),
      (
        Icons.swap_vert_rounded,
        'Subtitle position',
        'Moves subtitles higher or lower from the bottom of the video.',
      ),
      (
        Icons.timer_outlined,
        'Subtitle sync',
        'Sets the default subtitle timing offset. Individual titles can still be adjusted inside the player.',
      ),
      (
        Icons.opacity_rounded,
        'Subtitle background opacity',
        'Adjusts how visible the subtitle background is behind the text.',
      ),
      (
        Icons.rounded_corner_rounded,
        'Subtitle background radius',
        'Controls how rounded the subtitle background shape is, from squared edges to a pill shape.',
      ),
      (
        Icons.format_color_text_rounded,
        'Subtitle text color',
        'Sets the default subtitle text color. Custom colors can be selected from the color picker.',
      ),
      (
        Icons.format_color_fill_rounded,
        'Subtitle background color',
        'Sets the default background color behind subtitles. Custom colors can be selected from the color picker.',
      ),
      (
        Icons.smart_display_rounded,
        'Native player',
        'Switches between Juicr\'s in-app player and external player apps. In-app mode keeps Juicr controls, subtitles, PiP, and fallback switching.',
      ),
      (
        Icons.memory_rounded,
        'Playback engine',
        'Chooses the in-app engine. Auto can choose between Media3 and libVLC, while a manual choice keeps that engine unless fallback behavior is enabled.',
      ),
      (
        Icons.open_in_new_rounded,
        'External player',
        'When Native player is off, Juicr can hand playback to an installed player app on the device.',
      ),
      (
        Icons.play_circle_outline_rounded,
        'Start behavior',
        'Chooses whether saved progress asks first, resumes automatically, or starts from the beginning.',
      ),
      (
        Icons.sync_rounded,
        'Retry style',
        'Controls how quickly slow or broken sources move to the next option.',
      ),
      (
        Icons.closed_caption_outlined,
        'Subtitle auto-select',
        'Automatically picks subtitles using off, default language, last used, or forced-only rules.',
      ),
      (
        Icons.language_rounded,
        'Preferred subtitles',
        'Sets the language used when subtitle auto-select is on default language.',
      ),
      (
        Icons.record_voice_over_rounded,
        'Preferred audio',
        'Requests an audio language when the stream and selected engine expose compatible audio tracks.',
      ),
      (
        Icons.info_outline_rounded,
        'Audio support',
        'Audio language can be preferred now. True in-stream audio track switching still depends on stream and engine support.',
      ),
      (
        Icons.timer_rounded,
        'Controls timeout',
        'Sets how long playback controls stay visible after you interact. Juicr also tries to hide the HUD again after automatic playback changes.',
      ),
      (
        Icons.cable_rounded,
        'Prefer last working playback',
        'Tries the playback path that last worked for the same title before searching again. If that saved path is not usable for the selected engine, Juicr falls back to the normal search ladder.',
      ),
      (
        Icons.swap_horiz_rounded,
        'Auto-switch on stall',
        'Attempts another playback option if video freezes, errors, or stops progressing.',
      ),
      (
        Icons.skip_next_rounded,
        'Autoplay next episode',
        'Starts the next episode automatically near the end when one is available.',
      ),
      (
        Icons.picture_in_picture_alt_rounded,
        'Picture-in-picture',
        'Lets Android keep playback floating when you leave Juicr.',
      ),
      (
        Icons.exit_to_app_rounded,
        'Confirm before leaving',
        'Asks before closing playback so an accidental back press does not stop the video.',
      ),
      (
        Icons.restart_alt_rounded,
        'Reset overwrite settings',
        'Restores the global native player override defaults, including quality, video size, subtitle style, speed, and skip time.',
      ),
      (
        Icons.settings_backup_restore_rounded,
        'Reset player behavior',
        'Restores behavior options such as retry style, subtitle auto-select, control timeout, source preference, PiP, and exit confirmation.',
      ),
      (
        Icons.cleaning_services_outlined,
        'Clear saved player settings',
        'Removes per-title native player choices so titles stop remembering individual player settings.',
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          18,
          10,
          18,
          JuicrVisual.bottomSheetBottomBreathingRoom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Playback guide',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: JuicrVisual.iconBadge(
                      context,
                      icon: item.$1,
                      boxSize: 38,
                      iconSize: 18,
                      radius: 14,
                      shadowAlpha: 0.12,
                    ),
                    title: Text(
                      item.$2,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(item.$3),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryDataHelpSheet extends StatelessWidget {
  const _BatteryDataHelpSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const items = [
      (
        Icons.battery_saver_rounded,
        'Battery saver playback',
        'When enabled, Juicr prefers the Data saver quality path, softens artwork motion, and skips discovery prefetch so browsing and playback feel lighter.',
      ),
      (
        Icons.wifi_rounded,
        'Wi-Fi only for Advanced P2P',
        'Before Advanced P2P starts, Android reports a safe connection bucket. Juicr allows Wi-Fi or ethernet and blocks mobile data, offline, unknown, or other buckets.',
      ),
      (
        Icons.pause_circle_outline_rounded,
        'Pause P2P in background',
        'When playback leaves the foreground and is not protected by PiP, Juicr stops the local P2P session and clears temporary playback state.',
      ),
      (
        Icons.battery_alert_outlined,
        'Stop P2P on low battery',
        'Before Advanced P2P starts, Juicr refreshes Android battery evidence. If the device is not charging and is at or below the floor, P2P is blocked gracefully.',
      ),
      (
        Icons.battery_2_bar_rounded,
        'Battery floor',
        'Sets the cutoff used by the low-battery guard. The default is 20%, and the available range stays intentionally conservative.',
      ),
      (
        Icons.fact_check_outlined,
        'Proof evidence',
        'Diagnostics record only safe outcomes like battery level, charging state, and connection bucket. This proves the guard fired without exposing private network or playback details.',
      ),
      (
        Icons.privacy_tip_outlined,
        'Privacy boundary',
        'Juicr does not log Wi-Fi names, IP addresses, peers, playable URLs, account details, tokens, or headers for these checks.',
      ),
      (
        Icons.shield_outlined,
        'Automatic guards',
        'Screen awake still follows active playback, P2P startup keeps its preflight cap, and route-close cleanup stops stale local playback work.',
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          18,
          10,
          18,
          JuicrVisual.bottomSheetBottomBreathingRoom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Battery & data guide',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: JuicrVisual.iconBadge(
                      context,
                      icon: item.$1,
                      boxSize: 38,
                      iconSize: 18,
                      radius: 14,
                      shadowAlpha: 0.12,
                    ),
                    title: Text(
                      item.$2,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(item.$3),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DefaultSourceHelpSheet extends StatelessWidget {
  const _DefaultSourceHelpSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const items = [
      (
        Icons.grid_view_rounded,
        'Built-in catalog',
        'Adds optional Juicr catalog results to Home, Discovery, search, and title lists. Built-in browsing can refresh and rank safely without changing your private add-ons.',
      ),
      (
        Icons.closed_caption_outlined,
        'Built-in subtitles',
        'Lets the native player look for optional default subtitles. Keep one subtitle source active at a time so caption lists stay clean.',
      ),
      (
        Icons.movie_filter_outlined,
        'Built-in trailers',
        'Shows optional external trailer links on details pages when trailer results are available.',
      ),
      (
        Icons.play_circle_outline_rounded,
        'Built-in playback options',
        'Lets Juicr try optional built-in playback choices after consent. Stream add-ons, account-backed links, and P2P can stay separate as fallback paths.',
      ),
      (
        Icons.alt_route_rounded,
        'Content lanes',
        'Catalog/details and subtitle add-ons are kept to one active source at a time. Streams, Live TV, account-backed routes, and P2P can coexist as playback fallback paths.',
      ),
      (
        Icons.flag_outlined,
        'Default playback option',
        'Auto chooses the best playback order from recent safe health signals and available choices. A specific option only checks that path.',
      ),
      (
        Icons.auto_awesome_rounded,
        'Auto playback',
        'Ranks ready choices first, prefers more available options, and avoids choices that recently failed for the same title. If nothing works, Advanced fallback paths can help only when enabled.',
      ),
      (
        Icons.health_and_safety_outlined,
        'Playback availability',
        'Sample results are hints, not guarantees for the exact title you open. '
            'Shows whether built-in playback choices recently looked available, unavailable, or slow during a safe sample check.',
      ),
      (
        Icons.dns_rounded,
        'Playback option',
        'A playback option is one built-in route Juicr can try for the selected title.',
      ),
      (
        Icons.link_rounded,
        'Stream option',
        'A stream option is one playable media choice, such as HLS or MP4.',
      ),
      (
        Icons.alt_route_rounded,
        'Mirror',
        'A mirror is another playable address inside the same stream group. Juicr can try mirrors when one option stalls or fails.',
      ),
      (
        Icons.high_quality_rounded,
        'Quality',
        'Quality is the resolution Juicr is currently targeting, such as 720P, 1080P, 4K, or Auto.',
      ),
      (
        Icons.smart_display_rounded,
        'Native player',
        'The in-app player screen. It can use engines such as Media3 or libVLC while keeping Juicr controls and subtitles.',
      ),
      (
        Icons.memory_rounded,
        'Media3 and libVLC',
        'These are the current in-app engines. Media3 is Android-native and efficient; libVLC is an independent engine with broad format support. Auto keeps them in the safest order for the selected stream.',
      ),
      (
        Icons.travel_explore_rounded,
        'Checking playback option 1/13...',
        'Juicr is checking built-in playback choices. The numbers show the current option and total options.',
      ),
      (
        Icons.inventory_2_outlined,
        'Playable option found',
        'Juicr found a stream option that matches the current quality pass, for example: found 1 option to load [720P].',
      ),
      (
        Icons.play_arrow_rounded,
        'Trying stream 1/1 [720P]...',
        'Juicr is opening that stream in the selected native player engine.',
      ),
      (
        Icons.account_tree_outlined,
        'Trying stream 1/2 - mirror 1/3 [720P]...',
        'Juicr is trying a specific mirror from a stream group. This keeps the count explicit when mirrors exist.',
      ),
      (
        Icons.refresh_rounded,
        'Refreshing stream',
        'Juicr is reopening the current stream after a stall, error, or manual refresh.',
      ),
      (
        Icons.sync_rounded,
        'Refreshing playback',
        'Juicr is refreshing active playback without changing the title.',
      ),
      (
        Icons.manage_search_rounded,
        'Scanning quality 2/6 [1080P]...',
        'No source opened for the previous quality pass, so Juicr is checking the next quality target.',
      ),
      (
        Icons.video_settings_outlined,
        'Checking native player 1/2 - Media3...',
        'Juicr is checking a native playback engine. If you picked a specific engine, it should only use that engine.',
      ),
      (
        Icons.restore_rounded,
        'Restoring playback',
        'Juicr is bringing playback back after a route change, resume action, or player restoration.',
      ),
      (
        Icons.skip_next_rounded,
        'Opening next episode',
        'Autoplay is moving to the next episode when one is available.',
      ),
      (
        Icons.checklist_rounded,
        'All qualities checked',
        'Every allowed quality pass has been checked and none opened successfully.',
      ),
      (
        Icons.fact_check_outlined,
        'All native players checked',
        'Every allowed native player engine has been checked and none opened successfully.',
      ),
      (
        Icons.error_outline_rounded,
        'All failed',
        'No available source opened successfully, so Juicr closes playback and returns to the details screen.',
      ),
      (
        Icons.error_outline_rounded,
        'Engine-specific failure',
        'When shown, Media3 or libVLC could not open the available source. This means the selected engine failed, not that every engine was tried.',
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          18,
          10,
          18,
          JuicrVisual.bottomSheetBottomBreathingRoom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Built-in sources guide',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Juicr starts without media sources. These switches are optional tools you can enable after checking the source acknowledgements for media responsibility, allowed content, and no bypassing access controls.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: JuicrVisual.iconBadge(
                      context,
                      icon: item.$1,
                      boxSize: 38,
                      iconSize: 18,
                      radius: 14,
                      shadowAlpha: 0.12,
                    ),
                    title: Text(
                      item.$2,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(item.$3),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogBuilderHelpSheet extends StatelessWidget {
  const _CatalogBuilderHelpSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget row(IconData icon, String title, String body) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            JuicrVisual.iconBadge(
              context,
              icon: icon,
              boxSize: 38,
              iconSize: 18,
              radius: 14,
              shadowAlpha: 0.12,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.68),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Catalog Builder guide',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            row(
              Icons.lock_outline_rounded,
              'Parked for later',
              'Catalog Builder is parked as a future local-only feature. Current Juicr releases should not depend on it for Library, browsing, or playback.',
            ),
            row(
              Icons.touch_app_rounded,
              'Original safety shape',
              'If revived, it should stay picker-scoped: exact files chosen by the user, no broad storage permission, no device-wide scanning, and no uploads.',
            ),
            row(
              Icons.movie_creation_outlined,
              'Review before revival',
              'Future work can revisit private shelves, editable details, posters, tags, notes, and preferred engines after the core player and source lanes stay stable on real devices.',
            ),
          ],
        ),
      ),
    );
  }
}

class _AddOnsHelpSheet extends StatelessWidget {
  const _AddOnsHelpSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const items = [
      (
        Icons.play_circle_outline_rounded,
        'Streams',
        'Can add extra playback options from a trusted add-on. Direct and account-backed choices can coexist as fallbacks; Advanced P2P stays separate unless you enable it.',
      ),
      (
        Icons.info_outline_rounded,
        'Details',
        'Can improve title pages with posters, descriptions, metadata, or episode lists. Use one catalog/details source at a time.',
      ),
      (
        Icons.closed_caption_outlined,
        'Subtitles',
        'Adds caption tracks. Use one subtitle source at a time so caption lists stay clean.',
      ),
      (
        Icons.live_tv_rounded,
        'TV',
        'Adds live TV or channel-style catalogs. Juicr shows TV filters when this source is active, but browsing success does not guarantee every channel can play.',
      ),
      (
        Icons.key_rounded,
        'Account-backed links',
        'Some stream add-ons need account setup before direct playback is available. Advanced P2P stays behind its own controls and consent.',
      ),
      (
        Icons.manage_search_rounded,
        'Needs Check',
        'Juicr could read the manifest, but it did not find a clear capability yet. The add-on may still work after opening a matching catalog or title.',
      ),
      (
        Icons.swap_vert_rounded,
        'Fallback order',
        'Move trusted playback add-ons higher when you want Juicr to try their streams earlier. Catalog/details and subtitles still allow one active source.',
      ),
      (
        Icons.privacy_tip_outlined,
        'Private by default',
        'Juicr redacts private account, source, and playback details from diagnostics. Third-party services may still see requests made to them.',
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          18,
          10,
          18,
          JuicrVisual.bottomSheetBottomBreathingRoom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add-ons guide',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add-ons are third-party manifests you choose to add. Juicr can read what they claim to support, but you decide which sources you trust and enable.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Juicr reads each manifest and explains what it can do in plain language.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.68),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: JuicrVisual.iconBadge(
                      context,
                      icon: item.$1,
                      boxSize: 38,
                      iconSize: 18,
                      radius: 14,
                      shadowAlpha: 0.12,
                    ),
                    title: Text(
                      item.$2,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(item.$3),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonalServersHelpSheet extends StatelessWidget {
  const _PersonalServersHelpSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const items = [
      (
        Icons.dns_rounded,
        'What belongs here',
        'Use this for a media server you control. Personal servers stay separate from built-ins and add-ons.',
      ),
      (
        Icons.verified_user_outlined,
        'Beta means real-world validation',
        'The path is wired through browsing, title pages, and native playback, but different home server setups can behave differently. Keep testing with the server you actually use.',
      ),
      (
        Icons.lock_outline_rounded,
        'Kept on this device',
        'Server addresses, passwords, access keys, and media links stay out of Juicr diagnostics. Password-based server secrets are not kept after sign-in.',
      ),
      (
        Icons.grid_view_rounded,
        'Personal catalog lane',
        'Personal server results can appear in Home and Discovery while staying separate from built-in browsing and add-on catalog/details choices.',
      ),
      (
        Icons.play_circle_outline_rounded,
        'Playback uses Juicr',
        'When a personal item has a direct stream, Juicr sends it through the native player in its own lane instead of mixing it into built-in or add-on fallback paths.',
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          18,
          10,
          18,
          JuicrVisual.bottomSheetBottomBreathingRoom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Personal servers guide',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Connect your own library and keep it in its own lane. Juicr provides the app experience; you manage the server and access.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: JuicrVisual.iconBadge(
                      context,
                      icon: item.$1,
                      boxSize: 38,
                      iconSize: 18,
                      radius: 14,
                      shadowAlpha: 0.12,
                    ),
                    title: Text(
                      item.$2,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(item.$3),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvanceHelpSheet extends StatelessWidget {
  const _AdvanceHelpSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const items = [
      (
        Icons.tune_rounded,
        'Advanced playback',
        'Unlocks power-user controls for Media3, libVLC, retry timing, progress tracking, fallback order, and playback recovery.',
      ),
      (
        Icons.hourglass_bottom_rounded,
        'Failure read time',
        'How long the final failure message stays on screen before Juicr returns to the details page.',
      ),
      (
        Icons.route_rounded,
        'Playback warmup',
        'How many upcoming playback choices Juicr prepares while the current choice is being checked. Higher values can feel faster but use more work up front.',
      ),
      (
        Icons.network_check_rounded,
        'Playback timeout',
        'The base playback wait. Juicr can wait longer for slow, limited, or add-on choices when there are signs of life.',
      ),
      (
        Icons.memory_rounded,
        'Auto playback memory',
        'Fresh avoids previous title history, Balanced avoids recent failures, and Sticky keeps successful choices in play longer. Saved Media3 choices can help libVLC search faster, but libVLC still searches normally when needed.',
      ),
      (
        Icons.more_time_rounded,
        'Fallback progress clock',
        'Saves watch progress from wall time when an engine plays video but does not report a usable media clock. It helps progress tracking without treating quick seeks as full watches by itself.',
      ),
      (
        Icons.restore_rounded,
        'Resume seek retry',
        'How long Juicr keeps retrying saved-position resume while libVLC is still waiting for usable media metadata.',
      ),
      (
        Icons.visibility_off_rounded,
        'Black video watchdog',
        'How long Juicr lets libVLC keep playing with no visible video before reopening or skipping the source.',
      ),
      (
        Icons.health_and_safety_outlined,
        'libVLC startup grace',
        'How long libVLC can stay at zero position while it gathers stream details before Juicr decides whether it is stalled.',
      ),
      (
        Icons.speed_rounded,
        'Stall watchdog',
        'How often Juicr checks whether native playback is moving, paused, buffering, or stuck.',
      ),
      (
        Icons.hourglass_empty_rounded,
        'libVLC handoff pause',
        'A short pause after releasing a stalled libVLC option before Juicr opens the next libVLC option.',
      ),
      (
        Icons.not_interested_rounded,
        'Skip zero-clock source',
        'Moves to the next playback option when libVLC opens but never reports position, duration, or video size after startup. Juicr can retry the same libVLC option once before moving on.',
      ),
      (
        Icons.timer_outlined,
        'libVLC open timeout',
        'The base libVLC open wait. Juicr can add patience for add-ons, account-backed sources, and very high quality streams.',
      ),
      (
        Icons.slow_motion_video_rounded,
        'HLS relay visual grace',
        'How long libVLC can keep waiting for visible video while Juicr is relaying an HLS stream that is still delivering media data.',
      ),
      (
        Icons.smart_display_rounded,
        'Native Media3 surface',
        'Uses Android Media3 directly when the Media3 engine is selected. Turning this off keeps the Media3 timing settings but uses the fallback surface.',
      ),
      (
        Icons.smart_display_rounded,
        'Media3 open timeout',
        'The base Media3 open wait. Juicr can add patience for add-ons, account-backed sources, and very high quality streams.',
      ),
      (
        Icons.tune_rounded,
        'Advanced P2P playback',
        'Advanced P2P playback stays behind explicit consent and an on/off switch. User add-on P2P results and indexer connectors are separate entry points into this same guarded playback lane.',
      ),
      (
        Icons.manage_search_rounded,
        'Indexer connectors',
        'Optional beta connectors can search your own indexer server only when normal playback needs help. They do not replace add-ons, and their server URL/API key stay local.',
      ),
      (
        Icons.pending_actions_rounded,
        'Future playback proof',
        'Planning-only space for future engine controls. Candidates do not become selectable until dependency, license, rollback, and real-device proof are accepted.',
      ),
      (
        Icons.restart_alt_rounded,
        'Reset advanced controls',
        'Restores stable Media3, libVLC, retry, and progress timing defaults without clearing the rest of your playback settings.',
      ),
      (
        Icons.verified_user_outlined,
        'Clear playback shortcuts',
        'Forgets last-working playback choices so Auto starts fresh instead of reusing saved title shortcuts.',
      ),
      (
        Icons.route_outlined,
        'Clear add-on route evidence',
        'Removes recent add-on route diagnostics while keeping add-ons themselves untouched.',
      ),
      (
        Icons.health_and_safety_outlined,
        'Clear playback health samples',
        'Removes stale sample-only playback checks so future availability checks start clean.',
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          18,
          10,
          18,
          JuicrVisual.bottomSheetBottomBreathingRoom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Advanced guide',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: JuicrVisual.iconBadge(
                      context,
                      icon: item.$1,
                      boxSize: 38,
                      iconSize: 18,
                      radius: 14,
                      shadowAlpha: 0.12,
                    ),
                    title: Text(
                      item.$2,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(item.$3),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<_OptionItem<T>> options;
  final T selected;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final maxHeight = mediaQuery.size.height * 0.5;
    const chromeHeight = 84.0;
    final rowHeight =
        options.any(
          (option) => option.subtitle != null && option.subtitle!.isNotEmpty,
        )
        ? 78.0
        : 56.0;
    final estimatedListHeight = options.length * rowHeight;
    final wrapsContent = chromeHeight + estimatedListHeight <= maxHeight;
    Widget optionRow(int index) {
      final option = options[index];
      return JuicrSheetOptionTile(
        label: option.label,
        subtitle: option.subtitle,
        selected: option.value == selected,
        trailing: option.badge == null
            ? null
            : _SettingsBetaPill(label: option.badge!),
        onTap: () => Navigator.of(context).pop(option.value),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          18,
          12,
          18,
          JuicrVisual.bottomSheetBottomBreathingRoom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: wrapsContent
                ? chromeHeight + estimatedListHeight
                : maxHeight,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              if (wrapsContent)
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: options.length,
                  itemBuilder: (context, index) => optionRow(index),
                )
              else
                Flexible(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: options.length,
                    itemBuilder: (context, index) => optionRow(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsBetaPill extends StatelessWidget {
  const _SettingsBetaPill({this.label = 'Beta'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return JuicrBetaPill(label: label);
  }
}

class _ProviderSheetList extends StatelessWidget {
  const _ProviderSheetList({
    required this.providers,
    required this.selected,
    required this.showNativeHealth,
    required this.onChanged,
  });

  final List<ApiProvider> providers;
  final ApiProvider selected;
  final bool showNativeHealth;
  final ValueChanged<ApiProvider> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListView(
      shrinkWrap: true,
      children: [
        for (final provider in providers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: provider.id == AppState.autoNativeProviderId
                ? const _AutoProviderSummary(prominent: true)
                : showNativeHealth
                ? _ProviderHealthSummary(
                    provider: provider,
                    health: AppState.nativeProviderHealthDetailsFor(
                      provider.id,
                    ),
                    prominent: true,
                  )
                : Text(
                    provider.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
            trailing: provider.id == selected.id
                ? Icon(Icons.check_circle, color: colorScheme.primary)
                : Icon(
                    Icons.circle_outlined,
                    color: colorScheme.primary.withValues(alpha: 0.64),
                  ),
            onTap: () => onChanged(provider),
          ),
      ],
    );
  }
}

class _ProviderHealthSummary extends StatelessWidget {
  const _ProviderHealthSummary({
    required this.provider,
    required this.health,
    this.prominent = false,
  });

  final ApiProvider provider;
  final NativeProviderHealth health;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = health.status;
    final providerTextColor = _providerHealthTextColor(context, status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProviderHealthDot(status: status),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            provider.name,
            overflow: TextOverflow.ellipsis,
            style:
                (prominent
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.bodyMedium)
                    ?.copyWith(
                      color: providerTextColor,
                      fontWeight: FontWeight.w800,
                    ),
          ),
        ),
        const SizedBox(width: 10),
        _ProviderHealthPill(health: health),
      ],
    );
  }
}

class _AutoProviderSummary extends StatelessWidget {
  const _AutoProviderSummary({this.prominent = false});

  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.auto_awesome_rounded,
          size: prominent ? 18 : 16,
          color: colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'Auto',
            overflow: TextOverflow.ellipsis,
            style:
                (prominent
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.bodyMedium)
                    ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: JuicrVisual.badgeDecoration(
            colorScheme,
            colorScheme.primary,
          ),
          child: Text(
            'Smart pick',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProviderCheckingSummary extends StatelessWidget {
  const _ProviderCheckingSummary({required this.provider});

  final ApiProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 18,
          child: Center(
            child: SizedBox.square(
              dimension: 10,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            provider.name,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: JuicrVisual.badgeDecoration(
            colorScheme,
            colorScheme.primary,
          ),
          child: Text(
            'Checking',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProviderHealthPill extends StatelessWidget {
  const _ProviderHealthPill({required this.health});

  final NativeProviderHealth health;

  @override
  Widget build(BuildContext context) {
    final status = health.status;
    final color = _providerHealthColor(context, status);
    final isOutlined =
        status == NativeProviderHealthStatus.untested ||
        status == NativeProviderHealthStatus.checkedNoSample;
    return AnimatedContainer(
      duration: JuicrVisual.snapDuration,
      curve: JuicrVisual.snapCurve,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: JuicrVisual.badgeDecoration(
        Theme.of(context).colorScheme,
        color,
        outlined: isOutlined,
      ),
      child: AnimatedDefaultTextStyle(
        duration: JuicrVisual.snapDuration,
        curve: JuicrVisual.snapCurve,
        style:
            Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
            ) ??
            TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
            ),
        child: Text(_providerHealthPillLabel(health)),
      ),
    );
  }
}

class _ProviderHealthDot extends StatefulWidget {
  const _ProviderHealthDot({required this.status});

  final NativeProviderHealthStatus status;

  @override
  State<_ProviderHealthDot> createState() => _ProviderHealthDotState();
}

class _ProviderHealthDotState extends State<_ProviderHealthDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _ProviderHealthDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (_pulses(widget.status)) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _providerHealthColor(context, widget.status);
    if (!_pulses(widget.status)) {
      return _Dot(color: color, status: widget.status, pulse: 0);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return _Dot(
          color: color,
          status: widget.status,
          pulse: Curves.easeInOut.transform(_controller.value),
        );
      },
    );
  }

  bool _pulses(NativeProviderHealthStatus status) {
    return status == NativeProviderHealthStatus.ready ||
        status == NativeProviderHealthStatus.slow ||
        status == NativeProviderHealthStatus.failing;
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.status, required this.pulse});

  final Color color;
  final NativeProviderHealthStatus status;
  final double pulse;

  @override
  Widget build(BuildContext context) {
    final isOutlined =
        status == NativeProviderHealthStatus.untested ||
        status == NativeProviderHealthStatus.checkedNoSample;
    final size = 9.0 + (pulse * 2);
    return SizedBox.square(
      dimension: 18,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: isOutlined ? 0.18 : 1),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12 + pulse * 0.08),
                blurRadius: 4 + pulse * 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _providerHealthColor(
  BuildContext context,
  NativeProviderHealthStatus status,
) {
  return switch (status) {
    NativeProviderHealthStatus.ready => const Color(0xFF36D98B),
    NativeProviderHealthStatus.slow => const Color(0xFFFF9F43),
    NativeProviderHealthStatus.limited => const Color(0xFFFFC83D),
    NativeProviderHealthStatus.protected => const Color(0xFFFFC83D),
    NativeProviderHealthStatus.noSource => const Color(0xFFFFC83D),
    NativeProviderHealthStatus.failing => const Color(0xFFFF5C70),
    NativeProviderHealthStatus.checkedNoSample => const Color(0xFFFFC83D),
    NativeProviderHealthStatus.untested => const Color(0xFFFFC83D),
  };
}

Color? _providerHealthTextColor(
  BuildContext context,
  NativeProviderHealthStatus status,
) {
  final colorScheme = Theme.of(context).colorScheme;
  return switch (status) {
    NativeProviderHealthStatus.untested ||
    NativeProviderHealthStatus.checkedNoSample => null,
    _ => null,
  };
}

String _providerHealthPillLabel(NativeProviderHealth health) {
  return switch (health.status) {
    NativeProviderHealthStatus.ready => 'Available',
    NativeProviderHealthStatus.slow => 'Slow',
    NativeProviderHealthStatus.limited => 'Limited',
    NativeProviderHealthStatus.noSource => 'Limited',
    NativeProviderHealthStatus.failing => 'Offline',
    NativeProviderHealthStatus.untested ||
    NativeProviderHealthStatus.checkedNoSample ||
    NativeProviderHealthStatus.protected => 'Not checked',
  };
}

String _providerHealthPillLabelLegacy(NativeProviderHealth health) {
  final sourceCount = health.sourceCount;
  if (sourceCount == null ||
      health.status == NativeProviderHealthStatus.untested ||
      health.status == NativeProviderHealthStatus.checkedNoSample ||
      health.status == NativeProviderHealthStatus.protected ||
      health.status == NativeProviderHealthStatus.noSource ||
      health.status == NativeProviderHealthStatus.failing) {
    return health.status.label;
  }
  if (health.status == NativeProviderHealthStatus.slow && sourceCount <= 0) {
    return 'Slow · Probe failed';
  }
  final sourceLabel = sourceCount == 1 ? 'choice' : 'choices';
  if (health.status == NativeProviderHealthStatus.ready) {
    return 'Sample · $sourceCount $sourceLabel';
  }
  if (health.status == NativeProviderHealthStatus.slow) {
    return 'Slow sample · $sourceCount $sourceLabel';
  }
  return '${health.status.label} · $sourceCount $sourceLabel';
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          JuicrVisual.iconBadge(
            context,
            icon: icon,
            boxSize: 30,
            iconSize: 16,
            radius: 12,
            iconColor: colorScheme.onSurfaceVariant,
            shadowAlpha: 0.08,
            glowAlpha: 0.02,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      value: selected ? 'Current theme' : null,
      hint: selected ? 'Selected theme' : 'Choose $label theme',
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: JuicrVisual.elevatedIconDecoration(
                      colorScheme,
                      radius: 18,
                      shadowAlpha: selected ? 0.18 : 0.1,
                      glowAlpha: selected ? 0.08 : 0.02,
                    ),
                    child: Icon(icon, color: iconColor, size: 28),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccentThemeCard extends StatelessWidget {
  const _AccentThemeCard({
    required this.selectedId,
    required this.customColor,
    required this.onSelected,
    required this.onCustomSelected,
    this.enabled = true,
  });

  final String selectedId;
  final Color customColor;
  final ValueChanged<String> onSelected;
  final VoidCallback onCustomSelected;
  final bool enabled;

  static const _options = [
    _AccentOption(AppState.accentGreen, 'Green', Color(0xFF1DB954)),
    _AccentOption(AppState.accentPurple, 'Purple', Color(0xFF9B6DFF)),
    _AccentOption(AppState.accentOcean, 'Ocean', Color(0xFF00A8CC)),
    _AccentOption(AppState.accentAmber, 'Amber', Color(0xFFFFB703)),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : 0.48,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Accent color',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose the app highlight color',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final option in _options) ...[
                  Expanded(
                    child: _AccentChoice(
                      label: option.label,
                      color: option.color,
                      selected: selectedId == option.id,
                      onTap: enabled ? () => onSelected(option.id) : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: _AccentChoice(
                    label: 'Custom',
                    color: customColor,
                    selected: selectedId == AppState.accentCustom,
                    onTap: enabled ? onCustomSelected : null,
                    custom: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccentOption {
  const _AccentOption(this.id, this.label, this.color);

  final String id;
  final String label;
  final Color color;
}

class _AccentChoice extends StatelessWidget {
  const _AccentChoice({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.custom = false,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final bool custom;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: '$label accent color',
      value: selected ? 'Current accent' : null,
      hint: selected ? 'Selected accent color' : 'Choose $label accent color',
      child: Tooltip(
        message: '$label accent color',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: JuicrVisual.elevatedIconDecoration(
                    colorScheme,
                    radius: 15,
                    shadowAlpha: selected ? 0.18 : 0.1,
                  ),
                  child: Center(
                    child: custom
                        ? Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SweepGradient(
                                colors: [
                                  Color(0xFFFF3B30),
                                  Color(0xFFFFCC00),
                                  Color(0xFF34C759),
                                  Color(0xFF00C7BE),
                                  Color(0xFF5856D6),
                                  Color(0xFFFF2D55),
                                  Color(0xFFFF3B30),
                                ],
                              ),
                            ),
                            child: const Icon(
                              Icons.palette_outlined,
                              size: 14,
                              color: Colors.white,
                            ),
                          )
                        : Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? color : colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneralSwitchCard extends StatelessWidget {
  const _GeneralSwitchCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.badgeText,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: _GeneralSwitchTile(
        title: title,
        subtitle: subtitle,
        value: value,
        onChanged: onChanged,
        badgeText: badgeText,
      ),
    );
  }
}

class _GeneralSwitchTile extends StatelessWidget {
  const _GeneralSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.badgeText,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.fromLTRB(18, 8, 14, 8),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (badgeText != null) ...[
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: JuicrVisual.badgeDecoration(
                colorScheme,
                colorScheme.primary,
                outlined: true,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  badgeText!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          subtitle,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _GeneralLanguageCard extends StatelessWidget {
  const _GeneralLanguageCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(child: _GeneralLanguageTile(onTap: onTap));
  }
}

class _GeneralLanguageTile extends StatelessWidget {
  const _GeneralLanguageTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(JuicrVisual.cardRadius),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Language',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose the app display language',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'System default',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneralValueCard extends StatelessWidget {
  const _GeneralValueCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: _GeneralValueTile(
        title: title,
        subtitle: subtitle,
        value: value,
        onTap: onTap,
      ),
    );
  }
}

class _GeneralValueTile extends StatelessWidget {
  const _GeneralValueTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(JuicrVisual.cardRadius),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              value,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: JuicrVisual.iconBadge(
        context,
        icon: icon,
        boxSize: 38,
        iconSize: 18,
        radius: 14,
        shadowAlpha: 0.12,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
