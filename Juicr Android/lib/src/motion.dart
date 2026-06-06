import 'dart:async';

import 'package:flutter/material.dart';

import 'app_state.dart';

bool juicrMotionDisabled(BuildContext context) {
  final mediaQuery = MediaQuery.maybeOf(context);
  return AppState.reduceMotion.value ||
      mediaQuery?.disableAnimations == true ||
      mediaQuery?.accessibleNavigation == true;
}

class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
    bool opaque = true,
  }) : super(
         settings: settings,
         fullscreenDialog: fullscreenDialog,
         opaque: opaque,
         transitionDuration: const Duration(milliseconds: 320),
         reverseTransitionDuration: const Duration(milliseconds: 320),
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           if (juicrMotionDisabled(context)) return child;
           final curved = CurvedAnimation(
             parent: animation,
             curve: Curves.easeOutCubic,
             reverseCurve: Curves.easeOutCubic,
           );
           final position = Tween<Offset>(
             begin: const Offset(1, 0),
             end: Offset.zero,
           ).animate(curved);

           return SlideTransition(position: position, child: child);
         },
       );
}

class AppReveal extends StatefulWidget {
  const AppReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.offset = const Offset(0, 0.045),
    this.curve = Curves.easeOutCubic,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset offset;
  final Curve curve;

  @override
  State<AppReveal> createState() => _AppRevealState();
}

class _AppRevealState extends State<AppReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (juicrMotionDisabled(context)) return widget.child;
    final curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    final opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    final slide = Tween<Offset>(
      begin: widget.offset,
      end: Offset.zero,
    ).animate(curved);
    final scale = Tween<double>(begin: 0.985, end: 1).animate(curved);

    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(
        position: slide,
        child: ScaleTransition(scale: scale, child: widget.child),
      ),
    );
  }
}

class AppShimmer extends StatefulWidget {
  const AppShimmer({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1450),
  });

  final Widget child;
  final Duration duration;

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (juicrMotionDisabled(context)) return widget.child;
    final colorScheme = Theme.of(context).colorScheme;
    final base = colorScheme.surfaceContainerHighest.withValues(alpha: 0.74);
    final glow = Color.lerp(base, colorScheme.primary, 0.18) ?? base;
    final shine = Color.lerp(base, Colors.white, 0.20) ?? base;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final sweep = -1.35 + (_controller.value * 2.7);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(sweep, -0.8),
              end: Alignment(sweep + 0.72, 0.85),
              colors: [base, glow, shine, glow, base],
              stops: const [0, 0.34, 0.5, 0.66, 1],
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

class AppShimmerBox extends StatelessWidget {
  const AppShimmerBox({
    super.key,
    this.width,
    this.height,
    this.radius = 14,
    this.margin = EdgeInsets.zero,
    this.shape = BoxShape.rectangle,
    this.alpha = 0.72,
  });

  final double? width;
  final double? height;
  final double radius;
  final EdgeInsetsGeometry margin;
  final BoxShape shape;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = Color.lerp(
      colorScheme.surfaceContainerHigh,
      colorScheme.surfaceContainerHighest,
      0.72,
    )!.withValues(alpha: alpha.clamp(0.24, 1.0));
    return AppShimmer(
      child: Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          color: color,
          shape: shape,
          borderRadius: shape == BoxShape.circle
              ? null
              : BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class AppSkeletonLine extends StatelessWidget {
  const AppSkeletonLine({
    super.key,
    this.width,
    this.widthFactor,
    this.height = 12,
    this.radius = 99,
  });

  final double? width;
  final double? widthFactor;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final line = AppShimmerBox(width: width, height: height, radius: radius);
    if (widthFactor == null) return line;
    return FractionallySizedBox(widthFactor: widthFactor!, child: line);
  }
}

class AppSkeletonCircle extends StatelessWidget {
  const AppSkeletonCircle({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return AppShimmerBox(
      width: size,
      height: size,
      shape: BoxShape.circle,
      radius: size / 2,
    );
  }
}

class AppSkeletonCard extends StatelessWidget {
  const AppSkeletonCard({
    super.key,
    this.width,
    this.height,
    this.radius = 14,
    this.child,
    this.padding = EdgeInsets.zero,
  });

  final double? width;
  final double? height;
  final double radius;
  final Widget? child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppShimmerBox(radius: radius, alpha: 0.64),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class AppPosterSkeleton extends StatelessWidget {
  const AppPosterSkeleton({
    super.key,
    this.compact = false,
    this.showDatePill = false,
  });

  final bool compact;
  final bool showDatePill;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const AppSkeletonCard(radius: 14),
              if (showDatePill)
                const Positioned(
                  left: 8,
                  top: 8,
                  child: AppShimmerBox(width: 46, height: 18, radius: 99),
                ),
              const Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: AppSkeletonLine(height: 3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        AppSkeletonLine(height: compact ? 9 : 11),
      ],
    );
  }
}

class AppLiveTileSkeleton extends StatelessWidget {
  const AppLiveTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        Positioned.fill(child: AppSkeletonCard(radius: 10)),
        Center(
          child: FractionallySizedBox(
            widthFactor: 0.56,
            child: AspectRatio(
              aspectRatio: 2.4,
              child: AppShimmerBox(radius: 8),
            ),
          ),
        ),
        Positioned(
          left: 44,
          right: 44,
          bottom: 12,
          child: AppSkeletonLine(height: 8),
        ),
      ],
    );
  }
}

class AppSettingsSkeleton extends StatelessWidget {
  const AppSettingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      itemCount: 8,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return AppReveal(
          delay: Duration(milliseconds: 28 * index),
          child: AppSkeletonCard(
            height: 68,
            radius: 16,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: const [
                AppSkeletonCircle(size: 40),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSkeletonLine(height: 14, widthFactor: 0.54),
                      SizedBox(height: 8),
                      AppSkeletonLine(height: 10, widthFactor: 0.74),
                    ],
                  ),
                ),
                SizedBox(width: 14),
                AppSkeletonCircle(size: 22),
              ],
            ),
          ),
        );
      },
    );
  }
}
