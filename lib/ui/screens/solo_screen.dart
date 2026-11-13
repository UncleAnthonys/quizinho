import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/app_settings.dart';
import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../../games/game_screen_support.dart';
import '../../games/survival/survival_screen.dart';
import '../match_access.dart';
import '../match_flow.dart';
import '../widgets/common.dart';

/// Games you can play on your own, in Solo Cup order.
const soloGames = [
  GameModeId.clubConnections,
  GameModeId.careerPath,
  GameModeId.pointless,
  GameModeId.checkout501,
  GameModeId.startingXi,
  GameModeId.ticTacToe,
  GameModeId.top10,
];

/// How each game is scored when you play it alone — all out of 100.
String soloScoring(GameModeId m) => switch (m) {
      GameModeId.clubConnections => '5 pairs. Right answers score, more for speed and rare picks.',
      GameModeId.careerPath => '5 careers. The fewer clubs you need, the more you score.',
      GameModeId.pointless => '3 categories, one answer each. The more obscure, the more you score.',
      GameModeId.checkout501 => 'Check out from 501 in as few darts as you can.',
      GameModeId.startingXi => 'Name as much of the XI as you can. 3 lives.',
      GameModeId.ticTacToe => 'Fill all nine squares yourself. 3 lives. A full grid is 100.',
      GameModeId.top10 => 'Name as many of the ten as you can. 3 lives; 10 for each one.',
      _ => '',
    };

/// The rules for each game played alone (the party rules talk about teams).
List<String> soloRules(GameModeId m) => switch (m) {
      GameModeId.clubConnections => [
          'Two clubs appear. Name a player who played for both.',
          '5 pairs. Quicker answers and rarer picks score more.',
        ],
      GameModeId.careerPath => [
          'A player’s clubs appear one at a time. Name the player.',
          '5 careers. The fewer clubs you need, the more you score.',
        ],
      GameModeId.pointless => [
          'A category appears. Give one answer.',
          '3 categories. The more obscure your answer, the more you score.',
        ],
      GameModeId.checkout501 => [
          'Start on 501. Name a player: their league apps + goals for that club come off.',
          'Over 180 is a bust. Check out between 0 and −10 in as few darts as you can.',
        ],
      GameModeId.startingXi => [
          'A famous line-up with the names hidden. Name as many of the XI as you can.',
          '3 lives.',
        ],
      GameModeId.ticTacToe => [
          'Pick a square, then name a player who fits both its headers.',
          'Fill all nine. 3 lives. A full grid is 100. Each player only once.',
        ],
      GameModeId.top10 => [
          'Name as many of the ten as you can. Each one is worth 10.',
          'A wrong name costs a life. 3 lives.',
        ],
      _ => [soloScoring(m)],
    };

/// Play on your own: the real games, scored out of 100 each so personal
/// bests line up — one game, the Solo Cup (all six), or Survival.
class SoloScreen extends StatefulWidget {
  const SoloScreen({super.key});

  @override
  State<SoloScreen> createState() => _SoloScreenState();
}

class _SoloScreenState extends State<SoloScreen> {
  late Difficulty _difficulty = AppScope.read(context).settings.lastConfig().difficulty;
  late final Set<Era> _eras = {...AppScope.read(context).settings.lastConfig().eras};
  FootballGender _gender = FootballGender.men;

  // The run's results screen saves new bests after this screen's own
  // await has long returned (each game replaces the route before it), so
  // the tiles follow the settings instead.
  late final AppSettings _settings = AppScope.read(context).settings;

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _settings.addListener(_refresh);
  }

  @override
  void dispose() {
    _settings.removeListener(_refresh);
    super.dispose();
  }

  /// Starting XI and Top 10 are men's football only for now.
  List<GameModeId> get _games =>
      [for (final g in soloGames) if (g.hasWomensGame || _gender == FootballGender.men) g];

  Future<void> _play(List<GameModeId> games, {required bool cup}) async {
    if (!await MatchAccess.allowed(context) || !mounted) return;
    final base = AppScope.read(context).settings.lastConfig();
    final config = TournamentConfig(
      teams: [TeamSetup(name: 'You', colorIndex: 0, players: const [])],
      length: MatchLength.medium,
      difficulty: _difficulty,
      modes: games.toSet(),
      questionsPerRound: 5,
      answerSeconds: base.answerSeconds,
      bombSeconds: base.bombSeconds,
      bombLives: 3,
      eras: Set.of(_eras),
      gender: _gender,
      rounds: games.length,
    );
    await SoloRun(config: config, games: games, cup: cup).start(context);
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final d = _difficulty.name;
    final cupBest = settings.soloBest('cup', d);
    return Scaffold(
      appBar: AppBar(backgroundColor: Palette.pitch, title: Text('SOLO', style: AppText.headline(26))),
      body: PitchBackground(
        child: SafeArea(
          top: false,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
            // Solo Cup
            _Card(
              color: Palette.yellow,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.emoji_events_rounded, color: Palette.yellow, size: 30),
                  const SizedBox(width: 8),
                  Expanded(child: Text('SOLO CUP', style: AppText.headline(30, color: Palette.yellow))),
                  if (cupBest > 0) Text('BEST $cupBest', style: AppText.label(15, color: Palette.text)),
                ]),
                const SizedBox(height: 4),
                Text('All ${_games.length} games, one round each. Every game is out of 100.',
                    style: const TextStyle(color: Palette.muted, fontSize: 14)),
                const SizedBox(height: 12),
                BigButton(
                  label: 'Play the Solo Cup',
                  icon: Icons.sports_soccer,
                  onPressed: () => _play([..._games]..shuffle(), cup: true),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            Text('PICK A GAME', style: AppText.label(14, color: Palette.yellow)),
            const SizedBox(height: 8),
            for (final g in _games)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _GameTile(
                  mode: g,
                  best: settings.soloBest(g.name, d),
                  onTap: () => _play([g], cup: false),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Card(
                color: Palette.line,
                onTap: () async {
                  if (!await MatchAccess.allowed(context) || !context.mounted) return;
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SurvivalScreen()));
                  if (mounted) setState(() {});
                },
                child: Row(children: [
                  const Icon(Icons.favorite_rounded, color: Palette.danger, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('SURVIVAL', style: AppText.headline(22)),
                      const Text('Mixed questions until you run out of lives.',
                          style: TextStyle(color: Palette.muted, fontSize: 13)),
                    ]),
                  ),
                  if (settings.survivalBest(_gender) > 0)
                    Text('BEST ${settings.survivalBest(_gender)}', style: AppText.label(14, color: Palette.text)),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Text('DIFFICULTY', style: AppText.label(14, color: Palette.yellow)),
            const SizedBox(height: 8),
            SegmentedButton<Difficulty>(
              segments: [for (final x in Difficulty.values) ButtonSegment(value: x, label: Text(x.label))],
              selected: {_difficulty},
              onSelectionChanged: (s) => setState(() => _difficulty = s.first),
              showSelectedIcon: false,
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text('Bests are kept for each difficulty.', style: TextStyle(color: Palette.muted, fontSize: 13)),
            ),
            const SizedBox(height: 16),
            Text('FOOTBALL', style: AppText.label(14, color: Palette.yellow)),
            const SizedBox(height: 8),
            SegmentedButton<FootballGender>(
              segments: [for (final g in FootballGender.values) ButtonSegment(value: g, label: Text(g.label))],
              selected: {_gender},
              onSelectionChanged: (s) => setState(() => _gender = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 16),
            Text('ERAS', style: AppText.label(14, color: Palette.yellow)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in Era.values)
                FilterChip(
                  label: Text(e.label),
                  selected: _eras.contains(e),
                  // at least one era must stay on
                  onSelected: (on) => setState(() {
                    if (on) {
                      _eras.add(e);
                    } else if (_eras.length > 1) {
                      _eras.remove(e);
                    }
                  }),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, required this.color, this.onTap});
  final Widget child;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color, width: 1.5)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(14), child: child),
        ),
      );
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.mode, required this.best, required this.onTap});
  final GameModeId mode;
  final int best;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Card(
        color: mode.color.withValues(alpha: 0.6),
        onTap: onTap,
        child: Row(children: [
          Icon(mode.icon, color: mode.color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mode.soloTitle.toUpperCase(), style: AppText.headline(22, color: mode.color)),
              Text(soloScoring(mode), style: const TextStyle(color: Palette.muted, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(best > 0 ? 'BEST $best' : 'PLAY', style: AppText.label(14, color: Palette.text)),
        ]),
      );
}

/// One solo session: the [games] in order (Pointless is three one-answer
/// categories), each scored out of 100, then the results.
class SoloRun {
  SoloRun({required this.config, required this.games, required this.cup});
  final TournamentConfig config;
  final List<GameModeId> games;
  final bool cup;

  static const pointlessCategories = 3;

  late final Tournament _t = Tournament(config);
  final Map<GameModeId, List<int>> _scores = {};

  /// Rounds to play: Pointless counts three times.
  late final List<GameModeId> _plan = [
    for (final g in games) ...List.filled(g == GameModeId.pointless ? pointlessCategories : 1, g),
  ];

  Future<void> start(BuildContext context) =>
      Navigator.of(context).push(_route(_next(0)));

  Route<void> _route(Widget page) => MaterialPageRoute<void>(builder: (_) => page);

  /// Before each game: what it is and how it's scored (skipped between
  /// Pointless categories).
  Widget _next(int i) {
    final mode = _plan[i];
    final continuing = i > 0 && _plan[i - 1] == mode;
    if (continuing) return _game(i);
    return _SoloIntro(
      mode: mode,
      step: cup ? 'GAME ${games.indexOf(mode) + 1} OF ${games.length}' : 'SOLO',
      onGo: (context) => Navigator.of(context).pushReplacement(_route(_game(i))),
    );
  }

  Widget _game(int i) {
    final mode = _plan[i];
    return Builder(
      builder: (context) => MatchFlow.gameFor(
        mode,
        RoundContext(
          tournament: _t,
          multiplier: 1,
          onComplete: (result) {
            final score = result.solo ?? 0;
            (_scores[mode] ??= []).add(score);
            // The score strip shows your running total — once per game (after
            // Pointless's last category), so the round count matches the run.
            final lastOfGame = i + 1 >= _plan.length || _plan[i + 1] != mode;
            if (lastOfGame) _t.recordRound(RoundResult(mode: mode, points: {0: scores[mode]!}), multiplier: 1);
            final nav = Navigator.of(context);
            if (i + 1 < _plan.length) {
              nav.pushReplacement(_route(_next(i + 1)));
            } else {
              nav.pushReplacement(_route(_SoloResults(run: this)));
            }
          },
        ),
      ),
    );
  }

  /// Each game's score out of 100 (Pointless: the average of its categories).
  Map<GameModeId, int> get scores => {
        for (final e in _scores.entries) e.key: (e.value.reduce((a, b) => a + b) / e.value.length).round(),
      };
}

/// Before a solo game: its rules (folded away behind "Rules" once you've
/// played it alone before), then Kick off.
class _SoloIntro extends StatefulWidget {
  const _SoloIntro({required this.mode, required this.step, required this.onGo});
  final GameModeId mode;
  final String step;
  final void Function(BuildContext context) onGo;

  @override
  State<_SoloIntro> createState() => _SoloIntroState();
}

class _SoloIntroState extends State<_SoloIntro> {
  GameModeId get mode => widget.mode;
  String get _seenKey => 'solo_${mode.name}';
  late bool _showRules = !AppScope.read(context).settings.rulesSeen(_seenKey);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PitchBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Palette.muted),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                const Spacer(),
                Text(widget.step, style: AppText.label(15, color: Palette.text)),
                const SizedBox(height: 12),
                Icon(mode.icon, color: mode.color, size: 56),
                const SizedBox(height: 8),
                Text(mode.soloTitle.toUpperCase(), textAlign: TextAlign.center, style: AppText.headline(44, color: mode.color)),
                Text(mode.tagline, textAlign: TextAlign.center, style: const TextStyle(color: Palette.muted, fontSize: 16)),
                const SizedBox(height: 20),
                if (_showRules)
                  for (final (i, r) in soloRules(mode).indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CircleAvatar(
                            radius: 13,
                            backgroundColor: mode.color,
                            child: Text('${i + 1}', style: AppText.headline(15, color: Palette.pitchDeep))),
                        const SizedBox(width: 12),
                        Expanded(child: Text(r, style: const TextStyle(fontSize: 17, height: 1.4))),
                      ]),
                    )
                else
                  TextButton.icon(
                    onPressed: () => setState(() => _showRules = true),
                    icon: const Icon(Icons.menu_book_rounded, color: Palette.yellow),
                    label: Text('RULES', style: AppText.label(16, color: Palette.yellow)),
                  ),
                const Spacer(flex: 2),
                BigButton(
                  label: 'Kick off',
                  icon: Icons.sports_soccer,
                  onPressed: () {
                    final s = AppScope.read(context);
                    s.sound.play(Sfx.whistle);
                    s.haptic(HapticStrength.medium);
                    s.settings.markRulesSeen(_seenKey);
                    widget.onGo(context);
                  },
                ),
              ]),
            ),
          ),
        ),
      );
}

/// Full time: each game's score, the total, and personal bests.
class _SoloResults extends StatefulWidget {
  const _SoloResults({required this.run});
  final SoloRun run;

  @override
  State<_SoloResults> createState() => _SoloResultsState();
}

class _SoloResultsState extends State<_SoloResults> {
  late final Map<GameModeId, int> _scores = widget.run.scores;
  final Map<String, int> _oldBests = {};
  final Set<String> _newBests = {};
  late final int _total = _scores.values.fold(0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context);
    final d = widget.run.config.difficulty.name;
    for (final e in _scores.entries) {
      _oldBests[e.key.name] = s.settings.soloBest(e.key.name, d);
      if (s.settings.recordSolo(e.key.name, d, e.value)) _newBests.add(e.key.name);
    }
    if (widget.run.cup) {
      _oldBests['cup'] = s.settings.soloBest('cup', d);
      if (s.settings.recordSolo('cup', d, _total)) _newBests.add('cup');
    }
    if (_newBests.isNotEmpty) {
      s.sound.play(Sfx.fanfare);
      s.sound.play(Sfx.cheer);
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final cup = run.cup;
    final single = cup ? null : _scores.entries.first;
    final headline = cup ? _total : (single?.value ?? 0);
    final max = cup ? 100 * _scores.length : 100;
    final key = cup ? 'cup' : single!.key.name;
    final isNew = _newBests.contains(key);
    final oldBest = _oldBests[key] ?? 0;
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: [
            Text(cup ? 'SOLO CUP' : single!.key.soloTitle.toUpperCase(),
                textAlign: TextAlign.center, style: AppText.label(16, color: Palette.yellow)),
            const SizedBox(height: 8),
            Text('$headline', textAlign: TextAlign.center, style: AppText.headline(96, color: Palette.yellow)),
            Text('OUT OF $max · ${run.config.difficulty.label.toUpperCase()}',
                textAlign: TextAlign.center, style: AppText.label(15, color: Palette.text)),
            const SizedBox(height: 10),
            Center(
              child: isNew
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: Palette.gold, borderRadius: BorderRadius.circular(10)),
                      child: Text(oldBest > 0 ? 'NEW BEST! (WAS $oldBest)' : 'NEW BEST!',
                          style: AppText.headline(22, color: Palette.pitchDeep)),
                    )
                  : Text('BEST: $oldBest', style: AppText.headline(24, color: Palette.muted)),
            ),
            if (cup) ...[
              const SizedBox(height: 20),
              for (final e in _scores.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(e.key.icon, color: e.key.color),
                    const SizedBox(width: 10),
                    Expanded(child: Text(e.key.soloTitle.toUpperCase(), style: AppText.headline(20, color: e.key.color))),
                    if (_newBests.contains(e.key.name))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('BEST!', style: AppText.label(13, color: Palette.gold)),
                      ),
                    Text('${e.value}', style: AppText.headline(28)),
                  ]),
                ),
            ],
            const SizedBox(height: 24),
            BigButton(
              label: 'Play again',
              icon: Icons.replay_rounded,
              onPressed: () {
                final nav = Navigator.of(context);
                nav.pop();
                SoloRun(config: run.config, games: [...run.games]..shuffle(), cup: run.cup).start(nav.context);
              },
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('DONE', style: AppText.label(16, color: Palette.text)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
