import '../data/models.dart';
import 'text_normaliser.dart';

/// A ranked search hit.
class PlayerMatch {
  const PlayerMatch(this.player, this.score);
  final Player player;

  /// Higher is better. ≥100 means an exact name/alias hit.
  final double score;
}

/// In-memory, accent-insensitive lookup over every player in the database.
///
/// Used by the answer picker today (type 3 letters → tap the name) and by
/// speech recognition in Phase 2 (transcript → best candidates). Answers are
/// always judged by stable player IDs, never by the text itself.
class PlayerIndex {
  PlayerIndex(Iterable<Player> players) {
    for (final p in players) {
      final keys = <String>{};
      void add(String raw) {
        final k = normaliseName(raw);
        if (k.isNotEmpty) keys.add(k);
      }

      add(p.name);
      p.aliases.forEach(add);
      final tokens = <String>{};
      for (final k in keys) {
        for (final t in k.split(' ')) {
          if (t.length >= 3) tokens.add(t);
        }
      }
      _entries.add(_Entry(p, keys.toList(), tokens.toList()));
      _byId[p.id] = p;
    }
  }

  final List<_Entry> _entries = [];
  final Map<String, Player> _byId = {};

  int get length => _entries.length;
  Player? byId(String id) => _byId[id];

  List<PlayerMatch> search(String query, {int limit = 8}) {
    final q = normaliseName(query);
    if (q.isEmpty) return const [];
    final hits = <PlayerMatch>[];
    for (final e in _entries) {
      final s = _score(e, q);
      if (s > 0) hits.add(PlayerMatch(e.player, s + e.player.fame * 2));
    }
    hits.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.player.name.compareTo(b.player.name);
    });
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  /// For free text (typed or spoken): the single best player if the match is
  /// unambiguous enough to act on, else null so the UI can ask the room.
  Player? resolveConfidently(String text) {
    final hits = search(text, limit: 2);
    if (hits.isEmpty) return null;
    final best = hits.first;
    if (best.score < 90) return null;
    if (hits.length > 1 && hits[1].score >= best.score - 5) return null;
    return best.player;
  }

  double _score(_Entry e, String q) {
    var best = 0.0;
    for (final k in e.keys) {
      if (k == q) return 100;
      if (k.startsWith(q)) best = best < 80 ? 80 : best;
      // "alexander arnold" inside "trent alexander arnold"
      if (q.contains(' ') && k.contains(' $q')) best = best < 75 ? 75 : best;
    }
    for (final t in e.tokens) {
      if (t == q) best = best < 92 ? 92 : best; // surname typed in full
      if (t.startsWith(q)) best = best < 70 ? 70 : best;
    }
    if (best == 0 && q.length >= 4) {
      // typo tolerance: compare against full keys and single tokens
      var sim = 0.0;
      for (final k in [...e.keys, ...e.tokens]) {
        final s = similarity(q, k);
        if (s > sim) sim = s;
      }
      if (sim >= 0.75) best = 50 * sim;
    }
    return best;
  }
}

class _Entry {
  _Entry(this.player, this.keys, this.tokens);
  final Player player;
  final List<String> keys;
  final List<String> tokens;
}
