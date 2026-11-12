import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../core/app_services.dart';
import '../core/sound_service.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../domain/game_mode.dart';
import '../domain/tournament.dart';
import '../games/buzz_game_view.dart';
import '../games/buzz_race_controller.dart';
import '../games/career_path/career_path_controller.dart';
import '../games/tic_tac_toe/tic_tac_toe_screen.dart';
import '../ui/match_flow.dart';
import '../ui/screens/round_summary_screen.dart';
import '../ui/widgets/buzzer_pad.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/player_picker.dart';

/// Demo video mode (web only): `?demo=1` plays one round by itself, with real
/// taps and typing, framed 9:16 with captions for TikTok / Reels / Shorts.
/// `seed=20261112` picks the teams, game and answers; `game=careerPath` forces
/// the game; `slow=6` runs everything 6x slower so a machine without a
/// graphics card can draw every frame (the recorder speeds the video back up).
/// Sounds are logged with their time rather than recorded. Recorded daily by .github/workflows/demo-video.yml.
final bool demoMode = kIsWeb && Uri.base.queryParameters.containsKey('demo');

/// Starts the scripted match once the first frame is up.
class DemoStart extends StatefulWidget {
  const DemoStart({super.key});

  @override
  State<DemoStart> createState() => _DemoStartState();
}

class _DemoStartState extends State<DemoStart> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) DemoPilot.instance.start(context);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: PitchBackground(child: SizedBox.expand()));
}

/// One line the recorder reads from the browser console.
void _log(String event, [Map<String, Object?> data = const {}]) {
  // ignore: avoid_print
  print('QDEMO ${jsonEncode({'e': event, ...data})}');
}

/// Drives the app like a person would: taps (real pointer events, with a
/// visible touch) and typing into the answer box.
class DemoPilot {
  DemoPilot._();
  static final instance = DemoPilot._();

  /// Big line at the top of the video (the hook) and the line under it.
  final headline = ValueNotifier<String>('FOOTBALL QUIZ NIGHT\nONE PHONE, TWO TEAMS');
  final caption = ValueNotifier<String>('');

  /// Touches being drawn, in global coordinates.
  final touches = ValueNotifier<List<(Offset, int)>>(const []);

  late final Random _rnd;
  late final int _seed;
  AppServices? _services;
  bool _started = false;
  bool _done = false;
  bool _busy = false;
  Map<String, Object?> Function() _fps = () => const {};

  static const _teamNames = [
    ('THE GAFFERS', 'SUNDAY LEAGUE'),
    ('FIVE-A-SIDE FC', 'THE PUNDITS'),
    ('DINAMO SOFA', 'REAL MADRINKS'),
    ('INTER BRANDIGO', 'PARTIZAN TIME'),
    ('ATLETICO LADS', 'THE BENCH'),
    ('NEVER MIND THE BALLACKS', 'GIRLS ON TOUR'),
  ];

  static const _games = [GameModeId.careerPath, GameModeId.clubConnections, GameModeId.ticTacToe];

  void start(BuildContext context) {
    if (_started) return;
    _started = true;
    final q = Uri.base.queryParameters;
    final today = DateTime.now();
    _seed = int.tryParse(q['seed'] ?? '') ?? (today.year * 10000 + today.month * 100 + today.day);
    _rnd = Random(_seed);
    _slow = (double.tryParse(q['slow'] ?? '') ?? 1).clamp(1, 20).toDouble();
    timeDilation = _slow;
    _clock.start();
    SoundService.onPlay = (asset, volume) => _log('sfx', {'a': asset, 'v': volume, 't': _ms});
    _services = AppScope.read(context);
    final game = GameModeId.fromName(q['game'] ?? '') ?? _games[_seed % _games.length];
    final names = _teamNames[_rnd.nextInt(_teamNames.length)];
    final config = TournamentConfig(
      teams: [
        TeamSetup(name: names.$1, colorIndex: 0),
        TeamSetup(name: names.$2, colorIndex: 1),
      ],
      difficulty: Difficulty.easy,
      // One career per video (it takes a while to unfold); two club pairs.
      questionsPerRound: game == GameModeId.careerPath ? 1 : 2,
      careerRevealSeconds: 4,
      answerSeconds: 12,
    );
    final t = Tournament(config, random: Random(_seed));
    _log('ready', {'seed': _seed, 'game': game.name, 'teams': [names.$1, names.$2], 'slow': _slow});
    headline.value = _hook(game);
    caption.value = '';
    unawaited(_run(context, t, game));
  }

  Future<void> _run(BuildContext context, Tournament t, GameModeId game) async {
    // Gives the recorder time to start before anything moves.
    await _wait(3000);
    if (!context.mounted) return;
    // Straight into the question: no free kick, no rules screen. The video
    // starts the moment the question is up.
    MatchFlow.toGame(context, t, game, 1);
    while (_live<BuzzGameView>() == null) {
      await _wait(20);
    }
    _log('go', {'t': _ms});
    final began = _now();
    var frames = 0, slow = 0;
    SchedulerBinding.instance.addTimingsCallback((ts) {
      frames += ts.length;
      slow += ts.where((f) => f.totalSpan.inMilliseconds > 40).length;
    });
    _fps = () => {
          'fps': (frames / max(1, _now().difference(began).inMilliseconds) * 1000).toStringAsFixed(1),
          'slowFrames': slow,
          'frames': frames,
        };
    final end = _now().add(const Duration(minutes: 3));
    while (!_done && _now().isBefore(end)) {
      await _wait(120);
      if (_busy) continue;
      _busy = true;
      try {
        await _step();
      } catch (e, st) {
        _log('error', {'error': '$e', 'stack': '$st'.split('\n').take(6).join(' | ')});
      } finally {
        _busy = false;
      }
    }
    if (!_done) _log('end', {'timeout': true, ..._fps()});
  }

  // ---- what's on screen ----------------------------------------------------

  /// When each button (by label) first became tappable, and which were tapped.
  final Map<String, DateTime> _seen = {};
  final Set<Element> _tapped = {};

  Future<void> _step() async {
    final summary = _live<RoundSummaryScreen>();
    if (summary != null) return _finish(summary);

    final view = _live<BuzzGameView>();
    if (view != null && await _playBuzz(view.widget as BuzzGameView)) return;

    final ttt = _live<TicTacToeScreen>();
    if (ttt != null && !_tttPlayed) {
      _tttPlayed = true;
      await _playTtt(ttt.widget as TicTacToeScreen);
      return;
    }

    // The answer's up: a moment to take it in, then Next / Finish.
    const dwell = 2200;
    for (final b in _all<BigButton>()) {
      final w = b.widget as BigButton;
      if (w.onPressed == null || _tapped.contains(b) || !_hittable(b)) continue;
      final first = _seen.putIfAbsent(w.label, _now);
      if (_now().difference(first).inMilliseconds < dwell) return;
      _tapped.add(b);
      _seen.clear();
      await _tap(b);
      return;
    }
  }

  String _hook(GameModeId mode) => switch (mode) {
        GameModeId.careerPath => 'GUESS THE PLAYER\nFROM HIS CLUBS',
        GameModeId.clubConnections => 'NAME A PLAYER WHO\nPLAYED FOR BOTH',
        GameModeId.ticTacToe => 'FOOTBALL\nNOUGHTS & CROSSES',
        _ => mode.title.toUpperCase(),
      };

  // ---- a buzzer question ---------------------------------------------------

  String? _qKey;
  late DateTime _qStart;
  DateTime? _wrongAt;
  bool _wrongFirst = false;
  int _firstTeam = 0;
  int _buzzAfterClubs = 2;
  int _buzzAfterMs = 5000;
  bool _answered = false;
  BuzzPhase? _lastPhase;

  /// Plays the open and answering phases. False = nothing to do here (the
  /// answer is showing; the Next button is tapped like any other).
  Future<bool> _playBuzz(BuzzGameView view) async {
    final c = view.controller;
    final t = view.round.tournament;
    final key = '${identityHashCode(c)}-${c.questionIndex}';
    if (key != _qKey) {
      _qKey = key;
      _qStart = _now();
      _wrongAt = null;
      _answered = false;
      // Usually the first team gets it wrong and the other steals it — the
      // best bit of the game. Two questions: one of each.
      _wrongFirst = c.questionIndex == 0 ? _rnd.nextInt(10) < 7 : !_wrongFirstLast;
      _wrongFirstLast = _wrongFirst;
      _firstTeam = _rnd.nextInt(t.teamCount);
      // Buzz late enough that viewers have a fair go: Career Path waits for
      // most of the clubs (the famous ones come last); a wrong guess comes
      // around halfway and the steal a club or two later.
      if (c is CareerPathController) {
        final n = c.clueCount;
        int at(double f, int lo) => min(n, max(lo, (n * f).round()));
        _buzzAfterClubs = _wrongFirst ? min(at(0.5, 3), max(1, n - 1)) : at(0.75, 3);
        _stealAfterClubs = max(min(n, _buzzAfterClubs + 1), at(0.8, 3));
      }
      _buzzAfterMs = 8000 + _rnd.nextInt(2500);
      headline.value = _hook(c.mode);
      _sayLater(c.questionIndex > 0
          ? 'Question two.'
          : c is CareerPathController
              ? 'Guess the player from his clubs. First to buzz gets it.'
              : 'Name a player who played for both clubs. First to buzz gets it.');
    }
    if (c.phase != _lastPhase) _onPhase(c, t);
    _lastPhase = c.phase;

    switch (c.phase) {
      case BuzzPhase.open:
        final now = _now();
        final int team;
        if (c.lockedOut.isEmpty) {
          final ready = c is CareerPathController
              ? _clubShown(c, _buzzAfterClubs)
              : now.difference(_qStart).inMilliseconds >= _buzzAfterMs;
          if (!ready) return true;
          team = _firstTeam;
        } else {
          final ready = c is CareerPathController
              ? _clubShown(c, _stealAfterClubs) && now.difference(_wrongAt ?? now).inMilliseconds >= 1500
              : now.difference(_wrongAt ?? now).inMilliseconds >= 3000;
          if (!ready) return true;
          final free = [for (var i = 0; i < t.teamCount; i++) if (!c.lockedOut.contains(i)) i];
          if (free.isEmpty) return true;
          team = free.first;
        }
        final buzzer = _all<TeamBuzzer>()
            .where((e) => (e.widget as TeamBuzzer).name == t.teamName(team) && (e.widget as TeamBuzzer).enabled)
            .where(_hittable)
            .firstOrNull;
        if (buzzer != null) await _tap(buzzer);
        return true;
      case BuzzPhase.answering:
        if (_answered) return true;
        _answered = true;
        await _wait(500);
        final wrong = _wrongFirst && c.lockedOut.isEmpty && t.teamCount > 1;
        final player = wrong ? _wrongAnswer(c) : _rightAnswer(c);
        if (player == null) {
          c.giveUp();
          return true;
        }
        await _type(player.name);
        return true;
      case BuzzPhase.resolved:
      case BuzzPhase.finished:
        return false;
    }
  }

  bool _wrongFirstLast = false;
  int _stealAfterClubs = 3;

  /// Club [n] has been on screen for a couple of seconds (or a later one is up).
  static bool _clubShown(CareerPathController c, int n) =>
      c.revealed > n || (c.revealed == n && c.phaseSeconds - c.secondsLeft >= 2.0);

  void _onPhase(BuzzRaceController<Object?> c, Tournament t) {
    switch (c.phase) {
      case BuzzPhase.answering:
        _answered = false;
        _sayLater('${_n(t.teamName(c.answeringTeam!))} buzz!');
        if (c is CareerPathController) _log('buzz', {'club': c.revealed, 'of': c.clueCount});
      case BuzzPhase.open:
        if (c.lockedOut.isNotEmpty) {
          _wrongAt = _now();
          final other = [for (var i = 0; i < t.teamCount; i++) if (!c.lockedOut.contains(i)) t.teamName(i)];
          final miss = c.lastMiss;
          _sayLater('${miss == null || miss == 'Time ran out' ? 'Time\'s up' : '$miss? Wrong'}!'
              '${other.isEmpty ? '' : ' ${_n(other.first)} can steal it.'}');
        }
      case BuzzPhase.resolved:
        final o = c.outcome;
        final answer = _rightAnswer(c);
        _sayLater(o != null && o.scored
            ? 'It\'s ${answer?.name ?? o.player?.name}! Did you get it?'
            : 'Nobody got it. It was ${answer?.name}.');
        _log('question', {
          'mode': c.mode.name,
          'n': c.questionIndex + 1,
          'answer': answer?.name,
          'scored': o?.scored ?? false,
          'steal': c.lockedOut.isNotEmpty && (o?.scored ?? false),
        });
      case BuzzPhase.finished:
        break;
    }
  }

  Player? _rightAnswer(BuzzRaceController<Object?> c) => _mostFamous(c.isRightAnswer);
  Player? _wrongAnswer(BuzzRaceController<Object?> c) => _famousMiss(c.isRightAnswer);

  /// The best-known player [ok] accepts (viewers should know the answer).
  Player? _mostFamous(bool Function(Player) ok) {
    Player? best;
    for (final p in _services!.repo.players.all) {
      if (ok(p) && (best == null || p.fame > best.fame)) best = p;
    }
    return best;
  }

  /// A believable miss: someone famous who isn't an answer.
  Player? _famousMiss(bool Function(Player) answer) {
    final famous = _services!.repo.players.all.where((p) => p.fame >= 4 && !p.women && !answer(p)).toList();
    if (famous.isEmpty) return null;
    return famous[_rnd.nextInt(famous.length)];
  }

  // ---- Noughts & Crosses -----------------------------------------------------

  bool _tttPlayed = false;

  /// A game that shows everything off: centre, corners, a threat and a block,
  /// a wrong answer, then a steal of the centre that sets up three in a row.
  /// (square, wrong answer, steal); squares are 0-8, left to right.
  static const _tttPlan = [
    (4, false, false),
    (0, false, false),
    (2, false, false),
    (6, false, false),
    (3, true, false),
    (4, false, true),
    (8, false, false),
    (3, false, false),
  ];

  Map<String, Object?>? _ttt() => (_all<TttLayout>().firstOrNull?.widget as TttLayout?)?.data;

  static List<T?> _list<T>(Object? v) => v is List ? [for (final x in v) x is T ? x : null] : const [];

  /// Square [i]'s tap target on the board (squares are built 0-8 in order).
  Element? _square(int i) {
    final board = _live<TttBoard>();
    if (board == null) return null;
    final squares = _all<GestureDetector>(under: board)
        .where((e) => (e.widget as GestureDetector).child is AnimatedContainer)
        .toList();
    return i < squares.length ? squares[i] : null;
  }

  /// Off script: win if we can, block if we must, else centre, corners, edges.
  static int? _bestSquare(List<int?> owner, int team) {
    final empty = [for (var i = 0; i < 9; i++) if (owner[i] == null) i];
    if (empty.isEmpty) return null;
    int? finish(bool Function(int? o) mine) {
      for (final i in empty) {
        for (final l in _lines.where((l) => l.contains(i))) {
          if (l.where((j) => j != i).every((j) => mine(owner[j]))) return i;
        }
      }
      return null;
    }

    return finish((o) => o == team) ??
        finish((o) => o != null && o != team) ??
        [4, 0, 2, 6, 8, 1, 3, 5, 7].firstWhere(empty.contains);
  }

  static const _lines = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6], //
  ];

  Future<void> _playTtt(TicTacToeScreen screen) async {
    final t = screen.round.tournament;
    headline.value = _hook(GameModeId.ticTacToe);
    await _say('Football noughts and crosses. Name a player who played for both clubs to win the square.');
    await _spoken();
    for (var turn = 0; turn < 14; turn++) {
      var d = _ttt();
      if (d == null || d['phase'] != 'choosing') break;
      final team = (d['team'] as num?)?.toInt() ?? 0;
      final name = _n(t.teamName(team));
      final owner = [for (final o in _list<num>(d['owner'])) o?.toInt()];
      final stealable = {for (final i in _list<num>(d['stealable'])) if (i != null) i.toInt()};
      final step = turn < _tttPlan.length ? _tttPlan[turn] : null;
      final steal = step != null && step.$3 && stealable.isNotEmpty;
      final sq = steal
          ? (stealable.contains(step.$1) ? step.$1 : stealable.first)
          : (step != null && owner[step.$1] == null ? step.$1 : _bestSquare(owner, team));
      if (sq == null) break;
      final rows = _list<String>(d['rows']), cols = _list<String>(d['cols']);
      final taken = {for (final c in _list<String>(d['claimed'])) if (c != null) c};
      if (steal) {
        await _say('Steal! $name can take a square by naming a different player.');
      }
      await _say('$name go for ${rows[sq ~/ 3]} and ${cols[sq % 3]}.');
      await _wait(500);
      final target = _square(sq);
      if (target == null) break;
      await _tap(target);
      Element? picker;
      for (var i = 0; i < 40 && picker == null; i++) {
        await _wait(100);
        picker = _live<PlayerPicker>();
      }
      if (picker == null) break;
      final isAnswer = (picker.widget as PlayerPicker).isAnswer ?? ((Player _) => false);
      bool fresh(Player p) => isAnswer(p) && !taken.contains(p.name);
      final wrong = step != null && step.$2;
      final player = (wrong ? null : _mostFamous(fresh)) ?? _famousMiss(isAnswer);
      if (player == null) break;
      await _spoken();
      await _type(player.name);
      for (var i = 0; i < 60; i++) {
        await _wait(100);
        if (_ttt()?['phase'] != 'answering') break;
      }
      d = _ttt();
      if (d == null) break;
      final now = [for (final o in _list<num>(d['owner'])) o?.toInt()];
      final got = sq < now.length && now[sq] == team && _list<String>(d['claimed'])[sq] == player.name;
      _log('ttt', {'square': sq, 'player': player.name, 'claimed': got, 'steal': steal});
      if (d['phase'] == 'finished') {
        final winner = d['winner'];
        await _say(winner != null
            ? '${player.name}! Three in a row! ${_n('$winner')} win it!'
            : '${got ? '${player.name}. ' : ''}That\'s the game.');
        await _spoken();
        break;
      }
      await _say(got
          ? (steal ? '${player.name}! Stolen, and now it\'s locked.' : '${player.name}. Square taken.')
          : '${player.name}? Never played for both. Wrong!');
      await _spoken();
    }
  }

  // ---- the voiceover -------------------------------------------------------

  /// Lines are said one after another, never over each other.
  Future<void> _speech = Future<void>.value();
  int _speechEnds = 0;

  /// Says [text] (logged; the recorder voices it) and shows it as the
  /// subtitle once the line before has finished. Completes as it starts.
  Future<void> _say(String text) {
    final next = _speech.then((_) async {
      while (_ms < _speechEnds) {
        await _wait(40);
      }
      caption.value = text;
      _log('say', {'text': text, 't': _ms});
      final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      _speechEnds = _ms + 450 + words * 330;
    });
    _speech = next;
    return next;
  }

  void _sayLater(String text) => unawaited(_say(text));

  /// Waits until everything said so far has been said.
  Future<void> _spoken() async {
    await _speech;
    while (_ms < _speechEnds) {
      await _wait(40);
    }
  }

  /// A team name as it should be read out: "FIVE-A-SIDE FC" → "Five-A-Side F.C.".
  static String _n(String name) => name
      .split(' ')
      .map((w) => w == 'FC' ? 'F.C.' : w.split('-').map((p) => p.isEmpty ? p : p[0] + p.substring(1).toLowerCase()).join('-'))
      .join(' ');

  // ---- the end -------------------------------------------------------------

  DateTime? _summaryAt;

  Future<void> _finish(Element summary) async {
    if (_summaryAt == null) {
      _summaryAt = _now();
      headline.value = 'WHO\'S WINNING\nYOUR QUIZ NIGHT?';
      await _say('Who\'s winning your quiz night? Play Quizinho with your mates.');
      await _spoken();
      _summaryAt = _now();
    }
    if (_now().difference(_summaryAt!).inMilliseconds < 1200) return;
    _done = true;
    _log('end', _fps());
  }

  // ---- finding and touching widgets ----------------------------------------

  static int get _viewId => WidgetsBinding.instance.platformDispatcher.implicitView!.viewId;

  static void _walk(Element e, void Function(Element) f) {
    f(e);
    e.visitChildren((c) => _walk(c, f));
  }

  static List<Element> _all<T extends Widget>({Element? under}) {
    final root = under ?? WidgetsBinding.instance.rootElement;
    final out = <Element>[];
    if (root != null) _walk(root, (e) => e.widget is T ? out.add(e) : null);
    return out;
  }

  /// The [T] on screen right now (not one fading out underneath).
  static Element? _live<T extends Widget>() => _all<T>().where(_hittable).firstOrNull;

  static Offset? _centre(Element e) {
    final r = e.renderObject;
    if (r is! RenderBox || !r.attached || !r.hasSize) return null;
    return r.localToGlobal(r.size.center(Offset.zero));
  }

  /// A tap at the middle of [e] would reach it.
  static bool _hittable(Element e) {
    final r = e.renderObject;
    final c = _centre(e);
    if (c == null) return false;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, c, _viewId);
    return result.path.any((x) => x.target == r);
  }

  int _pointer = 9000;

  Future<void> _tap(Element e) async {
    final p = _centre(e);
    if (p == null) return;
    await _tapAt(p);
  }

  Future<void> _tapAt(Offset p) async {
    final id = ++_pointer;
    touches.value = [...touches.value, (p, id)];
    Timer(Duration(milliseconds: (650 * _slow).round()), () => touches.value = [...touches.value.where((t) => t.$2 != id)]);
    GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(pointer: id, position: p, kind: PointerDeviceKind.touch, viewId: _viewId));
    await _wait(90);
    GestureBinding.instance.handlePointerEvent(
        PointerUpEvent(pointer: id, position: p, kind: PointerDeviceKind.touch, viewId: _viewId));
  }

  /// Types [name] into the answer box a letter at a time and taps it in the
  /// suggestions as soon as it shows up (or presses GO).
  Future<void> _type(String name) async {
    final picker = _live<PlayerPicker>();
    if (picker == null) return;
    final field = _all<EditableText>(under: picker).firstOrNull;
    if (field is! StatefulElement || field.state is! EditableTextState) return;
    final state = field.state as EditableTextState;
    for (var i = 1; i <= name.length; i++) {
      final text = name.substring(0, i);
      state.userUpdateTextEditingValue(
        TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)),
        SelectionChangedCause.keyboard,
      );
      await _wait(45 + _rnd.nextInt(50));
      if (i >= 3 && i < name.length) {
        final hit = _suggestion(picker, name);
        if (hit != null) {
          await _wait(300);
          await _tap(hit);
          return;
        }
      }
    }
    await _wait(300);
    final hit = _suggestion(picker, name);
    if (hit != null) {
      await _tap(hit);
      return;
    }
    final go = _all<FilledButton>(under: picker).where(_hittable).firstOrNull;
    if (go != null) await _tap(go);
  }

  static Element? _suggestion(Element picker, String name) {
    for (final ink in _all<InkWell>(under: picker)) {
      final hasName = _all<Text>(under: ink).any((t) => (t.widget as Text).data == name);
      if (hasName && _hittable(ink)) return ink;
    }
    return null;
  }

  /// Demo time: real time divided by the slow-down.
  double _slow = 1;
  final _clock = Stopwatch();
  int get _ms => _clock.elapsedMilliseconds ~/ _slow;
  DateTime _now() => DateTime.fromMillisecondsSinceEpoch(_ms);
  Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: (ms * _slow).round()));
}

/// The 9:16 video frame: hook at the top, the app in the middle, a footer,
/// and every touch drawn as a ring.
class DemoFrame extends StatelessWidget {
  const DemoFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pilot = DemoPilot.instance;
    final size = MediaQuery.sizeOf(context);
    // Laid out on a 540×960 canvas (1080×1920 at 2x), scaled to fit the window.
    final s = min(size.width / 540, size.height / 960);
    const appW = 400.0, appH = 720.0, top = 160.0;
    final left = (540 - appW) / 2;
    return ColoredBox(
      color: const Color(0xFF031A10),
      child: Center(
        child: SizedBox(
          width: 540 * s,
          height: 960 * s,
          child: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 1.1,
                colors: [Color(0xFF0B4A2C), Color(0xFF021309)],
              ),
            ),
          ),
        ),
        // Hook (below the platforms' own top bar).
        Positioned(
          left: 16 * s,
          right: 16 * s,
          top: 48 * s,
          height: (top - 56) * s,
          child: IgnorePointer(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              ValueListenableBuilder(
                valueListenable: pilot.headline,
                builder: (context, h, _) => FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(h,
                      textAlign: TextAlign.center,
                      style: AppText.headline(40 * s, color: Palette.yellow).copyWith(height: 1.0)),
                ),
              ),
            ]),
          ),
        ),
        // The app, at a phone-like size.
        Positioned(
          left: left * s,
          top: top * s,
          width: appW * s,
          height: appH * s,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28 * s),
              border: Border.all(color: Colors.white24, width: 2 * s),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26 * s),
              child: FittedBox(
                child: SizedBox(
                  width: appW,
                  height: appH,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(size: const Size(appW, appH), padding: EdgeInsets.zero),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24 * s,
          child: IgnorePointer(
            child: Text('QUIZINHO · THE FOOTBALL PARTY GAME',
                textAlign: TextAlign.center, style: AppText.label(15 * s, color: Colors.white70)),
          ),
        ),
        // Subtitles: what's being said, big, over the lower part of the game
        // (above where the platforms put their own caption and buttons).
        Positioned(
          left: 34 * s,
          right: 34 * s,
          top: 590 * s,
          child: IgnorePointer(
            child: ValueListenableBuilder(
              valueListenable: pilot.caption,
              builder: (context, c, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, a) => ScaleTransition(
                  scale: Tween(begin: 0.85, end: 1.0).animate(a),
                  child: FadeTransition(opacity: a, child: child),
                ),
                child: c.isEmpty
                    ? const SizedBox.shrink()
                    : Container(
                        key: ValueKey(c),
                        padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 10 * s),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(16 * s),
                          border: Border.all(color: Palette.yellow, width: 2 * s),
                        ),
                        child: Text(c.toUpperCase(),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            style: AppText.headline(25 * s, color: Colors.white).copyWith(height: 1.1)),
                      ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder(
              valueListenable: pilot.touches,
              builder: (context, list, _) => Stack(children: [
                for (final (p, id) in list) _Touch(key: ValueKey(id), at: p),
              ]),
            ),
          ),
        ),
          ]),
        ),
      ),
    );
  }
}

/// A finger press: a ring that grows and fades.
class _Touch extends StatelessWidget {
  const _Touch({super.key, required this.at});
  final Offset at;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 600),
        builder: (context, v, _) {
          final r = 22 + 18 * v;
          return Positioned(
            left: at.dx - r,
            top: at.dy - r,
            width: r * 2,
            height: r * 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.35 * (1 - v)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.9 * (1 - v)), width: 3),
              ),
            ),
          );
        },
      );
}
