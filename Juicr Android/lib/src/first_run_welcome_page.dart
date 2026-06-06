import 'package:flutter/material.dart';

import 'app_state.dart';
import 'diagnostic_log.dart';
import 'visual_style.dart';

class FirstRunWelcomePage extends StatefulWidget {
  const FirstRunWelcomePage({super.key});

  @override
  State<FirstRunWelcomePage> createState() => _FirstRunWelcomePageState();
}

class _FirstRunWelcomePageState extends State<FirstRunWelcomePage> {
  final Set<int> _accepted = <int>{};

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
    AppState.markFirstRunWelcomeSeen();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
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
                for (var index = 0; index < _acknowledgements.length; index++)
                  _WelcomeAcknowledgementTile(
                    acknowledgement: _acknowledgements[index],
                    value: _accepted.contains(index),
                    onChanged: (value) => _toggle(index, value),
                  ),
                const SizedBox(height: 12),
                Text(
                  _allAccepted
                      ? 'Thanks. You can enter Juicr now.'
                      : 'Check each acknowledgement to continue.',
                  style: textTheme.bodySmall?.copyWith(
                    color: _allAccepted
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.56),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed:
                      _allAccepted ? () => _enterApp(openAddOns: true) : null,
                  icon: const Icon(Icons.extension_rounded),
                  label: const Text('Set up add-ons'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed:
                      _allAccepted ? () => _enterApp(openAddOns: false) : null,
                  child: const Text('I will set it up manually later'),
                ),
              ],
            ),
          ),
        ),
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
    required this.onChanged,
  });

  final _WelcomeAcknowledgement acknowledgement;
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        checked: value,
        label: acknowledgement.title,
        hint: value ? 'Acknowledged' : 'Tap to acknowledge',
        child: ExcludeSemantics(
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
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
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
    );
  }
}
