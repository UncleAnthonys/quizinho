import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/tournament.dart';
import 'room_link.dart';

/// Phones in a room. The host phone runs the game and judges everything; the
/// others show the question and send buzzes and answers.
///
/// rooms/CODE/
///   host       {teams: [{name, color, players}], at}
///   members/D  {name, team, at}     a phone (device D) that picked a name
///   view       what's on screen now, drawn by every phone
///   buzzes/K   {d, k, at}           device d buzzed on question k
///   answers/K  {d, k, p | pass}     device d answered player p (or passed)

/// No I, L, O or 0/1 — easy to read off a screen and type.
const _codeLetters = 'ABCDEFGHJKMNPQRSTUVWXYZ';

String newRoomCode([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(4, (_) => _codeLetters[r.nextInt(_codeLetters.length)]).join();
}

String normaliseRoomCode(String s) => s.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');

class RoomMember {
  const RoomMember({required this.device, required this.name, required this.team});
  final String device;
  final String name;
  final int team;
}

class RemoteBuzz {
  const RemoteBuzz({required this.device, required this.question, required this.at});
  final String device;
  final String question;

  /// The database's clock, so phones are timed fairly against each other.
  final int at;
}

class RemoteAnswer {
  const RemoteAnswer({required this.device, required this.question, this.playerId, this.pass = false});
  final String device;
  final String question;
  final String? playerId;
  final bool pass;
}

Map<String, RoomMember> _members(Object? v) => {
      for (final e in asMap(v).entries)
        if (asMap(e.value) case final m when m['name'] is String && m['team'] is num)
          e.key: RoomMember(device: e.key, name: m['name']! as String, team: (m['team']! as num).toInt()),
    };

/// The host phone's side of a room.
class HostRoom extends ChangeNotifier {
  HostRoom._(this.link, this.code);

  final RoomLink link;
  final String code;
  String get _root => 'rooms/$code';

  /// Phones that have picked a name, by device.
  Map<String, RoomMember> members = const {};

  final _buzzes = StreamController<RemoteBuzz>.broadcast();
  final _answers = StreamController<RemoteAnswer>.broadcast();
  final Set<String> _seenBuzzes = {};
  final Set<String> _seenAnswers = {};
  final List<StreamSubscription<Object?>> _subs = [];
  String? _lastView;

  Stream<RemoteBuzz> get buzzes => _buzzes.stream;
  Stream<RemoteAnswer> get answers => _answers.stream;

  static Future<HostRoom> open(RoomLink link, List<TeamSetup> teams, {Random? random}) async {
    final room = HostRoom._(link, newRoomCode(random));
    await room.setTeams(teams);
    await link.put('${room._root}/view', {'kind': 'lobby'});
    room._listen();
    return room;
  }

  /// Picks a room back up after the app was closed: same code, so phones
  /// that joined carry on without scanning again.
  static HostRoom reattach(RoomLink link, String code) => HostRoom._(link, code).._listen();

  /// Names to pick from on the phones (call again if the team sheet changes).
  Future<void> setTeams(List<TeamSetup> teams) => link.put('$_root/host', {
        'teams': [
          for (final t in teams) {'name': t.name, 'color': t.colorIndex, 'players': t.players},
        ],
        'at': serverTime,
      });

  void _listen() {
    _subs.add(link.watch('$_root/members').listen((v) {
      members = _members(v);
      notifyListeners();
    }));
    _subs.add(link.watch('$_root/buzzes').listen((v) {
      for (final e in asMap(v).entries) {
        if (!_seenBuzzes.add(e.key)) continue;
        final m = asMap(e.value);
        if (m['d'] is String && m['k'] is String) {
          _buzzes.add(RemoteBuzz(device: m['d']! as String, question: m['k']! as String, at: (m['at'] as num?)?.toInt() ?? 0));
        }
      }
    }));
    _subs.add(link.watch('$_root/answers').listen((v) {
      for (final e in asMap(v).entries) {
        if (!_seenAnswers.add(e.key)) continue;
        final m = asMap(e.value);
        if (m['d'] is String && m['k'] is String) {
          _answers.add(RemoteAnswer(
              device: m['d']! as String, question: m['k']! as String, playerId: m['p'] as String?, pass: m['pass'] == true));
        }
      }
    }));
  }

  /// The phone [name] in [team] is using, if they've joined.
  RoomMember? memberFor(int team, String name) {
    for (final m in members.values) {
      if (m.team == team && m.name == name) return m;
    }
    return null;
  }

  /// Puts [view] on every phone (skipped when nothing changed).
  Future<void> show(Map<String, Object?> view) async {
    final json = jsonEncode(view);
    if (json == _lastView) return;
    _lastView = json;
    try {
      await link.put('$_root/view', view);
    } catch (e) {
      debugPrint('Room view not sent: $e');
    }
  }

  /// "Eyes on the main screen" for parts of the game played on the host phone.
  Future<void> showMainScreen(Tournament t, String what) => show({
        'kind': 'main',
        'what': what,
        'teams': teamsView(t),
      });

  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      await link.put('$_root/view', {'kind': 'closed'});
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _buzzes.close();
    _answers.close();
    super.dispose();
  }
}

/// Team names, colours and scores for a view.
List<Map<String, Object?>> teamsView(Tournament t) => [
      for (var i = 0; i < t.teamCount; i++)
        {'name': t.teamName(i), 'color': t.config.teams[i].colorIndex, 'score': t.scores[i]},
    ];

/// A joining phone's side of a room.
class GuestRoom extends ChangeNotifier {
  GuestRoom(this.link, String code, this.device) : code = normaliseRoomCode(code);

  final RoomLink link;
  final String code;
  final String device;
  String get _root => 'rooms/$code';

  /// Team sheet from the host (null until loaded).
  List<TeamSetup>? teams;

  /// No room with this code.
  bool missing = false;
  Map<String, RoomMember> members = const {};

  /// What the host is showing now.
  Map<String, Object?> view = const {};
  final List<StreamSubscription<Object?>> _subs = [];

  RoomMember? get me => members[device];

  void start() {
    _subs.add(link.watch('$_root/host').listen((v) {
      final m = asMap(v);
      if (m.isEmpty) {
        missing = true;
      } else {
        missing = false;
        teams = [
          for (final t in asList(m['teams']))
            if (asMap(t) case final tm)
              TeamSetup(
                name: '${tm['name'] ?? ''}',
                colorIndex: (tm['color'] as num?)?.toInt() ?? 0,
                players: [for (final p in asList(tm['players'])) '$p'],
              ),
        ];
      }
      notifyListeners();
    }));
    _subs.add(link.watch('$_root/members').listen((v) {
      members = _members(v);
      notifyListeners();
    }));
    _subs.add(link.watch('$_root/view').listen((v) {
      view = asMap(v);
      notifyListeners();
    }));
  }

  /// Taken by another phone.
  bool taken(int team, String name) =>
      members.values.any((m) => m.team == team && m.name == name && m.device != device);

  Future<void> claim(int team, String name) =>
      link.put('$_root/members/$device', {'name': name, 'team': team, 'at': serverTime});

  Future<void> leave() => link.remove('$_root/members/$device');

  Future<void> buzz(String question) => link.push('$_root/buzzes', {'d': device, 'k': question, 'at': serverTime});

  Future<void> answer(String question, String playerId) =>
      link.push('$_root/answers', {'d': device, 'k': question, 'p': playerId});

  Future<void> pass(String question) => link.push('$_root/answers', {'d': device, 'k': question, 'pass': true});

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
