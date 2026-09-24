import 'dart:math';

import 'models.dart';

/// Unbiased in-place Fisher–Yates shuffle. THE source of randomness for all
/// candidate generation — never sort-by-random.
void fisherYates(List<Song> list, Random rng) {
  for (var i = list.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
  }
}

/// Structural Spotify-style shuffle (2014 "How to shuffle songs?"):
/// artist-dithered even spread + Fisher-Yates within artist + greedy
/// no-adjacent-artist repair. Used directly for single shuffles and as a
/// repair utility for SmartShuffler candidates.
class SpotifyShuffler {
  final Random rng;

  /// Jitter as a fraction of the ideal spacing (Spotify uses roughly +/- 10%).
  final double jitter;

  SpotifyShuffler({Random? rng, this.jitter = 0.10})
      : rng = rng ?? Random.secure();

  /// Returns a new shuffled list. [first] is pinned as the opening track.
  List<Song> shuffle(List<Song> songs, {Song? first}) {
    final pool =
        songs.where((s) => first == null || s.id != first.id).toList();
    if (pool.length < 2) {
      return first == null ? pool : [first, ...pool];
    }

    // -- artist buckets -------------------------------------------------------
    final byArtist = <String, List<Song>>{};
    for (final s in pool) {
      byArtist.putIfAbsent(s.artist.toLowerCase(), () => []).add(s);
    }

    // -- per-artist: Fisher-Yates, album sub-spread, even global positions ----
    final positioned = <(double, Song)>[];
    byArtist.forEach((_, list) {
      fisherYates(list, rng);
      final orderedWithinArtist =
          spread(list, keyOf: (s) => s.album.toLowerCase());
      final k = orderedWithinArtist.length;
      final spacing = 1.0 / k;
      final offset = rng.nextDouble() * spacing;
      for (var i = 0; i < k; i++) {
        final jitterAmount = (rng.nextDouble() * 2 - 1) * spacing * jitter;
        positioned.add(
          ((i * spacing + offset + jitterAmount) % 1.0, orderedWithinArtist[i]),
        );
      }
    });

    // -- global ordering by position -----------------------------------------
    positioned.sort((a, b) => a.$1.compareTo(b.$1));
    final sorted = positioned.map((e) => e.$2).toList();

    // -- greedy repair: never two songs from the same artist back-to-back ----
    final ordered = breakUpAdjacentArtists(
      sorted,
      firstArtist: first?.artist.toLowerCase(),
    );

    return first == null ? ordered : [first, ...ordered];
  }

  /// Core dithering spread: place each song of [songs] at a jittered multiple
  /// of its group's ideal spacing (1/k), plus a shared random phase offset.
  List<Song> spread(List<Song> songs, {required String Function(Song) keyOf}) {
    if (songs.length < 2) return songs;
    final byKey = <String, List<Song>>{};
    for (final s in songs) {
      byKey.putIfAbsent(keyOf(s), () => []).add(s);
    }
    if (byKey.length == 1) return songs;

    final positioned = <(double, Song)>[];
    byKey.forEach((_, list) {
      final k = list.length;
      final offset = rng.nextDouble() / k;
      final spacing = 1.0 / k;
      for (var i = 0; i < k; i++) {
        final j = (rng.nextDouble() * 2 - 1) * spacing * jitter;
        positioned.add(((i * spacing + offset + j) % 1.0, list[i]));
      }
    });
    positioned.sort((a, b) => a.$1.compareTo(b.$1));
    return positioned.map((e) => e.$2).toList();
  }

  /// Reorders [input] so that (when possible) no two consecutive songs share
  /// an artist. Uses a greedy approach: whenever the next song would repeat
  /// the previous artist, scans forward for the next different-artist song
  /// and pulls it forward. Only fails when all remaining songs are by one
  /// artist, which is mathematically unavoidable.
  static List<Song> breakUpAdjacentArtists(List<Song> input,
      {String? firstArtist}) {
    final pool = List.of(input);
    final result = <Song>[];
    String? lastArtist = firstArtist;

    while (pool.isNotEmpty) {
      // Find the first song whose artist differs from the last played.
      var pickIndex = -1;
      for (var i = 0; i < pool.length; i++) {
        if (pool[i].artist.toLowerCase() != lastArtist) {
          pickIndex = i;
          break;
        }
      }
      // If all remaining songs are the same artist, take the first one
      // (unavoidable cluster).
      if (pickIndex < 0) pickIndex = 0;

      final song = pool.removeAt(pickIndex);
      result.add(song);
      lastArtist = song.artist.toLowerCase();
    }
    return result;
  }
}

/// Spotify 2025 "Fewer Repeats" principle (engineering.atspotify.com):
/// generate several *genuinely random* candidate orders, score each COMPLETE
/// sequence for freshness against listening history, and select with
/// **temperature-weighted randomness** instead of always picking the best.
/// Selection among random candidates preserves surprise — it never sorts
/// tracks by history individually.
///
/// Candidate generation is ALWAYS unbiased Fisher–Yates (never
/// sort-by-random). The scoring layer only chooses among random candidates:
///
/// A. recently played songs are penalised, more the more recent they are;
/// B. recently played songs near the START of the candidate are penalised hard;
/// C. same-artist adjacency / clustering inside a small window is penalised;
/// D. repetitive local patterns (A-B-A, A-B-A-B) are penalised;
/// E. unheard / long-unheard songs get a freshness bonus weighted towards
///    the front of the queue;
/// F. recently played songs are banned from the first [recentBanWindow] positions.
class SmartShuffler {
  /// id -> rank, 0 = most recently played. Songs missing from the map are
  /// considered fresh.
  final Map<String, int> recentRank;

  /// How deep the "recent" window goes (ranks >= this are ignored).
  final int recentDepth;

  final Random rng;

  /// Number of Fisher–Yates candidates generated per shuffle request.
  final int numberOfCandidates;

  /// Songs with ranks in [0..recentBanWindow[ are banned from the first
  /// positions of the queue, preventing the "just played this" feeling.
  final int recentBanWindow;

  /// Temperature for candidate selection:
  /// - 0.0 = always pick the single best candidate (deterministic-optimal)
  /// - 1.0 = uniform random among all candidates (pure random)
  /// - < 1.0 = softmax weighting — higher score → more likely, but
  ///   lower-scoring candidates still get a chance (keeps it feeling human)
  final double temperature;

  SmartShuffler({
    required Iterable<Song> recent,
    Random? rng,
    this.recentDepth = 10,
    this.numberOfCandidates = 8,
    this.recentBanWindow = 3,
    this.temperature = 0.3,
  })  : recentRank = {
          for (var i = 0; i < recent.length; i++) recent.elementAt(i).id: i,
        },
        rng = rng ?? Random.secure();

  // -- weights (conservative: candidates stay genuinely random) --------------
  static const double _recencyW = 6.0;
  static const double _earlyW = 26.0;
  static const double _adjacentArtistW = 40.0;
  static const double _windowArtistW = 9.0;
  static const double _patternW = 7.0;

  /// A→B→A→B alternating artist pattern (8.2D "obvious local repetition").
  static const double _altPatternW = 11.0;
  static const double _freshW = 3.0;
  static const double _openerFreshW = 8.0;

  /// Scores one candidate order (complete sequence). Public for tests.
  double score(List<Song> order) {
    final n = order.length;
    if (n < 2) return 0;
    final earlyWindow = max(2, n ~/ 8).clamp(2, 6);
    final window = 3;

    // Precompute artist positions for O(n) clustering check.
    final artistPositions = <String, List<int>>{};
    for (var i = 0; i < n; i++) {
      artistPositions
          .putIfAbsent(order[i].artist.toLowerCase(), () => []).add(i);
    }

    var s = 0.0;
    for (var i = 0; i < n; i++) {
      final song = order[i];
      final r = recentRank[song.id];
      final isRecent = r != null && r < recentDepth;

      // A + B: recency penalty, stronger when more recent AND near front.
      if (isRecent) {
        final recency = 1.0 - r / recentDepth;
        s -= _recencyW * recency * (1.0 - i / n);
        if (i < earlyWindow) {
          s -= _earlyW * recency * (1.0 - i / earlyWindow);
        }
      } else {
        // E: freshness bonus.
        s += _freshW * (1.0 - i / n);
      }

      final artist = song.artist.toLowerCase();
      final positions = artistPositions[artist]!;

      // C: same-artist adjacency + clustering using precomputed positions.
      for (var p = 0; p < positions.length; p++) {
        final d = positions[p] - i;
        if (d > 0 && d <= window) {
          s -= d == 1 ? _adjacentArtistW : _windowArtistW;
        }
      }

      // D: A→B→A pattern (distance-2 repetition).
      if (i >= 2 &&
          order[i - 2].artist.toLowerCase() == artist &&
          order[i - 1].artist.toLowerCase() != artist) {
        s -= _patternW;
      }

      // D: alternating A→B→A→B pattern.
      if (i >= 3 &&
          order[i - 2].artist.toLowerCase() == artist &&
          order[i - 3].artist.toLowerCase() == order[i - 1].artist.toLowerCase() &&
          order[i - 1].artist.toLowerCase() != artist) {
        s -= _altPatternW;
      }
    }

    // E: opener freshness bonus.
    if (!recentRank.containsKey(order.first.id)) s += _openerFreshW;

    // F: cooldown penalty — recent songs in first positions.
    for (var i = 0; i < min(recentBanWindow, n); i++) {
      final r = recentRank[order[i].id];
      if (r != null && r < recentDepth) {
        s -= _earlyW * 0.5 * (1.0 - i / recentBanWindow);
      }
    }

    return s;
  }

  /// Temperature-weighted random selection among candidates.
  /// When [temperature] is effectively 0, always returns the best candidate.
  /// Higher temperatures produce more variety.
  List<Song> _selectCandidate(List<List<Song>> candidates, List<double> scores) {
    if (candidates.length == 1) return candidates.first;

    // For temperature near 0, always pick the best candidate.
    final temps = temperature.clamp(0.001, 10.0);
    if (temps < 0.01) {
      // Find the best score and return the first candidate with it.
      var bestScore = double.negativeInfinity;
      var bestIdx = 0;
      for (var i = 0; i < scores.length; i++) {
        if (scores[i] > bestScore) {
          bestScore = scores[i];
          bestIdx = i;
        }
      }
      return candidates[bestIdx];
    }

    // Softmax weighting.
    final maxScore = scores.reduce(max);
    final expScores = scores.map((s) => exp((s - maxScore) / temps)).toList();
    final total = expScores.reduce((a, b) => a + b);
    var roll = rng.nextDouble() * total;
    for (var i = 0; i < expScores.length; i++) {
      roll -= expScores[i];
      if (roll <= 0) return candidates[i];
    }
    return candidates.last;
  }

  /// Generates [numberOfCandidates] candidate orders, EACH produced by an
  /// unbiased Fisher–Yates shuffle (plus a no-adjacent-artist repair pass,
  /// itself seeded from the same RNG stream), scores each COMPLETE
  /// sequence, and returns a temperature-weighted random selection.
  /// [first] is pinned as the opening track; when null, the most recently
  /// played song is never the opener.
  List<Song> shuffle(List<Song> songs, {Song? first}) {
    if (songs.length <= 3) {
      // Tiny playlist: one plain Fisher–Yates pass, constraints relaxed.
      final pool = List.of(songs);
      fisherYates(pool, rng);
      if (first != null) {
        pool.removeWhere((s) => s.id == first.id);
        pool.insert(0, first);
      }
      return pool;
    }

    final candidates = <List<Song>>[];
    final scores = <double>[];

    for (var c = 0; c < numberOfCandidates; c++) {
      final candidate = _fisherYatesCandidate(songs, first: first);
      final cs = score(candidate);
      candidates.add(candidate);
      scores.add(cs);
    }

    // Temperature-weighted selection among candidates.
    final chosen = _selectCandidate(candidates, scores);

    // If no explicit first track and there's recent history, ensure
    // the most recently played song doesn't open the queue.
    if (first == null && chosen.isNotEmpty && recentRank.isNotEmpty) {
      final mostRecentId = recentRank.entries
          .reduce((a, b) => a.value <= b.value ? a : b)
          .key;
      if (chosen.first.id == mostRecentId) {
        for (var i = 1; i < chosen.length; i++) {
          if (!recentRank.containsKey(chosen[i].id) ||
              recentRank[chosen[i].id]! >= recentDepth) {
            final tmp = chosen[0];
            chosen[0] = chosen[i];
            chosen[i] = tmp;
            break;
          }
        }
      }
    }

    // Apply cooldown: move recently-played songs out of the first N positions.
    return _applyCooldown(chosen);
  }

  /// Moves recently-played songs out of the first [recentBanWindow] positions.
  List<Song> _applyCooldown(List<Song> order) {
    final result = List.of(order);
    final n = result.length;
    final banLimit = min(recentBanWindow, n);

    for (var i = 0; i < banLimit && i < n; i++) {
      final r = recentRank[result[i].id];
      if (r != null && r < recentDepth) {
        for (var j = n - 1; j > i; j--) {
          final rj = recentRank[result[j].id];
          if (rj == null || rj >= recentDepth) {
            final tmp = result[i];
            result[i] = result[j];
            result[j] = tmp;
            break;
          }
        }
      }
    }
    return result;
  }

  /// One candidate: Fisher–Yates on a copy, then the structural repair pass
  /// that breaks up adjacent same-artist tracks. The repair is deterministic
  /// given the FY order, so the candidate remains a genuine permutation with
  /// unbiased FY randomness.
  List<Song> _fisherYatesCandidate(List<Song> songs, {Song? first}) {
    final pool = List.of(songs);
    fisherYates(pool, rng);
    final repaired = SpotifyShuffler.breakUpAdjacentArtists(
      pool,
      firstArtist: first?.artist.toLowerCase(),
    );
    if (first != null) {
      repaired.removeWhere((s) => s.id == first.id);
      repaired.insert(0, first);
    }
    return repaired;
  }
}

/// Energy-based ordering: reorders [songs] to create a smooth energy arc
/// — starts moderate, builds to a peak, then cools down.
/// [energyOf] returns a value in [0.0, 1.0] for each song.
/// [rng] provides randomness for tie-breaking when energies are equal.
List<Song> energyCurve(List<Song> songs, double Function(Song) energyOf,
    {Random? rng}) {
  final random = rng ?? Random.secure();
  if (songs.length < 3) return List.of(songs);

  final n = songs.length;
  final used = <int>{};
  final ordered = <Song>[];

  // Build an arc: map each position to an energy target via sine curve.
  for (var i = 0; i < n; i++) {
    final targetEnergy = sin((i / (n - 1)) * pi);
    double bestDist = double.infinity;
    int bestIdx = -1;
    for (var j = 0; j < n; j++) {
      if (used.contains(j)) continue;
      final dist = (energyOf(songs[j]) - targetEnergy).abs();
      // Add tiny randomness to break ties.
      final tieBreak = random.nextDouble() * 0.001;
      if (dist + tieBreak < bestDist) {
        bestDist = dist + tieBreak;
        bestIdx = j;
      }
    }
    if (bestIdx >= 0) {
      ordered.add(songs[bestIdx]);
      used.add(bestIdx);
    }
  }

  return ordered;
}

/// Moves songs in [bannedIds] past position [windowSize - 1] in [order].
/// If a banned song is in a forbidden position, it is swapped with the
/// nearest eligible song after the window.
List<Song> applyCooldown(List<Song> order, Set<String> bannedIds, int windowSize) {
  final result = List.of(order);
  final n = result.length;
  final limit = min(windowSize, n);

  for (var i = 0; i < limit && i < n; i++) {
    if (bannedIds.contains(result[i].id)) {
      for (var j = i + 1; j < n; j++) {
        if (!bannedIds.contains(result[j].id)) {
          final tmp = result[i];
          result[i] = result[j];
          result[j] = tmp;
          break;
        }
      }
    }
  }
  return result;
}
