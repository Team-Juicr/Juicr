part of 'main.dart';

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

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autoReveal: autoReveal,
      onPressed: onPressed,
      focusNode: focusNode,
      onArrowLeft: onArrowLeft,
      onArrowRight: onArrowRight,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      onFocus: onFocus,
      builder: (focused) {
        final contentWidth = width - 16;
        final rating = item.imdbRating?.trim();
        return SizedBox(
          width: width,
          height: posterHeight + 10,
          child: Center(
            child: AnimatedScale(
              scale: focused ? 1.035 : 1,
              duration: _tvDuration(130),
              child: SizedBox(
                width: contentWidth,
                height: posterHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: posterHeight,
                      child: _PosterArtwork(
                        item: item,
                        width: contentWidth,
                        height: posterHeight,
                      ),
                    ),
                    if (rating != null && rating.isNotEmpty)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _ImdbPill(label: rating),
                      ),
                    if (showRank)
                      Positioned(
                        right: 8,
                        top: posterHeight - 34,
                        child: _Pill(label: 'Rank $rank'),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: posterHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
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
        );
      },
    );
  }
}

class _ImdbPill extends StatelessWidget {
  const _ImdbPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xA611131A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x24FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x52000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'IMDb',
            maxLines: 1,
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              height: 1,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: _tvAccentColor,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

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
        color: item.color,
        child: image == null
            ? _TvPosterArtworkFallback(color: item.color)
            : Image.network(
                image,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _TvPosterArtworkFallback(color: item.color),
              ),
      ),
    );
  }
}

class _TvPosterArtworkFallback extends StatelessWidget {
  const _TvPosterArtworkFallback({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(const Color(0x551B2030), color),
            const Color(0xF40A0C12),
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.image_not_supported_rounded,
          color: Color(0x66FFFFFF),
          size: 34,
        ),
      ),
    );
  }
}

class _CircleArrowButton extends StatelessWidget {
  const _CircleArrowButton({
    required this.onPressed,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowDown,
  });

  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed,
      onArrowLeft: onArrowLeft,
      onArrowDown: onArrowDown,
      builder: (focused) {
        return AnimatedContainer(
          duration: _tvDuration(130),
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: focused ? _tvAccentColor : const Color(0x1FFFFFFF),
            shape: BoxShape.circle,
            border: Border.all(
              color: focused ? _tvFocusBorder : Colors.transparent,
              width: 2,
            ),
          ),
          child: Icon(
            Icons.chevron_right_rounded,
            color: focused ? Colors.black : Colors.white,
            size: 30,
          ),
        );
      },
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
              color: selected ? _tvAccentColor : const Color(0x1AFFFFFF),
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
              color: selected ? Colors.black : const Color(0xFFDAD8E8),
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

  @override
  Widget build(BuildContext context) {
    return _TvFocusable(
      autofocus: autofocus,
      enabled: enabled,
      focusNode: focusNode,
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
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: active ? _tvAccentColor : const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? _tvFocusBorder : const Color(0x22FFFFFF),
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
                          ? Colors.white
                          : const Color(0xFFAAA6BD),
                  fontWeight: FontWeight.w900,
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
                                  ? Colors.white
                                  : const Color(0xFFAAA6BD),
                        )
                      : Icon(
                          icon,
                          color: active
                              ? Colors.black
                              : enabled
                                  ? Colors.white
                                  : const Color(0xFFAAA6BD),
                          size: 22,
                        ),
                  const SizedBox(width: 8),
                  if (constraints.hasBoundedWidth) Flexible(child: labelText) else labelText,
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
  const _LoopingIcon({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  State<_LoopingIcon> createState() => _LoopingIconState();
}

class _LoopingIconState extends State<_LoopingIcon> with SingleTickerProviderStateMixin {
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
    if (key == LogicalKeyboardKey.arrowLeft && widget.onArrowLeft != null) {
      if (widget.enabled) widget.onArrowLeft!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && widget.onArrowRight != null) {
      if (widget.enabled) widget.onArrowRight!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && widget.onArrowUp != null) {
      if (widget.enabled) widget.onArrowUp!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && widget.onArrowDown != null) {
      if (widget.enabled) widget.onArrowDown!();
      return KeyEventResult.handled;
    }
    if (!widget.enabled) return KeyEventResult.handled;
    final direction = switch (key) {
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    if (direction != null) {
      final moved = FocusScope.of(context).focusInDirection(direction);
      return moved ? KeyEventResult.handled : KeyEventResult.ignored;
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
        descendantsAreFocusable: false,
        onKeyEvent: (_, event) => _handleKey(event),
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused) widget.onFocus?.call();
          if (!focused || !widget.autoReveal) return;
          Scrollable.ensureVisible(
            context,
            duration: _tvDuration(180),
            curve: Curves.easeOutCubic,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
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
  const _TvLoadingState();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 260,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 18),
            Text(
              'Loading Juicr catalog...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvErrorState extends StatelessWidget {
  const _TvErrorState({
    required this.message,
    required this.onRetry,
  });

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
          const SizedBox(height: 18),
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
    return Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xA611131A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x24FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x52000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
          height: 1,
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
    final light = settings.theme == 'Light';
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.2,
          colors: light
              ? const [
                  Color(0xFFE7FFF0),
                  Color(0xFFF7F5FF),
                  Color(0xFFFFFFFF),
                ]
              : const [
                  Color(0xFF172B1D),
                  Color(0xFF111024),
                  Color(0xFF07080D),
                ],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}


