import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/audio_handler.dart';
import 'services/network_status.dart';
import 'services/storage_service.dart';
import 'providers/music_player_provider.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize persistent local storage (Hive)
  final storageService = StorageService();
  await storageService.init();

  // Wi-Fi vs mobile data decides stream quality and pre-caching.
  await NetworkStatus.instance.start();

  // Initialize background AudioService
  final audioHandler = await initAudioService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => MusicPlayerProvider(audioHandler, storageService),
        ),
      ],
      child: const MusicPlayerApp(),
    ),
  );
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode =
        context.select<MusicPlayerProvider, ThemeMode>((p) => p.themeMode);
    return MaterialApp(
      title: 'Pulse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const MainNavigationScreen(),
    );
  }
}
