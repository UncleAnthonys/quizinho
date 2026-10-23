import 'football_repository.dart';
import 'sqlite_football_repository.dart';

Future<FootballRepository> openFootballRepository() async => SqliteFootballRepository.open();
