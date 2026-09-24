import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'library_store.dart';
import 'models.dart';
import 'remote_catalog.dart';
import 'shuffle.dart';

enum RepeatMode { off, all, one }

/// Single source of truth for playback. Wraps just_audio +
/// just_audio_background (notification controls, lockscreen art).
/// Everything plays from the remote JioSaavn catalog.
class PlayerService {
  PlayerService._();
  static final PlayerService instance = PlayerService._();

  final AudioPlayer _player = AudioPlayer();

  List<Song> _context = const [];
  final List<Song> _history = <Song>[];

  /// Shuffle order when shuffle is on. Stable until a deliberate re-shuffle:
  /// toggling other controls, seeking or pausing must NOT regenerate it.
  List<Song> _shuffled = const [];

  /// Shuffle is ON by default — every new queue starts shuffled.
  bool _shuffleOn = true;
  RepeatMode _repeat = RepeatMode.off;

  final _notifier = StreamController<void>.broadcast();
  Stream<void> get changes => _notifier.stream;

  Song? _current;
  Song? get current => _current;
  bool get shuffleOn => _shuffleOn;
  RepeatMode get repeat => _repeat;

  /// Queue shown to the UI (upcoming tracks). In shuffle mode the stored
  /// order includes the current track; the UI only sees what comes after it.
  List<Song> get upNext {
    if (_shuffleOn) {
      if (_shuffled.isEmpty) return const [];
      final idx = _indexOfCurrent(_shuffled);
      if (idx < 0) return _shuffled;
      return idx + 1 >= _shuffled.length
          ? const []
          : _shuffled.sublist(idx + 1);
    }
    final idx = _indexOfCurrent(_context);
    if (idx < 0 || idx + 1 >= _context.length) return const [];
    return _context.sublist(idx + 1);
  }

  /// Songs are re-instantiated when stream URLs are refreshed, so identity
  /// comparison is wrong — always match by id.
  int _indexOfCurrent(List<Song> list) {
    final id = _current?.id;
    if (id == null) return -1;
    return list.indexWhere((s) => s.id == id);
  }

  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.playing;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get stateStream => _player.playerStateStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  Future<void> init() async {
    await _player
        .setLoopMode(_repeat == RepeatMode.one ? LoopMode.one : LoopMode.off);
    // Auto-advance when a track completes (unless repeat-one handles it).
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_repeat != RepeatMode.one) next();
      }
    });
    _player.playingStream.listen((_) => _notify());
  }

  /// Plays a list of songs; [start] defaults to the first. [shuffle] defaults
  /// to the current shuffle state (ON unless the user turned it off). With
  /// shuffle, builds a smart-shuffled order (Fisher–Yates candidates +
  /// freshness scoring against recently played tracks).
  Future<void> playQueue(List<Song> songs,
      {Song? start, bool? shuffle, String name = 'Queue'}) async {
    if (songs.isEmpty) return;
    _context = List.of(songs);
    _shuffleOn = shuffle ?? _shuffleOn;
    _history.clear();
    _suggestionsLoadedFor = null; // new deliberate queue: allow radio rebuild
    _radioPool = const [];

    List<Song> order;
    if (_shuffleOn) {
      order = _smartShuffle(first: start);
      start ??= order.first;
    } else {
      order = _context;
      start ??= _context.first;
    }
    _shuffled = order;
    await _playSong(start);
  }

  /// Suggestions fetched for the current song (radio pool). Merged with the
  /// deliberate context so shuffle always has a wide, varied pool.
  List<Song> _radioPool = const [];

  /// Union of the deliberate queue context and the loaded radio pool,
  /// de-duplicated by id and capped so scoring stays cheap.
  List<Song> _mergedPool() {
    final seen = <String>{};
    final out = <Song>[];
    for (final s in [..._context, ..._radioPool]) {
      if (seen.add(s.id)) out.add(s);
    }
    if (out.length > 60) out.removeRange(60, out.length);
    return out;
  }

  /// Smart shuffle over the merged pool, penalising recently played tracks
  /// and artist clustering. One source of truth: LibraryStore recents.
  List<Song> _smartShuffle({Song? first}) => SmartShuffler(
        recent: LibraryStore.instance.recentSongs,
      ).shuffle(_mergedPool(), first: first);

  Future<void> toggleShuffle() async {
    final currentSong = _current;
    if (currentSong == null) return;
    _shuffleOn = !_shuffleOn;
    if (_shuffleOn) {
      _shuffled = _smartShuffle(first: currentSong);
      // Enrich the pool with this song's suggestions if not loaded yet —
      // shuffle should never be trapped in a tiny search-result queue.
      if (currentSong.remote && currentSong.id.startsWith('saavn_')) {
        unawaited(_loadSuggestionsQueue(currentSong));
      }
    } else {
      _shuffled = const [];
    }
    _notify();
  }

  Future<void> _playSong(Song song) async {
    // Play the cached URL instantly — no network round-trip before playback.
    // If the URL has expired the error handler refreshes it once and retries.
    _current = song;
    unawaited(LibraryStore.instance.recordPlay(song));
    if (_shuffleOn) {
      _history.add(song);
      if (_history.length > 64) _history.removeAt(0);
    }
    _notify();
    final mediaItem = MediaItem(
      id: song.id,
      album: song.album,
      title: song.title,
      artist: song.artist,
      artUri: Uri.parse(song.cover.startsWith('http')
          ? song.cover
          : 'asset:///${song.cover}'),
    );
    final source = song.remote
        ? AudioSource.uri(
            Uri.parse(song.asset),
            tag: mediaItem,
            headers: {'User-Agent': 'Mozilla/5.0 (Android; ListenGood/1.0)'},
          )
        : AudioSource.asset(song.asset, tag: mediaItem);
    try {
      await _player.setAudioSource(source);
      unawaited(_player.play());
      // Radio-style queue: once audio is rolling, build the upcoming queue
      // from JioSaavn's suggestions for this song (Perfect → I Wanna Be
      // Yours → Shape of You), like DayNight-Music. Never blocks playback.
      if (song.remote && song.id.startsWith('saavn_')) {
        unawaited(_loadSuggestionsQueue(song));
      }
    } catch (e) {
      // Expired URL / blocked stream: refresh once and retry, else skip.
      // ignore: avoid_print
      print('ListenGood playback error for ${song.title}: $e');
      final refreshed = await _refreshCurrentUrl();
      if (refreshed) {
        try {
          final retrySource = _current!.remote
              ? AudioSource.uri(Uri.parse(_current!.asset), tag: mediaItem)
              : AudioSource.asset(_current!.asset, tag: mediaItem);
          await _player.setAudioSource(retrySource);
          unawaited(_player.play());
          return;
        } catch (_) {
          // fall through to skip
        }
      }
      await next();
    }
  }

  String? _suggestionsLoadedFor;

  /// Rebuilds the upcoming queue from the current song's JioSaavn
  /// suggestions. Runs in the background after a track starts; the queue is
  /// NOT regenerated on seeks/pauses — only when the track itself changes.
  Future<void> _loadSuggestionsQueue(Song song) async {
    final saavnId = song.id.substring(6);
    if (_suggestionsLoadedFor == saavnId) return;
    final sugg = await RemoteCatalog.suggestions(saavnId, limit: 30);
    if (sugg.isEmpty || _current?.id != song.id) return;
    _suggestionsLoadedFor = saavnId;

    // Deduplicate against the current song and each other.
    final seen = <String>{song.id};
    final fresh = sugg.where((s) => seen.add(s.id)).toList();
    if (fresh.isEmpty) return;

    if (_shuffleOn) {
      // Smart-shuffle the merged pool (suggestions + original context),
      // current song pinned as playing.
      _radioPool = fresh;
      _shuffled = _smartShuffle(first: song);
    } else {
      // Keep the played portion of the context, replace what's upcoming.
      final idx = _indexOfCurrent(_context);
      _context = idx >= 0
          ? [..._context.sublist(0, idx + 1), ...fresh]
          : [song, ...fresh];
    }
    _notify();
  }

  /// Re-fetches the current song's stream URL from the catalog. Returns
  /// true when a fresh URL was obtained.
  Future<bool> _refreshCurrentUrl() async {
    final song = _current;
    if (song == null || !song.remote || !song.id.startsWith('saavn_')) {
      return false;
    }
    final fresh = await RemoteCatalog.refreshSong(song.id.substring(6));
    if (fresh == null || fresh.asset.isEmpty) return false;
    _current = fresh;
    _notify();
    return true;
  }

  /// Plays a single song in the context of [queue] when provided.
  Future<void> play(Song song, {List<Song>? queue}) async {
    if (queue != null && queue.isNotEmpty) {
      await playQueue(queue, start: song);
    } else {
      if (_context.isEmpty || !_context.any((s) => s.id == song.id)) {
        _context = [song];
        _shuffled = const [];
        // Keep the shuffle toggle as-is: the radio pool fills the queue
        // right after playback starts.
      }
      await _playSong(song);
    }
  }

  /// Jumps to [song] from the queue sheet *within* the existing shuffle
  /// order (no re-shuffle, current song keeps playing until the new one
  /// starts). Falls back to a plain play when it is not in the order.
  Future<void> playFromUpNext(Song song) async {
    final list = _shuffleOn ? _shuffled : _context;
    final i = list.indexWhere((s) => s.id == song.id);
    if (i < 0) {
      await play(song);
      return;
    }
    await _playSong(list[i]);
  }

  Future<void> togglePlay() async {
    if (_current == null) return;
    _player.playing ? await _player.pause() : await _player.play();
  }

  Future<void> next() async {
    final list = _shuffleOn ? _shuffled : _context;
    if (list.isEmpty) return;
    final i = _indexOfCurrent(list);
    Song song;
    if (i + 1 < list.length) {
      song = list[i + 1];
    } else {
      if (_repeat == RepeatMode.all || _shuffleOn) {
        if (_shuffleOn) {
          // Re-shuffle at the end of the pass, like Spotify. The smart
          // shuffler already pushes the just-played track away from the
          // opener slot; if it still lands first, start from the next one.
          _shuffled = _smartShuffle();
          final justPlayedId = _current?.id;
          if (_shuffled.length > 1 && _shuffled.first.id == justPlayedId) {
            // Rotate the just-played song to the back so nothing is lost.
            final skipped = _shuffled.removeAt(0);
            _shuffled.add(skipped);
          }
          song = _shuffled.first;
        } else {
          song = list.first;
        }
      } else {
        await _player.pause();
        return;
      }
    }
    await _playSong(song);
  }

  Future<void> previous() async {
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    if (_shuffleOn && _history.length >= 2) {
      final prev = _history[_history.length - 2];
      _history.removeRange(_history.length - 2, _history.length);
      await _playSong(prev);
      return;
    }
    final list = _shuffleOn ? _shuffled : _context;
    if (list.isEmpty) return;
    final i = _indexOfCurrent(list) == -1 ? 0 : _indexOfCurrent(list);
    final song = list[(i - 1 + list.length) % list.length];
    await _playSong(song);
  }

  Future<void> seekTo(Duration d) => _player.seek(d);

  Future<void> cycleRepeat() async {
    switch (_repeat) {
      case RepeatMode.off:
        _repeat = RepeatMode.all;
        await _player.setLoopMode(LoopMode.off);
      case RepeatMode.all:
        _repeat = RepeatMode.one;
        await _player.setLoopMode(LoopMode.one);
      case RepeatMode.one:
        _repeat = RepeatMode.off;
        await _player.setLoopMode(LoopMode.off);
    }
    _notify();
  }

  void _notify() {
    if (!_notifier.isClosed) _notifier.add(null);
  }

  void dispose() {
    _notifier.close();
    _player.dispose();
  }
}
