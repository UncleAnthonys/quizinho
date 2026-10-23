import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../domain/game_mode.dart';
import '../domain/tournament.dart';

/// Preferences + the last match setup, so a group can rematch in two taps.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  /// Separator for storing a team's player names in one string.
  static const _sep = '\u001F';

  /// Games that existed before new-game tracking was added.
  static const _modesBeforeTracking = ['clubConnections', 'careerPath', 'startingXi', 'wildcard'];

  static Future<AppSettings> load() async => AppSettings._(await SharedPreferences.getInstance());

  bool get soundOn => _prefs.getBool('soundOn') ?? true;
  bool get commentaryOn => _prefs.getBool('commentaryOn') ?? true;
  bool get hapticsOn => _prefs.getBool('hapticsOn') ?? true;
  bool get voiceOn => _prefs.getBool('voiceOn') ?? true;

  set soundOn(bool v) => _setBool('soundOn', v);
  set commentaryOn(bool v) => _setBool('commentaryOn', v);
  set hapticsOn(bool v) => _setBool('hapticsOn', v);
  set voiceOn(bool v) => _setBool('voiceOn', v);

  void _setBool(String key, bool v) {
    _prefs.setBool(key, v);
    notifyListeners();
  }

  /// Last-used setup, or sensible defaults for a first match.
  TournamentConfig lastConfig() {
    final names = _prefs.getStringList('teamNames') ?? const ['Home', 'Away'];
    final colours = _prefs.getStringList('teamColours') ?? const ['0', '1'];
    final players = _prefs.getStringList('teamPlayers') ?? const [];
    final modeNames = _prefs.getStringList('modes');
    final modes = modeNames?.map(GameModeId.fromName).whereType<GameModeId>().where((m) => m.playable).toSet();
    // Games added since the last save are switched on automatically.
    final known = (_prefs.getStringList('knownModes') ?? _modesBeforeTracking).toSet();
    modes?.addAll(GameModeId.values.where((m) => m.playable && !known.contains(m.name)));
    return TournamentConfig(
      teams: [
        for (var i = 0; i < names.length; i++)
          TeamSetup(
            name: names[i],
            colorIndex: i < colours.length ? int.tryParse(colours[i]) ?? i : i,
            players: i < players.length && players[i].isNotEmpty ? players[i].split(_sep) : null,
          ),
      ],
      length: MatchLength.fromName(_prefs.getString('length')),
      difficulty: Difficulty.fromName(_prefs.getString('difficulty')),
      modes: (modes == null || modes.isEmpty) ? null : modes,
      answerSeconds: _prefs.getInt('answerSeconds') ?? 15,
      bombSeconds: _prefs.getInt('bombSeconds') ?? 20,
      bombLives: _prefs.getInt('bombLives') ?? 3,
      headsUpSeconds: _prefs.getInt('headsUpSeconds') ?? 60,
      eras: Era.fromMask(_prefs.getInt('eras') ?? Era.allMask),
    );
  }

  Future<void> saveConfig(TournamentConfig c) async {
    await _prefs.setStringList('teamNames', [for (final t in c.teams) t.name]);
    await _prefs.setStringList('teamColours', [for (final t in c.teams) '${t.colorIndex}']);
    await _prefs.setStringList('teamPlayers', [for (final t in c.teams) t.players.join(_sep)]);
    await _prefs.setStringList('modes', [for (final m in c.modes) m.name]);
    await _prefs.setString('length', c.length.name);
    await _prefs.setString('difficulty', c.difficulty.name);
    await _prefs.setInt('answerSeconds', c.answerSeconds);
    await _prefs.setInt('bombSeconds', c.bombSeconds);
    await _prefs.setInt('bombLives', c.bombLives);
    await _prefs.setInt('headsUpSeconds', c.headsUpSeconds);
    await _prefs.setInt('eras', c.eraMask);
    await _prefs.setStringList('knownModes', [for (final m in GameModeId.values) if (m.playable) m.name]);
  }
}
