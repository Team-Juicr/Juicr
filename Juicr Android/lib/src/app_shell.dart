import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ad_policy.dart';
import 'app_state.dart';
import 'catalog_page.dart';
import 'diagnostic_log.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'providers_page.dart';
import 'visual_style.dart';

const _fluidNavigationItems = [
  _NavItem(label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home),
  _NavItem(
    label: 'Discovery',
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore_outlined,
  ),
  _NavItem(
    label: 'Library',
    icon: Icons.favorite_border,
    selectedIcon: Icons.favorite,
  ),
  _NavItem(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _exitBackPressWindow = Duration(seconds: 2);
  static const _tabScreenDiagnosticWindow = Duration(milliseconds: 900);
  static const _sectionTransitionDuration = Duration(milliseconds: 320);
  static const _pageCount = 4;
  static const _bottomTabMaxIndex = 3;

  final Map<int, Widget> _pageCache = <int, Widget>{};
  late final PageController _pageController;
  Timer? _adSlotDelayTimer;
  DateTime? _lastExitBackPressedAt;
  DateTime? _lastTabScreenDiagnosticAt;
  int? _scheduledPageSyncTarget;
  String _scheduledPageSyncReason = 'unknown';
  bool _showAdSlot = false;
  bool _pageSyncScheduled = false;
  bool _scheduledPageSyncAnimated = false;

  @override
  void initState() {
    super.initState();
    final startupTab = AppState.settingsIntent.value == 'addons'
        ? 3
        : AppState.preferredStartupTabIndex()
              .clamp(0, _bottomTabMaxIndex)
              .toInt();
    AppState.shellTab.value = startupTab;
    _pageCache[startupTab] = _buildPage(startupTab);
    _pageController = PageController(initialPage: startupTab);
    AppState.shellTab.addListener(_syncTab);
    _adSlotDelayTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _showAdSlot = true);
    });
    DiagnosticLog.add('app shell init tab=${AppState.shellTab.value}');
  }

  @override
  void dispose() {
    AppState.shellTab.removeListener(_syncTab);
    _pageController.dispose();
    _adSlotDelayTimer?.cancel();
    super.dispose();
  }

  void _syncTab() {
    if (!mounted) return;
    final target = AppState.shellTab.value.clamp(0, _pageCount - 1).toInt();
    if (target != AppState.shellTab.value) {
      AppState.shellTab.value = target;
      return;
    }
    _pageCache.putIfAbsent(target, () => _buildPage(target));
    setState(() {});
    _schedulePageControllerSync(target, animate: true, reason: 'tab_change');
  }

  void _schedulePageControllerSync(
    int target, {
    required bool animate,
    required String reason,
  }) {
    _scheduledPageSyncTarget = target.clamp(0, _pageCount - 1).toInt();
    if (animate || !_scheduledPageSyncAnimated) {
      _scheduledPageSyncReason = reason;
    }
    _scheduledPageSyncAnimated = _scheduledPageSyncAnimated || animate;
    if (_pageSyncScheduled) return;
    _pageSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageSyncScheduled = false;
      final target = _scheduledPageSyncTarget;
      final reason = _scheduledPageSyncReason;
      final shouldAnimate =
          _scheduledPageSyncAnimated && !AppState.reduceMotion.value;
      _scheduledPageSyncTarget = null;
      _scheduledPageSyncReason = 'unknown';
      _scheduledPageSyncAnimated = false;
      if (!mounted || target == null || !_pageController.hasClients) return;
      try {
        final page = _pageController.page;
        if (page != null && (page - target).abs() < 0.01) return;
        DiagnosticLog.add(
          'app shell page sync reason=$reason target=$target animated=$shouldAnimate',
        );
        if (shouldAnimate) {
          unawaited(
            _pageController
                .animateToPage(
                  target,
                  duration: _sectionTransitionDuration,
                  curve: Curves.easeOutCubic,
                )
                .catchError((Object error, StackTrace stack) {
                  DiagnosticLog.asyncError(error, stack);
                }),
          );
        } else {
          _pageController.jumpToPage(target);
        }
      } catch (error, stack) {
        DiagnosticLog.asyncError(error, stack);
      }
    });
  }

  Widget _buildPage(int index) {
    return switch (index) {
      0 => const _KeepAlivePage(child: HomePage()),
      1 => const _KeepAlivePage(child: CatalogPage()),
      2 => const _KeepAlivePage(child: LibraryPage()),
      _ => const _KeepAlivePage(child: SettingsPage()),
    };
  }

  void _handleExitBackPress() {
    final now = DateTime.now();
    final lastPressedAt = _lastExitBackPressedAt;
    final shouldExit =
        lastPressedAt != null &&
        now.difference(lastPressedAt) <= _exitBackPressWindow;
    if (shouldExit) {
      DiagnosticLog.add('app shell exit confirmed by second back press');
      SystemNavigator.pop();
      return;
    }

    _lastExitBackPressedAt = now;
    DiagnosticLog.add('app shell exit armed by first back press');
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Go back again to exit Juicr.')),
      );
  }

  void _handleTabSelected(int index) {
    if (index == AppState.shellTab.value) return;
    AppState.markUserInteraction('tab');
    if (AppState.hapticsEnabled.value) {
      HapticFeedback.selectionClick();
    }
    final now = DateTime.now();
    final lastScreenDiagnostic = _lastTabScreenDiagnosticAt;
    if (lastScreenDiagnostic == null ||
        now.difference(lastScreenDiagnostic) >= _tabScreenDiagnosticWindow) {
      _lastTabScreenDiagnosticAt = now;
      DiagnosticLog.screen(context, 'AppShell before tab tap');
    }
    DiagnosticLog.add(
      'bottom nav tap index=$index current=${AppState.shellTab.value}',
    );
    AppState.shellTab.value = index;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppState.shellTab,
      builder: (context, tabIndex, _) {
        final currentPage = tabIndex.clamp(0, _pageCount - 1).toInt();
        final selectedIndex = currentPage.clamp(0, _bottomTabMaxIndex).toInt();
        _pageCache.putIfAbsent(currentPage, () => _buildPage(currentPage));
        _schedulePageControllerSync(
          currentPage,
          animate: false,
          reason: 'build_sync',
        );
        return ValueListenableBuilder<String>(
          valueListenable: AppState.navigationStyle,
          builder: (context, navigationStyle, __) {
            return ValueListenableBuilder<bool>(
              valueListenable: AppState.reduceMotion,
              builder: (context, reduceMotion, ___) {
                final landscape =
                    MediaQuery.orientationOf(context) == Orientation.landscape;
                final pageBody = PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (var index = 0; index < _pageCount; index += 1)
                      _pageCache.putIfAbsent(index, () => _buildPage(index)),
                  ],
                );
                final shellBody = landscape
                    ? Row(
                        children: [
                          _FluidNavigationRail(
                            selectedIndex: selectedIndex,
                            labelStyle: navigationStyle,
                            reduceMotion: reduceMotion,
                            onSelected: _handleTabSelected,
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(child: pageBody),
                                if (_showAdSlot)
                                  const JuicrBannerAdSlot(
                                    placement: 'shell_bottom_landscape',
                                  ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : pageBody;
                return PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, __) {
                    if (didPop) return;
                    _handleExitBackPress();
                  },
                  child: Scaffold(
                    body: shellBody,
                    bottomNavigationBar: landscape
                        ? null
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_showAdSlot)
                                const JuicrBannerAdSlot(
                                  placement: 'shell_bottom',
                                ),
                              _FluidBottomNavigation(
                                selectedIndex: selectedIndex,
                                labelStyle: navigationStyle,
                                reduceMotion: reduceMotion,
                                onSelected: _handleTabSelected,
                              ),
                            ],
                          ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _FluidBottomNavigation extends StatelessWidget {
  const _FluidBottomNavigation({
    required this.selectedIndex,
    required this.labelStyle,
    required this.reduceMotion,
    required this.onSelected,
  });

  final int selectedIndex;
  final String labelStyle;
  final bool reduceMotion;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = colorScheme.surfaceContainerLowest;
    return SafeArea(
      top: false,
      child: ColoredBox(
        color: background,
        child: SizedBox(
          height: 76,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final clampedIndex = selectedIndex
                  .clamp(0, _fluidNavigationItems.length - 1)
                  .toInt();
              return Row(
                children: [
                  for (
                    var index = 0;
                    index < _fluidNavigationItems.length;
                    index++
                  )
                    Expanded(
                      child: _FluidNavButton(
                        item: _fluidNavigationItems[index],
                        selected: index == clampedIndex,
                        labelStyle: labelStyle,
                        reduceMotion: reduceMotion,
                        onTap: () => onSelected(index),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FluidNavigationRail extends StatelessWidget {
  const _FluidNavigationRail({
    required this.selectedIndex,
    required this.labelStyle,
    required this.reduceMotion,
    required this.onSelected,
  });

  final int selectedIndex;
  final String labelStyle;
  final bool reduceMotion;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = colorScheme.surfaceContainerLowest;
    final compact = JuicrVisual.compactLandscape(context);
    final clampedIndex = selectedIndex
        .clamp(0, _fluidNavigationItems.length - 1)
        .toInt();
    return SafeArea(
      right: false,
      child: ColoredBox(
        color: background,
        child: SizedBox(
          width: compact ? 74 : 92,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < _fluidNavigationItems.length; index++)
                _FluidRailButton(
                  item: _fluidNavigationItems[index],
                  selected: index == clampedIndex,
                  labelStyle: labelStyle,
                  reduceMotion: reduceMotion,
                  onTap: () => onSelected(index),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FluidRailButton extends StatelessWidget {
  const _FluidRailButton({
    required this.item,
    required this.selected,
    required this.labelStyle,
    required this.reduceMotion,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final String labelStyle;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = colorScheme.primary;
    final inactiveColor = colorScheme.onSurface.withValues(alpha: 0.62);
    final compact = JuicrVisual.compactLandscape(context);
    final showLabel =
        labelStyle == 'always' || (labelStyle == 'selected' && selected);
    final animationDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: item.label,
      value: selected ? 'Current tab' : null,
      hint: selected ? 'Selected tab' : 'Open ${item.label} tab',
      child: Tooltip(
        message: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ExcludeSemantics(
            child: SizedBox(
              height: compact ? (showLabel ? 58 : 48) : (showLabel ? 72 : 58),
              width: double.infinity,
              child: AnimatedContainer(
                duration: animationDuration,
                curve: Curves.easeOutCubic,
                margin: EdgeInsets.symmetric(
                  horizontal: compact ? 6 : 8,
                  vertical: compact ? 3 : 4,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? activeColor.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(compact ? 16 : 18),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: animationDuration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.82,
                            end: 1,
                          ).animate(animation),
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: Icon(
                        selected ? item.selectedIcon : item.icon,
                        key: ValueKey('rail-${item.label}-$selected'),
                        color: selected ? activeColor : inactiveColor,
                        size: compact ? 20 : (selected ? 22 : 24),
                      ),
                    ),
                    AnimatedContainer(
                      duration: animationDuration,
                      height: showLabel ? (compact ? 5 : 7) : 0,
                    ),
                    AnimatedOpacity(
                      duration: animationDuration,
                      opacity: showLabel ? 1 : 0,
                      child: AnimatedDefaultTextStyle(
                        duration: animationDuration,
                        curve: Curves.easeOutCubic,
                        style: TextStyle(
                          color: selected ? activeColor : inactiveColor,
                          fontSize: compact ? 9.5 : 10.5,
                          fontWeight: selected
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                        ),
                      ),
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

class _FluidNavButton extends StatelessWidget {
  const _FluidNavButton({
    required this.item,
    required this.selected,
    required this.labelStyle,
    required this.reduceMotion,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final String labelStyle;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = colorScheme.primary;
    final inactiveColor = colorScheme.onSurface.withValues(alpha: 0.62);
    final showLabel =
        labelStyle == 'always' || (labelStyle == 'selected' && selected);
    final animationDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: item.label,
      value: selected ? 'Current tab' : null,
      hint: selected ? 'Selected tab' : 'Open ${item.label} tab',
      child: Tooltip(
        message: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                SizedBox(
                  width: 42,
                  height: 42,
                  child: Center(
                    child: AnimatedScale(
                      scale: selected ? 1.04 : 1,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      child: AnimatedSwitcher(
                        duration: animationDuration,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.82,
                              end: 1,
                            ).animate(animation),
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: Icon(
                          selected ? item.selectedIcon : item.icon,
                          key: ValueKey('${item.label}-$selected'),
                          color: selected ? activeColor : inactiveColor,
                          size: selected ? 21 : 24,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedOpacity(
                  duration: animationDuration,
                  opacity: showLabel ? 1 : 0,
                  child: AnimatedDefaultTextStyle(
                    duration: animationDuration,
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      color: selected ? activeColor : inactiveColor,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    ),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                    ),
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

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin<_KeepAlivePage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
