import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// One timed lyric line. [start] and [end] are in milliseconds.
class LyricLine {
  final int start;
  final int end;
  final String text;
  const LyricLine(this.start, this.end, this.text);
}

/// LRC parser + online synced-lyrics lookup (LRCLIB, free and key-less).
/// Asset lyrics load first for instant display; LRCLIB is the fallback
/// for remote songs without a bundled .lrc.
class LyricsService {
  static final RegExp _tag =
      RegExp(r'^\[(\d{1,2}):(\d{2}(?:[.:]\d{1,3})?)\](.*)$');

  static final Map<String, List<LyricLine>> _cache = {};

  static List<LyricLine> parseLrc(String src) {
    final lines = <LyricLine>[];
    for (var raw in src.split('\n')) {
      final m = _tag.firstMatch(raw.trim());
      if (m == null) continue;
      final minutes = int.parse(m.group(1)!);
      final seconds = double.parse(m.group(2)!.replaceAll(':', '.'));
      final text = m.group(3)!.trim();
      final startMs = ((minutes * 60 + seconds) * 1000).round();
      lines.add(LyricLine(startMs, 0, text));
    }
    lines.sort((a, b) => a.start.compareTo(b.start));
    for (var i = 0; i < lines.length; i++) {
      final nextStart =
          i + 1 < lines.length ? lines[i + 1].start : lines[i].start + 8000;
      lines[i] = LyricLine(lines[i].start, nextStart, lines[i].text);
    }
    return lines;
  }

  static Future<List<LyricLine>> fromAsset(String asset) async {
    final raw = await rootBundle.loadString(asset);
    return parseLrc(raw);
  }

  /// Queries LRCLIB for synced lyrics. Returns an empty list when the track
  /// is unknown or the device is offline.
  static Future<List<LyricLine>> fetchOnline({
    required String title,
    required String artist,
    required int durationMs,
  }) async {
    final cacheKey = '$title|$artist|$durationMs';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    List<LyricLine> result = const [];
    try {
      final uri = Uri.https('lrclib.net', '/api/get', {
        'track_name': title,
        'artist_name': artist,
        'duration': (durationMs / 1000).round().toString(),
      });
      final response = await http
          .get(uri, headers: {'User-Agent': 'ListenGood/1.0 (freebuff.dev)'})
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final synced = body['syncedLyrics'] as String?;
        if (synced != null && synced.isNotEmpty) {
          result = parseLrc(synced);
        }
      }
    } catch (_) {
      // offline / not found -> empty
    }
    _cache[cacheKey] = result;
    return result;
  }

  /// Bundled asset first (instant), LRCLIB for everything else.
  static Future<List<LyricLine>> bestEffort(Song song) async {
    if (song.lrcAsset.isNotEmpty) {
      try {
        return await fromAsset(song.lrcAsset);
      } catch (_) {
        // fall through to online
      }
    }
    final artist = song.artist.split(',').first.trim();
    return fetchOnline(
      title: song.title,
      artist: artist,
      durationMs: song.durationMs,
    );
  }
}
