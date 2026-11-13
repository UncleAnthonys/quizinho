import 'package:flutter/material.dart';

import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../../multiplayer/turn_bridge.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/player_picker.dart';
import '../buzz_game_view.dart' show LoadingRound, OutOfChallenges;
import '../game_screen_support.dart';
import 'top10_controller.dart';

/// Top 10's gold (as GameModeStyle.color in match_flow.dart).
const _accent = Color(0xFFFFD34D);

/// Top 10: a record-book list, ten slots. Solo: name as many as you can.
/// Teams: take turns naming one, on this phone or the named player's own.
class Top10Screen extends StatefulWidget {
  const Top10Screen({super.key, required this.round});
  final RoundContext round;

  @override
  State<Top10Screen> createState() => _Top10ScreenState();
}

class _Top10ScreenState extends State<Top10Screen> with TickerProviderStateMixin<Top10Screen>, GameScreenSupport<Top10Screen> {
  static const _mode = GameModeId.top10;
  Top10Controller? _c;
  bool _empty = false;
  int _pickerKey = 0;
  int _turnFor = -1;
  int _lastSecond = -1;
  String? _turnPlayer;

  /// Each player's turn on their own phone, when they've joined.
  TurnBridge? _phones;

  Tournament get _t => widget.round.tournament;
  bool get _solo => _t.teamCount == 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final bank = await services.top10;
    if (!mounted) return;
    final list = bank.pick(difficulty: _t.config.difficulty, history: services.settings.history);
    if (list == null) {
      setState(() => _empty = true);
      return;
    }
    final c = Top10Controller(
      list: list,
      teamCount: _t.teamCount,
      startTeam: _solo ? 0 : _t.standings.last,
      answerSeconds: _t.config.answerSeconds < 20 ? 20 : _t.config.answerSeconds,
    );
    c.addListener(() => _onChange(c));
    if (roomFor(_t) case final room?) _phones = TurnBridge(room, _t)..start();
    setState(() => _c = c);
    _onChange(c);
    startClock(c.advance);
  }

  void _onChange(Top10Controller c) {
    if (c.turnSerial != _turnFor) {
      _turnFor = c.turnSerial;
      _turnPlayer = phoneTurnPlayer(_t, c.currentTeam);
    }
    _syncPhones(c);
    handleEvent(c.eventSerial, c.lastEvent, miss: c.misses.isEmpty ? null : c.misses.last);
    if (c.clockRunning) {
      final sec = c.secondsLeft.ceil();
      if (sec != _lastSecond) {
        _lastSecond = sec;
        if (sec <= 5 && sec > 0) services.sound.play(Sfx.tickFast);
      }
    } else {
      _lastSecond = -1;
    }
    if (mounted) setState(() {});
  }

  /// Under each team's score: answers found and lives ("2 ✓  ♥♥").
  String _scoreLine(Top10Controller c, int team) =>
      '${c.foundByTeam(team)} ✓  ${c.livesLeft[team] > 0 ? '♥' * c.livesLeft[team] : 'OUT'}';

  Map<String, Object?> _view(Top10Controller c) => Top10Layout.snapshot(c, _t);

  void _syncPhones(Top10Controller c) {
    final p = _phones;
    if (p == null) return;
    final extra = [for (var i = 0; i < _t.teamCount; i++) _scoreLine(c, i)];
    if (c.finished) {
      p.idle('Top 10', game: 'top10', board: _view(c), extra: extra);
      return;
    }
    p.show(
      key: '${_t.rounds.length}-top10-${c.turnSerial}',
      team: c.currentTeam,
      name: _turnPlayer,
      stage: TurnStage.answer,
      title: 'TOP 10',
      headline: c.list.prompt,
      game: 'top10',
      board: _view(c),
      extra: extra,
      left: c.secondsLeft,
      total: c.answerSeconds.toDouble(),
      index: services.repo.players,
      answers: {
        for (final (i, e) in c.list.entries.indexed)
          if (!c.found.containsKey(i)) ...[for (final a in e.all) a.$1],
      },
      hint: 'Name one of the ten…',
      onPick: (pl) => _submit(c, pl),
      onPass: c.pass,
    );
  }

  void _submit(Top10Controller c, Player player) {
    final r = c.submit(player);
    if (r == Top10Answer.alreadyFound) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${player.name} is already up there'), duration: const Duration(milliseconds: 1400)));
    }
    setState(() => _pickerKey++);
  }

  @override
  void dispose() {
    disposeGameSupport();
    _phones?.dispose();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_empty) {
      return OutOfChallenges(
          mode: _mode,
          onContinue: () => widget.round.onComplete(
              RoundResult(mode: _mode, points: {for (var t = 0; t < _t.teamCount; t++) t: 0}, solo: _solo ? 0 : null)));
    }
    final c = _c;
    if (c == null) return const LoadingRound();
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: ValueListenableBuilder<bool>(
            valueListenable: answerTyping,
            builder: (context, typing, _) => Column(children: [
              if (_solo)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(children: [
                    const ExitMatchButton(),
                    const Spacer(),
                    for (var i = 0; i < c.lives; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(i < c.livesNow ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: i < c.livesNow ? Palette.danger : Palette.muted, size: 24),
                      ),
                  ]),
                )
              else if (!typing)
                Scoreboard(
                  tournament: _t,
                  highlightTeam: c.finished ? null : c.currentTeam,
                  extra: (i) => _scoreLine(c, i),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: Top10Layout(data: _view(c), typing: typing, bottom: _bottom(c, typing)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _bottom(Top10Controller c, bool typing) {
    if (c.finished) {
      if (_solo) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SoloScore(score: c.score, color: _accent),
          const SizedBox(height: 8),
          BigButton(label: 'Finish', icon: Icons.flag, onPressed: () => widget.round.onComplete(c.result())),
        ]);
      }
      // The standings are part of the layout (joined phones show them too).
      return BigButton(label: 'Finish round', icon: Icons.flag, onPressed: () => widget.round.onComplete(c.result()));
    }
    if (_phones?.remote case final m?) {
      return OnTheirPhone(name: m.name);
    }
    final colour = _solo ? null : _t.config.teams[c.currentTeam].colorIndex;
    final lastLife = !_solo && c.livesLeft[c.currentTeam] == 1;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (!_solo && !typing) ...[
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TeamChip(name: _turnPlayer ?? _t.teamName(c.currentTeam), colorIndex: colour!, size: 18),
          const SizedBox(width: 10),
          Text(lastLife ? 'LAST LIFE' : 'YOUR GO', style: AppText.headline(20, color: lastLife ? Palette.gold : Palette.text)),
        ]),
        const SizedBox(height: 6),
      ],
      if (c.clockRunning) ...[
        TimerBar(fraction: c.fractionLeft, seconds: c.secondsLeft),
        const SizedBox(height: 6),
      ],
      PlayerPicker(
        key: ValueKey('top10-$_pickerKey-${c.turnSerial}'),
        index: services.repo.players,
        voice: services.voice,
        accent: colour == null ? _accent : Palette.team(colour),
        hint: 'Name one of the ten…',
        onPick: (p) => _submit(c, p),
        isAnswer: (p) => c.list.indexOf(p.id) != null,
        onPass: _solo ? null : c.pass,
      ),
      if (!typing && _solo)
        TextButton(
          onPressed: c.giveUp,
          child: Text("I'M OUT - SHOW THE REST", style: AppText.label(13)),
        ),
    ]);
  }
}

/// The list and its heading, drawn from [snapshot] so joined phones draw
/// exactly what the main phone does, with [bottom] (answer box, buttons).
class Top10Layout extends StatelessWidget {
  const Top10Layout({super.key, required this.data, required this.bottom, this.typing = false});
  final Map<String, Object?> data;
  final Widget bottom;

  /// Keyboard up: a smaller heading so the list stays in view.
  final bool typing;

  /// No nulls in lists (the rooms database drops them): '' and -1 = none.
  static Map<String, Object?> snapshot(Top10Controller c, Tournament t) => {
        'prompt': c.list.prompt,
        'asof': c.list.asOf,
        'finished': c.finished,
        if (t.teamCount == 1) 'solo': true,
        'teams': [for (var i = 0; i < t.teamCount; i++) t.teamName(i)],
        'found': [for (var i = 0; i < t.teamCount; i++) c.foundByTeam(i)],
        'fresh': c.lastFound ?? -1,
        'colours': [for (final team in t.config.teams) team.colorIndex],
        'rows': [
          for (final (i, e) in c.list.entries.indexed)
            {
              'rank': e.rank,
              'name': c.found.containsKey(i)
                  ? c.found[i]!
                  : (c.finished ? [for (final a in e.all) a.$2].join(' / ') : ''),
              'figure': c.found.containsKey(i) || c.finished ? e.figure : '',
              'team': c.foundBy[i] ?? -1,
            },
        ],
      };

  @override
  Widget build(BuildContext context) {
    final rows = [for (final r in (data['rows'] as List?) ?? const []) Map<String, Object?>.from(r as Map)];
    final colours = [for (final c in (data['colours'] as List?) ?? const []) (c as num).toInt()];
    final solo = data['solo'] == true;
    final fresh = (data['fresh'] as num?)?.toInt() ?? -1;
    final asOf = '${data['asof'] ?? ''}';
    return Column(children: [
      Text('TOP 10', style: AppText.label(15, color: _accent)),
      const SizedBox(height: 2),
      Text('${data['prompt'] ?? ''}'.toUpperCase(),
          textAlign: TextAlign.center, style: AppText.headline(typing ? 20 : 26).copyWith(height: 1.05)),
      if (asOf.isNotEmpty && !typing) Text('As of $asOf', style: AppText.label(12)),
      const SizedBox(height: 8),
      Expanded(
        // All ten in view: rows shrink to fit the space (down to a floor,
        // then it scrolls).
        child: LayoutBuilder(builder: (context, box) {
          const gap = 4.0;
          final n = rows.isEmpty ? 1 : rows.length;
          final fit = (box.maxHeight - gap * (n - 1)) / n;
          final rowH = fit.clamp(_minRow, _maxRow).toDouble();
          final font = (rowH * 0.5).clamp(14.0, 20.0).toDouble();
          return ListView.separated(
          physics: fit >= _minRow ? const NeverScrollableScrollPhysics() : null,
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: gap),
          itemBuilder: (context, i) {
            final r = rows[i];
            final team = (r['team'] as num?)?.toInt() ?? -1;
            final got = team >= 0;
            final colour = !got ? null : (solo || team >= colours.length ? _accent : Palette.team(colours[team]));
            final name = '${r['name'] ?? ''}';
            final figure = '${r['figure'] ?? ''}';
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: rowH,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colour?.withValues(alpha: 0.22) ?? Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: i == fresh ? (colour ?? _accent) : Palette.line, width: i == fresh ? 2 : 1),
              ),
              child: Row(children: [
                SizedBox(width: 30, child: Text('${r['rank']}', style: AppText.headline(font, color: colour ?? Palette.muted))),
                Expanded(
                  child: Text(name.toUpperCase(),
                      overflow: TextOverflow.ellipsis, style: AppText.headline(font, color: got ? Palette.text : Palette.muted)),
                ),
                if (figure.isNotEmpty) Text(figure, style: AppText.label(font < 18 ? 12 : 13, color: got ? Palette.text : Palette.muted)),
              ]),
            );
          },
        );
        }),
      ),
      const SizedBox(height: 8),
      if (data['finished'] == true && !solo) ...[
        _Standings(data: data, colours: colours),
        const SizedBox(height: 8),
      ],
      bottom,
    ]);
  }

  static const _minRow = 30.0;
  static const _maxRow = 44.0;
}

/// Who found how many, most first (main phone and joined phones alike).
class _Standings extends StatelessWidget {
  const _Standings({required this.data, required this.colours});
  final Map<String, Object?> data;
  final List<int> colours;

  @override
  Widget build(BuildContext context) {
    final names = [for (final n in (data['teams'] as List?) ?? const []) '$n'];
    final found = [for (final f in (data['found'] as List?) ?? const []) (f as num).toInt()];
    if (names.length != found.length || names.isEmpty) return const SizedBox.shrink();
    final order = List.generate(names.length, (i) => i)..sort((a, b) => found[b].compareTo(found[a]));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final t in order)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            TeamChip(name: names[t], colorIndex: t < colours.length ? colours[t] : 0, size: 16),
            const Spacer(),
            Text('${found[t]} found', style: AppText.headline(20)),
          ]),
        ),
    ]);
  }
}
