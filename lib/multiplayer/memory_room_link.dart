import 'dart:async';

import 'room_link.dart';

/// Rooms in memory: for tests (several "phones" share one instance).
class MemoryRoomLink extends RoomLink {
  MemoryRoomLink({int Function()? clock}) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _clock;
  Object? _tree;
  int _pushes = 0;
  final _changes = StreamController<void>.broadcast(sync: true);

  @override
  Stream<Object?> watch(String path) async* {
    final parts = pathParts(path);
    yield readAt(_tree, parts);
    await for (final _ in _changes.stream) {
      yield readAt(_tree, parts);
    }
  }

  Object? _stamp(Object? v) {
    if (v is Map && v.length == 1 && v['.sv'] == 'timestamp') return _clock();
    if (v is Map) return {for (final e in v.entries) '${e.key}': _stamp(e.value)};
    return v;
  }

  @override
  Future<void> put(String path, Object? value) async {
    _tree = writeAt(_tree, pathParts(path), _stamp(value));
    _changes.add(null);
  }

  @override
  Future<void> patch(String path, Map<String, Object?> values) async {
    _tree = writeAt(_tree, pathParts(path), _stamp(values), merge: true);
    _changes.add(null);
  }

  @override
  Future<String> push(String path, Object? value) async {
    final key = 'k${(_pushes++).toString().padLeft(8, '0')}';
    await put('$path/$key', value);
    return key;
  }
}
