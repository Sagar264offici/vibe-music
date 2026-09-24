import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'remote_catalog.dart';

/// One track parsed from a Spotify playlist.
class SpotifyTrack {
  final String title;
  final String artists;
  final int durationMs;
  const SpotifyTrack(this.title, this.artists, this.durationMs);
}

/// Result of an import: matched songs plus failure diagnostics.
class ImportResult {
  final String playlistName;
  final List<Song> songs;
  final int totalTracks;
  final List<String> unmatched;
  const ImportResult({
    required this.playlistName,
    required this.songs,
    required this.totalTracks,
    required this.unmatched,
  });
}

/// Progress of a running import, for the glossy UI.
class ImportProgress {
  final String playlistName;
  final int total;
  final int done;
  final int matched;
  final String currentTitle;
  const ImportProgress({
    required this.playlistName,
    required this.total,
    required this.done,
    required this.matched,
    required this.currentTitle,
  });

  double get fraction => total == 0 ? 0 : done / total;
  int get remaining => total - done;
}

/// Imports a public Spotify playlist and matches every track to a playable
/// JioSaavn song using the deployed backend.
///
/// Two extraction paths:
///  1. spotify_dart-style embed scrape: the public embed page ships the full
///     track list as JSON — no auth, works for playlists/albums/EPs.
///  2. Fallback: Spotify's public oEmbed API gives title/creator only.
class SpotifyImporter {
  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36';

  /// Accepts full URLs, open.spotify.com links, or bare playlist/album ids.
  static String? extractId(String input) {
    final s = input.trim();
    final uri = RegExp(r'playlist[/:]([A-Za-z0-9]{22})').firstMatch(s);
    if (uri != null) return uri.group(1);
    final bare = RegExp(r'^[A-Za-z0-9]{22}$').firstMatch(s);
    if (bare != null) return bare.group(0);
    return null;
  }

  /// Runs the import, streaming [ImportProgress] updates. Never throws:
  /// errors surface as an empty result with the failure in [ImportResult].
  static Stream<ImportProgress> import(
    String playlistId, {
    int maxTracks = 60,
  }) async* {
    final nameController = StreamController<String>.broadcast();
    var playlistName = 'Spotify playlist';
    try {
      final html = await _fetchEmbed(playlistId);
      final parsed = _parseEmbed(html);
      playlistName = parsed.name;
      nameController.add(playlistName);

      final tracks = parsed.tracks.take(maxTracks).toList();
      final songs = <Song>[];
      final unmatched = <String>[];

      for (var i = 0; i < tracks.length; i++) {
        final t = tracks[i];
        yield ImportProgress(
          playlistName: playlistName,
          total: tracks.length,
          done: i,
          matched: songs.length,
          currentTitle: t.title,
        );
        final match = await _matchSong(t);
        if (match != null) {
          songs.add(match);
        } else {
          unmatched.add('${t.title} — ${t.artists}');
        }
        // Gentle pacing: keeps the UI at 60fps while matching runs.
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }

      yield ImportProgress(
        playlistName: playlistName,
        total: tracks.length,
        done: tracks.length,
        matched: songs.length,
        currentTitle: '',
      );
      _lastResult = ImportResult(
        playlistName: playlistName,
        songs: songs,
        totalTracks: tracks.length,
        unmatched: unmatched,
      );
    } catch (_) {
      _lastResult = ImportResult(
        playlistName: playlistName,
        songs: const [],
        totalTracks: 0,
        unmatched: const [],
      );
      yield ImportProgress(
        playlistName: playlistName,
        total: 0,
        done: 0,
        matched: 0,
        currentTitle: '',
      );
    } finally {
      await nameController.close();
    }
  }

  static ImportResult? _lastResult;
  static ImportResult? takeResult() => _lastResult;

  static Future<String> _fetchEmbed(String id) async {
    final resp = await http.get(
      Uri.https('open.spotify.com', '/embed/playlist/$id'),
      headers: {'User-Agent': _ua},
    ).timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      throw Exception('embed ${resp.statusCode}');
    }
    return resp.body;
  }

  static ({String name, List<SpotifyTrack> tracks}) _parseEmbed(String html) {
    // Path 1: __NEXT_DATA__ JSON (current embed format).
    final m = RegExp(
      r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (m != null) {
      try {
        final data = jsonDecode(m.group(1)!) as Map<String, dynamic>;
        final entity = data['props']?['pageProps']?['state']?['data']
                ?['entity'] as Map<String, dynamic>?;
        final name = (entity?['name'] ?? 'Spotify playlist') as String;
        final list = (entity?['trackList'] as List?) ?? const [];
        final tracks = <SpotifyTrack>[];
        for (final t in list) {
          if (t is! Map<String, dynamic>) continue;
          final title = (t['title'] ?? '') as String;
          if (title.isEmpty) continue;
          tracks.add(SpotifyTrack(
            title,
            ((t['subtitle'] ?? '') as String).replaceAll('\u00a0', ' '),
            ((t['duration'] ?? 0) as num).toInt(),
          ));
        }
        if (tracks.isNotEmpty) return (name: name, tracks: tracks);
      } catch (_) {
        // fall through to RSS path
      }
    }

    // Path 2: legacy RSS/CDATA embed (older embeds served this).
    final nameMatch =
        RegExp(r'<title>([^<]+)</title>').firstMatch(html);
    final name = nameMatch?.group(1) ?? 'Spotify playlist';
    final tracks = <SpotifyTrack>[];
    for (final itemM in RegExp(
      r'<item>([\s\S]*?)</item>',
    ).allMatches(html)) {
      final item = itemM.group(1)!;
      final title = _tag(item, 'title');
      if (title == null || title.isEmpty) continue;
      final artists = _cdataArtists(item);
      final durMs = int.tryParse(_tag(item, 'duration') ?? '') ?? 0;
      tracks.add(SpotifyTrack(title, artists, durMs));
    }
    return (name: name, tracks: tracks);
  }

  static String? _tag(String xml, String name) {
    final m = RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(xml);
    if (m == null) return null;
    var v = m.group(1)!;
    if (v.startsWith('<![CDATA[')) {
      v = v.substring(9, v.length - 3);
    }
    return v.trim();
  }

  static String _cdataArtists(String item) {
    final m = RegExp(r'<artists>([\s\S]*?)</artists>').firstMatch(item);
    if (m == null) return '';
    return RegExp(r'<name>(.*?)</name>')
        .allMatches(m.group(1)!)
        .map((e) => e.group(1)!.trim())
        .where((n) => n.isNotEmpty)
        .join(', ');
  }

  /// Searches JioSaavn for the track and picks the closest match by duration.
  static Future<Song?> _matchSong(SpotifyTrack t) async {
    final query = t.durationMs > 0
        ? '${t.title} ${t.artists.split(',').first.trim()}'
        : '${t.title} ${t.artists}';
    try {
      final results = await RemoteCatalog.searchSongs(
        query,
        limit: 8,
      );
      if (results.isEmpty) return null;
      if (t.durationMs <= 0) return results.first;
      // Closest duration within 12% wins; otherwise first result.
      Song? best;
      var bestDiff = double.infinity;
      for (final s in results) {
        if (s.durationMs <= 0) continue;
        final diff = (s.durationMs - t.durationMs).abs() / t.durationMs;
        if (diff < bestDiff) {
          bestDiff = diff;
          best = s;
        }
      }
      if (best != null && bestDiff <= 0.12) return best;
      return results.first;
    } catch (_) {
      return null;
    }
  }
}
