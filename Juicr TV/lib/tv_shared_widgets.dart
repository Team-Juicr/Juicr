part of 'main.dart';

const double _tvPosterFocusGutter = 8.0;
const double _tvPosterFocusedScale = 1.035;
const double _tvHomeHeroHeight = 320;
const double _tvHomeHeroCopyLeftInset = 34;
const double _tvHomeHeroCopyTopInset = 58;
const double _tvHomeHeroCopyRightInset = 28;
const double _tvEmptyStateVisualOffset = 16;
const double _tvHomeEmptyStateHeaderSpacer = 106;
const double _tvCompactPillHeight = 30;
const double _tvCompactPillPadding = 9;
const double _tvCompactPillGap = 6;
const double _tvRankPillMinWidth = 62;
const double _tvImdbPillMinWidth = 68;
const double _tvCompactPillMaxWidth = 86;
const double _tvCompactPillFontSize = 9.5;
const double _tvHomeUpcomingPosterWidth = 136;
const double _tvHomeUpcomingPosterHeight = 210;
const double _tvHomeUpcomingRailHeight = 248;
const double _tvHomeHeroBackdropOverscan = 54;
const double _tvHomeHeroBottomBlurHeight = 24;
const double _tvDetailsHeroHeight = 386;
const double _tvDetailsHeroBackdropOverscan = 72;
const double _tvDetailsHeroBottomBlurHeight = 32;

String tvRemoteCatalogItemLabel({
  required String title,
  required String? year,
  required String? imdbRating,
}) {
  final parts = <String>[];
  final rating = imdbRating?.trim();
  if (rating != null && rating.isNotEmpty) parts.addAll(['IMDb', rating]);
  final releaseYear = year?.trim();
  if (releaseYear != null && releaseYear.isNotEmpty) parts.add(releaseYear);
  final safeTitle = title.trim();
  if (safeTitle.isNotEmpty) parts.add(safeTitle);
  return parts.join('\n');
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.item,
    required this.rank,
    required this.width,
    required this.posterHeight,
    required this.onPressed,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
    this.onFocus,
    this.autoReveal = true,
    this.showRank = true,
    this.badgeLabel,
  });

  final _TvItem item;
  final int rank;
  final double width;
  final double posterHeight;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final VoidCallback? onFocus;
  final bool autoReveal;
  final bool showRank;
  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tvRemoteCatalogItemLabel(
        title: item.title,
        year: item.year,
        imdbRating: item.imdbRating,
      ),
      excludeSemantics: true,
      child: _TvFocusable(
        autoReveal: autoReveal,
        onPressed: onPressed,
        focusNode: focusNode,
        onArrowLeft: onArrowLeft,
        onArrowRight: onArrowRight,
        onArrowUp: onArrowUp,
        onArrowDown: onArrowDown,
        onFocus: onFocus,
        builder: (focused) {
          final contentWidth = width - (_tvPosterFocusGutter * 2);
          final contentHeight = posterHeight - (_tvPosterFocusGutter * 2);
          final rating = badgeLabel ?? item.imdbRating?.trim();
          return SizedBox(
            width: width,
            height: posterHeight + 18,
            child: Center(
              child: AnimatedScale(
                scale: focused ? _tvPosterFocusedScale : 1,
                duration: _tvDuration(130),
                child: Padding(
                  padding: const EdgeInsets.all(_tvPosterFocusGutter),
                  child: SizedBox(
                    width: contentWidth,
                    height: contentHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: contentHeight,
                          child: _PosterArtwork(
                            item: item,
                            width: contentWidth,
                            height: contentHeight,
                          ),
                        ),
                        if (rating != null && rating.isNotEmpty)
                          Positioned(
                            left: 7,
                            top: 7,
                            child: badgeLabel == null
                                ? _ImdbPill(label: rating)
                                : _Pill(label: rating),
                          ),
                        if (showRank)
                          Positioned(
                            right: 7,
                            bottom: 7,
                            child: _Pill(label: 'Rank $rank'),
                          ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: contentHeight,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: focused
                                    ? _tvFocusBorder
                                    : const Color(0x22FFFFFF),
                                width: focused ? 2 : 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ImdbPill extends StatelessWidget {
  const _ImdbPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: _tvImdbPillMinWidth,
        maxWidth: _tvCompactPillMaxWidth,
      ),
      child: Container(
        height: _tvCompactPillHeight,
        padding: const EdgeInsets.symmetric(horizontal: _tvCompactPillPadding),
        decoration: _tvPillDecoration,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'IMDb',
              maxLines: 1,
              style: TextStyle(
                color: Colors.white,
                fontSize: _tvCompactPillFontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                height: 1,
              ),
            ),
            const SizedBox(width: _tvCompactPillGap),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: _tvAccentColor,
                fontSize: _tvCompactPillFontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration get _tvPillDecoration => BoxDecoration(
      color: const Color(0xA611131A),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0x24FFFFFF)),
      boxShadow: const [
        BoxShadow(
            color: Color(0x52000000), blurRadius: 12, offset: Offset(0, 5)),
      ],
    );

class _PosterArtwork extends StatelessWidget {
  const _PosterArtwork({
    required this.item,
    required this.width,
    required this.height,
  });

  final _TvItem item;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final image = item.poster ?? item.background;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: width,
        height: height,
        color: const Color(0xFF08090D),
        child: image == null
            ? const _TvPosterArtworkFallback()
            : Image.network(
                image,
                fit: BoxFit.cover,
                cacheWidth: 420,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const _TvPosterArtworkFallback();
                },
                errorBuilder: (_, error, __) {
                  _reportTvArtworkFailure(error, 'poster');
                  return const _TvPosterArtworkFallback();
                },
              ),
      ),
    );
  }
}

class _TvPosterArtworkFallback extends StatelessWidget {
  const _TvPosterArtworkFallback();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        _TvShimmerBox(radius: 18, alpha: 0.58),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF101216),
                Color(0xFF08090D),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FocusableIconButton extends StatelessWidget {
  const _FocusableIconButton({
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.onArrowUp,
    this.onArrowDown,
    this.onArrowRight,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowRight;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onPressed: onPressed,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      onArrowRight: onArrowRight,
      builder: (focused) {
        return AnimatedScale(
          scale: focused ? 1.06 : 1,
          duration: _tvDuration(130),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: selected ? _tvAccentColor : _tvTheme.cardAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: focused
                    ? selected
                        ? Colors.white
                        : _tvFocusBorder
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              color: selected ? Colors.black : _tvTheme.muted,
              size: 24,
            ),
          ),
        );
      },
    );
  }
}

class _TvTextButton extends StatelessWidget {
  const _TvTextButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.enabled = true,
    this.animateIcon = false,
    this.focusNode,
    this.onFocus,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
    this.minHeight = 48,
    this.horizontalPadding = _tvSpacing,
    this.verticalPadding = _tvSpacing,
    this.iconSize = 22,
    this.fontSize,
    this.autoReveal = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool enabled;
  final bool animateIcon;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final double minHeight;
  final double horizontalPadding;
  final double verticalPadding;
  final double iconSize;
  final double? fontSize;
  final bool autoReveal;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: autofocus,
      enabled: enabled,
      focusNode: focusNode,
      autoReveal: autoReveal,
      onFocus: onFocus,
      onPressed: onPressed,
      onArrowLeft: onArrowLeft,
      onArrowRight: onArrowRight,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      builder: (focused) {
        final active = focused && enabled;
        return AnimatedContainer(
          duration: _tvDuration(130),
          constraints: BoxConstraints(minHeight: minHeight),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          decoration: BoxDecoration(
            color: active ? _tvAccentColor : _tvTheme.valuePill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? _tvSolidFocusBorder : _tvTheme.valuePillBorder,
              width: active ? 2 : 1,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final labelText = Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active
                      ? Colors.black
                      : enabled
                          ? _tvTheme.text
                          : _tvTheme.muted,
                  fontWeight: FontWeight.w900,
                  fontSize: fontSize,
                ),
              );
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  animateIcon
                      ? _LoopingIcon(
                          icon: icon,
                          color: active
                              ? Colors.black
                              : enabled
                                  ? _tvTheme.text
                                  : _tvTheme.muted,
                        )
                      : Icon(
                          icon,
                          color: active
                              ? Colors.black
                              : enabled
                                  ? _tvTheme.text
                                  : _tvTheme.muted,
                          size: iconSize,
                        ),
                  SizedBox(width: horizontalPadding * 0.55),
                  if (constraints.hasBoundedWidth)
                    Flexible(child: labelText)
                  else
                    labelText,
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _LoopingIcon extends StatefulWidget {
  const _LoopingIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  State<_LoopingIcon> createState() => _LoopingIconState();
}

class _LoopingIconState extends State<_LoopingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, color: widget.color, size: 22),
    );
  }
}

class _TvFocusable extends StatefulWidget {
  const _TvFocusable({
    required this.builder,
    required this.onPressed,
    this.autofocus = false,
    this.enabled = true,
    this.autoReveal = false,
    this.descendantsAreFocusable = false,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowRight,
    this.onArrowUp,
    this.onArrowDown,
    this.onFocus,
  });

  final Widget Function(bool focused) builder;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool enabled;
  final bool autoReveal;
  final bool descendantsAreFocusable;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final VoidCallback? onFocus;

  @override
  State<_TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<_TvFocusable> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.enabled && (widget.focusNode?.hasFocus ?? false);
  }

  @override
  void didUpdateWidget(covariant _TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasFocus = widget.enabled && (widget.focusNode?.hasFocus ?? false);
    if (_focused != hasFocus) {
      _focused = hasFocus;
    }
  }

  bool _activateForKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA;
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_activateForKey(key)) {
      if (!widget.enabled) return KeyEventResult.handled;
      widget.onPressed();
      return KeyEventResult.handled;
    }
    if (!widget.enabled) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && widget.onArrowLeft != null) {
      widget.onArrowLeft!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && widget.onArrowRight != null) {
      widget.onArrowRight!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && widget.onArrowUp != null) {
      widget.onArrowUp!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && widget.onArrowDown != null) {
      widget.onArrowDown!();
      return KeyEventResult.handled;
    }
    final direction = switch (key) {
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    if (direction != null) {
      var moved = false;
      try {
        moved = FocusScope.of(context).focusInDirection(direction);
      } on FlutterError {
        moved = false;
      }
      if (moved) return KeyEventResult.handled;
      final currentFocus = FocusManager.instance.primaryFocus;
      if (currentFocus?.canRequestFocus == true) {
        currentFocus?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    void activate() {
      if (!widget.enabled) return;
      widget.onPressed();
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.select): activate,
        const SingleActivator(LogicalKeyboardKey.enter): activate,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): activate,
        const SingleActivator(LogicalKeyboardKey.space): activate,
        const SingleActivator(LogicalKeyboardKey.gameButtonA): activate,
      },
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus && widget.enabled,
        canRequestFocus: widget.enabled,
        descendantsAreFocusable: widget.descendantsAreFocusable,
        onKeyEvent: (_, event) => _handleKey(event),
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused) widget.onFocus?.call();
          if (!focused || !widget.autoReveal) return;
          Scrollable.ensureVisible(
            context,
            duration: _tvDuration(180),
            curve: Curves.easeOutCubic,
            alignment: 0.42,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
        },
        child: GestureDetector(
          onTap: widget.enabled ? widget.onPressed : null,
          child: widget.builder(widget.enabled && _focused),
        ),
      ),
    );
  }
}

class _TvLoadingState extends StatelessWidget {
  const _TvLoadingState({required this.selectedTab});

  final int selectedTab;

  @override
  Widget build(BuildContext context) {
    if (selectedTab == 0) {
      return const ClipRect(
        child: SingleChildScrollView(
          physics: NeverScrollableScrollPhysics(),
          child: _TvHomeSkeletonPage(),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 32, 0, 70),
      child: selectedTab == 1
          ? const _TvCatalogSkeletonGrid()
          : const _TvCatalogSkeletonPage(),
    );
  }
}

class _TvShimmer extends StatefulWidget {
  const _TvShimmer({required this.child});

  final Widget child;

  @override
  State<_TvShimmer> createState() => _TvShimmerState();
}

class _TvShimmerState extends State<_TvShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_tvMotionEnabled) return widget.child;
    final base =
        Color.lerp(_tvTheme.background, const Color(0xFF151619), 0.86) ??
            const Color(0xFF111214);
    final glow = Color.lerp(base, _tvAccentColor, 0.045) ?? base;
    final shine = Color.lerp(base, Colors.white, 0.045) ?? base;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final sweep = -1.35 + (_controller.value * 2.7);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(sweep, -0.8),
            end: Alignment(sweep + 0.72, 0.85),
            colors: [base, glow, shine, glow, base],
            stops: const [0, 0.34, 0.5, 0.66, 1],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

class _TvShimmerBox extends StatelessWidget {
  const _TvShimmerBox({
    this.width,
    this.height,
    this.radius = 14,
    this.alpha = 0.72,
  });

  final double? width;
  final double? height;
  final double radius;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return _TvShimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color:
              (Color.lerp(_tvTheme.background, const Color(0xFF151619), 0.82) ??
                      const Color(0xFF111214))
                  .withValues(alpha: alpha.clamp(0.28, 0.72)),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
      ),
    );
  }
}

class _TvCatalogSkeletonPage extends StatelessWidget {
  const _TvCatalogSkeletonPage();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TvShimmerBox(width: 280, height: 38, radius: 8),
        SizedBox(height: 36),
        _TvShimmerBox(width: 420, height: 22, radius: 8),
        SizedBox(height: _tvSpacing),
        _TvCatalogSkeletonRow(),
        SizedBox(height: 34),
        _TvShimmerBox(width: 340, height: 22, radius: 8),
        SizedBox(height: _tvSpacing),
        _TvCatalogSkeletonRow(),
      ],
    );
  }
}

class _TvHomeHeroArtClipper extends CustomClipper<Path> {
  const _TvHomeHeroArtClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _TvHomeHeroCurveScrim extends StatelessWidget {
  const _TvHomeHeroCurveScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xB8000000),
                  Color(0xB0000000),
                  Color(0x70000000),
                  Color(0x18000000),
                  Color(0x00000000),
                ],
                stops: [0, 0.34, 0.50, 0.72, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvHomeSkeletonPage extends StatelessWidget {
  const _TvHomeSkeletonPage();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _tvHomeHeroHeight,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Color(0xFF000000)),
              ClipPath(
                clipper: _TvHomeHeroArtClipper(),
                child: _TvShimmerBox(radius: 0, alpha: 0.30),
              ),
              _TvHomeHeroCurveScrim(),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xFF000000),
                      Color(0xD6000000),
                      Color(0x66000000),
                      Color(0x18000000),
                      Color(0x00000000),
                    ],
                    stops: [0, 0.16, 0.36, 0.62, 1],
                  ),
                ),
              ),
              Positioned(
                left: _tvHomeHeroCopyLeftInset,
                top: _tvHomeHeroCopyTopInset,
                right: _tvHomeHeroCopyRightInset,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: double.infinity,
                    child: _TvHomeHeroCopySkeleton(),
                  ),
                ),
              ),
              Positioned(
                right: 84,
                bottom: 26,
                child: _TvHomeHeroDotsSkeleton(),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        Padding(
          padding: EdgeInsets.fromLTRB(30, 0, 48, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TvShimmerBox(width: 250, height: 28, radius: 8, alpha: 0.44),
              SizedBox(height: _tvHomeRailGap),
              _TvHomeRailSkeletonRow(),
            ],
          ),
        ),
      ],
    );
  }
}

class _TvHomeHeroCopySkeleton extends StatelessWidget {
  const _TvHomeHeroCopySkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _TvShimmerBox(width: 156, height: 242, radius: 18, alpha: 0.38),
        SizedBox(width: 26),
        SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TvShimmerBox(width: 360, height: 92, radius: 12, alpha: 0.40),
              SizedBox(height: _tvSpacing),
              _TvShimmerBox(width: 500, height: 18, radius: 99, alpha: 0.34),
              SizedBox(height: _tvSpacing),
              _TvShimmerBox(width: 540, height: 16, radius: 99, alpha: 0.30),
              SizedBox(height: 8),
              _TvShimmerBox(width: 470, height: 16, radius: 99, alpha: 0.30),
              SizedBox(height: 8),
              _TvShimmerBox(width: 360, height: 16, radius: 99, alpha: 0.28),
              SizedBox(height: 18),
              Row(
                children: [
                  _TvShimmerBox(
                    width: 116,
                    height: 42,
                    radius: 24,
                    alpha: 0.36,
                  ),
                  SizedBox(width: 10),
                  _TvShimmerBox(width: 42, height: 42, radius: 99, alpha: 0.34),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TvHomeHeroDotsSkeleton extends StatelessWidget {
  const _TvHomeHeroDotsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TvShimmerBox(width: 8, height: 8, radius: 99, alpha: 0.34),
        SizedBox(width: 7),
        _TvShimmerBox(width: 8, height: 8, radius: 99, alpha: 0.34),
        SizedBox(width: 7),
        _TvShimmerBox(width: 28, height: 8, radius: 99, alpha: 0.48),
        SizedBox(width: 7),
        _TvShimmerBox(width: 8, height: 8, radius: 99, alpha: 0.34),
        SizedBox(width: 7),
        _TvShimmerBox(width: 8, height: 8, radius: 99, alpha: 0.34),
        SizedBox(width: 7),
        _TvShimmerBox(width: 8, height: 8, radius: 99, alpha: 0.30),
      ],
    );
  }
}

class _TvCatalogSkeletonGrid extends StatelessWidget {
  const _TvCatalogSkeletonGrid({this.catalogType});

  final String? catalogType;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final type = catalogType ?? '';
        final landscape = tvCatalogUsesLandscapeSkeleton(type);
        final columns = landscape
            ? ((constraints.maxWidth + _tvPosterGridGap) /
                    (_TvHomeLandscapeCard._width + _tvPosterGridGap))
                .floor()
                .clamp(1, 8)
                .toInt()
            : 6;
        final cardWidth =
            (constraints.maxWidth - (_tvPosterGridGap * (columns - 1))) /
                columns;
        return _TvCatalogSkeletonRow(
          count: 18,
          landscape: landscape,
          cardWidth: cardWidth,
          cardHeight: tvCatalogSkeletonHeight(type: type, width: cardWidth),
        );
      },
    );
  }
}

class _TvCatalogSkeletonRow extends StatelessWidget {
  const _TvCatalogSkeletonRow({
    this.count = 5,
    this.landscape = true,
    this.cardWidth = 220,
    this.cardHeight,
  });

  final int count;
  final bool landscape;
  final double cardWidth;
  final double? cardHeight;

  @override
  Widget build(BuildContext context) {
    final height = cardHeight ??
        (landscape
            ? cardWidth * _TvHomeLandscapeCard.aspectRatio
            : cardWidth * 1.42);
    return Wrap(
      spacing: _tvPosterGridGap,
      runSpacing: _tvPosterGridGap,
      children: [
        for (var index = 0; index < count; index++)
          _TvCatalogSkeletonCard(
            width: cardWidth,
            height: height,
            landscape: landscape,
          ),
      ],
    );
  }
}

class _TvHomeRailSkeletonRow extends StatelessWidget {
  const _TvHomeRailSkeletonRow({this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: _tvPosterGridGap,
      runSpacing: _tvPosterGridGap,
      children: [
        for (var index = 0; index < count; index++)
          _TvHomeLandscapeSkeletonCard(rank: index + 1),
      ],
    );
  }
}

class _TvHomeLandscapeSkeletonCard extends StatelessWidget {
  const _TvHomeLandscapeSkeletonCard({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    const width = _TvHomeLandscapeCard._width;
    const height = _TvHomeLandscapeCard._height;
    return SizedBox(
      width: width,
      height: height + 10,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Stack(
          children: [
            const Positioned.fill(
              child: _TvShimmerBox(radius: 18, alpha: 0.54),
            ),
            const Positioned(
              left: 12,
              top: 12,
              child: _TvShimmerBox(
                width: 72,
                height: 28,
                radius: 99,
                alpha: 0.36,
              ),
            ),
            const Positioned(
              left: 14,
              right: 72,
              bottom: 16,
              child: _TvShimmerBox(height: 17, radius: 6, alpha: 0.42),
            ),
            if (rank <= 3)
              const Positioned(
                right: 10,
                bottom: 12,
                child: _TvShimmerBox(
                  width: 58,
                  height: 36,
                  radius: 16,
                  alpha: 0.34,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TvCatalogSkeletonCard extends StatelessWidget {
  const _TvCatalogSkeletonCard({
    required this.width,
    required this.height,
    required this.landscape,
  });

  final double width;
  final double height;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final inset = landscape ? 5.0 : _tvPosterFocusGutter;
    final outerHeight = landscape ? height : height + 18;
    return SizedBox(
      width: width,
      height: outerHeight,
      child: Padding(
        padding: EdgeInsets.all(inset),
        child: _TvShimmerBox(
          width: width - (inset * 2),
          height: height - (inset * 2),
          radius: 18,
          alpha: 0.54,
        ),
      ),
    );
  }
}

class _TvPendingHomeRailsSkeleton extends StatelessWidget {
  const _TvPendingHomeRailsSkeleton({this.railCount = 1});

  final int railCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < railCount; index++) ...[
          const _TvShimmerBox(width: 260, height: 28, radius: 8, alpha: 0.44),
          const SizedBox(height: _tvHomeRailGap),
          const _TvHomeRailSkeletonRow(count: 3),
          if (index != railCount - 1) const SizedBox(height: 34),
        ],
      ],
    );
  }
}

class _TvErrorState extends StatelessWidget {
  const _TvErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: _tvSpacing),
          _TvTextButton(
            icon: Icons.refresh_rounded,
            label: 'Try again',
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: _tvRankPillMinWidth,
        maxWidth: _tvCompactPillMaxWidth,
      ),
      child: Container(
        height: _tvCompactPillHeight,
        padding: const EdgeInsets.symmetric(horizontal: _tvCompactPillPadding),
        alignment: Alignment.center,
        decoration: _tvPillDecoration,
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _TvBackdrop extends StatelessWidget {
  const _TvBackdrop({required this.settings});

  final _TvSettingsState settings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.2,
          colors: _themeForSetting(settings.theme).backdropGradient,
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}
