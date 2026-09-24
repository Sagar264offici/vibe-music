import 'package:flutter/material.dart';

import '../core/models.dart';

/// Glass surfaces and gradients matching the provided musicHome.html design.
class VibeTheme {
  static const bgTop = Color(0xFF5B1FA8);
  static const bgMid = Color(0xFF3A1478);
  static const bgBottom = Color(0xFF2A0F5C);
  static const pink = Color(0xFFD23DD6);
  static const violet = Color(0xFF8A46F0);
  static const accent = Color(0xFF8B3FF0);
  static const accentLight = Color(0xFFC79BFF);
  static const text = Color(0xFFF3EEFE);
  static const textDim = Color(0xFFC0AEE8);
  static const textFaint = Color(0xFF9B8CC9);

  static const glassBorder = Color(0x52FFFFFF);
  static const glassFillTop = Color(0x42FFFFFF);
  static const glassFillBottom = Color(0x14FFFFFF);

  static const LinearGradient bgGradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bgTop, bgMid, bgBottom],
      );

  static const LinearGradient accentGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFC79BFF), Color(0xFF8B3FF0), Color(0xFF7126D8)],
      );

  /// Frosted "touching glass" surface: bright top-edge highlight, soft
  /// inner sheen, crisp 1px border and a deep ambient shadow.
  static BoxDecoration glass({double radius = 20, bool strong = false}) =>
      BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.45, 0.5, 1.0],
          colors: [
            Color(0x66FFFFFF), // bright wet-glass top highlight
            Color(0x1FFFFFFF),
            Color(0x0AFFFFFF), // seam line at the middle
            Color(0x24FFFFFF),
          ],
        ),
        border: Border.all(color: const Color(0x66FFFFFF), width: 1),
        boxShadow: [
          BoxShadow(
            color: strong ? const Color(0x66140537) : const Color(0x4D140537),
            blurRadius: strong ? 36 : 24,
            offset: const Offset(0, 16),
          ),
          const BoxShadow(
            color: Color(0x14FFFFFF), // faint inner glow
            blurRadius: 2,
            spreadRadius: -1,
            offset: Offset(0, -1),
          ),
        ],
      );

  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: pink,
        surface: bgMid,
      ),
      fontFamilyFallback: const ['Roboto', 'SF Pro', 'Segoe UI'],
    );
    return base.copyWith(
      scaffoldBackgroundColor: bgBottom,
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      // InkSparkle runs a GPU shader on every tap — measurable jank on
      // budget devices. Plain splash is instant.
      splashFactory: InkRipple.splashFactory,
    );
  }
}

/// Small reusable glass pill for buttons/chips.
class GlassPill extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsets padding;

  const GlassPill({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 16,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: VibeTheme.glass(radius: radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Rounded cover art with optional gradient placeholder while loading.
class CoverArt extends StatelessWidget {
  final Song song;
  final double size;
  final double radius;
  final BoxFit fit;

  const CoverArt({
    super.key,
    required this.song,
    required this.size,
    this.radius = 14,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final isNetwork = song.cover.startsWith('http');
    // Bound the decoded size to 2x display pixels: CDN covers are 500x500,
    // decoding them for a 42px tile costs ~30x the needed memory/bandwidth.
    final image = isNetwork
        ? Image.network(
            song.cover,
            width: size,
            height: size,
            fit: fit,
            cacheWidth: (size * 2).round(),
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _fallback(),
          )
        : Image.asset(
            song.cover,
            width: size,
            height: size,
            fit: fit,
            cacheWidth: (size * 2).round(),
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _fallback(),
          );
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }

  Widget _fallback() => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(gradient: VibeTheme.accentGradient),
        child: const Icon(Icons.music_note, color: Colors.white70),
      );
}

/// Tiny song row model used by list tiles so lists don't depend on the player.
class SongTileData {
  final Song song;
  final String? subtitle;
  const SongTileData(this.song, {this.subtitle});
}
