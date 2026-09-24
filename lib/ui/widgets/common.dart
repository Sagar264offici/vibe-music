import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/player.dart';
import '../../core/library_store.dart';
import '../theme.dart';

/// Responsive scaffold body: phone gets the given child; wide screens get a
/// centered, constrained column so the app scales gracefully on desktop.
class ResponsiveBody extends StatelessWidget {
  final Widget child;
  const ResponsiveBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 900) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: child,
      ),
    );
  }
}

/// Mini bar shown above the bottom nav with the current track.
class MiniPlayerBar extends StatelessWidget {
  final VoidCallback onOpen;
  const MiniPlayerBar({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final player = PlayerService.instance;
    return StreamBuilder<void>(
      stream: player.changes,
      builder: (context, _) {
        final song = player.current;
        if (song == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: GlassPill(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            onTap: onOpen,
            child: Row(
              children: [
                CoverArt(song: song, size: 36, radius: 11),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              color: VibeTheme.text,
                              fontWeight: FontWeight.w500)),
                      Text(song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, color: VibeTheme.textDim)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => LibraryStore.instance.toggleLike(song),
                  child: const Icon(Icons.favorite_outline,
                      size: 17, color: VibeTheme.text),
                ),
                const SizedBox(width: 6),
                StreamBuilder<bool>(
                  stream: player.stateStream
                      .map((s) => s.playing)
                      .distinct(),
                  builder: (context, snap) {
                    final playing = snap.data ?? false;
                    return GestureDetector(
                      onTap: player.togglePlay,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          gradient: VibeTheme.accentGradient,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Frosted backdrop used behind sheets.
class BlurBackdrop extends StatelessWidget {
  final Widget child;
  const BlurBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: child,
    );
  }
}
