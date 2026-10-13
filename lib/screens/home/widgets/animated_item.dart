import 'package:flutter/material.dart';

class AnimatedItem extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;
  
  const AnimatedItem({
    super.key,
    required this.child,
    required this.index,
    this.delay = const Duration(milliseconds: 50),
  });

  /// Track which keys have already animated so we never replay.
  static final Set<Key> _animatedKeys = {};

  /// Call once when the parent list is first mounted (e.g. in HomeScreen initState)
  /// so that a fresh navigation into the screen re-triggers entrance animations.
  static void resetAll() => _animatedKeys.clear();

  @override
  State<AnimatedItem> createState() => _AnimatedItemState();
}

class _AnimatedItemState extends State<AnimatedItem> with SingleTickerProviderStateMixin {
  late final bool _shouldAnimate;
  AnimationController? _controller;
  Animation<double>? _fadeAnimation;
  Animation<Offset>? _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Only animate if this key hasn't been seen before.
    _shouldAnimate = widget.key != null && !AnimatedItem._animatedKeys.contains(widget.key);

    if (_shouldAnimate) {
      if (widget.key != null) AnimatedItem._animatedKeys.add(widget.key!);

      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 260),
      );

      _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.easeOutCubic),
      );

      _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.easeOutCubic),
      );

      final stagger = widget.index <= 5 ? widget.delay * widget.index : const Duration(milliseconds: 150);
      if (stagger == Duration.zero) {
        _controller!.forward();
      } else {
        Future.delayed(stagger, () {
          if (mounted) {
            _controller!.forward();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Already animated before – render immediately with no animation wrapper.
    if (!_shouldAnimate) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _fadeAnimation!,
      child: SlideTransition(
        position: _slideAnimation!,
        child: widget.child,
      ),
    );
  }
}
