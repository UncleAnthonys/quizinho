import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quizinho/core/app_services.dart';
import 'package:quizinho/core/app_settings.dart';
import 'package:quizinho/core/sound_service.dart';
import 'package:quizinho/data/in_memory_football_repository.dart';
import 'package:quizinho/main.dart';
import 'package:quizinho/ui/widgets/logo.dart';

import 'fixtures.dart';

void main() {
  testWidgets('home → setup shows two default teams and a kick-off button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final services = AppServices(
      repo: InMemoryFootballRepository(players: allPlayers, connections: [arsenalBarca()]),
      settings: settings,
      sound: SoundService(settings), // not initialised → silent in tests
    );

    await tester.pumpWidget(QuizinhoApp(services: services));
    expect(find.byType(QuizinhoWordmark), findsOneWidget);

    await tester.tap(find.text('NEW MATCH'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Away'), findsOneWidget);
    expect(find.text('KICK OFF'), findsOneWidget);
  });
}
