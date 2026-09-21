import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/audio_handler.dart';
import 'services/storage_service.dart';
import 'providers/music_player_provider.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize persistent local storage (Hive)
  final storageService = StorageService();
  await storageService.init();

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
    return MaterialApp(
      title: 'Pulse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainNavigationScreen(),
    );
  }
}
