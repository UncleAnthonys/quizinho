import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../domain/game_mode.dart';
import '../domain/tournament.dart';

/// Preferences + the last match setup, so a group can rematch in two taps.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async => AppSettings._(await SharedPreferences.getInstance());

  bool get soundOn => _prefs.getBool('soundOn') ?? true;
  bool get commentaryOn => _prefs.getBool('commentaryOn') ?? true;
  bool get hapticsOn => _prefs.getBool('hapticsOn') ?? true;

  set soundOn(bool v) => _setBool('soundOn', v);
  set commentaryOn(bool v) => _setBool('commentaryOn', v);
  set hapticsOn(bool v) => _setBool('hapticsOn', v);

  void _setBool(String key, bool v) {
    _prefs.setBool(key, v);
    notifyListeners();
  }

  /// Last-used setup, or sensible defaults for a first match.
  TournamentConfig lastConfig() {
    final names = _prefs.getStringList('teamNames') ?? const ['Home', 'Away'];
    final colours = _prefs.getStringList('teamColours') ?? const ['0', '1'];
    final modeNames = _prefs.getStringList('modes');
    final modes = modeNames?.map(GameModeId.fromName).whereType<GameModeId>().where((m) => m.playable).toSet();
    return TournamentConfig(
      teams: [
        for (var i = 0; i < names.length; i++)
          TeamSetup(name: names[i], colorIndex: i < colours.length ? int.tryParse(colours[i]) ?? i : i),
      ],
      length: MatchLength.fromName(_prefs.getString('length')),
      difficulty: Difficulty.fromName(_prefs.getString('difficulty')),
      modes: (modes == null || modes.isEmpty) ? null : modes,
      answerSeconds: _prefs.getInt('answerSeconds') ?? 15,
      bombSeconds: _prefs.getInt('bombSeconds') ?? 20,
      bombLives: _prefs.getInt('bombLives') ?? 3,
    );
  }

  Future<void> saveConfig(TournamentConfig c) async {
    await _prefs.setStringList('teamNames', [for (final t in c.teams) t.name]);
    await _prefs.setStringList('teamColours', [for (final t in c.teams) '${t.colorIndex}']);
    await _prefs.setStringList('modes', [for (final m in c.modes) m.name]);
    await _prefs.setString('length', c.length.name);
    await _prefs.setString('difficulty', c.difficulty.name);
    await _prefs.setInt('answerSeconds', c.answerSeconds);
    await _prefs.setInt('bombSeconds', c.bombSeconds);
    await _prefs.setInt('bombLives', c.bombLives);
  }
}
