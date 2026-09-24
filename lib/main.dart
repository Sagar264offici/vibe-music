import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'core/library_store.dart';
import 'core/player.dart';
import 'ui/home_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  await JustAudioBackground.init(
    androidNotificationChannelId: 'dev.freebuff.listengood.audio',
    androidNotificationChannelName: 'ListenGood playback',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );
  // Hand the splash frame budget over: heavy init continues after first
  // frame so the native splash → UI handoff feels instant.
  runApp(const ListenGoodApp());
  unawaited(LibraryStore.instance.init());
  unawaited(PlayerService.instance.init());
}

class ListenGoodApp extends StatelessWidget {
  const ListenGoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ListenGood',
      debugShowCheckedModeBanner: false,
      theme: VibeTheme.dark(),
      home: const HomeShell(),
    );
  }
}
