import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'diagnostic_log.dart';
import 'visual_style.dart';

int? firstRunAcknowledgementTargetIndex({
  required int index,
  required TraversalDirection direction,
  required int columns,
  required int itemCount,
}) {
  if (columns <= 0 || index < 0 || index >= itemCount) return null;
  final candidate = switch (direction) {
    TraversalDirection.left =>
      columns > 1 && index % columns > 0 ? index - 1 : null,
    TraversalDirection.right =>
      columns > 1 && index % columns < columns - 1 ? index + 1 : null,
    TraversalDirection.up => index - columns,
    TraversalDirection.down => index + columns,
  };
  return candidate != null && candidate >= 0 && candidate < itemCount
      ? candidate
      : null;
}

class FirstRunWelcomePage extends StatefulWidget {
  const FirstRunWelcomePage({super.key});

  @override
  State<FirstRunWelcomePage> createState() => _FirstRunWelcomePageState();
}

class _FirstRunWelcomePageState extends State<FirstRunWelcomePage> {
  final Set<int> _accepted = <int>{};
  final List<FocusNode> _acknowledgementFocusNodes = List<FocusNode>.generate(
    5,
    (index) => FocusNode(debugLabel: 'first_run_acknowledgement_$index'),
  );
  final FocusNode _manualSetupFocusNode =
      FocusNode(debugLabel: 'first_run_manual_setup');
  final FocusNode _addOnSetupFocusNode =
      FocusNode(debugLabel: 'first_run_addon_setup');

  static const _acknowledgements = <_WelcomeAcknowledgement>[
    _WelcomeAcknowledgement(
      icon: Icons.cloud_off_rounded,
      title: 'Juicr does not provide media',
      text:
          'Juicr does not host, sell, upload, or supply movies, shows, animation, live TV, or copyrighted media.',
    ),
    _WelcomeAcknowledgement(
      icon: Icons.extension_rounded,
      title: 'Sources are your choice',
      text:
          'Built-in helpers and third-party add-ons are optional tools. You choose what to enable and which add-ons to trust.',
    ),
    _WelcomeAcknowledgement(
      icon: Icons.verified_user_outlined,
      title: 'Use only allowed content',
      text:
          'You are responsible for subscriptions, permissions, local laws, and only accessing content you are allowed to use.',
    ),
    _WelcomeAcknowledgement(
      icon: Icons.lock_outline_rounded,
      title: 'No bypassing protections',
      text:
          'Do not use Juicr or add-ons to bypass DRM, paywalls, site protections, geoblocks, subscriptions, or access controls.',
    ),
    _WelcomeAcknowledgement(
      icon: Icons.public_rounded,
      title: 'Add-ons may contact outside services',
      text:
          'Third-party add-ons can make network requests outside Juicr. Those services may see network information such as your IP address.',
    ),
  ];

  bool get _allAccepted => _accepted.length == _acknowledgements.length;

  @override
  void dispose() {
    for (final node in _acknowledgementFocusNodes) {
      node.dispose();
    }
    _manualSetupFocusNode.dispose();
    _addOnSetupFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleAcknowledgementKey(
    int index,
    KeyEvent event, {
    required int columns,
  }) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    FocusNode? target;
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    final targetIndex = direction == null
        ? null
        : firstRunAcknowledgementTargetIndex(
            index: index,
            direction: direction,
            columns: columns,
            itemCount: _acknowledgementFocusNodes.length,
          );
    if (targetIndex != null) {
      target = _acknowledgementFocusNodes[targetIndex];
    } else if (index == _acknowledgementFocusNodes.length - 1 &&
        (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            (columns > 1 &&
                event.logicalKey == LogicalKeyboardKey.arrowRight))) {
      target = _manualSetupFocusNode;
    } else if (columns > 1 &&
        index == _acknowledgementFocusNodes.length - 2 &&
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      target = _addOnSetupFocusNode;
    }
    if (target == null || !target.canRequestFocus) {
      return KeyEventResult.ignored;
    }
    target.requestFocus();
    return KeyEventResult.handled;
  }

  void _toggle(int index, bool? value) {
    setState(() {
      if (value == true) {
        _accepted.add(index);
      } else {
        _accepted.remove(index);
      }
    });
  }

  void _enterApp({required bool openAddOns}) {
    DiagnosticLog.add(
      'first run welcome accepted action=${openAddOns ? 'open_addons' : 'manual'}',
    );
    if (openAddOns) AppState.openAddOnsSettings();
    AppState.requestFirstRunGuide(afterAddOns: openAddOns);
    AppState.markFirstRunWelcomeSeen();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wideLayout = constraints.maxWidth >= 900;
            return SizedBox(
              width: double.infinity,
              child: FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    wideLayout ? 48 : 22,
                    wideLayout ? 40 : 28,
                    wideLayout ? 48 : 22,
                    24,
                  ),
                  children: [
                    Text(
                      'Welcome to Juicr',
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Juicr is a media tool: a clean way to browse, organize, and play sources you choose to use.',
                      style: textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Before the app opens',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Builder(
                      builder: (context) {
                        final items = List<Widget>.generate(
                          _acknowledgements.length + 1,
                          (index) {
                            if (index == _acknowledgements.length) {
                              return FocusTraversalOrder(
                                order: const NumericFocusOrder(5),
                                child: _WelcomeActions(
                                  allAccepted: _allAccepted,
                                  manualSetupFocusNode: _manualSetupFocusNode,
                                  addOnSetupFocusNode: _addOnSetupFocusNode,
                                  onSetUpAddOns: () =>
                                      _enterApp(openAddOns: true),
                                  onEnterManually: () =>
                                      _enterApp(openAddOns: false),
                                ),
                              );
                            }
                            return FocusTraversalOrder(
                              order: NumericFocusOrder(index.toDouble()),
                              child: _WelcomeAcknowledgementTile(
                                acknowledgement: _acknowledgements[index],
                                value: _accepted.contains(index),
                                autofocus: index == 0,
                                focusNode: _acknowledgementFocusNodes[index],
                                onKeyEvent: (event) =>
                                    _handleAcknowledgementKey(
                                  index,
                                  event,
                                  columns: wideLayout ? 2 : 1,
                                ),
                                onChanged: (value) => _toggle(index, value),
                              ),
                            );
                          },
                        );
                        if (!wideLayout) {
                          return Column(
                            children: [
                              for (var index = 0; index < items.length; index++)
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index == items.length - 1 ? 0 : 10,
                                  ),
                                  child: items[index],
                                ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            for (var index = 0;
                                index < items.length;
                                index += 2)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: index + 2 >= items.length ? 0 : 10,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: items[index]),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: index + 1 < items.length
                                          ? items[index + 1]
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WelcomeActions extends StatelessWidget {
  const _WelcomeActions({
    required this.allAccepted,
    required this.manualSetupFocusNode,
    required this.addOnSetupFocusNode,
    required this.onSetUpAddOns,
    required this.onEnterManually,
  });

  final bool allAccepted;
  final FocusNode manualSetupFocusNode;
  final FocusNode addOnSetupFocusNode;
  final VoidCallback onSetUpAddOns;
  final VoidCallback onEnterManually;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            allAccepted
                ? 'Thanks. You can enter Juicr now.'
                : 'Check each acknowledgement to continue.',
            textAlign: TextAlign.end,
            style: textTheme.bodySmall?.copyWith(
              color: allAccepted
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.56),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              TextButton(
                focusNode: manualSetupFocusNode,
                onPressed: allAccepted ? onEnterManually : null,
                child: const Text('Set up manually later'),
              ),
              FilledButton.icon(
                focusNode: addOnSetupFocusNode,
                onPressed: allAccepted ? onSetUpAddOns : null,
                icon: const Icon(Icons.extension_rounded),
                label: const Text('Set up add-ons'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WelcomeAcknowledgement {
  const _WelcomeAcknowledgement({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;
}

class _WelcomeAcknowledgementTile extends StatelessWidget {
  const _WelcomeAcknowledgementTile({
    required this.acknowledgement,
    required this.value,
    required this.autofocus,
    required this.focusNode,
    required this.onKeyEvent,
    required this.onChanged,
  });

  final _WelcomeAcknowledgement acknowledgement;
  final bool value;
  final bool autofocus;
  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
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
        child: Focus(
          onKeyEvent: (node, event) => onKeyEvent(event),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onChanged(!value),
            child: Container(
              decoration: JuicrVisual.elevatedCardDecoration(
                colorScheme,
                radius: 16,
                color: value
                    ? colorScheme.primary.withValues(alpha: 0.14)
                    : colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.48,
                      ),
                borderAlpha: 0,
                shadowAlpha: value ? 0.1 : 0.05,
              ),
              padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      acknowledgement.icon,
                      size: 19,
                      color: value
                          ? colorScheme.primary
                          : colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          acknowledgement.title,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          acknowledgement.text,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.68,
                                    ),
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Checkbox(
                    value: value,
                    focusNode: focusNode,
                    autofocus: autofocus,
                    onChanged: onChanged,
                    semanticLabel: acknowledgement.title,
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
