/// Questions this phone has already been asked, per kind ([kinds]), across
/// matches, solo runs and games joined on a friend's phone. Games pick
/// something new first and only repeat once a pool has run dry — so a group
/// playing match after match, or a solo player coming back, doesn't get the
/// same questions again.
///
/// In a room, the main phone also counts what every joined phone has had
/// ([setOthers]): a question anyone in the room has seen comes after the
/// fresh ones, and when a pool runs dry the one the fewest of them have seen
/// (longest ago) comes back first ([repeatOrder]).
///
/// Storage is supplied by the app (SharedPreferences); without it the
/// history just lives in memory (tests).
class QuestionHistory {
  QuestionHistory({List<String>? Function(String key)? read, void Function(String key, List<String> ids)? write})
      : _read = read,
        _write = write;

  final List<String>? Function(String key)? _read;
  final void Function(String key, List<String> ids)? _write;
  final Map<String, List<String>> _lists = {};

  /// Every kind of question that's remembered.
  static const kinds = ['conn', 'career', 'match', 'bidding', 'checkout', 'ttt', 'headsup', 'teaser', 'top10'];

  /// Enough to cycle through every Easy and Medium pool before forgetting.
  static const cap = 3000;

  /// How many of each kind a joining phone hands over (its most recent).
  static const shareCap = 1000;

  List<String> _list(String kind) => _lists.putIfAbsent(kind, () => [...?_read?.call('history_$kind')]);

  /// Joined phones' lists, by phone, then kind (oldest first).
  final Map<String, Map<String, List<String>>> _others = {};

  /// Told whenever something's recorded here (the room passes it on to the
  /// joined phones, so they remember it too).
  void Function(String kind, List<String> ids)? onRecord;

  /// What the phones in the room have had ([export] from each).
  void setOthers(Map<String, Map<String, List<String>>> byPhone) {
    _others
      ..clear()
      ..addAll(byPhone);
  }

  /// Seen by this phone or any phone in the room.
  Set<String> seen(String kind) => {..._list(kind), for (final o in _others.values) ...?o[kind]};

  /// This phone's own, oldest first.
  List<String> order(String kind) => List.unmodifiable(_list(kind));

  /// How many phones (this one and the room's) have had each one.
  Map<String, int> seenCounts(String kind) {
    final counts = <String, int>{};
    for (final list in [_list(kind), for (final o in _others.values) o[kind] ?? const <String>[]]) {
      for (final id in list.toSet()) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Everything seen, best to bring back first: fewest phones had it, then
  /// longest ago (by whichever phone had it most recently).
  List<String> repeatOrder(String kind) {
    final counts = seenCounts(kind);
    final recent = <String, double>{};
    for (final list in [_list(kind), for (final o in _others.values) o[kind] ?? const <String>[]]) {
      for (final (i, id) in list.indexed) {
        final r = (i + 1) / list.length; // 1 = newest on that phone
        if (r > (recent[id] ?? 0)) recent[id] = r;
      }
    }
    return counts.keys.toList()
      ..sort((a, b) {
        final c = counts[a]!.compareTo(counts[b]!);
        return c != 0 ? c : recent[a]!.compareTo(recent[b]!);
      });
  }

  /// This phone's lists to hand to a room (the most recent [shareCap] of each).
  Map<String, List<String>> export() => {
        for (final k in kinds)
          if (_list(k) case final l when l.isNotEmpty) k: l.length > shareCap ? l.sublist(l.length - shareCap) : [...l],
      };

  void add(String kind, String id) => addAll(kind, [id]);

  void addAll(String kind, Iterable<String> ids) {
    final added = [...ids];
    if (added.isEmpty) return;
    final list = _list(kind);
    for (final id in added) {
      list
        ..remove(id)
        ..add(id); // newest last
    }
    if (list.length > cap) list.removeRange(0, list.length - cap);
    _write?.call('history_$kind', list);
    onRecord?.call(kind, added);
  }

  /// Recorded from another phone (the main phone's game): kept, not passed on.
  void addFromRoom(String kind, Iterable<String> ids) {
    final keep = onRecord;
    onRecord = null;
    try {
      addAll(kind, ids);
    } finally {
      onRecord = keep;
    }
  }
}
