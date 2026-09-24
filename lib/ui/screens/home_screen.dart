import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/library_store.dart';
import '../../core/models.dart';
import '../../core/player.dart';
import '../../core/remote_catalog.dart';
import '../now_playing_sheet.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/song_row.dart';

/// Home tab — weather/mood card, quick actions, recents and trending.
/// All music comes from the remote JioSaavn backend.
class HomeScreen extends StatefulWidget {
  final void Function(int tab) goToTab;

  const HomeScreen({super.key, required this.goToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Song> _trending = const [];
  bool _trendingLoading = true;
  StreamSubscription<void>? _storeSub;

  @override
  void initState() {
    super.initState();
    _loadTrending();
    _storeSub = LibraryStore.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _storeSub?.cancel();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    final songs = await RemoteCatalog.trending(limit: 8);
    if (!mounted) return;
    setState(() {
      _trending = songs;
      _trendingLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final recent = LibraryStore.instance.recentSongs.take(5).toList();

    return RefreshIndicator(
      color: VibeTheme.accentLight,
      backgroundColor: VibeTheme.bgMid,
      onRefresh: () async {
        setState(() => _trendingLoading = true);
        await _loadTrending();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          _buildHeader(context),
          const SizedBox(height: 18),
          const _WeatherMoodCard(),
          const SizedBox(height: 20),
          _buildCategories(context),
          const SizedBox(height: 22),
          if (recent.isNotEmpty) ...[
            _sectionTitle('Recently played',
                onMore: () => widget.goToTab(2)),
            const SizedBox(height: 12),
            _CoverCarousel(songs: recent),
            const SizedBox(height: 22),
          ],
          _sectionTitle('Trending now', onMore: () => widget.goToTab(1)),
          const SizedBox(height: 12),
          if (_trendingLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: VibeTheme.accentLight),
                ),
              ),
            )
          else if (_trending.isEmpty)
            GlassContainer(
              child: const Text(
                'Could not reach the music service.\nPull down to retry.',
                textAlign: TextAlign.center,
                style: TextStyle(color: VibeTheme.textDim, fontSize: 12),
              ),
            )
          else
            for (var i = 0; i < _trending.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SongRow(
                    song: _trending[i],
                    rank: i + 1,
                    showLike: true,
                    queue: _trending),
              ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: VibeTheme.accentGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x99691ED2),
                  blurRadius: 20,
                  offset: Offset(0, 10)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset('assets/icons/logo_mark.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.music_note,
                    color: Colors.white, size: 22)),
          ),
        ),
        const SizedBox(width: 11),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ListenGood',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: VibeTheme.text)),
              Text('What do you want to listen to?',
                  style: TextStyle(fontSize: 11, color: VibeTheme.textDim)),
            ],
          ),
        ),
        _roundIcon(Icons.search, () => widget.goToTab(1)),
      ],
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x59FFFFFF), Color(0x0FFFFFFF)],
          ),
          border: Border.all(color: VibeTheme.glassBorder),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: VibeTheme.text),
      ),
    );
  }

  Widget _buildCategories(BuildContext context) {
    final items = [
      (Icons.playlist_play, 'Trending', 1, true),
      (Icons.search_rounded, 'Search', 1, false),
      (Icons.favorite, 'Liked', 2, false),
    ];
    return Row(
      children: [
        for (final (icon, label, tab, accent) in items)
          Expanded(
            child: GestureDetector(
              onTap: () => widget.goToTab(tab),
              child: Container(
                margin: EdgeInsets.only(right: label == 'Liked' ? 0 : 10),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: accent
                    ? BoxDecoration(
                        gradient: VibeTheme.accentGradient,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x99691ED2),
                              blurRadius: 22,
                              offset: Offset(0, 12)),
                        ],
                      )
                    : VibeTheme.glass(radius: 16),
                child: Column(
                  children: [
                    Icon(icon, size: 18, color: Colors.white),
                    const SizedBox(height: 5),
                    Text(label,
                        style:
                            const TextStyle(fontSize: 10, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String title, {VoidCallback? onMore}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: VibeTheme.text)),
        GestureDetector(
          onTap: onMore,
          child:
              const Icon(Icons.chevron_right, size: 16, color: VibeTheme.textDim),
        ),
      ],
    );
  }
}

/// 24°C / light rain mood card (static demo widget kept from the design).
class _WeatherMoodCard extends StatelessWidget {
  const _WeatherMoodCard();

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      radius: 20,
      strong: true,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x59FFFFFF), Color(0x0DFFFFFF)],
              ),
              border: Border.all(color: VibeTheme.glassBorder),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.cloud, color: Color(0xFFFFD68A), size: 24),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('24°C',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w500,
                            color: VibeTheme.text)),
                    SizedBox(width: 6),
                    Padding(
                      padding: EdgeInsets.only(bottom: 3),
                      child: Text('light rain',
                          style: TextStyle(
                              fontSize: 12, color: VibeTheme.textDim)),
                    ),
                  ],
                ),
                SizedBox(height: 3),
                Text('Rishikesh, Uttarakhand',
                    style:
                        TextStyle(fontSize: 11, color: VibeTheme.textDim)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Mood mix',
                  style: TextStyle(fontSize: 10, color: VibeTheme.textFaint)),
              const SizedBox(height: 3),
              GestureDetector(
                onTap: () async {
                  final songs = await RemoteCatalog.searchSongs('rain lofi',
                      limit: 15);
                  if (songs.isNotEmpty && context.mounted) {
                    await PlayerService.instance
                        .playQueue(songs, shuffle: true, name: 'Rainy lo-fi');
                    if (context.mounted) showNowPlayingSheet(context);
                  }
                },
                child: const Text('Rainy lo-fi',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: VibeTheme.text)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 3D perspective cover carousel: center cover large, sides tilted.
class _CoverCarousel extends StatelessWidget {
  final List<Song> songs;
  const _CoverCarousel({required this.songs});

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();
    final player = PlayerService.instance;

    Widget tile(Song song, double size, {double tilt = 0, VoidCallback? onTap}) {
      return GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)
                ..rotateY(tilt)
                ..scale(size / 96, size / 96, size / 96),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x8C140537),
                        blurRadius: 24,
                        offset: Offset(0, 14)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: song.cover.startsWith('http')
                      ? Image.network(song.cover,
                          fit: BoxFit.cover,
                          cacheWidth: (size * 2).round(),
                          filterQuality: FilterQuality.low,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => Container(
                              decoration: BoxDecoration(
                                  gradient: VibeTheme.accentGradient)))
                      : Image.asset(song.cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                              decoration: BoxDecoration(
                                  gradient: VibeTheme.accentGradient))),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: size + 12,
              child: Text(song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: VibeTheme.text)),
            ),
            Text(song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: VibeTheme.textDim)),
          ],
        ),
      );
    }

    void play(Song s) async {
      await player.play(s, queue: songs);
      if (context.mounted) showNowPlayingSheet(context);
    }

    return SizedBox(
      height: 158,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (songs.length > 2)
            tile(songs[2], 80, tilt: 0.42, onTap: () => play(songs[2])),
          const SizedBox(width: 12),
          if (songs.isNotEmpty)
            tile(songs[0], 94, onTap: () => play(songs[0])),
          const SizedBox(width: 12),
          if (songs.length > 1)
            tile(songs[1], 80, tilt: -0.42, onTap: () => play(songs[1])),
        ],
      ),
    );
  }
}
