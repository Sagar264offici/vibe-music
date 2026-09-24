import 'dart:ui';

import 'package:flutter/material.dart';

/// A real frosted-glass container: blurs whatever is behind it and layers a
/// glossy highlight on top, like the CSS backdrop-filter design.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;
  final bool strong;

  const GlassContainer({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(12),
    this.margin,
    this.onTap,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.45, 0.5, 1.0],
              colors: [
                Color(0x59FFFFFF),
                Color(0x1AFFFFFF),
                Color(0x08FFFFFF),
                Color(0x20FFFFFF),
              ],
            ),
            border: Border.all(color: const Color(0x61FFFFFF), width: 1),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
    final withShadow = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: strong ? const Color(0x66140537) : const Color(0x4D140537),
            blurRadius: strong ? 36 : 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: body,
    );
    if (onTap == null) return withShadow;
    return GestureDetector(onTap: onTap, child: withShadow);
  }
}
