import 'package:flutter/material.dart';

import 'now_playing_sheet.dart';
import 'screens/explore_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/profile_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Holds the gradient background + bottom nav + mini player + tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [VibeTheme.bgTop, VibeTheme.bgMid, VibeTheme.bgBottom],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -60,
              child: _glow(220, VibeTheme.violet.withOpacity(0.5)),
            ),
            Positioned(
              bottom: -60,
              left: -50,
              child: _glow(200, VibeTheme.pink.withOpacity(0.42)),
            ),
            SafeArea(
              child: wide
                  ? Row(
                      children: [
                        NavigationRail(
                          backgroundColor: Colors.transparent,
                          selectedIndex: _tab,
                          onDestinationSelected: (i) => setState(() => _tab = i),
                          labelType: NavigationRailLabelType.all,
                          destinations: const [
                            NavigationRailDestination(
                                icon: Icon(Icons.home_outlined),
                                selectedIcon: Icon(Icons.home),
                                label: Text('Home')),
                            NavigationRailDestination(
                                icon: Icon(Icons.explore_outlined),
                                selectedIcon: Icon(Icons.explore),
                                label: Text('Explore')),
                            NavigationRailDestination(
                                icon: Icon(Icons.library_music_outlined),
                                selectedIcon: Icon(Icons.library_music),
                                label: Text('Library')),
                            NavigationRailDestination(
                                icon: Icon(Icons.person_outline),
                                selectedIcon: Icon(Icons.person),
                                label: Text('Profile')),
                          ],
                        ),
                        Expanded(child: _buildTab()),
                      ],
                    )
                  : _buildTab(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : _BottomNav(
              tab: _tab,
              onChange: (i) => setState(() => _tab = i),
              onOpenPlayer: () => showNowPlayingSheet(context),
            ),
    );
  }

  Widget _buildTab() {
    switch (_tab) {
      case 0:
        return HomeScreen(goToTab: (i) => setState(() => _tab = i));
      case 1:
        return const ExploreScreen();
      case 2:
        return const LibraryScreen();
      case 3:
        return const ProfileScreen();
    }
    return const SizedBox.shrink();
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onChange;
  final VoidCallback onOpenPlayer;
  const _BottomNav({
    required this.tab,
    required this.onChange,
    required this.onOpenPlayer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MiniPlayerBar(onOpen: onOpenPlayer),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0x2E1E0B3F),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: VibeTheme.glassBorder, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _item(Icons.home_rounded, 'Home', 0),
                _item(Icons.explore_rounded, 'Explore', 1),
                _item(Icons.library_music_rounded, 'Library', 2),
                _item(Icons.person_rounded, 'Profile', 3),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _item(IconData icon, String label, int index) {
    final active = tab == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChange(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: active ? Colors.white : VibeTheme.textFaint),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  color: active ? Colors.white : VibeTheme.textFaint)),
        ],
      ),
    );
  }
}
