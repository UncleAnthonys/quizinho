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
      _entries.add(_Entry(
        p,
        keys.toList(),
        tokens.toList(),
        {for (final k in keys) soundKey(k)}..removeWhere((k) => k.length < 3),
        {for (final t in tokens) soundKey(t)}..removeWhere((k) => k.length < 2),
      ));
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

  /// Words people say around a name: "it's… um… David Luiz".
  static const _filler = {
    'its', 'it', 'is', 'um', 'uh', 'er', 'erm', 'umm', 'the', 'i', 'think', 'maybe', 'was', 'that',
    'player', 'oh', 'ah', 'yeah', 'yes', 'no', 'wait', 'a', 'and', 'like',
  };

  static String _cleanSpoken(String text) =>
      normaliseName(text).split(' ').where((w) => w.isNotEmpty && !_filler.contains(w)).join(' ');

  /// Search tuned for speech: spelling-based matching plus sound-alike matching.
  List<PlayerMatch> searchSpoken(String transcript, {int limit = 6}) {
    final q = _cleanSpoken(transcript);
    if (q.isEmpty) return const [];
    final words = q.split(' ');
    final whole = soundKey(q);
    final wordKeys = [for (final w in words) soundKey(w)];
    final hits = <PlayerMatch>[];
    for (final e in _entries) {
      var s = _score(e, q);
      if (whole.length >= 3 && e.sounds.contains(whole)) {
        s = s < 95 ? 95 : s; // whole name sounds right: "david louise" = David Luiz
      } else if (words.length >= 2 && wordKeys.every((k) => k.length >= 2 && e.tokenSounds.contains(k))) {
        s = s < 93 ? 93 : s; // every word sounds like part of the name
      } else if (words.length == 1 && whole.length >= 3 && e.tokenSounds.contains(whole)) {
        s = s < 90 ? 90 : s; // surname alone sounds right
      }
      if (s > 0) hits.add(PlayerMatch(e.player, s + e.player.fame * 2));
    }
    hits.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.player.name.compareTo(b.player.name);
    });
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  /// Best player across speech alternatives, or null if it isn't clear-cut.
  /// [partial] = words still coming in: only a complete name (full name,
  /// alias, or a full-name sound match) counts — never a first name alone.
  Player? resolveSpoken(List<String> alternatives, {bool partial = false}) {
    final best = <String, PlayerMatch>{};
    for (final alt in alternatives) {
      for (final m in searchSpoken(alt, limit: 3)) {
        final prev = best[m.player.id];
        if (prev == null || m.score > prev.score) best[m.player.id] = m;
      }
    }
    if (best.isEmpty) return null;
    final ranked = best.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    final top = ranked.first;
    // fame adds up to +10, so thresholds sit on the base score
    final base = top.score - top.player.fame * 2;
    if (base < (partial ? 95 : 88)) return null;
    if (ranked.length > 1 && ranked[1].score >= top.score - 6) return null;
    return top.player;
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
  _Entry(this.player, this.keys, this.tokens, this.sounds, this.tokenSounds);
  final Player player;
  final List<String> keys;
  final List<String> tokens;

  /// Sound keys of full names/aliases, and of individual name words.
  final Set<String> sounds;
  final Set<String> tokenSounds;
}
