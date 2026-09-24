import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Persistence: liked songs + recently played, stored as full song
/// snapshots (JSON) so remote tracks restore completely after restart.
class LibraryStore {
  LibraryStore._();
  static final LibraryStore instance = LibraryStore._();

  static const _likedKey = 'vibe.liked.v2';
  static const _recentKey = 'vibe.recent.v2';

  final List<Song> _liked = [];
  final List<Song> _recent = [];

  final _notifier = StreamController<void>.broadcast();
  Stream<void> get changes => _notifier.stream;

  List<Song> get likedSongs => List.unmodifiable(_liked);
  List<Song> get recentSongs => List.unmodifiable(_recent.take(10));

  bool isLiked(Song s) => _liked.any((x) => x.id == s.id);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    void load(String key, List<Song> into) {
      final raw = prefs.getStringList(key) ?? const [];
      for (final s in raw) {
        try {
          into.add(Song.fromJson(jsonDecode(s) as Map<String, dynamic>));
        } catch (_) {}
      }
    }

    load(_likedKey, _liked);
    load(_recentKey, _recent);
  }

  Future<void> toggleLike(Song song) async {
    final existing = _liked.indexWhere((x) => x.id == song.id);
    if (existing >= 0) {
      _liked.removeAt(existing);
    } else {
      _liked.insert(0, song);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _likedKey, _liked.map((s) => jsonEncode(s.toJson())).toList());
    _notifier.add(null);
  }

  Future<void> recordPlay(Song song) async {
    _recent.removeWhere((x) => x.id == song.id);
    _recent.insert(0, song);
    if (_recent.length > 20) _recent.removeLast();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _recentKey, _recent.map((s) => jsonEncode(s.toJson())).toList());
    _notifier.add(null);
  }
}
