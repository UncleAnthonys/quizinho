import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../core/app_services.dart';
import '../core/hinted_speech.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../domain/tournament.dart';
import '../games/buzz_game_view.dart' show FaceOffIntro;
import '../games/career_path/career_path_screen.dart' show CareerTrail;
import '../games/club_connections/club_connections_screen.dart' show ClubsCard;
import '../ui/widgets/common.dart';
import '../ui/widgets/player_picker.dart';
import 'room.dart';
import 'room_link.dart';

/// A phone joining someone else's game: enter (or scan) the code, pick your
/// name, then play — the question on your screen, your own buzzer, and your
/// own answer box (mic or typing) when you buzz.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, this.code});

  /// From the QR code link (…?join=ABCD); null = type it in.
  final String? code;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _codeField = TextEditingController();
  GuestRoom? _room;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_room == null && widget.code != null) _join(widget.code!);
  }

  void _join(String code) {
    final s = AppScope.read(context);
    final link = s.roomLink;
    if (link == null || normaliseRoomCode(code).length != 4) return;
    final room = GuestRoom(link, code, s.settings.deviceId)..start();
    setState(() => _room = room);
  }

  @override
  void dispose() {
    _room?.dispose();
    _codeField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: room == null
              ? _enterCode()
              : ListenableBuilder(listenable: room, builder: (context, _) => _inRoom(room)),
        ),
      ),
    );
  }

  Widget _enterCode() => Padding(
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
          Text('JOIN A GAME', style: AppText.headline(40, color: Palette.yellow)),
          const SizedBox(height: 8),
          Text('Type the 4-letter code under the QR\non the host’s phone',
              textAlign: TextAlign.center, style: AppText.label(15, color: Palette.text)),
          const SizedBox(height: 20),
          TextField(
            controller: _codeField,
            autofocus: true,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            maxLength: 4,
            style: AppText.headline(48, weight: FontWeight.w900),
            decoration: const InputDecoration(counterText: '', hintText: 'ABCD'),
            onChanged: (v) {
              if (normaliseRoomCode(v).length == 4) _join(v);
            },
          ),
          const Spacer(flex: 2),
        ]),
      );

  Widget _inRoom(GuestRoom room) {
    if (room.missing) {
      return _message('NO GAME FOUND', 'Check the code ${room.code} on the main phone.', back: true);
    }
    final teams = room.teams;
    if (teams == null) return const Center(child: CircularProgressIndicator(color: Palette.yellow));
    final me = room.me;
    if (me == null) return _pickName(room, teams);
    return _GuestGame(room: room, me: me);
  }

  Widget _message(String title, String body, {bool back = false}) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(title, textAlign: TextAlign.center, style: AppText.headline(36, color: Palette.yellow)),
          const SizedBox(height: 10),
          Text(body, textAlign: TextAlign.center, style: AppText.label(16, color: Palette.text)),
          if (back) ...[
            const SizedBox(height: 24),
            GhostButton(
              label: 'Try another code',
              icon: Icons.refresh_rounded,
              onPressed: () {
                _room?.dispose();
                setState(() => _room = null);
              },
            ),
          ],
        ]),
      );

  Widget _pickName(GuestRoom room, List<TeamSetup> teams) => ListView(padding: const EdgeInsets.all(20), children: [
        Text('WHO ARE YOU?', textAlign: TextAlign.center, style: AppText.headline(40, color: Palette.yellow)),
        const SizedBox(height: 4),
        Text('Game ${room.code}', textAlign: TextAlign.center, style: AppText.label(14)),
        const SizedBox(height: 18),
        for (final (i, t) in teams.indexed) ...[
          TeamChip(name: t.name, colorIndex: t.colorIndex, size: 22),
          const SizedBox(height: 8),
          if (t.players.isEmpty)
            Text('No names on this team yet — add them on the main phone.', style: AppText.label(13))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (j, n) in t.players.indexed)
                ChoiceChip(
                  label: Text(j == 0 ? '$n (C)' : n, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  selected: false,
                  avatar: room.taken(i, n) ? const Icon(Icons.check_circle_rounded, color: Palette.green, size: 18) : null,
                  onSelected: room.taken(i, n)
                      ? null
                      : (_) {
                          if (kIsWeb) unawaited(HintedSpeech.primeMic());
                          room.claim(i, n);
                        },
                ),
            ]),
          const SizedBox(height: 20),
        ],
      ]);
}

/// The game as a joined phone sees it.
class _GuestGame extends StatefulWidget {
  const _GuestGame({required this.room, required this.me});
  final GuestRoom room;
  final RoomMember me;

  @override
  State<_GuestGame> createState() => _GuestGameState();
}

class _GuestGameState extends State<_GuestGame> with SingleTickerProviderStateMixin {
  /// Local countdown from the last time the host sent the clock: redrawn
  /// every frame (smooth, like the host), and only the timer bar rebuilds.
  late final Ticker _ticker;
  final ValueNotifier<double> _left = ValueNotifier(0);
  double _syncedLeft = 0;
  final Stopwatch _sinceSync = Stopwatch();
  double _total = 1;
  String? _clockFrom;
  String? _buzzedOn;

  @override
  void initState() {
    super.initState();
    // Straight after picking a name (a tap), so Chrome may start fetching its
    // on-device speech pack now rather than at the first buzz.
    if (kIsWeb) unawaited(HintedSpeech.ready());
    _ticker = createTicker((_) {
      if (_left.value <= 0) return;
      _left.value = (_syncedLeft - _sinceSync.elapsedMicroseconds / 1e6).clamp(0, _total);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _left.dispose();
    super.dispose();
  }

  void _syncClock(Map<String, Object?> v) {
    // Only a fresh clock from the host resets the countdown; anything else
    // (a view without one) leaves it running.
    final left = (v['left'] as num?)?.toDouble();
    if (left == null) return;
    final key = '${v['q']}|${v['phase']}|$left|${v['answering']}';
    if (key == _clockFrom) return;
    _clockFrom = key;
    _total = (v['total'] as num?)?.toDouble() ?? 1;
    _syncedLeft = left;
    _sinceSync
      ..reset()
      ..start();
    _left.value = left;
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.room.view;
    final me = widget.me;
    final teams = widget.room.teams ?? const [];
    final colour = me.team < teams.length ? teams[me.team].colorIndex : 0;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(children: [
        TeamChip(name: me.name, colorIndex: colour, size: 18),
        const Spacer(),
        Text('GAME ${widget.room.code}', style: AppText.label(13)),
      ]),
    );
    final body = switch (v['kind']) {
      'buzz' => _buzz(v, colour),
      'main' => _center('EYES ON THE MAIN SCREEN', '${v['what'] ?? ''}', scores: v['teams']),
      'closed' => _center('FULL TIME', 'Thanks for playing!'),
      _ => _center('YOU’RE IN', 'Waiting for kick-off on the main phone…'),
    };
    return Column(children: [header, if (kIsWeb) const _VoiceBoost(), Expanded(child: body)]);
  }

  /// The host's score strip, drawn from the view.
  Widget _scores(Object? teams, {String round = '', int? highlight}) => ScoreStrip(
        round: round,
        highlightTeam: highlight,
        teams: [
          for (final t in asList(teams))
            if (asMap(t) case final m)
              ('${m['name'] ?? ''}', (m['color'] as num?)?.toInt() ?? 0, (m['score'] as num?)?.toInt() ?? 0),
        ],
      );

  /// The question with the host's own widgets, so both screens look the same.
  Widget _question(Map<String, Object?> v, {bool compact = false}) {
    final q = asMap(v['question']);
    final clubs = asList(q['clubs']);
    if (clubs.length == 2) return ClubsCard(a: '${clubs[0]}', b: '${clubs[1]}', compact: compact);
    final spells = [
      for (final sp in asList(q['spells']))
        if (asMap(sp) case final m)
          CareerSpell(
            club: Club(id: '', name: '${m['c'] ?? ''}', fame: 1),
            startYear: (m['s'] as num?)?.toInt(),
            endYear: (m['e'] as num?)?.toInt(),
            isLoan: m['l'] == true,
          ),
    ];
    if (spells.isEmpty) return const SizedBox.shrink();
    final worth = (q['worth'] as num?)?.toInt();
    return Column(children: [
      if (worth != null)
        Text('WORTH $worth ${worth == 1 ? 'POINT' : 'POINTS'}', style: AppText.headline(compact ? 18 : 24, color: Palette.gold)),
      CareerTrail(
        spells: spells,
        shown: (q['shown'] as num?)?.toInt() ?? spells.length,
        highlight: (q['highlight'] as num?)?.toInt() ?? spells.length - 1,
        maxHeight: compact ? 190 : 250,
      ),
    ]);
  }

  Widget _center(String title, String body, {Object? scores}) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          if (scores != null) _scores(scores, round: '${widget.room.view['round'] ?? ''}'),
          const Spacer(),
          Text(title, textAlign: TextAlign.center, style: AppText.headline(34, color: Palette.yellow)),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: AppText.label(16, color: Palette.text)),
          const Spacer(),
        ]),
      );

  Widget _buzz(Map<String, Object?> v, int colour) {
    _syncClock(v);
    final s = AppScope.of(context);
    final me = widget.me;
    final q = '${v['q']}';
    final phase = '${v['phase']}';
    final faceOff = asMap(v['faceOff']);
    final answering = asMap(v['answering']);
    final canBuzz = [for (final t in asList(v['canBuzz'])) (t as num).toInt()];
    final inFaceOff = faceOff.isEmpty || faceOff['${me.team}'] == me.name;
    final myBuzzer = phase == 'open' && canBuzz.contains(me.team) && inFaceOff;
    final iAnswer = phase == 'answering' && answering['device'] == widget.room.device;
    final result = asMap(v['result']);

    final question = _question(v, compact: iAnswer);

    Widget action;
    if (iAnswer) {
      final ids = {for (final a in asList(v['answers'])) '$a'};
      action = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: PlayerPicker(
          key: ValueKey('guest-$q'),
          index: s.repo.players,
          voice: s.voice,
          accent: Palette.team(colour),
          isAnswer: (p) => ids.contains(p.id),
          onPick: (p) => widget.room.answer(q, p.id),
          onPass: () => widget.room.pass(q),
        ),
      );
    } else if (myBuzzer) {
      final buzzed = _buzzedOn == q;
      action = Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 180,
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Palette.team(colour),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
            onPressed: buzzed
                ? null
                : () {
                    s.haptic(HapticStrength.heavy);
                    setState(() => _buzzedOn = q);
                    widget.room.buzz(q);
                  },
            child: Text(buzzed ? 'BUZZED!' : 'BUZZ', style: AppText.headline(56, color: Palette.onTeam(colour))),
          ),
        ),
      );
    } else if (phase == 'ready') {
      action = _status(faceOff.isEmpty ? 'GET READY…' : 'FACE-OFF: ${faceOff.values.join(' v ')}\nGet ready…');
    } else if (phase == 'answering') {
      action = _status('${answering['name'] ?? ''} is answering…'.toUpperCase());
    } else if (phase == 'open' && faceOff.isNotEmpty && !inFaceOff) {
      action = _status('FACE-OFF: ${faceOff.values.join(' v ')}\nOnly they can buzz');
    } else if (phase == 'open') {
      action = _status('LOCKED OUT — WAIT FOR THE STEAL');
    } else if (result.isNotEmpty) {
      final scorer = (result['team'] as num?)?.toInt();
      final teamsV = asList(v['teams']);
      final scorerTeam = scorer != null && scorer < teamsV.length ? asMap(teamsV[scorer]) : const <String, Object?>{};
      action = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          if (result['scored'] == true) ...[
            TeamChip(
                name: '${scorerTeam['name'] ?? ''}', colorIndex: (scorerTeam['color'] as num?)?.toInt() ?? 0, size: 22),
            const SizedBox(height: 8),
            Text('+${result['points']}', style: AppText.headline(64, color: Palette.yellow)),
            Text('${result['player'] ?? ''}', textAlign: TextAlign.center, style: AppText.headline(30)),
          ] else
            Text('NOBODY GOT IT', style: AppText.headline(40, color: Palette.danger)),
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            for (final n in asList(result['reveal'])) Chip(label: Text('$n'), backgroundColor: Palette.card),
          ]),
        ]),
      );
    } else {
      action = const SizedBox.shrink();
    }

    // The host's face-off intro, on every phone: who's up, before the question.
    if (phase == 'ready' && faceOff.isNotEmpty) {
      final teamsV = asList(v['teams']);
      final sides = [
        for (final e in faceOff.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          if (int.tryParse(e.key) case final t? when t < teamsV.length)
            ('${e.value}', (asMap(teamsV[t])['color'] as num?)?.toInt() ?? 0, '${asMap(teamsV[t])['name'] ?? ''}'),
      ];
      return Column(children: [
        _scores(v['teams'], round: '${v['round'] ?? ''}'),
        Expanded(
          child: FaceOffIntro(
            players: sides,
            questionNumber: int.tryParse('${v['n'] ?? ''}'.split('/').first) ?? 1,
            showButton: false,
            message: faceOff['${me.team}'] == me.name
                ? 'You’re up! Buzz on this phone\nwhen the question appears.'
                : 'Hands off — no helping!',
          ),
        ),
      ]);
    }

    return ListView(children: [
      _scores(v['teams'], round: '${v['round'] ?? ''}', highlight: (answering['team'] as num?)?.toInt()),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
        child: Row(children: [
          Text('${v['title'] ?? ''}', style: AppText.label(15, color: Palette.yellow)),
          const SizedBox(width: 8),
          Text('Q ${v['n'] ?? ''}', style: AppText.label(15)),
        ]),
      ),
      if (!iAnswer) question,
      if (phase == 'open' || phase == 'answering')
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: ValueListenableBuilder<double>(
            valueListenable: _left,
            builder: (context, left, _) => TimerBar(fraction: _total == 0 ? 0 : left / _total, seconds: left),
          ),
        ),
      action,
      if (iAnswer) question,
    ]);
  }

  Widget _status(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center, style: AppText.headline(26, color: Palette.muted)),
      );
}

/// Whether this browser's mic is getting the answer-name boost (Chrome's
/// on-device speech with hints), so it's obvious which phones have it.
class _VoiceBoost extends StatelessWidget {
  const _VoiceBoost();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: HintedSpeech.status,
        builder: (context, s, _) {
          final (text, colour) = switch (s) {
            'ready' => ('Voice boost ON', Palette.green),
            'downloading' => ('Voice boost: downloading…', Palette.gold),
            'checking' => ('Voice boost: checking…', Palette.muted),
            'no on-device speech' => ('Voice boost: not on this phone', Palette.muted),
            _ => ('Voice boost: needs Chrome on Android (or the app)', Palette.muted),
          };
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: Row(children: [
              Icon(s == 'ready' ? Icons.mic_rounded : Icons.mic_none_rounded, size: 15, color: colour),
              const SizedBox(width: 4),
              Text(text, style: AppText.label(12, color: colour)),
            ]),
          );
        },
      );
}
