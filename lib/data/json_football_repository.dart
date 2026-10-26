import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'in_memory_football_repository.dart';
import 'models.dart';

/// Loads assets/db/football.json (same data as the SQLite file) into memory.
/// Used by the web build, where the SQLite plugin isn't available.
Future<InMemoryFootballRepository> loadJsonFootballRepository() async =>
    parseFootballJson(await rootBundle.loadString('assets/db/football.json'));

InMemoryFootballRepository parseFootballJson(String source) {
  final doc = jsonDecode(source) as Map<String, dynamic>;

  final clubs = <String, Club>{
    for (final c in doc['clubs'] as List)
      c[0] as String: Club(
        id: c[0] as String,
        name: c[1] as String,
        country: c[2] as String?,
        fame: c[3] as int,
        aliases: (c as List).length > 4 ? [for (final a in c[4] as List) a as String] : const [],
        women: c.length > 5 && c[5] == 'w',
      ),
  };
  Club club(String id) => clubs[id] ?? Club(id: id, name: id, fame: 1);

  final players = <String, Player>{
    for (final p in doc['players'] as List)
      p['id'] as String: Player(
        id: p['id'] as String,
        name: p['name'] as String,
        fame: p['fame'] as int,
        position: p['pos'] as String?,
        nationality: p['nat'] as String?,
        aliases: [for (final a in p['aliases'] as List) a as String],
        women: p['g'] == 'w',
      ),
  };

  return InMemoryFootballRepository(
    players: players.values.toList(),
    clubs: clubs.values.toList(),
    dataStatus: (doc['data_status'] as String?) ?? 'unknown',
    connections: [
      for (final c in doc['connections'] as List)
        ClubConnection(
          id: c[0] as String,
          clubA: club(c[1] as String),
          clubB: club(c[2] as String),
          difficulty: c[3] as int,
          answerIds: {for (final a in c[4] as List) a as String},
          eras: (c as List).length > 5 ? c[5] as int : Era.allMask,
        ),
    ],
    careers: [
      for (final c in doc['careers'] as List)
        if (players[c['player']] != null)
          CareerPath(
            player: players[c['player']]!,
            difficulty: c['difficulty'] as int,
            eras: (c['eras'] as int?) ?? Era.allMask,
            spells: [
              for (final s in c['spells'] as List)
                CareerSpell(
                  club: club(s[0] as String),
                  startYear: s[1] as int?,
                  endYear: s[2] as int?,
                  isLoan: s[3] == 1,
                ),
            ],
          ),
    ],
    bidding: [
      for (final b in (doc['bidding'] as List?) ?? const [])
        BiddingCategory(
          id: b[0] as String,
          prompt: b[1] as String,
          difficulty: b[2] as int,
          answerIds: {for (final a in b[3] as List) a as String},
          eras: b[4] as int,
          // [5] Pointless scores, aligned with the answers; [6] 1 = women's
          scores: (b as List).length > 5
              ? {for (var i = 0; i < (b[3] as List).length; i++) b[3][i] as String: (b[5] as List)[i] as int}
              : const {},
          women: b.length > 6 && b[6] == 1,
        ),
    ],
    checkouts: [
      for (final c in (doc['checkouts'] as List?) ?? const [])
        CheckoutCategory(
          id: c[0] as String,
          prompt: c[1] as String,
          difficulty: c[2] as int,
          eras: c[3] as int,
          women: c[4] == 1,
          values: {for (final v in c[5] as List) v[0] as String: (v[1] as int, v[2] as int)},
          noStats: {for (final id in c[6] as List) id as String},
        ),
    ],
    matches: [
      for (final m in doc['matches'] as List)
        HistoricMatch(
          id: m['id'] as String,
          title: m['title'] as String,
          competition: (m['competition'] as String?) ?? '',
          date: (m['date'] as String?) ?? '',
          home: m['home'] as String,
          away: m['away'] as String,
          score: (m['score'] as String?) ?? '',
          targetTeam: m['target'] as String,
          difficulty: m['difficulty'] as int,
          eras: (m['eras'] as int?) ?? Era.allMask,
          lineup: [
            for (final (i, s) in (m['xi'] as List).indexed)
              LineupSlot(
                index: i,
                playerId: s[0] as String,
                playerName: players[s[0]]?.name ?? s[1] as String,
                position: s[2] as String,
              ),
          ],
        ),
    ],
  );
}
