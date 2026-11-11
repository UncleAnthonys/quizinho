import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/player_index.dart';
import 'models.dart';
import 'question_history.dart';

/// One Half-Time Teaser: a slow-burn "Name a player who…" question with
/// every right answer checked (assets/db/teasers.json, built by
/// data_pipeline/teasers_build.py).
class Teaser {
  const Teaser({
    required this.question,
    required this.family,
    required this.level,
    required this.eras,
    required this.answerIds,
    required this.answerNames,
    this.prefix = 'NAME A PLAYER WHO…',
    this.unsure = const {},
    this.herrings = const {},
  });

  factory Teaser.fromJson(Map<String, Object?> m) => Teaser(
        question: '${m['q']}',
        family: '${m['f'] ?? 'other'}',
        level: (m['d'] as num?)?.toInt() ?? 2,
        eras: (m['e'] as num?)?.toInt() ?? Era.allMask,
        answerIds: [for (final a in m['a'] as List? ?? const []) '$a'],
        answerNames: [for (final a in m['n'] as List? ?? const []) '$a'],
        prefix: (m['p'] as String?) ?? 'NAME A PLAYER WHO…',
        unsure: {for (final a in m['u'] as List? ?? const []) '$a'},
        herrings: {for (final e in (m['r'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'},
      );

  /// "Played in El Clásico, the Merseyside derby AND the North London derby".
  /// Also the id (history, saved matches).
  final String question;
  String get id => question;

  /// final · derby · mixed · teammates · managers · other — for spacing.
  final String family;

  /// 1–4, as challenges ([Difficulty.allowedLevels]).
  final int level;
  final int eras;
  final List<String> answerIds;

  /// Display names, in the same order as [answerIds].
  final List<String> answerNames;
  final String prefix;

  /// Fit on paper, but we couldn't confirm the appearance: the host decides.
  final Set<String> unsure;

  /// Players people will say who don't count → why not.
  final Map<String, String> herrings;

  bool isAnswer(String playerId) => answerIds.contains(playerId);
}

class TeaserBank {
  TeaserBank(this.teasers) : _byId = {for (final t in teasers) t.id: t};

  static Future<TeaserBank> load() async => parse(await rootBundle.loadString('assets/db/teasers.json'));

  static TeaserBank parse(String json) {
    final doc = jsonDecode(json) as Map<String, Object?>;
    return TeaserBank([
      for (final t in doc['teasers'] as List? ?? const []) Teaser.fromJson(Map<String, Object?>.from(t as Map)),
    ]);
  }

  final List<Teaser> teasers;
  final Map<String, Teaser> _byId;
  Teaser? byId(String id) => _byId[id];
}

/// Picks the teaser for a tournament. Properly random, and per phone:
/// nothing this phone has had comes back until the level has run dry
/// (then the longest-ago first). Final scorers are the filler (about one
/// in seven); derby questions at most one in three; never the same kind
/// twice running, or an answer from the last few.
class TeaserPicker {
  TeaserPicker({required this.bank, required this.history, required this.players, Random? random})
      : _random = random ?? Random();

  static const kind = 'teaser';
  static const finalShare = 0.15;

  final TeaserBank bank;
  final QuestionHistory history;
  final PlayerIndex players;
  final Random _random;

  /// Easy has no teasers of its own: Medium ones with a superstar answer.
  bool _fits(Teaser t, Difficulty d) => d == Difficulty.easy
      ? t.level <= 2 && t.answerIds.any((id) => (players.byId(id)?.fame ?? 0) >= 5)
      : d.allowedLevels.contains(t.level);

  Teaser? pick({required Difficulty difficulty, int eras = Era.allMask}) {
    var pool = [for (final t in bank.teasers) if (_fits(t, difficulty) && t.eras & eras != 0) t];
    if (pool.isEmpty) pool = [for (final t in bank.teasers) if (_fits(t, difficulty)) t];
    if (pool.isEmpty) return null;

    final order = history.order(kind);
    final seen = order.toSet();
    final recent = [for (final id in order.reversed.take(5)) if (bank.byId(id) case final t?) t];
    final recentAnswers = {for (final t in recent) ...t.answerIds};
    final lastFamily = recent.isEmpty ? null : recent.first.family;
    final derbyLately = recent.take(2).any((t) => t.family == 'derby');

    var fresh = [for (final t in pool) if (!seen.contains(t.id)) t];
    if (fresh.isEmpty) {
      // Everything at this level has been played: the longest-ago half again.
      final rank = {for (final (i, id) in order.indexed) id: i};
      fresh = [...pool]..sort((a, b) => (rank[a.id] ?? 0).compareTo(rank[b.id] ?? 0));
      fresh = fresh.take(max(1, fresh.length ~/ 2)).toList();
    }

    // Spacing rules, dropped one at a time if they'd leave nothing.
    List<Teaser> where(bool Function(Teaser) keep, List<Teaser> from) {
      final kept = [for (final t in from) if (keep(t)) t];
      return kept.isEmpty ? from : kept;
    }

    var options = where((t) => !t.answerIds.any(recentAnswers.contains), fresh);
    options = where((t) => !(derbyLately && t.family == 'derby'), options);
    options = where((t) => t.family != lastFamily, options);

    final finals = [for (final t in options) if (t.family == 'final') t];
    final rest = [for (final t in options) if (t.family != 'final') t];
    final group = finals.isEmpty
        ? rest
        : rest.isEmpty
            ? finals
            : (_random.nextDouble() < finalShare ? finals : rest);
    final choice = group[_random.nextInt(group.length)];
    history.add(kind, choice.id);
    return choice;
  }
}
