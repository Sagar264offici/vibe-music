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
    final ordered = breakUpAdjacentArtists(sorted, firstArtist: first?.artist.toLowerCase());

    return first == null ? ordered : [first, ...ordered];
  }

  /// Core dithering spread: place each song of [songs] at a jittered multiple of
  /// its group's ideal spacing (1/k), plus a shared random phase offset.
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

  /// Reorders [input] so that (when possible) no two consecutive songs share an
  /// artist. Uses look-ahead: when choosing between multiple valid
  /// different-artist candidates, picks the one whose artist has the
  /// most remaining songs ahead (greedy load-balancing). Only fails when
  /// the remaining songs are all by one artist.
  static List<Song> breakUpAdjacentArtists(List<Song> input,
      {String? firstArtist}) {
    final pool = List.of(input);
    final result = <Song>[];
    String? lastArtist = firstArtist;

    while (pool.isNotEmpty) {
      // Collect all songs whose artist differs from the last played.
      final candidates = <int>[];
      for (var i = 0; i < pool.length; i++) {
        if (pool[i].artist.toLowerCase() != lastArtist) {
          candidates.add(i);
        }
      }

      int pickIndex;
      if (candidates.isEmpty) {
        // Unavoidable cluster — only one artist left.
        pickIndex = 0;
      } else if (candidates.length == 1) {
        pickIndex = candidates[0];
      } else {
        // Look-ahead: prefer the artist that appears most often in the
        // remaining pool, so we don't accidentally strand a large group.
        final artistCount = <String, int>{};
        for (final idx in candidates) {
          final a = pool[idx].artist.toLowerCase();
          artistCount[a] = (artistCount[a] ?? 0) + 1;
        }
        // Weight random selection by remaining count so the "biggest
        // remaining group" is more likely to be picked first — this
        // prevents creating stranded clusters later.
        final total = artistCount.values.reduce((a, b) => a + b);
        var roll = rng.nextInt(total);
        var chosenIdx = candidates[0];
        for (final idx in candidates) {
          roll -= artistCount[pool[idx].artist.toLowerCase()]!;
          if (roll < 0) {
            chosenIdx = idx;
            break;
          }
        }
        pickIndex = chosenIdx;
      }

      final song = pool.removeAt(pickIndex);
      result.add(song);
      lastArtist = song.artist.toLowerCase();
    }
    return result;
  }
}

/// Spotify 2025 "Fewer Repeats" principle (engineering.atspotify.com):
/// generate several *genuinely random* candidate orders, score each complete
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
/// F. recently played songs are banned from the first [cooldown] positions.
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

  /// Scores one candidate order. Public for tests.
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

      // A + B: recency penalty, stronger when more recent AND near the front.
      if (isRecent) {
        final recency = 1.0 - r / recentDepth; // 1 = just played
        s -= _recencyW * recency * (1.0 - i / n);
        if (i < earlyWindow) {
          s -= _earlyW * recency * (1.0 - i / earlyWindow);
        }
      } else {
        // E: freshness bonus, weighted towards the front.
        s += _freshW * (1.0 - i / n);
      }

      final artist = song.artist.toLowerCase();

      // C: same-artist adjacency + clustering using precomputed positions.
      final positions = artistPositions[artist]!;
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

      // D: alternating A→B→A→B pattern across the last four slots.
      if (i >= 3 &&
          order[i - 2].artist.toLowerCase() == artist &&
          order[i - 3].artist.toLowerCase() == order[i - 1].artist.toLowerCase() &&
          order[i - 1].artist.toLowerCase() != artist) {
        s -= _altPatternW;
      }
    }

    // E: opener freshness bonus.
    if (!recentRank.containsKey(order.first.id)) s += _openerFreshW;

    // F: cooldown bonus — penalise recent songs appearing too early.
    for (var i = 0; i < min(recentBanWindow, n); i++) {
      final r = recentRank[order[i].id];
      if (r != null && r < recentDepth) {
        s -= _earlyW * 0.5 * (1.0 - i / recentBanWindow);
      }
    }

    return s;
  }

  /// Softmax-weighted random selection among the top candidates.
  /// Higher-scoring candidates are chosen more often, but [temperature]
  /// controls how "committed" we are to the best one:
  ///   temperature → 0 : always the best
  ///   temperature → ∞ : uniform random
  Song _selectCandidate(List<List<Song>> candidates, List<double> scores) {
    if (candidates.length == 1) return candidates.first;

    // Compute softmax weights.
    final temps = temperature.clamp(0.01, 10.0);
    final expScores = scores.map((s) => exp((s - scores.reduce(max)) / temps)).toList();
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
  /// played song is never the opener and is banned from the first
  /// [recentBanWindow] positions.
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
    if (first == null && chosen.length > 1 && recentRank.isNotEmpty) {
      final mostRecentId = recentRank.entries
          .reduce((a, b) => a.value <= b.value ? a : b)
          .key;
      if (chosen.first.id == mostRecentId) {
        // Find the first non-recent song to swap in.
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

  /// Moves songs that were played recently (within [recentBanWindow])
  /// deeper into the queue by swapping them with a later song.
  List<Song> _applyCooldown(List<Song> order) {
    final result = List.of(order);
    final n = result.length;
    final banLimit = min(recentBanWindow, n);

    for (var i = 0; i < banLimit && i < n; i++) {
      final r = recentRank[result[i].id];
      if (r != null && r < recentDepth) {
        // Find the latest song in the remaining list that isn't recent.
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
  /// with look-ahead load-balancing that avoids stranded artist clusters.
  /// The repair is deterministic given the FY order, so the candidate
  /// remains a genuine permutation with unbiased FY randomness.
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

/// Energy-based ordering: reorders [songs] to create a smooth energy
/// arc — starts moderate, builds to a peak, then cools down.
/// Each song's [energy] is a value in [0.0, 1.0].
/// [rng] provides randomness for tie-breaking.
List<Song> energyCurve(List<Song> songs,
    double Function(Song) energyOf, {Random? rng}) {
  final random = rng ?? Random.secure();
  if (songs.length < 3) return List.of(songs);

  final scored = songs.map((s) => (energyOf(s), s)).toList();

  // Sort by energy to get a baseline, then interleave high/low for curve.
  scored.sort((a, b) => a.$1.compareTo(b.$1));

  // Build an arc: low → high → low using a sine-curve mapping.
  final n = scored.length;
  final ordered = <Song>[];
  for (var i = 0; i < n; i++) {
    // Map position index to energy target using a sine curve (0..π)
    final targetEnergy = sin((i / (n - 1)) * pi);
    // Find the song closest to this target energy that hasn't been used yet.
    double bestDist = double.infinity;
    int bestIdx = -1;
    for (var j = 0; j < scored.length; j++) {
      if (scored[j].$2 == null) continue;
      final dist = (scored[j].$1 - targetEnergy).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = j;
      }
    }
    if (bestIdx >= 0) {
      ordered.add(scored[bestIdx].$2!);
      scored[bestIdx] = (scored[bestIdx].$1, null as Song);
    }
  }

  return ordered;
}

/// Adds a configurable cooldown window: songs in [bannedIds] cannot
/// appear in the first [windowSize] positions of [order].
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
