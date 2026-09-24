import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/library_store.dart';
import '../spotify_import_screen.dart';
import '../theme.dart';
import '../widgets/glass.dart';

/// Profile tab: user header + listening stats + settings rows.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = LibraryStore.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liked = LibraryStore.instance.likedSongs.length;
    final played = LibraryStore.instance.recentSongs.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      children: [
        Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: VibeTheme.accentGradient,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x99691ED2),
                      blurRadius: 24,
                      offset: Offset(0, 12)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset('assets/icons/logo_mark.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.person,
                        color: Colors.white, size: 30)),
              ),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aarav Sharma',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: VibeTheme.text)),
                SizedBox(height: 3),
                Text('ListenGood · Rishikesh',
                    style: TextStyle(fontSize: 11, color: VibeTheme.textDim)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 22),
        GlassContainer(
          radius: 20,
          strong: true,
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('$liked', 'Liked'),
              _stat('$played', 'Played'),
              _stat('Live', 'Catalog'),
            ],
          ),
        ),
        const SizedBox(height: 22),
        // Spotify playlist import — glossy feature card.
        GestureDetector(
          onTap: () => showSpotifyImport(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1DB954), Color(0xFF124D26)],
              ),
              border: Border.all(color: const Color(0x55FFFFFF), width: 1),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x5900A344),
                    blurRadius: 24,
                    offset: Offset(0, 10)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.library_music_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Import from Spotify',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 2),
                      Text('Paste a playlist link — we match every song',
                          style: TextStyle(
                              color: Color(0xCCFFFFFF), fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: Colors.white, size: 22),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text('Settings',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: VibeTheme.text)),
        const SizedBox(height: 10),
        GlassContainer(
          radius: 18,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _row(Icons.high_quality_outlined, 'Streaming quality · High'),
              const Divider(height: 1, color: Color(0x1AFFFFFF)),
              _row(Icons.notifications_active_outlined, 'Notifications'),
              const Divider(height: 1, color: Color(0x1AFFFFFF)),
              _row(Icons.info_outline, 'About ListenGood'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text('ListenGood 1.0 · Made with Freebuff',
              style: TextStyle(fontSize: 10, color: VibeTheme.textFaint)),
        ),
      ],
    );
  }

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: VibeTheme.text)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 10, color: VibeTheme.textDim)),
        ],
      );

  Widget _row(IconData icon, String label) => ListTile(
        leading: Icon(icon, color: VibeTheme.textDim, size: 20),
        title: Text(label,
            style: const TextStyle(fontSize: 13, color: VibeTheme.text)),
        trailing: const Icon(Icons.chevron_right,
            size: 16, color: VibeTheme.textDim),
        onTap: () {},
      );
}
