import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';

class JuicrVisual {
  const JuicrVisual._();

  static const double cardRadius = 16;
  static const double cardStrokeWidth = 0.5;
  static const double softRadius = 14;
  static const double pillRadius = 999;
  static const double topLevelTitleSpacing = 22;
  static const double topLevelToolbarHeight = 64;
  static const double topLevelEmptyTitleTop = 19;
  static const double bottomSheetTopRadius = 28;
  static const double bottomSheetBottomBreathingRoom = 28;
  static const double bottomSheetMaxHeightFactor = 0.5;
  static const double bottomSheetLandscapeMaxHeightFactor = 0.78;
  static const BorderRadius bottomSheetTopBorderRadius = BorderRadius.vertical(
    top: Radius.circular(bottomSheetTopRadius),
  );
  static const BorderRadius bottomSheetFloatingBorderRadius = BorderRadius.all(
    Radius.circular(bottomSheetTopRadius),
  );
  static const ShapeBorder bottomSheetShape = RoundedRectangleBorder(
    borderRadius: bottomSheetTopBorderRadius,
  );
  static const Duration snapDuration = Duration(milliseconds: 180);
  static const Curve snapCurve = Curves.easeOutCubic;
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 10,
  );
  static const TextStyle buttonTextStyle = TextStyle(
    fontWeight: FontWeight.w900,
    letterSpacing: 0.1,
  );

  static bool compactLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height;
  }

  static double topLevelTitleSpacingFor(BuildContext context) {
    return compactLandscape(context) ? 16 : topLevelTitleSpacing;
  }

  static double topLevelToolbarHeightFor(BuildContext context) {
    return compactLandscape(context) ? 54 : topLevelToolbarHeight;
  }

  static double topLevelHorizontalInsetFor(BuildContext context) {
    return compactLandscape(context) ? 14 : 18;
  }

  static EdgeInsets topLevelListPaddingFor(
    BuildContext context, {
    double top = 0,
    double bottom = 24,
  }) {
    final inset = topLevelHorizontalInsetFor(context);
    return EdgeInsets.fromLTRB(inset, top, inset, bottom);
  }

  static double bottomSheetMaxHeight(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final landscape = bottomSheetUsesFloatingLayout(context);
    return mediaQuery.size.height *
        (landscape
            ? bottomSheetLandscapeMaxHeightFactor
            : bottomSheetMaxHeightFactor);
  }

  static bool bottomSheetUsesFloatingLayout(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height;
  }

  static BoxConstraints bottomSheetFrameConstraints(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final floating = bottomSheetUsesFloatingLayout(context);
    return BoxConstraints(
      maxWidth: floating ? math.min(size.width - 28, 780) : size.width,
      maxHeight: bottomSheetMaxHeight(context),
    );
  }

  static Widget bottomSheetDragHandle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 4,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  static Widget bottomSheetFrame(
    BuildContext context, {
    required Widget child,
    bool includeHandle = false,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 10, 16, 16),
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final floating = bottomSheetUsesFloatingLayout(context);
    if (!floating) {
      return ConstrainedBox(
        constraints: bottomSheetFrameConstraints(context),
        child: child,
      );
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: bottomSheetFrameConstraints(context),
        child: Container(
          margin: const EdgeInsets.all(14),
          padding: padding,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: bottomSheetFloatingBorderRadius,
            boxShadow: softShadow(colorScheme, alpha: 0.16, blur: 24, y: 10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (includeHandle) bottomSheetDragHandle(context),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }

  static List<BoxShadow> softShadow(
    ColorScheme colorScheme, {
    double alpha = 0.18,
    double blur = 18,
    double y = 8,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final shadowColor = isDark ? Colors.black : colorScheme.primary;
    final effectiveAlpha = isDark ? alpha * 0.58 : alpha * 0.72;
    return [
      BoxShadow(
        color: shadowColor.withValues(alpha: effectiveAlpha),
        blurRadius: blur,
        spreadRadius: -3,
        offset: Offset(0, y),
      ),
    ];
  }

  static Color flatCardColor(ColorScheme colorScheme) {
    if (colorScheme.brightness == Brightness.dark) {
      return colorScheme.surfaceContainer;
    }
    return colorScheme.surfaceContainer;
  }

  static Color flatCardBorder(ColorScheme colorScheme) {
    if (colorScheme.brightness == Brightness.dark) {
      return colorScheme.outlineVariant.withValues(alpha: 0.22);
    }
    return colorScheme.outlineVariant;
  }

  static Color _solidCardFill(ColorScheme colorScheme, Color? color) {
    final base = flatCardColor(colorScheme);
    if (color == null) return base;
    return Color.alphaBlend(color, base);
  }

  static BoxDecoration softPanel(
    ColorScheme colorScheme, {
    Color? color,
    double radius = cardRadius,
    double alpha = 0.42,
  }) {
    final fill = _solidCardFill(
      colorScheme,
      color ?? colorScheme.surfaceContainerHighest.withValues(alpha: alpha),
    );
    return BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: flatCardBorder(colorScheme),
        width: cardStrokeWidth,
      ),
      boxShadow: const [],
    );
  }

  static BoxDecoration elevatedCardDecoration(
    ColorScheme colorScheme, {
    Color? color,
    double radius = cardRadius,
    double borderAlpha = 0.3,
    double shadowAlpha = 0.16,
  }) {
    final fill = _solidCardFill(colorScheme, color);
    return BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: flatCardBorder(colorScheme),
        width: cardStrokeWidth,
      ),
      boxShadow: const [],
    );
  }

  static BoxDecoration elevatedCircleDecoration(
    ColorScheme colorScheme, {
    Color? color,
    double shadowAlpha = 0.24,
    double glowAlpha = 0,
  }) {
    final fill = color ?? colorScheme.surfaceContainerHighest;
    return BoxDecoration(
      shape: BoxShape.circle,
      color: fill,
      boxShadow: [
        ...softShadow(colorScheme, alpha: shadowAlpha, blur: 18, y: 8),
        BoxShadow(
          color: Colors.white.withValues(
            alpha: colorScheme.brightness == Brightness.dark ? 0.03 : 0.64,
          ),
          blurRadius: 2,
          offset: const Offset(0, -1),
        ),
      ],
    );
  }

  static BoxDecoration elevatedIconDecoration(
    ColorScheme colorScheme, {
    Color? color,
    double radius = 12,
    double shadowAlpha = 0.22,
    double glowAlpha = 0,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final base = flatCardColor(colorScheme);
    final tint =
        color ?? colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.14);
    final fill = Color.alphaBlend(tint, base);
    return BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: colorScheme.primary.withValues(
            alpha: isDark ? shadowAlpha * 0.62 : shadowAlpha * 0.72,
          ),
          blurRadius: 14,
          spreadRadius: -7,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  static Color iconBadgeSurface(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;
    return Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.14),
      flatCardColor(colorScheme),
    );
  }

  static Color floatingActionSurface(ColorScheme colorScheme) {
    return Colors.black.withValues(alpha: 0.58);
  }

  static Color floatingActionShadow(ColorScheme colorScheme) {
    return const Color(
      0xFF020609,
    ).withValues(alpha: colorScheme.brightness == Brightness.dark ? 0.5 : 0.34);
  }

  static Widget iconBadge(
    BuildContext context, {
    required IconData icon,
    double boxSize = 46,
    double iconSize = 20,
    double radius = 16,
    Color? iconColor,
    Color? color,
    double shadowAlpha = 0.16,
    double glowAlpha = 0.04,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? colorScheme.primary;
    return Container(
      width: boxSize,
      height: boxSize,
      decoration: elevatedIconDecoration(
        colorScheme,
        color: color ?? iconBadgeSurface(colorScheme),
        radius: radius,
        shadowAlpha: shadowAlpha,
        glowAlpha: glowAlpha,
      ),
      child: Icon(icon, size: iconSize, color: effectiveIconColor),
    );
  }

  static ShapeBorder cardShape(ColorScheme colorScheme, {double alpha = 0.34}) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cardRadius),
      side: BorderSide(
        color: flatCardBorder(colorScheme).withValues(alpha: alpha),
        width: cardStrokeWidth,
      ),
    );
  }

  static BoxDecoration badgeDecoration(
    ColorScheme colorScheme,
    Color color, {
    bool outlined = false,
  }) {
    return BoxDecoration(
      color: outlined
          ? color.withValues(alpha: 0.08)
          : color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(pillRadius),
      boxShadow: outlined
          ? softShadow(colorScheme, alpha: 0.05, blur: 10, y: 3)
          : const [],
    );
  }

  static Widget posterTone(String intensity, {required Widget child}) {
    final saturation = switch (intensity) {
      'soft' => 0.82,
      'bold' => 1.16,
      _ => 1.0,
    };
    if (saturation == 1.0) return child;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_saturationMatrix(saturation)),
      child: child,
    );
  }

  static List<double> _saturationMatrix(double saturation) {
    const red = 0.2126;
    const green = 0.7152;
    const blue = 0.0722;
    final inverse = 1 - saturation;
    return <double>[
      red * inverse + saturation,
      green * inverse,
      blue * inverse,
      0,
      0,
      red * inverse,
      green * inverse + saturation,
      blue * inverse,
      0,
      0,
      red * inverse,
      green * inverse,
      blue * inverse + saturation,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }
}

class JuicrBetaPill extends StatelessWidget {
  const JuicrBetaPill({super.key, this.label = 'Beta', this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: JuicrVisual.badgeDecoration(colorScheme, colorScheme.primary),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
    if (hint == null || hint!.isEmpty) return pill;
    return Tooltip(message: hint!, child: pill);
  }
}

class JuicrSheetOptionTile extends StatelessWidget {
  const JuicrSheetOptionTile({
    super.key,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.selected = false,
    this.enabled = true,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: 8),
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 11,
    ),
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final bool enabled;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mutedColor = colorScheme.onSurface.withValues(alpha: 0.38);
    final activeColor = selected ? colorScheme.primary : colorScheme.onSurface;
    return Padding(
      padding: padding,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Container(
            width: double.infinity,
            padding: contentPadding,
            decoration: JuicrVisual.elevatedCardDecoration(
              colorScheme,
              radius: 16,
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.16)
                  : colorScheme.surfaceContainerHighest.withValues(
                      alpha: enabled ? 0.54 : 0.32,
                    ),
              borderAlpha: 0,
              shadowAlpha: selected ? 0.12 : 0.06,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 20,
                    color: enabled ? activeColor : mutedColor,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: enabled ? colorScheme.onSurface : mutedColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: enabled
                                    ? colorScheme.onSurface.withValues(
                                        alpha: 0.62,
                                      )
                                    : mutedColor,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (trailing != null)
                  trailing!
                else if (selected)
                  Icon(
                    Icons.check_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  )
                else if (!enabled)
                  Icon(Icons.lock_rounded, color: mutedColor, size: 19),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class JuicrAutoScrollText extends StatefulWidget {
  const JuicrAutoScrollText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.height = 18,
    this.pause = const Duration(milliseconds: 1000),
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final double height;
  final Duration pause;

  @override
  State<JuicrAutoScrollText> createState() => _JuicrAutoScrollTextState();
}

class _JuicrAutoScrollTextState extends State<JuicrAutoScrollText> {
  final ScrollController _controller = ScrollController();
  bool _started = false;
  bool _overflowing = false;

  @override
  void didUpdateWidget(covariant JuicrAutoScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _started = false;
      _overflowing = false;
      if (_controller.hasClients) _controller.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startIfNeeded({required bool reduceMotion}) {
    if (_started || !_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    if (_overflowing != max > 0 && mounted) {
      setState(() => _overflowing = max > 0);
    }
    if (max <= 0 || reduceMotion) return;
    _started = true;
    Future<void>.delayed(widget.pause, _loop);
  }

  Future<void> _loop() async {
    if (!mounted || !_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    if (max <= 0) return;
    final forwardMs = (max * 34).clamp(1400, 4200).round();
    await _controller.animateTo(
      max,
      duration: Duration(milliseconds: forwardMs),
      curve: Curves.easeInOutCubic,
    );
    if (!mounted) return;
    await Future<void>.delayed(widget.pause);
    if (!mounted || !_controller.hasClients) return;
    await _controller.animateTo(
      0,
      duration: Duration(milliseconds: (forwardMs * 0.72).round()),
      curve: Curves.easeInOutCubic,
    );
    if (!mounted) return;
    await Future<void>.delayed(widget.pause);
    if (mounted) unawaited(_loop());
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = juicrMotionDisabled(context);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _startIfNeeded(reduceMotion: reduceMotion),
    );
    final scroller = SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: reduceMotion
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        textAlign: widget.textAlign,
        maxLines: 1,
        softWrap: false,
        style: widget.style,
      ),
    );
    return SizedBox(
      height: widget.height,
      child: _overflowing
          ? ShaderMask(
              shaderCallback: (bounds) {
                return LinearGradient(
                  colors: const [
                    Color(0xCCFFFFFF),
                    Colors.white,
                    Colors.white,
                    Color(0xCCFFFFFF),
                  ],
                  stops: const [0, 0.035, 0.965, 1],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: scroller,
            )
          : scroller,
    );
  }
}
