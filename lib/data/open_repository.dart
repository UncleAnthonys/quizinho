import 'football_repository.dart';
import 'open_repository_web.dart' if (dart.library.io) 'open_repository_io.dart' as platform;

/// SQLite on iOS/Android, in-memory JSON on the web. Same data either way.
Future<FootballRepository> openFootballRepository() => platform.openFootballRepository();
