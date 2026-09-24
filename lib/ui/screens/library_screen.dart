import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/library_store.dart';
import '../../core/player.dart';
import '../now_playing_sheet.dart';
import '../theme.dart';
import '../widgets/song_row.dart';

/// Library tab: liked songs (persisted) + recently played.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = LibraryStore.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liked = LibraryStore.instance.likedSongs;
    final recent = LibraryStore.instance.recentSongs;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      children: [
        const Text('Your Library',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: VibeTheme.text)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _actionCard(
                icon: Icons.shuffle,
                label: 'Shuffle liked',
                gradient: true,
                onTap: () async {
                  if (liked.isEmpty) return;
                  await PlayerService.instance
                      .playQueue(liked, shuffle: true, name: 'Liked songs');
                  if (context.mounted) showNowPlayingSheet(context);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _actionCard(
                icon: liked.isEmpty ? Icons.favorite_outline : Icons.favorite,
                label: 'Liked · ${liked.length}',
                onTap: () async {
                  if (liked.isEmpty) return;
                  await PlayerService.instance
                      .playQueue(liked, name: 'Liked songs');
                  if (context.mounted) showNowPlayingSheet(context);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Text('Liked songs',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: VibeTheme.text)),
        const SizedBox(height: 12),
        if (liked.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Tap the heart on any song to save it here.',
                style: TextStyle(color: VibeTheme.textDim, fontSize: 12)),
          )
        else
          for (final s in liked)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SongRow(song: s, showLike: true, queue: liked),
            ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Recently played',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: VibeTheme.text)),
          const SizedBox(height: 12),
          for (final s in recent)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SongRow(song: s, showLike: true, queue: recent),
            ),
        ],
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool gradient = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: gradient
            ? BoxDecoration(
                gradient: VibeTheme.accentGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x99691ED2),
                      blurRadius: 20,
                      offset: Offset(0, 10)),
                ],
              )
            : VibeTheme.glass(radius: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: Colors.white),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
