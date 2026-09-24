import 'dart:async';

import 'package:flutter/material.dart';

import '../core/player.dart';
import '../core/spotify_import.dart';
import 'theme.dart';
import 'now_playing_sheet.dart';
import 'widgets/glass.dart';

/// Glossy Spotify-import screen: paste a playlist link, watch tracks get
/// matched one-by-one with a live "done / remaining" counter, then play.
class SpotifyImportScreen extends StatefulWidget {
  const SpotifyImportScreen({super.key});

  @override
  State<SpotifyImportScreen> createState() => _SpotifyImportScreenState();
}

enum _Phase { input, importing, done, failed }

class _SpotifyImportScreenState extends State<SpotifyImportScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  _Phase _phase = _Phase.input;
  ImportProgress? _progress;
  ImportResult? _result;
  String? _error;
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  Future<void> _startImport() async {
    final id = SpotifyImporter.extractId(_controller.text);
    if (id == null) {
      setState(() {
        _error = 'Paste a valid Spotify playlist link or 22-character id.';
        _phase = _Phase.failed;
      });
      return;
    }
    setState(() {
      _phase = _Phase.importing;
      _error = null;
      _result = null;
      _progress = null;
    });
    await for (final p in SpotifyImporter.import(id)) {
      if (!mounted) return;
      setState(() => _progress = p);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    if (!mounted) return;
    final result = SpotifyImporter.takeResult();
    if (result == null || result.songs.isEmpty) {
      setState(() {
        _error =
            'No tracks could be matched on JioSaavn. Check the link and try again.';
        _phase = _Phase.failed;
      });
      return;
    }
    setState(() {
      _result = result;
      _phase = _Phase.done;
    });
  }

  void _playImported() {
    final result = _result;
    if (result == null || result.songs.isEmpty) return;
    // Shuffle is the default queue mode.
    unawaited(PlayerService.instance
        .playQueue(List.of(result.songs), shuffle: true, name: result.playlistName));
    Navigator.of(context).pop();
    showNowPlayingSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(gradient: VibeTheme.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _header(context),
              Expanded(
                child: switch (_phase) {
                  _Phase.input => _buildInput(),
                  _Phase.importing => _buildImporting(),
                  _Phase.done => _buildDone(),
                  _Phase.failed => _buildFailed(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: VibeTheme.text, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text('Import from Spotify',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: VibeTheme.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ input

  Widget _buildInput() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heroCard(),
          const SizedBox(height: 22),
          Container(
            decoration: VibeTheme.glass(radius: 18),
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: VibeTheme.text, fontSize: 13),
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                border: InputBorder.none,
                hintText:
                    'https://open.spotify.com/playlist/… or playlist id',
                hintStyle: TextStyle(color: VibeTheme.textFaint, fontSize: 12),
                prefixIcon: Icon(Icons.link, color: VibeTheme.accentLight),
              ),
              cursorColor: VibeTheme.accentLight,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(
                    color: Color(0xFFFF8FA8), fontSize: 12)),
          ],
          const SizedBox(height: 18),
          _glossyButton(
            label: 'Import playlist',
            icon: Icons.download_rounded,
            onTap: _startImport,
          ),
          const SizedBox(height: 20),
          const Text(
            'Public playlists and albums work — no Spotify login needed. '
            'Every track is matched to a playable song on JioSaavn.',
            textAlign: TextAlign.center,
            style: TextStyle(color: VibeTheme.textFaint, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      height: 148,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1DB954), Color(0xFF0E5A2B)],
        ),
        border: Border.all(color: const Color(0x55FFFFFF), width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color(0x6600C853),
              blurRadius: 30,
              offset: Offset(0, 12)),
        ],
      ),
      child: Stack(
        children: [
          // gloss sweep
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AnimatedBuilder(
                animation: _shimmer,
                builder: (context, _) {
                  final t = _shimmer.value;
                  return Align(
                    alignment: Alignment(-2 + 4 * t, -0.6),
                    child: Transform.rotate(
                      angle: 0.35,
                      child: Container(
                        width: 70,
                        height: 260,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.0),
                              Colors.white.withOpacity(0.18),
                              Colors.white.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.library_music_rounded,
                    color: Colors.white, size: 40),
                const SizedBox(height: 8),
                const Text('Bring your Spotify playlists',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('Matched to playable songs, ready to shuffle',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- importing

  Widget _buildImporting() {
    final p = _progress;
    if (p == null) {
      return const Center(
          child: CircularProgressIndicator(color: VibeTheme.accentLight));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(p.playlistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: VibeTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          // Glossy progress track
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  color: const Color(0x22FFFFFF),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
              ),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: p.fraction.clamp(0.02, 1.0),
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1DB954), Color(0xFF8B3FF0)],
                    ),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x771DB954), blurRadius: 16),
                    ],
                  ),
                ),
              ),
              Text('${(p.fraction * 100).round()}%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _counter('${p.matched}', 'matched'),
              _counter('${p.remaining}', 'remaining'),
              _counter('${p.total}', 'total'),
            ],
          ),
          const SizedBox(height: 22),
          GlassContainer(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: VibeTheme.accentLight),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    p.currentTitle.isEmpty
                        ? 'Finishing up…'
                        : 'Matching: ${p.currentTitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: VibeTheme.textDim, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- done

  Widget _buildDone() {
    final r = _result!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: VibeTheme.glass(radius: 22, strong: true),
            child: Column(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF1DB954), size: 44),
                const SizedBox(height: 10),
                Text(r.playlistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: VibeTheme.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _counter('${r.songs.length}', 'ready to play'),
                    _counter('${r.unmatched.length}', 'unmatched'),
                    _counter('${r.totalTracks}', 'scanned'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: r.songs.length.clamp(0, 50),
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final s = r.songs[i];
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x2EFFFFFF), Color(0x12FFFFFF)],
                    ),
                    border: Border.all(color: const Color(0x26FFFFFF)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: s.cover.startsWith('http')
                            ? Image.network(s.cover,
                                width: 38,
                                height: 38,
                                fit: BoxFit.cover,
                                cacheWidth: 76,
                                filterQuality: FilterQuality.low,
                                errorBuilder: (_, _, _) => Container(
                                    width: 38,
                                    height: 38,
                                    color: const Color(0x22FFFFFF)))
                            : Container(
                                width: 38,
                                height: 38,
                                color: const Color(0x22FFFFFF)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: VibeTheme.text, fontSize: 12.5)),
                            Text(s.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: VibeTheme.textDim, fontSize: 10.5)),
                          ],
                        ),
                      ),
                      const Icon(Icons.music_note,
                          size: 15, color: VibeTheme.accentLight),
                    ],
                  ),
                );
              },
            ),
          ),
          if (r.unmatched.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Couldn\u2019t match: ${r.unmatched.take(3).join(' · ')}'
                '${r.unmatched.length > 3 ? ' +${r.unmatched.length - 3} more' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: VibeTheme.textFaint, fontSize: 10.5),
              ),
            ),
          const SizedBox(height: 14),
          _glossyButton(
            label: 'Play shuffled',
            icon: Icons.play_arrow_rounded,
            onTap: _playImported,
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- failed

  Widget _buildFailed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off_rounded,
                color: VibeTheme.textFaint, size: 44),
            const SizedBox(height: 12),
            Text(_error ?? 'Import failed',
                textAlign: TextAlign.center,
                style: const TextStyle(color: VibeTheme.textDim, fontSize: 13)),
            const SizedBox(height: 18),
            _glossyButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onTap: () => setState(() {
                _phase = _Phase.input;
                _error = null;
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- shared

  Widget _counter(String value, String label) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: VibeTheme.text)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  const TextStyle(fontSize: 10.5, color: VibeTheme.textDim)),
        ],
      );

  Widget _glossyButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: VibeTheme.accentGradient,
          border: Border.all(color: const Color(0x55FFFFFF), width: 1),
          boxShadow: const [
            BoxShadow(
                color: Color(0x8C691ED2), blurRadius: 22, offset: Offset(0, 10)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Opens the import screen as a modal route.
Future<void> showSpotifyImport(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const SpotifyImportScreen(),
  ));
}
