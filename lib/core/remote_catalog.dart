import 'dart:convert';
import 'dart:ui';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Real music catalog backed by the JioSaavn API deployment on Vercel.
/// Search results include playable 320kbps stream URLs and cover art.
class RemoteCatalog {
  RemoteCatalog._();

  static const String base =
      'https://backend-sagar264officis-projects.vercel.app/api';

  static final Map<String, List<Song>> _searchCache = {};
  static final Map<String, List<Song>> _suggestionCache = {};
  static List<Song>? _trendingCache;

  static Future<dynamic> _getJson(String path,
      [Map<String, String>? query]) async {
    try {
      final uri = Uri.parse('$base/$path').replace(queryParameters: query);
      final resp = await http
          .get(uri, headers: {
            'Accept': 'application/json',
            'User-Agent': 'ListenGood/1.0',
          })
          .timeout(kApiTimeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is Map<String, dynamic> && body['success'] == true) {
        return body['data'];
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// JioSaavn CDN urls often come back as http:// — Android 9+ blocks
  /// cleartext by default, so upgrade to https (the CDN supports it).
  static String _toHttps(String url) => url.replaceFirst('http://', 'https://');

  /// JioSaavn returns HTML-escaped names ("She &amp; Him", "Don&#039;t").
  static String _clean(String s) {
    var out = s
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
    // Numeric entities in general form: &#1234;
    return out.replaceAllMapped(RegExp(r'&#(\d{2,5});'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code != null && code > 31 ? String.fromCharCode(code) : m.group(0)!;
    });
  }

  static Song _mapSong(Map<String, dynamic> j) {
    final download = (j['downloadUrl'] as List?) ?? const [];
    String streamUrl = '';
    for (final d in download.reversed) {
      final u = _toHttps((d['url'] ?? '') as String);
      if (u.isNotEmpty) {
        streamUrl = u;
        break;
      }
    }
    final images = (j['image'] as List?) ?? const [];
    String cover = '';
    for (final i in images.reversed) {
      final u = _toHttps((i['url'] ?? '') as String);
      if (u.isNotEmpty && !u.startsWith('data:')) {
        cover = u;
        break;
      }
    }
    final artists = j['artists'] as Map<String, dynamic>?;
    final primary = (artists?['primary'] as List?) ?? const [];
    final artistNames = primary
        .map((a) => (a['name'] ?? '') as String)
        .where((n) => n.isNotEmpty)
        .join(', ');
    final album = j['album'] as Map<String, dynamic>?;
    final id = (j['id'] ?? '') as String;
    return Song(
      id: 'saavn_$id',
      title: _clean((j['name'] ?? 'Unknown') as String),
      artist: artistNames.isNotEmpty ? _clean(artistNames) : 'Unknown artist',
      album: _clean((album?['name'] ?? '') as String),
      asset: streamUrl,
      cover: cover,
      lrcAsset: '',
      durationMs: ((j['duration'] as num?)?.toInt() ?? 0) * 1000,
      accent: _accentFor(id),
      remote: true,
    );
  }

  /// Search songs. Empty list on failure (UI falls back to demo songs).
  static Future<List<Song>> searchSongs(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final cacheKey = '${q.toLowerCase()}:$limit';
    final cached = _searchCache[cacheKey];
    if (cached != null) return cached;

    final data = await _getJson('search/songs', {
      'query': q,
      'page': '0',
      'limit': '$limit',
    });
    final results = (data?['results'] as List?) ?? const [];
    final songs = results
        .whereType<Map<String, dynamic>>()
        .map(_mapSong)
        .where((s) => s.asset.isNotEmpty)
        .toList();
    if (songs.isNotEmpty) _searchCache[cacheKey] = songs;
    return songs;
  }

  /// Trending/top-chart songs for the home screen.
  static Future<List<Song>> trending({int limit = 10}) async {
    final cached = _trendingCache;
    if (cached != null) return cached.take(limit).toList();
    final data = await _getJson('search/songs', {
      'query': 'top hits 2026',
      'page': '0',
      'limit': '$limit',
    });
    final results = (data?['results'] as List?) ?? const [];
    final songs = results
        .whereType<Map<String, dynamic>>()
        .map(_mapSong)
        .where((s) => s.asset.isNotEmpty)
        .toList();
    if (songs.isNotEmpty) _trendingCache = songs;
    return songs;
  }

  /// Fresh details (fresh stream URLs — they expire after a while).
  static Future<Song?> refreshSong(String saavnId) async {
    final data = await _getJson('songs/$saavnId');
    final list = (data as List?) ?? const [];
    if (list.isEmpty) return null;
    final first = list.first;
    if (first is! Map<String, dynamic>) return null;
    return _mapSong(first);
  }

  /// JioSaavn's own "similar songs" for [saavnId] — this is what makes the
  /// queue feel like a real streaming service: Perfect → I Wanna Be Yours →
  /// Shape of You, not five different "Perfect" covers.
  static Future<List<Song>> suggestions(String saavnId, {int limit = 20}) async {
    final cacheKey = 'sugg:$saavnId:$limit';
    final cached = _suggestionCache[cacheKey];
    if (cached != null) return cached;
    final data = await _getJson('songs/$saavnId/suggestions', {
      'limit': '$limit',
    });
    final list = (data as List?) ?? const [];
    final songs = list
        .whereType<Map<String, dynamic>>()
        .map(_mapSong)
        .where((s) => s.asset.isNotEmpty)
        .toList();
    if (songs.isNotEmpty) _suggestionCache[cacheKey] = songs;
    return songs;
  }
}

const kApiTimeout = Duration(seconds: 8);

Color _accentFor(String id) {
  const palette = <Color>[
    Color(0xFF9C90F5), Color(0xFFFB9FBF), Color(0xFF6FE2BC),
    Color(0xFFFFD08F), Color(0xFFFFA1A0), Color(0xFF9ACDFA),
    Color(0xFFCBA6FF), Color(0xFFFFD68A), Color(0xFF8CE1F0),
    Color(0xFFE6B4FF), Color(0xFFFFB36B), Color(0xFF8FE3C0),
  ];
  return palette[id.hashCode.abs() % palette.length];
}
