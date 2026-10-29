import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_services.dart';
import 'core/app_settings.dart';
import 'core/purchases.dart';
import 'core/sound_service.dart';
import 'core/theme.dart';
import 'core/voice_service.dart';
import 'data/open_repository.dart';
import 'ui/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    final settings = await AppSettings.load();
    final repo = await openFootballRepository();
    final sound = SoundService(settings);
    await sound.init();
    final voice = VoiceService(settings);
    // iPhone: build the player-name voice model in the background while
    // people set up teams; it's kept on the phone afterwards.
    if (settings.voiceOn) unawaited(voice.prepareModel());
    // Listen for purchases from the start (incl. ones finished while closed).
    final purchases = Purchases(settings);
    unawaited(purchases.init());
    runApp(QuizinhoApp(
        services: AppServices(repo: repo, settings: settings, sound: sound, voice: voice, purchases: purchases)));
  } catch (e, st) {
    debugPrint('Startup failed: $e\n$st');
    runApp(_StartupError(error: '$e'));
  }
}

class QuizinhoApp extends StatelessWidget {
  const QuizinhoApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) => AppScope(
        services: services,
        child: MaterialApp(
          title: 'Quizinho',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          builder: (context, child) => _PhoneFrame(child: child!),
          home: const HomeScreen(),
        ),
      );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Quizinho couldn’t start.\n\n$error', textAlign: TextAlign.center),
            ),
          ),
        ),
      );
}

/// On a laptop browser, show the game in a phone-width column instead of
/// stretching it across the screen. No effect on phones.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Phones (either way up) fill the screen; only a laptop-sized window gets the frame.
    if (size.width <= 520 || size.height < 600) return child;
    final width = 430.0;
    final height = size.height > 940 ? 900.0 : size.height - 24;
    return ColoredBox(
      color: const Color(0xFF020C08),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: SizedBox(
            width: width,
            height: height,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(width, height)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
