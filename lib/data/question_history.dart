/// Questions this phone has already been asked, per kind ("conn", "career",
/// "match", "bidding", "checkout", "ttt", "headsup"), across matches and
/// solo runs. Games pick something new first and only repeat once a pool
/// has run dry — so a group playing match after match, or a solo player
/// coming back, doesn't get the same questions again.
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

  /// Enough to cycle through every Easy and Medium pool before forgetting.
  static const cap = 3000;

  List<String> _list(String kind) => _lists.putIfAbsent(kind, () => [...?_read?.call('history_$kind')]);

  Set<String> seen(String kind) => _list(kind).toSet();

  void add(String kind, String id) {
    final list = _list(kind)
      ..remove(id)
      ..add(id); // newest last
    if (list.length > cap) list.removeRange(0, list.length - cap);
    _write?.call('history_$kind', list);
  }

  void addAll(String kind, Iterable<String> ids) {
    for (final id in ids) {
      final list = _list(kind)
        ..remove(id)
        ..add(id);
      if (list.length > cap) list.removeRange(0, list.length - cap);
    }
    _write?.call('history_$kind', _list(kind));
  }
}
