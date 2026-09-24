import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/remote_catalog.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/song_row.dart';

/// Explore tab: live search (remote API) + filter chips + results list.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;

  bool _loading = false;
  List _remote = const [];
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() {
        _remote = const [];
        _loading = false;
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _runSearch(v.trim());
    });
  }

  Future<void> _runSearch(String q) async {
    setState(() {
      _loading = true;
    });
    final results = await RemoteCatalog.searchSongs(q, limit: 30);
    if (!mounted) return;
    setState(() {
      _remote = results;
      _loading = false;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
          child: GlassContainer(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(color: VibeTheme.text, fontSize: 13),
              decoration: InputDecoration(
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: VibeTheme.accentLight))
                    : const Icon(Icons.search,
                        color: VibeTheme.textDim, size: 20),
                hintText: 'Songs, artists, albums…',
                hintStyle: const TextStyle(
                    color: VibeTheme.textFaint, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onChanged: _onChanged,
            ),
          ),
        ),
        Expanded(
          child: !_searched
              ? const Center(
                  child: Text('Search millions of songs',
                      style: TextStyle(color: VibeTheme.textDim)))
              : _remote.isEmpty && !_loading
                  ? const Center(
                      child: Text('No results found',
                          style: TextStyle(color: VibeTheme.textDim)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
                      itemCount: _remote.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SongRow(
                          song: _remote[i],
                          rank: i + 1,
                          showLike: true,
                          queue: _remote.cast(),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}
