/// A shared live JSON tree that every phone in a room reads and writes —
/// Firebase Realtime Database in the app, in memory in tests.
///
/// Paths are slash-separated ("rooms/ABCD/view"). Values are JSON: maps,
/// lists, strings, numbers, bools; null removes.
abstract class RoomLink {
  /// The value at [path] now, then again after every change (null = absent).
  Stream<Object?> watch(String path);

  /// Replaces the value at [path].
  Future<void> put(String path, Object? value);

  /// Merges [values] into the map at [path].
  Future<void> patch(String path, Map<String, Object?> values);

  /// Adds [value] under a new, time-ordered key in [path]; returns the key.
  Future<String> push(String path, Object? value);

  Future<void> remove(String path) => put(path, null);

  void close() {}
}

/// Placeholder the database replaces with its own clock (ms since epoch) —
/// so buzzes from different phones are timed by one clock, not each phone's.
const Map<String, String> serverTime = {'.sv': 'timestamp'};

/// Splits "a/b/c" (or "/a/b/c/") into its parts.
List<String> pathParts(String path) => [for (final p in path.split('/')) if (p.isNotEmpty) p];

/// Returns [tree] with [value] written at [path] (relative to the tree root).
/// [merge]: merge a map into what's there instead of replacing it. Never
/// mutates [tree] — returns a new one where anything changed.
Object? writeAt(Object? tree, List<String> path, Object? value, {bool merge = false}) {
  if (path.isEmpty) {
    if (!merge) return _clean(value);
    final base = tree is Map ? Map<String, Object?>.from(tree) : <String, Object?>{};
    for (final e in (value as Map).entries) {
      final v = _clean(e.value);
      if (v == null) {
        base.remove('${e.key}');
      } else {
        base['${e.key}'] = v;
      }
    }
    return base.isEmpty ? null : base;
  }
  final key = path.first;
  final Map<String, Object?> base;
  if (tree is Map) {
    base = Map<String, Object?>.from(tree);
  } else if (tree is List) {
    base = {for (var i = 0; i < tree.length; i++) if (tree[i] != null) '$i': tree[i]};
  } else {
    base = {};
  }
  final child = writeAt(base[key], path.sublist(1), value, merge: merge);
  if (child == null) {
    base.remove(key);
  } else {
    base[key] = child;
  }
  return base.isEmpty ? null : base;
}

/// The value at [path] inside [tree], or null.
Object? readAt(Object? tree, List<String> path) {
  var node = tree;
  for (final key in path) {
    if (node is Map) {
      node = node[key];
    } else if (node is List) {
      final i = int.tryParse(key);
      node = i != null && i >= 0 && i < node.length ? node[i] : null;
    } else {
      return null;
    }
  }
  return node;
}

/// Drops nulls inside maps, as the database does.
Object? _clean(Object? v) {
  if (v is Map) {
    final m = <String, Object?>{
      for (final e in v.entries)
        if (_clean(e.value) case final c?) '${e.key}': c,
    };
    return m.isEmpty ? null : m;
  }
  return v;
}

/// A map that may arrive as a list (the database turns {"0":…, "1":…} into
/// a list) — read either way.
Map<String, Object?> asMap(Object? v) {
  if (v is Map) return {for (final e in v.entries) '${e.key}': e.value};
  if (v is List) return {for (var i = 0; i < v.length; i++) if (v[i] != null) '$i': v[i]};
  return const {};
}

List<Object?> asList(Object? v) {
  if (v is List) return v;
  if (v is Map) {
    final keys = v.keys.map((k) => int.tryParse('$k')).whereType<int>().toList()..sort();
    return [for (final k in keys) v['$k'] ?? v[k]];
  }
  return const [];
}
