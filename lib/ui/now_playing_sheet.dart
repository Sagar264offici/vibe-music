import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'theme.dart';
import '../core/library_store.dart';
import '../core/lyrics.dart';
import '../core/models.dart';
import '../core/player.dart';

/// Full-screen Now Playing: cover art on top, then one premium frosted-glass
/// panel containing (in order) synced lyrics, a waveform playback timeline,
/// time labels, compact song info and the playback controls.
class NowPlayingSheet extends StatefulWidget {
  const NowPlayingSheet({super.key});

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet> {
  List<LyricLine> _lyrics = const [];
  bool _lyricsLoading = false;

  /// Lyrics are lazy: nothing is fetched or timed until the user opens the
  /// lyrics view. Toggling back to the player pauses lyric syncing entirely.
  bool _showLyrics = false;
  final ScrollController _lyricsCtrl = ScrollController();
  Timer? _ticker;
  int _activeLine = -1;
  StreamSubscription<void>? _sub;
  Song? _lyricsForSong;

  @override
  void initState() {
    super.initState();
    _sub = PlayerService.instance.changes.listen((_) => _onTrackChanged());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _lyricsCtrl.dispose();
    super.dispose();
  }

  void _onTrackChanged() {
    if (!_showLyrics) return; // lazy: fetch only when the lyrics view is open
    final song = PlayerService.instance.current;
    if (song == null || identical(song, _lyricsForSong)) return;
    _lyricsForSong = song;
    _loadLyrics(song);
  }

  void _openLyrics() {
    setState(() => _showLyrics = true);
    final song = PlayerService.instance.current;
    if (song == null || identical(song, _lyricsForSong)) {
      _startTicker();
      return;
    }
    _lyricsForSong = song;
    _loadLyrics(song);
  }

  void _closeLyrics() {
    setState(() => _showLyrics = false);
    _ticker?.cancel();
    _ticker = null; // stop the 150ms lyric sync while not viewing lyrics
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(
        const Duration(milliseconds: 150), (_) => _syncLyrics());
  }

  Future<void> _loadLyrics(Song song) async {
    setState(() {
      _lyricsLoading = true;
      _lyrics = const [];
      _activeLine = -1;
    });
    final lyrics = await LyricsService.bestEffort(song);
    if (!mounted || _lyricsForSong?.id != song.id) return;
    setState(() {
      _lyrics = lyrics;
      _lyricsLoading = false;
    });
    _startTicker();
  }

  bool get _hasSyncedLyrics =>
      _lyrics.length > 1 && _lyrics.any((l) => l.start > 0);

  void _syncLyrics() {
    if (!mounted ||
        !_showLyrics ||
        _lyrics.isEmpty ||
        !_hasSyncedLyrics ||
        !_lyricsCtrl.hasClients) {
      return;
    }
    final posMs = PlayerService.instance.position.inMilliseconds;
    var idx = -1;
    for (var i = 0; i < _lyrics.length; i++) {
      if (_lyrics[i].start <= posMs) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx == _activeLine) return;
    setState(() => _activeLine = idx);
    if (idx >= 0 && _lyricsCtrl.hasClients) {
      final viewport = _lyricsCtrl.position.viewportDimension;
      final itemExtent = _lyricsItemExtent(viewport);
      final target = (idx * itemExtent - viewport / 2 + itemExtent / 2)
          .clamp(0.0, _lyricsCtrl.position.maxScrollExtent);
      _lyricsCtrl.animateTo(target,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic);
    }
  }

  double _lyricsItemExtent(double viewport) => (viewport * 0.155).clamp(30.0, 46.0);

  @override
  Widget build(BuildContext context) {
    final player = PlayerService.instance;
    return StreamBuilder<void>(
      stream: player.changes,
      builder: (context, _) {
        final song = player.current;
        if (song == null) return const SizedBox.shrink();
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (song.cover.startsWith('http'))
                Image.network(song.cover,
                    fit: BoxFit.cover,
                    cacheWidth: 720,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => _bgFallback())
              else
                Image.asset(song.cover,
                    fit: BoxFit.cover, errorBuilder: (_, _, _) => _bgFallback()),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                child: Container(color: Colors.black.withOpacity(0.42)),
              ),
              SafeArea(child: _buildBody(context, song, player)),
            ],
          ),
        );
      },
    );
  }

  Widget _bgFallback() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [VibeTheme.bgTop, VibeTheme.bgBottom],
          ),
        ),
      );

  // ------------------------------------------------------------------- body

  Widget _buildBody(BuildContext context, Song song, PlayerService player) {
    return LayoutBuilder(builder: (context, constraints) {
      final h = constraints.maxHeight;
      // Responsive: shrink artwork + panel on small 9:16 viewports so the
      // controls always stay comfortably reachable.
      final coverSize = (h * 0.30).clamp(140.0, 210.0);
      final panelH = h - 48 - coverSize - 24;
      final lyricsH = (panelH * 0.34).clamp(96.0, 170.0);

      return Column(
        children: [
          _sheetHeader(
            context,
            title: 'Now Playing',
            subtitle: song.album.isEmpty ? song.artist : song.album,
            trailing: Icons.queue_music,
            onTrailing: () => _showQueue(context),
          ),
          SizedBox(height: h < 680 ? 2 : 8),
          _CoverDisc(song: song, size: coverSize),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, h < 680 ? 8 : 14, 16, h < 680 ? 8 : 12),
              child: _GlassPanel(
                lyricsHeight: lyricsH,
                lyrics: _buildLyricsArea(player, lyricsH),
                waveform: _WaveformTimeline(player: player),
                info: _buildSongInfo(song),
                controls: _buildControls(player),
              ),
            ),
          ),
        ],
      );
    });
  }

  // ------------------------------------------------------------ lyrics area

  Widget _buildLyricsArea(PlayerService player, double height) {
    // Lyrics stay completely unloaded until the user taps the lyrics tile.
    if (!_showLyrics) {
      return SizedBox(
        height: height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openLyrics,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0x33FFFFFF)),
                color: const Color(0x14FFFFFF),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lyrics, size: 18, color: VibeTheme.accentLight),
                  SizedBox(width: 8),
                  Text('Lyrics',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: VibeTheme.text)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_lyricsLoading) {
      return SizedBox(
        height: height,
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: VibeTheme.accentLight),
          ),
        ),
      );
    }
    if (_lyrics.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeLyrics,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Lyrics unavailable',
                    style:
                        TextStyle(color: VibeTheme.textFaint, fontSize: 13)),
                SizedBox(height: 8),
                Text('Close',
                    style: TextStyle(
                        color: VibeTheme.accentLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }
    final synced = _hasSyncedLyrics;
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.0, 0.16, 0.8, 1.0],
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _lyricsCtrl,
        padding: EdgeInsets.symmetric(vertical: height * 0.28),
        itemCount: _lyrics.length,
        itemBuilder: (context, i) {
          final dist = _activeLine < 0 ? 3 : (i - _activeLine).abs();
          final active = i == _activeLine && synced;
          // Distance-based hierarchy: active = dominant, nearby = secondary,
          // distant = barely visible.
          final opacity = active
              ? 1.0
              : switch (dist) {
                  1 => 0.62,
                  2 => 0.42,
                  _ => 0.22,
                };
          final fontSize = active
              ? 19.0
              : switch (dist) {
                  1 => 16.0,
                  2 => 15.0,
                  _ => 14.0,
                };
          final weight = active ? FontWeight.w800 : FontWeight.w500;
          final color = active ? VibeTheme.text : VibeTheme.textDim;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: synced
                ? () =>
                    player.seekTo(Duration(milliseconds: _lyrics[i].start))
                : null,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
              opacity: synced ? opacity : (active ? 1 : 0.62),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: weight,
                  color: color,
                  height: 1.3,
                  shadows: active
                      ? const [
                          Shadow(
                              blurRadius: 22, color: Color(0x99C79BFF)),
                        ]
                      : const [],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 7),
                  child: Text(
                    _lyrics[i].text,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------- info/ctrl

  Widget _buildSongInfo(Song song) {
    return Row(
      children: [
        StreamBuilder<void>(
          stream: LibraryStore.instance.changes,
          builder: (context, _) {
            final liked = LibraryStore.instance.isLiked(song);
            return IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => LibraryStore.instance.toggleLike(song),
              icon: Icon(
                liked ? Icons.favorite : Icons.favorite_outline,
                size: 20,
                color:
                    liked ? const Color(0xFFFF7BAC) : VibeTheme.textDim,
              ),
            );
          },
        ),
        Expanded(
          child: Column(
            children: [
              Text(song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: VibeTheme.text)),
              const SizedBox(height: 1),
              Text(song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 12, color: VibeTheme.textDim)),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => _showQueue(context),
          icon: const Icon(Icons.queue_music,
              size: 20, color: VibeTheme.textDim),
        ),
      ],
    );
  }

  Widget _buildControls(PlayerService player) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _ctrl(Icons.shuffle,
            active: player.shuffleOn, onTap: player.toggleShuffle),
        _ctrl(Icons.skip_previous, color: VibeTheme.text, onTap: player.previous),
        _playButton(player),
        _ctrl(Icons.skip_next, color: VibeTheme.text, onTap: player.next),
        _ctrl(
          switch (player.repeat) {
            RepeatMode.off => Icons.repeat,
            RepeatMode.all => Icons.repeat,
            RepeatMode.one => Icons.repeat_one,
          },
          color: player.repeat == RepeatMode.off
              ? VibeTheme.textDim
              : VibeTheme.accentLight,
          active: player.repeat != RepeatMode.off,
          onTap: player.cycleRepeat,
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- shared

  Future<void> _showQueue(BuildContext context) async {
    final player = PlayerService.instance;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: const Color(0xE6220E42),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: VibeTheme.glassBorder),
          ),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text('Up Next',
                    style: TextStyle(
                        color: VibeTheme.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ),
              Expanded(
                child: StreamBuilder<void>(
                  stream: player.changes,
                  builder: (context, _) {
                    final queue = player.upNext;
                    if (queue.isEmpty) {
                      return const Center(
                          child: Text('Queue is empty',
                              style: TextStyle(color: VibeTheme.textDim)));
                    }
                    return ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                      itemCount: queue.length,
                      itemBuilder: (context, i) => ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: queue[i].cover.startsWith('http')
                              ? Image.network(queue[i].cover,
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                  cacheWidth: 84,
                                  filterQuality: FilterQuality.low,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox(width: 42, height: 42))
                              : const SizedBox(width: 42, height: 42),
                        ),
                        title: Text(queue[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: VibeTheme.text, fontSize: 13)),
                        subtitle: Text(queue[i].artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: VibeTheme.textDim, fontSize: 11)),
                        onTap: () {
                          Navigator.pop(context);
                          // Play within the full shuffle order so the queue
                          // around the tapped track is preserved (8.6).
                          player.playFromUpNext(queue[i]);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData trailing,
    required VoidCallback onTrailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down,
                  color: VibeTheme.text, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: VibeTheme.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: VibeTheme.textDim, fontSize: 10)),
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              icon: Icon(trailing, color: VibeTheme.textDim, size: 22),
              onPressed: onTrailing,
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctrl(IconData icon,
      {bool active = false, Color? color, VoidCallback? onTap}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon,
              size: 22,
              color: active
                  ? VibeTheme.accentLight
                  : (color ?? VibeTheme.textDim)),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? VibeTheme.accentLight : Colors.transparent,
          ),
        ),
      ],
    );
  }

  Widget _playButton(PlayerService player) {
    return StreamBuilder<bool>(
      stream: player.stateStream.map((s) => s.playing).distinct(),
      builder: (context, snap) {
        final playing = snap.data ?? false;
        return GestureDetector(
          onTap: player.togglePlay,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: VibeTheme.accentGradient,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x55FFFFFF), width: 1),
              boxShadow: [
                BoxShadow(
                  color: VibeTheme.accent.withOpacity(0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(playing ? Icons.pause : Icons.play_arrow,
                size: 30, color: Colors.white),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------- panels

/// The single frosted-glass panel: lyrics hero on top, waveform timeline,
/// time labels, song info, controls — the exact required hierarchy.
class _GlassPanel extends StatelessWidget {
  final double lyricsHeight;
  final Widget lyrics;
  final Widget waveform;
  final Widget info;
  final Widget controls;

  const _GlassPanel({
    required this.lyricsHeight,
    required this.lyrics,
    required this.waveform,
    required this.info,
    required this.controls,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: VibeTheme.glass(radius: 26, strong: true),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: const BoxDecoration(
              // faint top inner highlight, like light catching glass
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x14FFFFFF), Color(0x00FFFFFF)],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Column(
              children: [
                SizedBox(
                  height: lyricsHeight,
                  child: lyrics,
                ),
                const SizedBox(height: 8),
                waveform,
                const SizedBox(height: 2),
                info,
                const SizedBox(height: 2),
                controls,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Premium playback timeline: deterministic per-track waveform bars, played
/// portion tinted with the accent, remaining portion subtle; draggable seek
/// with a circular playhead. Bar heights are a lightweight visual signature
/// derived from the track id (no real PCM), and the fill strictly follows the
/// real audio position.
class _WaveformTimeline extends StatefulWidget {
  final PlayerService player;
  const _WaveformTimeline({required this.player});

  @override
  State<_WaveformTimeline> createState() => _WaveformTimelineState();
}

class _WaveformTimelineState extends State<_WaveformTimeline> {
  List<double> _bars = const [];
  String _barsForId = '';
  double? _dragFraction;

  static const int _barCount = 44;

  void _ensureBars(String songId) {
    if (_barsForId == songId) return;
    _barsForId = songId;
    final rng = Random(songId.hashCode);
    final raw = List.generate(_barCount, (_) => rng.nextDouble());
    // Smooth into a gentle wave so it reads as audio, not noise.
    final smoothed = List<double>.filled(_barCount, 0);
    for (var i = 0; i < _barCount; i++) {
      var sum = 0.0;
      var count = 0;
      for (var d = -1; d <= 1; d++) {
        final j = i + d;
        if (j >= 0 && j < _barCount) {
          sum += raw[j];
          count++;
        }
      }
      smoothed[i] = sum / count;
    }
    // Normalize to a pleasant 0.28..1.0 range.
    final maxV = smoothed.reduce(max);
    _bars = smoothed.map((v) => 0.28 + 0.72 * (v / maxV)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final song = player.current;
    _ensureBars(song?.id ?? 'unknown');
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final pos = _dragFraction != null && player.duration != null
            ? Duration(
                milliseconds:
                    (_dragFraction! * player.duration!.inMilliseconds).round())
            : (snap.data ?? Duration.zero);
        final dur = player.duration ?? Duration.zero;
        final fraction = dur.inMilliseconds <= 0
            ? 0.0
            : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
        return Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => _setDrag(d.localPosition.dx, context),
              onHorizontalDragUpdate: (d) =>
                  _setDrag(d.localPosition.dx, context),
              onHorizontalDragEnd: (_) => _commitSeek(),
              onTapDown: (d) {
                _setDrag(d.localPosition.dx, context);
                _commitSeek();
              },
              child: SizedBox(
                height: 34,
                width: double.infinity,
                child: CustomPaint(
                  painter: _WaveformPainter(
                    bars: _bars,
                    progress: fraction,
                    dragging: _dragFraction != null,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(pos),
                      style: const TextStyle(
                          fontSize: 11,
                          color: VibeTheme.textDim,
                          fontFeatures: [])),
                  Text(_fmt(dur),
                      style: const TextStyle(
                          fontSize: 11, color: VibeTheme.textDim)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _setDrag(double dx, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final width = box.size.width;
    if (width <= 0) return;
    setState(() => _dragFraction = (dx / width).clamp(0.0, 1.0));
  }

  Future<void> _commitSeek() async {
    final f = _dragFraction;
    if (f == null) return;
    setState(() => _dragFraction = null);
    final dur = widget.player.duration;
    if (dur != null && dur > Duration.zero) {
      await widget.player.seekTo(
          Duration(milliseconds: (f * dur.inMilliseconds).round()));
    }
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final bool dragging;

  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final n = bars.length;
    final slot = size.width / n;
    final barW = min(slot * 0.55, 4.0);
    final midY = size.height / 2;

    final playedPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFC79BFF), Color(0xFF8B3FF0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barW;
    final restPaint = Paint()
      ..color = const Color(0x2EFFFFFF)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barW;

    final playedX = progress * size.width;
    for (var i = 0; i < n; i++) {
      final x = slot * (i + 0.5);
      final barH = bars[i] * size.height * 0.82;
      final paint = x <= playedX ? playedPaint : restPaint;
      canvas.drawLine(Offset(x, midY - barH / 2), Offset(x, midY + barH / 2),
          paint);
    }

    // Playhead: elegant ring slightly taller than the bars.
    final px = playedX.clamp(0.0, size.width);
    final playhead = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(dragging ? 1.0 : 0.9);
    canvas.drawCircle(Offset(px, midY), dragging ? 7 : 5.5, playhead);
    final fill = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(px, midY), 2.4, fill);
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.dragging != dragging;
}

// -------------------------------------------------------------------- cover

class _CoverDisc extends StatelessWidget {
  final Song song;
  final double size;

  const _CoverDisc({required this.song, required this.size});

  @override
  Widget build(BuildContext context) {
    final image = song.cover.startsWith('http')
        ? Image.network(song.cover,
            fit: BoxFit.cover,
            cacheWidth: (size * 2).round(),
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _ph())
        : Image.asset(song.cover,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _ph());
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.22), width: 5),
        boxShadow: const [
          BoxShadow(
              color: Color(0x66000000), blurRadius: 36, offset: Offset(0, 14)),
        ],
      ),
      child: ClipOval(child: image),
    );
  }

  Widget _ph() => Container(
        decoration: const BoxDecoration(gradient: VibeTheme.accentGradient),
        child: const Icon(Icons.music_note, color: Colors.white70, size: 44),
      );
}

/// Opens the Now Playing sheet as a modal full-screen route.
Future<void> showNowPlayingSheet(BuildContext context) {
  return Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) => const NowPlayingSheet(),
    transitionsBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ));
}
