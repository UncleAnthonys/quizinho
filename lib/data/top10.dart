import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';
import 'question_history.dart';

/// One place on a Top 10: who, and their figure ("260 goals").
class Top10Entry {
  const Top10Entry(
      {required this.rank, required this.playerId, required this.name, this.figure = '', this.alternates = const []});
  final int rank;
  final String playerId;
  final String name;
  final String figure;

  /// Level with 10th beyond the ten (Keane and Pirès with Beattie on 14):
  /// any of them fills this slot. (id, name).
  final List<(String, String)> alternates;

  /// Everyone who fills this slot: (id, name).
  List<(String, String)> get all => [(playerId, name), ...alternates];
}

/// A Top 10 list read from a Wikipedia record table (assets/db/top10.json,
/// built by data_pipeline/top10_build.py), e.g. "Premier League all-time top
/// scorers".
class Top10List {
  const Top10List(
      {required this.id,
      required this.prompt,
      required this.level,
      required this.entries,
      this.asOf = '',
      this.category = 'classic',
      String? family})
      : family = family ?? id;

  factory Top10List.fromJson(Map<String, Object?> m) => Top10List(
        id: '${m['id']}',
        prompt: '${m['q']}',
        level: (m['d'] as num?)?.toInt() ?? 2,
        asOf: '${m['asof'] ?? ''}',
        family: m['f'] as String?,
        category: '${m['c'] ?? 'classic'}',
        entries: [
          for (final e in m['e'] as List? ?? const [])
            Top10Entry(
              rank: ((e as List)[0] as num).toInt(),
              playerId: '${e[1]}',
              name: '${e[2]}',
              figure: e.length > 3 ? '${e[3]}' : '',
              alternates: e.length > 4
                  ? [for (final a in e[4] as List) ('${(a as List)[0]}', '${a[1]}')]
                  : const [],
            ),
        ],
      );

  final String id;
  final String prompt;

  /// Lists that are one idea many times over (each season's top scorers,
  /// each club's) share a family; a one-off list is its own.
  final String family;

  /// classic, club, era, quirky or nations (see [Top10Bank.mix]).
  final String category;

  /// 1–3, as challenges ([Difficulty.allowedLevels]).
  final int level;

  /// When the table was read ("Nov 2026"): live records move on.
  final String asOf;
  final List<Top10Entry> entries;

  int? indexOf(String playerId) {
    for (final (i, e) in entries.indexed) {
      if (e.all.any((a) => a.$1 == playerId)) return i;
    }
    return null;
  }
}

class Top10Bank {
  Top10Bank(this.lists);

  static Future<Top10Bank> load() async => parse(await rootBundle.loadString('assets/db/top10.json'));

  static Top10Bank parse(String json) {
    final doc = jsonDecode(json) as Map<String, Object?>;
    return Top10Bank([
      for (final l in doc['lists'] as List? ?? const []) Top10List.fromJson(Map<String, Object?>.from(l as Map)),
    ]);
  }

  final List<Top10List> lists;

  /// How often each kind of list comes up, by difficulty: famous records
  /// lead on Easy, the odd ones on Hard. A kind with nothing fresh left
  /// drops out and the rest share its turn.
  static const mix = {
    Difficulty.easy: {'classic': 35, 'club': 20, 'era': 15, 'quirky': 20, 'nations': 10},
    Difficulty.medium: {'classic': 25, 'club': 20, 'era': 20, 'quirky': 25, 'nations': 10},
    Difficulty.hard: {'classic': 15, 'club': 20, 'era': 20, 'quirky': 35, 'nations': 10},
    Difficulty.expert: {'classic': 15, 'club': 20, 'era': 20, 'quirky': 35, 'nations': 10},
  };

  /// The kind just played comes up again at this share of its weight, so
  /// two club lists in a row are rare but possible.
  static const repeatFactor = 0.3;

  /// Top 10 lists go up to level 3; Expert gets the hardest.
  static Set<int> _levels(Difficulty d) => d == Difficulty.expert ? {3} : d.allowedLevels;

  /// One this phone hasn't had at [difficulty] (then the longest-ago), and
  /// records it. A kind of list first ([mix]), then a family within it (all
  /// 41 club lists are one family), then a list.
  Top10List? pick({required Difficulty difficulty, required QuestionHistory history, Random? random}) {
    final rnd = random ?? Random();
    var pool = [for (final l in lists) if (_levels(difficulty).contains(l.level)) l];
    if (pool.isEmpty) pool = [for (final l in lists) if (difficulty.atMostLevels.contains(l.level)) l];
    if (pool.isEmpty) pool = lists;
    if (pool.isEmpty) return null;
    final order = history.order(kind);
    final fresh = [for (final l in pool) if (!order.contains(l.id)) l];
    final Top10List choice;
    if (fresh.isNotEmpty) {
      final byId = {for (final l in lists) l.id: l};
      final last = order.isEmpty ? null : byId[order.last]?.category;
      final kinds = <String, List<Top10List>>{};
      for (final l in fresh) {
        kinds.putIfAbsent(l.category, () => []).add(l);
      }
      final weights = mix[difficulty]!;
      final names = kinds.keys.toList();
      final w = [for (final k in names) (weights[k] ?? 10) * (k == last && names.length > 1 ? repeatFactor : 1.0)];
      var r = rnd.nextDouble() * w.reduce((a, b) => a + b);
      var picked = names.last;
      for (final (i, k) in names.indexed) {
        r -= w[i];
        if (r < 0) {
          picked = k;
          break;
        }
      }
      // Then a family, then one of its lists: 41 club lists count as one
      // idea, so "Blackburn's scorers" is as likely as "a club's derby".
      final families = <String, List<Top10List>>{};
      for (final l in kinds[picked]!) {
        families.putIfAbsent(l.family, () => []).add(l);
      }
      final keys = families.keys.toList();
      final pickFrom = families[keys[rnd.nextInt(keys.length)]]!;
      choice = pickFrom[rnd.nextInt(pickFrom.length)];
    } else {
      final rank = {for (final (i, id) in order.indexed) id: i};
      choice = ([...pool]..sort((a, b) => (rank[a.id] ?? 0).compareTo(rank[b.id] ?? 0))).first;
    }
    history.add(kind, choice.id);
    return choice;
  }

  static const kind = 'top10';
}
