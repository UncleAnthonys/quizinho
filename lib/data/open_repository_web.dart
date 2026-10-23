import 'football_repository.dart';
import 'json_football_repository.dart';

Future<FootballRepository> openFootballRepository() async => loadJsonFootballRepository();
