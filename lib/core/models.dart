import 'dart:ui';

class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String asset;
  final String cover;
  final String lrcAsset;
  final int durationMs;
  final Color accent;

  /// True when [asset] is an http(s) stream instead of a bundled asset.
  final bool remote;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.asset,
    required this.cover,
    required this.lrcAsset,
    required this.durationMs,
    required this.accent,
    this.remote = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'asset': asset,
        'cover': cover,
        'durationMs': durationMs,
        'remote': remote,
      };

  static Song fromJson(Map<String, dynamic> j) => Song(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? 'Unknown') as String,
        artist: (j['artist'] ?? '') as String,
        album: (j['album'] ?? '') as String,
        asset: (j['asset'] ?? '') as String,
        cover: (j['cover'] ?? '') as String,
        lrcAsset: '',
        durationMs: (j['durationMs'] ?? 0) as int,
        accent: const Color(0xFF8B3FF0),
        remote: (j['remote'] ?? false) as bool,
      );

  Song copyWith({String? asset, int? durationMs}) => Song(
        id: id,
        title: title,
        artist: artist,
        album: album,
        asset: asset ?? this.asset,
        cover: cover,
        lrcAsset: lrcAsset,
        durationMs: durationMs ?? this.durationMs,
        accent: accent,
        remote: remote,
      );
}

class PlayContext {
  final String name;
  final List<Song> songs;

  const PlayContext(this.name, this.songs);
}
