import 'package:flutter/material.dart';

import '../../core/library_store.dart';
import '../../core/models.dart';
import '../../core/player.dart';
import '../now_playing_sheet.dart';
import '../theme.dart';

/// Row tile used in Trending / Recently played / Liked lists.
/// Translucent surface WITHOUT a backdrop blur: a scrolling list must not
/// run one BlurFilter per row (each is a saveLayer that melts the GPU on
/// mid-range phones). Visually near-identical over the static background.
class SongRow extends StatelessWidget {
  final Song song;
  final int? rank;
  final String? subtitleOverride;
  final VoidCallback? onPlay;
  final bool showLike;
  final List<Song>? queue;

  const SongRow({
    super.key,
    required this.song,
    this.rank,
    this.subtitleOverride,
    this.onPlay,
    this.showLike = false,
    this.queue,
  });

  @override
  Widget build(BuildContext context) {
    final player = PlayerService.instance;
    final isCurrent = player.current?.id == song.id;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x2EFFFFFF), Color(0x12FFFFFF)],
          ),
          border: Border.all(color: const Color(0x26FFFFFF), width: 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPlay ??
              () async {
                await player.play(song, queue: queue);
                await LibraryStore.instance.recordPlay(song);
                if (context.mounted) showNowPlayingSheet(context);
              },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: _rowContent(isCurrent),
          ),
        ),
      ),
    );
  }

  Widget _rowContent(bool isCurrent) {
    return Row(
      children: [
        _RemoteCover(song: song, size: 42),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isCurrent ? VibeTheme.accentLight : VibeTheme.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitleOverride ?? song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 10.5, color: VibeTheme.textDim),
              ),
            ],
          ),
        ),
        if (rank != null)
          Text('#$rank',
              style:
                  const TextStyle(fontSize: 10, color: VibeTheme.textDim)),
        if (showLike) ...[
          const SizedBox(width: 8),
          StreamBuilder<void>(
            stream: LibraryStore.instance.changes,
            builder: (context, _) {
              final liked = LibraryStore.instance.isLiked(song);
              return GestureDetector(
                onTap: () => LibraryStore.instance.toggleLike(song),
                child: Icon(
                  liked ? Icons.favorite : Icons.favorite_outline,
                  size: 17,
                  color:
                      liked ? const Color(0xFFFF7BAC) : VibeTheme.text,
                ),
              );
            },
          ),
        ],
        const SizedBox(width: 10),
        Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            gradient: VibeTheme.accentGradient,
            shape: BoxShape.circle,
          ),
          child: isCurrent
              ? const Icon(Icons.graphic_eq, size: 15, color: Colors.white)
              : const Icon(Icons.play_arrow, size: 15, color: Colors.white),
        ),
      ],
    );
  }
}

/// Cover art that fades in when the network image loads.
class _RemoteCover extends StatelessWidget {
  final Song song;
  final double size;
  const _RemoteCover({required this.song, required this.size});

  @override
  Widget build(BuildContext context) {
    Widget inner;
    if (song.cover.startsWith('http')) {
      inner = Image.network(
        song.cover,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 2).round(),
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSync) {
          if (wasSync) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 250),
            child: child,
          );
        },
        errorBuilder: (_, _, _) => _ph(),
      );
    } else {
      inner = Image.asset(
        song.cover,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _ph(),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(width: size, height: size, color: const Color(0x22FFFFFF), child: inner),
    );
  }

  Widget _ph() => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(gradient: VibeTheme.accentGradient),
        child: const Icon(Icons.music_note, color: Colors.white70, size: 18),
      );
}
