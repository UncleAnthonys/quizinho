import 'dart:async';
import 'dart:convert';

import '../data/models.dart';
import '../domain/player_index.dart';
import '../domain/tournament.dart';
import 'room.dart';

/// What a phone does on someone's turn.
enum TurnStage {
  /// Tap to start their turn (XI Bomb's "pass to…", so the clock starts when they're ready).
  ready,

  /// Pick a square (Tic-Tac-Toe).
  choose,

  /// Say or type an answer.
  answer,
}

/// Turn-based games (XI Bomb, Tic-Tac-Toe, Pointless, 501, Bidding War)
/// across the room's phones, from the host phone. Whoever's turn it is plays
/// it on their own phone if they've joined: a named player's turn goes to
/// their phone; a whole-team turn goes to the captain's (first name on the
/// team sheet). Nobody joined for it → it's played on the host, as before.
///
/// The screen calls [show] whenever its state changes, and [idle] between
/// turns. Answers come back through [show]'s callbacks.
class TurnBridge {
  TurnBridge(this.room, this.tournament);

  final HostRoom room;
  final Tournament tournament;

  /// The phone playing the current turn (null = played on the host).
  RoomMember? remote;

  StreamSubscription<RemoteAnswer>? _sub;
  String _key = '';

  /// A turn the host took back ("play it on this phone instead").
  String? _hereKey;
  PlayerIndex? _index;
  void Function(Player)? _onPick;
  void Function()? _onPass;
  void Function()? _onReady;
  void Function(int)? _onChoose;

  String? _lastShape;
  double? _sentLeft;
  final Stopwatch _sinceSent = Stopwatch();

  void start() => _sub ??= room.answers.listen(_onAnswer);

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// The phone for [team]'s turn: [name]'s if given, else the captain's.
  RoomMember? phoneFor(int team, {String? name}) {
    final players = tournament.config.teams[team].players;
    final who = name ?? (players.isEmpty ? null : players.first);
    return who == null ? null : room.memberFor(team, who);
  }

  /// Puts [team]'s turn on the phones. Returns the phone playing it, or null
  /// when it's played on the host (nobody joined for it).
  RoomMember? show({
    required String key,
    required int team,
    String? name,
    required TurnStage stage,
    required String title,
    required String headline,
    String sub = '',
    List<String> lines = const [],
    Map<String, Object?>? grid,
    double? left,
    double? total,
    PlayerIndex? index,
    Set<String> answers = const {},
    bool clubs = false,
    bool rapid = false,
    bool showFlags = true,
    bool showPositions = true,
    String hint = 'Say or type a name…',
    void Function(Player)? onPick,
    void Function()? onPass,
    void Function()? onReady,
    void Function(int square)? onChoose,
  }) {
    final m = key == _hereKey ? null : phoneFor(team, name: name);
    remote = m;
    _key = key;
    _index = index;
    _onPick = onPick;
    _onPass = onPass;
    _onReady = onReady;
    _onChoose = onChoose;
    final who = name ?? tournament.teamName(team);
    final view = <String, Object?>{
      'kind': 'turn',
      'q': key,
      'title': title,
      'headline': headline,
      'sub': sub,
      if (lines.isNotEmpty) 'lines': lines.take(40).toList(),
      if (grid != null) 'grid': grid,
      'stage': stage.name,
      'round': '${tournament.roundNumber.clamp(1, tournament.totalRounds)}/${tournament.totalRounds}',
      'teams': teamsView(tournament),
      'who': {'team': team, 'name': who, if (m != null) 'device': m.device},
      if (m != null && stage == TurnStage.answer) ...{
        'answers': answers.take(400).toList(),
        'clubs': clubs,
        'rapid': rapid,
        'flags': showFlags,
        'positions': showPositions,
        'hint': hint,
      },
    };
    _publish(view, left: left, total: total);
    return m;
  }

  /// The host takes this turn back (that phone's gone quiet).
  void playHere() {
    _hereKey = _key;
    remote = null;
  }

  /// Between turns: "eyes on the main screen".
  void idle(String what) {
    remote = null;
    _key = '';
    _lastShape = null;
    _sentLeft = null;
    room.showMainScreen(tournament, what);
  }

  void _publish(Map<String, Object?> v, {double? left, double? total}) {
    // The clock goes with each change, then every few seconds or when it's
    // drifted from the phones' countdown — like the buzzer games.
    final shape = jsonEncode(v);
    final ticking = left != null && total != null;
    final sent = _sentLeft;
    final drifted = ticking &&
        (sent == null ||
            _sinceSent.elapsed >= const Duration(seconds: 3) ||
            (sent - _sinceSent.elapsedMilliseconds / 1000 - left).abs() > 0.5);
    if (shape == _lastShape && !drifted) return;
    _lastShape = shape;
    if (ticking) {
      v['left'] = (left * 10).round() / 10;
      v['total'] = (total * 10).round() / 10;
      _sentLeft = left;
      _sinceSent
        ..reset()
        ..start();
    } else {
      _sentLeft = null;
    }
    room.show(v);
  }

  void _onAnswer(RemoteAnswer a) {
    final r = remote;
    if (r == null || a.device != r.device || a.question != _key || _key.isEmpty) return;
    if (a.pass) {
      _onPass?.call();
      return;
    }
    final id = a.playerId;
    if (id == null) return;
    if (id == 'ready') {
      _onReady?.call();
    } else if (id.startsWith('choice:')) {
      final i = int.tryParse(id.substring(7));
      if (i != null) _onChoose?.call(i);
    } else if (_index?.byId(id) case final p?) {
      _onPick?.call(p);
    }
  }
}
