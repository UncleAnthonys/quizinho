import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// Everyone who played for each club Hat-Trick deals: the career data's
/// players, and everyone else in the club's Wikipedia players category
/// ("Christian Roberts" at Swindon) - assets/db/hat_trick_rosters.json, built
/// by build_db.py. The extra names are Hat-Trick's alone: they're added to the
/// answer box for a set, never to the main player list (voice and search
/// run through that).
class HatTrickRosters {
  HatTrickRosters(this._extras, this._clubs);

  static const empty = HatTrickRosters._empty();
  const HatTrickRosters._empty()
      : _extras = const {},
        _clubs = const {};

  /// Extra player id ("x:Q123", or "x:" + the article title) -> name.
  final Map<String, String> _extras;

  /// Club id -> (career-data player ids, extra player ids).
  final Map<String, (List<String>, List<String>)> _clubs;

  static Future<HatTrickRosters> load() async {
    try {
      return parse(await rootBundle.loadString('assets/db/hat_trick_rosters.json'));
    } catch (e) {
      debugPrint('Hat-Trick rosters not loaded: $e');
      return empty;
    }
  }

  static HatTrickRosters parse(String source) {
    final doc = jsonDecode(source) as Map<String, dynamic>;
    final extras = <String, String>{
      for (final e in (doc['extras'] as List?) ?? const []) (e as List)[0] as String: e[1] as String,
    };
    final clubs = <String, (List<String>, List<String>)>{
      for (final e in ((doc['clubs'] as Map?) ?? const {}).entries)
        e.key as String: (
          [for (final id in (e.value as List)[0] as List) id as String],
          [for (final id in (e.value as List)[1] as List) id as String],
        ),
    };
    return HatTrickRosters(extras, clubs);
  }

  bool get isEmpty => _clubs.isEmpty;

  /// [set] with everyone at its three clubs, and the extra players to add to
  /// the answer box for it.
  (HatTrickSet, List<Player>) fill(HatTrickSet set) {
    if (isEmpty) return (set, const []);
    final played = {...set.played};
    final extra = <String>{};
    for (final (i, club) in set.clubs.indexed) {
      final (ids, extras) = _clubs[club.id] ?? (const <String>[], const <String>[]);
      for (final id in [...ids, ...extras]) {
        played[id] = (played[id] ?? 0) | (1 << i);
      }
      extra.addAll(extras);
    }
    return (
      HatTrickSet(id: set.id, clubs: set.clubs, played: played, difficulty: set.difficulty, eras: set.eras),
      [for (final id in extra) Player(id: id, name: _extras[id] ?? id, fame: 1)],
    );
  }

  /// The extra players at any of [clubIds] (a joined phone: the sets' clubs
  /// come from the main phone).
  List<Player> extrasFor(Iterable<String> clubIds) => [
        for (final id in {for (final c in clubIds) ...?_clubs[c]?.$2}) Player(id: id, name: _extras[id] ?? id, fame: 1),
      ];
}
