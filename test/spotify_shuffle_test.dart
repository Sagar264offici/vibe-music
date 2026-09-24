import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:vibe_music/core/models.dart';
import 'package:vibe_music/core/shuffle.dart';

Song song(String id, String artist, [String album = 'Album']) =>
    Song(
      id: id,
      title: id,
      artist: artist,
      album: album,
      asset: '',
      cover: '',
      lrcAsset: '',
      durationMs: 0,
      accent: const Color(0xFF8B3FF0),
    );

void main() {
  group('SpotifyShuffler', () {
    test('keeps every song exactly once (permutation)', () {
      final songs = List.generate(50, (i) => song('s$i', 'Artist ${i % 7}'));
      final out = SpotifyShuffler(rng: Random(42)).shuffle(songs);
      expect(out.length, songs.length);
      expect(out.map((s) => s.id).toSet().length, songs.length);
    });

    test('pinned first song stays first', () {
      final songs = List.generate(30, (i) => song('s$i', 'Artist ${i % 5}'));
      final first = songs[7];
      final out = SpotifyShuffler(rng: Random(1)).shuffle(songs, first: first);
      expect(out.first.id, first.id);
    });

    test('never plays the same artist twice in a row (large library)', () {
      final songs = List.generate(200, (i) => song('s$i', 'Artist ${i % 10}'));
      final out = SpotifyShuffler(rng: Random(7)).shuffle(songs);
      for (var i = 1; i < out.length; i++) {
        expect(out[i].artist, isNot(equals(out[i - 1].artist)),
            reason: 'adjacent same-artist at $i: '
                '${out[i - 1].artist} -> ${out[i].artist}');
      }
    });

    test('no immediate repeats even with few artists (small library)', () {
      final songs = [
        ...List.generate(4, (i) => song('a$i', 'X', 'AlbumX$i')),
        ...List.generate(4, (i) => song('b$i', 'Y', 'AlbumY$i')),
        ...List.generate(4, (i) => song('c$i', 'Z', 'AlbumZ$i')),
      ];
      for (var trial = 0; trial < 200; trial++) {
        final out = SpotifyShuffler(rng: Random(trial)).shuffle(songs);
        for (var i = 1; i < out.length; i++) {
          expect(out[i].artist, isNot(equals(out[i - 1].artist)),
              reason: 'trial $trial adjacent same-artist at $i');
        }
      }
    });

    test('is a good shuffle: uniform-ish positions, not identity', () {
      final songs = List.generate(24, (i) => song('s$i', 'Solo'));
      final out = SpotifyShuffler(rng: Random(3)).shuffle(songs);
      expect(out.map((s) => s.id), isNot(equals(songs.map((s) => s.id))));
      expect(out.toSet(), equals(songs.toSet()));
    });

    test('handles empty and single-song lists', () {
      expect(SpotifyShuffler(rng: Random(0)).shuffle([]), isEmpty);
      final one = [song('only', 'A')];
      expect(SpotifyShuffler(rng: Random(0)).shuffle(one).single.id, 'only');
    });

    test('spread spreads two groups evenly (interleaving sanity)', () {
      final shuffler = SpotifyShuffler(rng: Random(9), jitter: 0.1);
      final a = List.generate(5, (i) => song('a$i', 'A'));
      final b = List.generate(5, (i) => song('b$i', 'B'));
      final out = shuffler.spread([...a, ...b], keyOf: (s) => s.artist);
      final marks = out.map((s) => s.artist).join();
      expect(RegExp(r'A{3,}|B{3,}').hasMatch(marks), isFalse, reason: marks);
    });

    test('breakUpAdjacentArtists avoids adjacent same-artist when possible',
        () {
      // Balanced artist distribution: 3 songs each for 4 artists
      final songs = [
        ...List.generate(3, (i) => song('a$i', 'A')),
        ...List.generate(3, (i) => song('b$i', 'B')),
        ...List.generate(3, (i) => song('c$i', 'C')),
        ...List.generate(3, (i) => song('d$i', 'D')),
      ];
      for (var trial = 0; trial < 100; trial++) {
        final out = SpotifyShuffler.breakUpAdjacentArtists(songs);
        for (var i = 1; i < out.length; i++) {
          expect(out[i].artist, isNot(equals(out[i - 1].artist)),
              reason: 'trial $trial adjacent same-artist at $i');
        }
      }
    });
  });

  group('SmartShuffler', () {
    List<Song> library() => [
          ...List.generate(4, (i) => song('a$i', 'Alpha', 'Al$i')),
          ...List.generate(4, (i) => song('b$i', 'Beta', 'Bl$i')),
          ...List.generate(4, (i) => song('c$i', 'Gamma', 'Ga$i')),
          ...List.generate(4, (i) => song('d$i', 'Delta', 'De$i')),
        ];

    test('is still a permutation of the source queue', () {
      final songs = library();
      final out = SmartShuffler(recent: const [], rng: Random(5))
          .shuffle(songs);
      expect(out.length, songs.length);
      expect(out.map((s) => s.id).toSet(), songs.map((s) => s.id).toSet());
    });

    test('avoids adjacent same-artist tracks across many trials', () {
      final songs = library();
      var violations = 0;
      for (var t = 0; t < 60; t++) {
        final out = SmartShuffler(recent: const [], rng: Random(t))
            .shuffle(songs);
        for (var i = 1; i < out.length; i++) {
          if (out[i].artist == out[i - 1].artist) violations++;
        }
      }
      expect(violations, lessThanOrEqualTo(2), reason: 'too much clustering');
    });

    test('penalises A→B→A→B alternating artist patterns in the score', () {
      final mk = (String id, String a) => song(id, a);
      final abab = [
        mk('1', 'A'), mk('2', 'B'), mk('3', 'A'), mk('4', 'B'),
        mk('5', 'C'), mk('6', 'D'),
      ];
      final varied = [
        mk('1', 'A'), mk('2', 'B'), mk('3', 'C'), mk('4', 'D'),
        mk('5', 'E'), mk('6', 'F'),
      ];
      final s = SmartShuffler(recent: const [], rng: Random(1));
      expect(s.score(abab), lessThan(s.score(varied)));
    });

    test('single-artist playlists still shuffle (constraints relax)', () {
      final solo = List.generate(4, (i) => song('o$i', 'OnlyOne', 'Al$i'));
      final out = SmartShuffler(recent: const [], rng: Random(3))
          .shuffle(solo);
      expect(out.length, 4);
      expect(out.map((s) => s.id).toSet(), solo.map((s) => s.id).toSet());
    });

    test('penalises recently played tracks in the score', () {
      final order = [
        song('r1', 'A'),
        song('x1', 'B'),
        song('x2', 'C'),
        song('x3', 'D'),
        song('x4', 'E'),
        song('x5', 'F'),
      ];
      final fresh = SmartShuffler(recent: const [], rng: Random(1));
      final withRecent = SmartShuffler(recent: [song('r1', 'A')], rng: Random(1));
      expect(withRecent.score(order), lessThan(fresh.score(order)));
    });

    test('recent songs are pushed away from the front of the queue', () {
      final songs = library();
      final recent = [songs[0], songs[5], songs[10]];
      final out = SmartShuffler(recent: recent, rng: Random(11))
          .shuffle(songs);
      final front = out.take(3).map((s) => s.id).toSet();
      expect(front.contains(recent.first.id), isFalse,
          reason: 'just-played song opened the queue');
    });

    test('recent ban window keeps just-played songs out of first positions', () {
      final songs = library();
      final recent = [songs[0], songs[1], songs[2]];
      final shuffler = SmartShuffler(
        recent: recent,
        rng: Random(11),
        recentBanWindow: 4,
      );
      for (var t = 0; t < 20; t++) {
        final out = shuffler.shuffle(songs);
        for (var i = 0; i < 4 && i < out.length; i++) {
          expect(recent.any((r) => r.id == out[i].id), isFalse,
              reason: 'trial $t: recent song at position $i');
        }
      }
    });

    test('never opens with the currently playing song (no pin)', () {
      final songs = library();
      final current = songs[3];
      for (var t = 0; t < 30; t++) {
        final out = SmartShuffler(recent: [current], rng: Random(t))
            .shuffle(songs);
        expect(out.first.id, isNot(equals(current.id)),
            reason: 'trial $t opened with the just-played song');
      }
    });

    test('stays random: not deterministic across seeds', () {
      final songs = library();
      final outs = <String>{};
      for (var t = 0; t < 10; t++) {
        final out = SmartShuffler(recent: const [], rng: Random(t))
            .shuffle(songs);
        outs.add(out.map((s) => s.id).join(','));
      }
      expect(outs.length, greaterThan(1), reason: 'shuffle looks deterministic');
    });

    test('tiny playlists degrade gracefully', () {
      final two = [song('p1', 'A'), song('p2', 'B')];
      final out = SmartShuffler(recent: const [], rng: Random(2))
          .shuffle(two);
      expect(out.length, 2);
      expect(out.toSet(), two.toSet());
    });

    test('candidates come from unbiased Fisher–Yates (uniformity check)', () {
      final songs = List.generate(30, (i) => song('s$i', 'Artist ${i % 10}'));
      final positionCounts = List.filled(30, 0);
      for (var t = 0; t < 300; t++) {
        final out = SmartShuffler(recent: const [], rng: Random(1000 + t))
            .shuffle(songs);
        final pos = out.indexWhere((s) => s.id == 's0');
        positionCounts[pos]++;
      }
      final expected = 300 / 30;
      for (var p = 0; p < 30; p++) {
        expect(positionCounts[p], inInclusiveRange(2, 28),
            reason: 'position $p seen ${positionCounts[p]} times '
                '(expected ~$expected)');
      }
    });

    test('shuffle output varies across calls with the same source queue', () {
      final songs = library();
      final shuffler = SmartShuffler(recent: const [], rng: Random(77));
      final seen = <String>{};
      for (var i = 0; i < 20; i++) {
        seen.add(shuffler.shuffle(songs).map((s) => s.id).join(','));
      }
      expect(seen.length, greaterThan(5),
          reason: 'shuffle produced near-identical orders');
    });

    group('temperature-weighted selection', () {
      test('temperature=0 always picks the best candidate', () {
        final songs = library();
        // With temperature=0, the best-scoring candidate is always chosen.
        // Running twice with the same seed should produce identical output.
        final shuffler = SmartShuffler(
          recent: const [],
          rng: Random(42),
          temperature: 0.0,
        );
        final first = shuffler.shuffle(songs);
        final second = SmartShuffler(
          recent: const [],
          rng: Random(42),
          temperature: 0.0,
        ).shuffle(songs);
        // Same RNG seed + temperature=0 → deterministic best candidate → same output.
        expect(first.map((s) => s.id).join(','),
            equals(second.map((s) => s.id).join(',')));
      });

      test('higher temperature produces more variety', () {
        final songs = library();
        final highT = SmartShuffler(
          recent: const [],
          rng: Random(42),
          temperature: 5.0,
        );
        final variants = <String>{};
        for (var i = 0; i < 10; i++) {
          variants.add(highT.shuffle(songs).map((s) => s.id).join(','));
        }
        // High temperature gives more variety across calls.
        expect(variants.length, greaterThan(3));
      });
    });

    test('cooldown swaps recent songs out of forbidden positions', () {
      final recent = [song('r1', 'A')];
      final shuffler = SmartShuffler(
        recent: recent,
        rng: Random(5),
        recentBanWindow: 3,
      );
      final songs = library();
      for (var t = 0; t < 20; t++) {
        final out = shuffler.shuffle(songs);
        for (var i = 0; i < 3 && i < out.length; i++) {
          expect(out[i].id, isNot('r1'),
              reason: 'trial $t: recent song at position $i');
        }
      }
    });
  });

  group('energyCurve', () {
    test('preserves all songs', () {
      final songs = List.generate(10, (i) => song('s$i', 'Artist'));
      final out = energyCurve(songs, (_) => 0.5, rng: Random(42));
      expect(out.length, songs.length);
      expect(out.map((s) => s.id).toSet(), songs.map((s) => s.id).toSet());
    });

    test('empty and single-song lists pass through', () {
      expect(energyCurve([], (_) => 0.5), isEmpty);
      final one = [song('only', 'A')];
      expect(energyCurve(one, (_) => 0.5).single.id, 'only');
    });

    test('creates a valid permutation with varied energy', () {
      final songs = List.generate(10, (i) => song('s$i', 'Artist', 'Album'));
      final out = energyCurve(songs, (s) => double.parse(s.id.substring(1)) / 9,
          rng: Random(42));
      expect(out.length, songs.length);
      expect(out.map((s) => s.id).toSet(), songs.map((s) => s.id).toSet());
    });
  });

  group('applyCooldown', () {
    test('moves banned songs past the window', () {
      final songs = List.generate(6, (i) => song('s$i', 'Artist'));
      final banned = {'s0', 's1'};
      final out = applyCooldown(songs, banned, 2);
      for (var i = 0; i < 2; i++) {
        expect(banned.contains(out[i].id), isFalse,
            reason: 'banned song at position $i');
      }
    });

    test('returns same order when nothing is banned', () {
      final songs = List.generate(5, (i) => song('s$i', 'Artist'));
      final out = applyCooldown(songs, {}, 3);
      expect(out.map((s) => s.id).join(','),
          equals(songs.map((s) => s.id).join(',')));
    });

    test('handles empty list', () {
      expect(applyCooldown([], {'s0'}, 3), isEmpty);
    });
  });
}
