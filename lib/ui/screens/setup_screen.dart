import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../match_access.dart';
import '../match_flow.dart';
import '../widgets/common.dart';

/// Teams, length, difficulty, games — then kick off. Prefilled from last time.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  static const _maxTeams = 6;
  static const _defaultNames = ['Home', 'Away', 'Neutrals', 'Ultras', 'Away End', 'Family Stand'];

  final List<TextEditingController> _names = [];
  final List<int> _colours = [];

  /// Optional player names per team (parallel to [_names]).
  final List<List<String>> _players = [];
  MatchLength _length = MatchLength.medium;
  Difficulty _difficulty = Difficulty.medium;
  final Set<GameModeId> _modes = {};
  int _answerSeconds = 8;
  int _bombSeconds = 20;
  int _lives = 3;
  int _headsUpSeconds = 60;
  final Set<Era> _eras = {};
  FootballGender _gender = FootballGender.men;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final c = AppScope.of(context).settings.lastConfig();
    for (final t in c.teams) {
      _names.add(TextEditingController(text: t.name));
      _colours.add(t.colorIndex);
      _players.add([...t.players]);
    }
    while (_names.length < 2) {
      _addTeam();
    }
    _length = c.length;
    _difficulty = c.difficulty;
    _modes.addAll(c.modes);
    _answerSeconds = c.answerSeconds;
    _bombSeconds = c.bombSeconds;
    _lives = c.bombLives;
    _headsUpSeconds = c.headsUpSeconds;
    _eras.addAll(c.eras);
    // Men's is always the starting choice; Both / Women's is picked per match.
    _gender = FootballGender.men;
  }

  @override
  void dispose() {
    for (final n in _names) {
      n.dispose();
    }
    super.dispose();
  }

  void _addTeam() {
    final i = _names.length;
    final used = _colours.toSet();
    var colour = 0;
    while (used.contains(colour) && colour < Palette.teams.length - 1) {
      colour++;
    }
    _names.add(TextEditingController(text: _defaultNames[i % _defaultNames.length]));
    _colours.add(colour);
    _players.add([]);
  }

  bool get _valid =>
      _names.every((n) => n.text.trim().isNotEmpty) &&
      _modes.any((m) => m != GameModeId.wildcard);

  Future<void> _start() async {
    final services = AppScope.read(context);
    final config = TournamentConfig(
      teams: [
        for (var i = 0; i < _names.length; i++)
          TeamSetup(name: _names[i].text.trim(), colorIndex: _colours[i], players: [..._players[i]]),
      ],
      length: _length,
      difficulty: _difficulty,
      modes: Set.of(_modes),
      answerSeconds: _answerSeconds,
      bombSeconds: _bombSeconds,
      bombLives: _lives,
      headsUpSeconds: _headsUpSeconds,
      eras: Set.of(_eras),
      gender: _gender,
    );
    await services.settings.saveConfig(config);
    if (!mounted) return;
    await MatchAccess.start(context, config);
  }

  @override
  Widget build(BuildContext context) {
    final warmUp = MatchAccess.warmUpNext(AppScope.of(context));
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.pitch,
        title: Text('HEAD TO HEAD', style: AppText.headline(26)),
      ),
      body: PitchBackground(
        child: SafeArea(
          top: false,
          child: Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
                _section('TEAMS'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _players.every((p) => p.isNotEmpty)
                        ? 'Face-offs ON: some questions pit one named player against another.'
                        : 'Optional: add player names to every team to unlock head-to-head face-offs.',
                    style: const TextStyle(color: Palette.muted, fontSize: 13),
                  ),
                ),
                for (var i = 0; i < _names.length; i++) _teamRow(i),
                if (_names.length < _maxTeams)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GhostButton(
                      label: 'Add team',
                      icon: Icons.add,
                      onPressed: () => setState(_addTeam),
                    ),
                  ),
                const SizedBox(height: 12),
                if (warmUp)
                  const _WarmUpBanner()
                else ...[
                _section('MATCH LENGTH'),
                SegmentedButton<MatchLength>(
                  segments: [for (final m in MatchLength.values) ButtonSegment(value: m, label: Text(m.label))],
                  selected: {_length},
                  onSelectionChanged: (s) => setState(() => _length = s.first),
                  showSelectedIcon: false,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(_length.description, style: const TextStyle(color: Palette.muted)),
                ),
                const SizedBox(height: 18),
                _section('DIFFICULTY'),
                SegmentedButton<Difficulty>(
                  segments: [for (final d in Difficulty.values) ButtonSegment(value: d, label: Text(d.label))],
                  selected: {_difficulty},
                  onSelectionChanged: (s) => setState(() => _difficulty = s.first),
                  showSelectedIcon: false,
                ),
                const SizedBox(height: 18),
                _section('FOOTBALL'),
                SegmentedButton<FootballGender>(
                  segments: [for (final g in FootballGender.values) ButtonSegment(value: g, label: Text(g.label))],
                  selected: {_gender},
                  onSelectionChanged: (s) => setState(() => _gender = s.first),
                  showSelectedIcon: false,
                ),
                if (_gender == FootballGender.women)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Text('Starting XI and Heads Up are men’s only for now, so they’re left out.',
                        style: TextStyle(color: Palette.muted)),
                  ),
                const SizedBox(height: 18),
                _section('ERAS'),
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
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    _eras.length == Era.values.length
                        ? 'All eras. Untick any your group doesn’t know.'
                        : 'Questions from: ${[for (final e in Era.values) if (_eras.contains(e)) e.label].join(', ')}',
                    style: const TextStyle(color: Palette.muted),
                  ),
                ),
                const SizedBox(height: 18),
                _section('GAMES'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in GameModeId.values)
                    FilterChip(
                      avatar: Icon(m.icon, size: 18, color: m.playable ? m.color : Palette.muted),
                      label: Text(m.playable ? m.title : '${m.title} · soon'),
                      selected: _modes.contains(m),
                      onSelected: m.playable
                          ? (on) => setState(() => on ? _modes.add(m) : _modes.remove(m))
                          : null,
                    ),
                ]),
                if (!_modes.any((m) => m != GameModeId.wildcard))
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Pick at least one game.', style: TextStyle(color: Palette.danger)),
                  ),
                const SizedBox(height: 8),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('TIMERS & RULES', style: AppText.label(15)),
                    children: [
                      _choice('Answer time', [5, 8, 12], _answerSeconds, (v) => _answerSeconds = v, suffix: 's'),
                      _choice('Bomb timer', [10, 20, 30], _bombSeconds, (v) => _bombSeconds = v, suffix: 's'),
                      _choice('Heads Up turn', [30, 60, 90], _headsUpSeconds, (v) => _headsUpSeconds = v, suffix: 's'),
                      _choice('Bomb lives', [1, 3], _lives, (v) => _lives = v, labels: {1: 'Sudden death', 3: 'Three lives'}),
                    ],
                  ),
                ),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: BigButton(
                  label: warmUp ? 'Kick off the Warm-Up Cup' : 'Kick off',
                  icon: Icons.sports_soccer,
                  onPressed: _valid ? _start : null),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: AppText.label(14, color: Palette.yellow)),
      );

  Widget _teamRow(int i) => Padding(
        key: ObjectKey(_names[i]),
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _teamNameRow(i),
          Padding(
            padding: const EdgeInsets.only(left: 58, top: 6),
            child: _PlayerNames(
              names: _players[i],
              colorIndex: _colours[i],
              onChanged: () => setState(() {}),
            ),
          ),
        ]),
      );

  Widget _teamNameRow(int i) => Padding(
        padding: EdgeInsets.zero,
        child: Row(children: [
          GestureDetector(
            onTap: () => setState(() => _colours[i] = (_colours[i] + 1) % Palette.teams.length),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Palette.team(_colours[i]),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Icon(Icons.palette, size: 20, color: Palette.onTeam(_colours[i])),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _names[i],
              textCapitalization: TextCapitalization.words,
              maxLength: 16,
              style: AppText.headline(24, weight: FontWeight.w800),
              decoration: const InputDecoration(counterText: '', hintText: 'Team name'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_names.length > 2)
            IconButton(
              icon: const Icon(Icons.close, color: Palette.muted),
              onPressed: () {
                final removed = _names.removeAt(i);
                setState(() {
                  _colours.removeAt(i);
                  _players.removeAt(i);
                });
                WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
              },
            ),
        ]),
      );

  Widget _choice(String label, List<int> options, int value, void Function(int) set,
          {String suffix = '', Map<int, String>? labels}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          SegmentedButton<int>(
            segments: [
              for (final o in options) ButtonSegment(value: o, label: Text(labels?[o] ?? '$o$suffix')),
            ],
            selected: {value},
            onSelectionChanged: (s) => setState(() => set(s.first)),
            showSelectedIcon: false,
          ),
        ]),
      );
}

/// Chips for a team's players plus a quick "add player" field.
class _PlayerNames extends StatefulWidget {
  const _PlayerNames({required this.names, required this.colorIndex, required this.onChanged});
  final List<String> names;
  final int colorIndex;
  final VoidCallback onChanged;

  @override
  State<_PlayerNames> createState() => _PlayerNamesState();
}

class _PlayerNamesState extends State<_PlayerNames> {
  static const _maxPlayers = 10;
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _add() {
    final name = _field.text.trim();
    _field.clear();
    if (name.isEmpty || widget.names.length >= _maxPlayers) return;
    if (widget.names.any((n) => n.toLowerCase() == name.toLowerCase())) return;
    widget.names.add(name);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.names.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final n in widget.names)
              InputChip(
                label: Text(n),
                backgroundColor: Palette.team(widget.colorIndex).withValues(alpha: 0.25),
                side: BorderSide(color: Palette.team(widget.colorIndex)),
                onDeleted: () {
                  widget.names.remove(n);
                  widget.onChanged();
                },
              ),
          ]),
        if (widget.names.length < _maxPlayers)
          SizedBox(
            height: 44,
            child: TextField(
              controller: _field,
              textCapitalization: TextCapitalization.words,
              maxLength: 14,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                hintText: '+ Add player (optional)',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: IconButton(icon: const Icon(Icons.add, color: Palette.yellow), onPressed: _add),
              ),
              onSubmitted: (_) => _add(),
            ),
          ),
      ]);
}

/// Before the unlock: what the free cup is, and what the full game adds.
class _WarmUpBanner extends StatelessWidget {
  const _WarmUpBanner();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.yellow, width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('FREE WARM-UP CUP', style: AppText.headline(28, color: Palette.yellow)),
          const SizedBox(height: 4),
          Text('3 rounds: Club Connections, Career Path and Bidding War.',
              style: AppText.label(15, color: Palette.text)),
          const SizedBox(height: 8),
          const Text(
            'The Warm-Up Cup has the same hand-picked challenges for everyone. '
            'The full game (£2.99, one-off) gives you random challenges from a huge database, '
            'all 8 games and unlimited matches.',
            style: TextStyle(color: Palette.muted, fontSize: 14),
          ),
        ]),
      );
}
