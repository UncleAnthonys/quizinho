import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../core/app_links.dart';
import '../core/app_services.dart';
import '../core/hinted_speech.dart';
import '../core/web_keyboard.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../domain/tournament.dart';
import '../games/bidding_war/bidding_war_screen.dart' show BidControls, BidLayout;
import '../games/buzz_game_view.dart' show FaceOffIntro;
import '../games/checkout_501/checkout_screen.dart' show CoLayout;
import '../games/pointless/pointless_screen.dart' show PtLayout;
import '../games/starting_xi/starting_xi_screen.dart' show XiLayout;
import '../games/tic_tac_toe/tic_tac_toe_screen.dart' show TttLayout, showSquareAnswers;
import '../games/top10/top10_screen.dart' show Top10Layout;
import '../games/career_path/career_path_screen.dart' show CareerTrail;
import '../games/club_connections/club_connections_screen.dart' show ClubsCard;
import '../ui/screens/free_kick_screen.dart' show FreeKickMirror;
import '../ui/teaser/teaser_widgets.dart' show TeaserPrompt;
import '../ui/widgets/buzzer_pad.dart' show TeamBuzzer;
import '../ui/widgets/common.dart';
import '../ui/widgets/match_table.dart';
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
    final room = GuestRoom(link, code, s.settings.deviceId, history: s.settings.history)..start();
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
            Text('No names on this team yet - add them on the main phone.', style: AppText.label(13))
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

/// A joined phone's game screen, for screenshots.
@visibleForTesting
Widget guestGamePreview(GuestRoom room, RoomMember me) => _GuestGame(room: room, me: me);

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
    Widget body() => switch (v['kind']) {
      'buzz' => _buzz(v, colour),
      'turn' => _turn(v, colour),
      'main' => _center('EYES ON THE MAIN SCREEN', '${v['what'] ?? ''}', scores: v['teams']),
      // The free kick picking the next game, played here too.
      'freekick' => FreeKickMirror(
          key: ValueKey('fk-${v['n']}'),
          data: v,
          scores: _scores(v['teams'], round: '${v['round'] ?? ''}'),
        ),
      'rules' => _rules(v),
      'table' => _table(v),
      'closed' => _center('FULL TIME', 'Thanks for playing!'),
      _ => _center('YOU’RE IN', 'Waiting for kick-off on the main phone…'),
    };
    // Typing: the keyboard slides over the page, so lift everything above it
    // and let the game shrink to its compact "typing" layout, like the app.
    return ListenableBuilder(
      listenable: Listenable.merge([keyboardInset, answerTyping]),
      // Slides with the keyboard rather than jumping (Collapse.duration).
      builder: (context, _) => AnimatedPadding(
        duration: Collapse.duration,
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: keyboardInset.value),
        child: Column(children: [
          Collapse(
            hidden: keyboardInset.value > 0 || answerTyping.value,
            // (No name/game-code strip: the screen's for the game.)
            child: Column(children: [if (_AppNudge.shows) const _AppNudge()]),
          ),
          Expanded(child: body()),
        ]),
      ),
    );
  }

  /// The host's score strip, drawn from the view.
  Widget _scores(Object? teams, {String round = '', int? highlight, List<String> extra = const []}) => ScoreStrip(
        round: round,
        highlightTeam: highlight,
        extra: extra.isEmpty ? null : (i) => i < extra.length ? extra[i] : '',
        teams: [
          for (final t in asList(teams))
            if (asMap(t) case final m)
              ('${m['name'] ?? ''}', (m['color'] as num?)?.toInt() ?? 0, (m['score'] as num?)?.toInt() ?? 0),
        ],
      );

  /// The question with the host's own widgets, so both screens look the same.
  Widget _question(Map<String, Object?> v, {bool compact = false}) {
    final q = asMap(v['question']);
    if (q['teaser'] is String) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: TeaserPrompt(
          question: q['teaser']! as String,
          prefix: '${q['prefix'] ?? 'NAME A PLAYER WHO…'}',
          halfTime: q['worth'] == 5,
          compact: compact,
        ),
      );
    }
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

  /// The table after a round, or full time: the main phone's own screen.
  Widget _table(Map<String, Object?> v) {
    final full = v['full'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(children: [
        if (full) FullTimeHeader(data: v) else RoundTableHeader(data: v),
        Expanded(child: ListView(children: matchTableRows(v))),
        if (full) Text('Thanks for playing!', style: AppText.label(14)),
      ]),
    );
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

  /// The rules for the game about to start, read along with the main phone:
  /// the same sizes as its rules screen, and centred in the space below the
  /// scores rather than bunched at the top.
  Widget _rules(Map<String, Object?> v) {
    final colour = Color((v['color'] as num?)?.toInt() ?? 0xFFFFCC29);
    final rules = [for (final r in asList(v['rules'])) '$r'];
    return Column(children: [
      _scores(v['teams'], round: '${widget.room.view['round'] ?? ''}'),
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 40),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${v['title'] ?? ''}'.toUpperCase(),
                    textAlign: TextAlign.center, style: AppText.headline(48, color: colour)),
                Text('${v['tagline'] ?? ''}',
                    textAlign: TextAlign.center, style: const TextStyle(color: Palette.muted, fontSize: 17)),
                if (v['double'] == true) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: Palette.gold, borderRadius: BorderRadius.circular(10)),
                    child: Text('WILDCARD · DOUBLE POINTS', style: AppText.headline(20, color: Palette.pitchDeep)),
                  ),
                ],
                const SizedBox(height: 24),
                for (final (i, r) in rules.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
                        child: Text('${i + 1}', style: AppText.headline(18, color: Palette.pitchDeep)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: RuleText(r)),
                    ]),
                  ),
                if (v['who'] != null) ...[
                  const SizedBox(height: 6),
                  // As on the main phone: a plain line in a dark box, not a bold label.
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration:
                        BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.people_alt_rounded, color: Palette.gold),
                      const SizedBox(width: 10),
                      Expanded(child: Text('${v['who']}', style: const TextStyle(fontSize: 16, color: Palette.text))),
                    ]),
                  ),
                ],
                const SizedBox(height: 20),
                Text('Kicking off on the main phone…', textAlign: TextAlign.center, style: AppText.label(13)),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

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
    // A player who types gets the answer box the moment they buzz, before
    // the main phone confirms it: then it's already there when the finger
    // lifts, the only moment an iPhone lets the keyboard open. If someone
    // else was first, it goes again (and the main phone ignores an answer
    // from a phone that hasn't got the turn).
    final voice = s.voice;
    final types = kIsWeb && (voice == null || !voice.enabled || voice.preferTyping);
    // Only while this buzz is still waiting for the main phone: once it's
    // answered (wrong, and the steal is on), this team can't buzz again and
    // the box goes, so the phone shows the game again.
    // A buzz belongs to one go at the question: once that's over (answered,
    // or a new question), forget it. The teaser keeps its key between games,
    // so a buzz at half-time used to open the box straight away next time.
    if (phase != 'open') _buzzedOn = null;
    final early = types && _buzzedOn == q && myBuzzer;
    final iAnswer = early || phase == 'answering' && answering['device'] == widget.room.device;
    final result = asMap(v['result']);

    final teaser = v['mode'] == 'teaser';
    final miss = asMap(v['miss']);
    final question = MissShake(
      trigger: (miss['n'] as num?)?.toInt(),
      child: _question(v, compact: iAnswer),
    );

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
      final teamName = me.team < asList(v['teams']).length ? '${asMap(asList(v['teams'])[me.team])['name'] ?? ''}' : '';
      // The host's own buzzer, filling the rest of the screen like it does there.
      final buzzer = TeamBuzzer(
            name: faceOff.isEmpty ? teamName : '${me.name} · $teamName',
            colorIndex: colour,
            enabled: !buzzed,
            locked: false,
            onBuzz: () {
              s.haptic(HapticStrength.heavy);
              // A player who types: the keyboard comes up with the buzz, so
              // it's already there when the answer box appears.
              if (types) primeKeyboard();
              setState(() => _buzzedOn = q);
              widget.room.buzz(q);
              // The main phone should take it within a second; if it
              // hasn't (asleep, lost signal), let them buzz again.
              Future.delayed(const Duration(seconds: 3), () {
                if (!mounted || _buzzedOn != q) return;
                final v = widget.room.view;
                if ('${v['q']}' == q && v['phase'] == 'open') {
                  setState(() => _buzzedOn = null);
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                      content: Text('The main phone didn’t get that - keep it open and buzz again')));
                }
              });
            },
          );
      // The teaser: a smaller buzzer under the question, like the main
      // phone's team buttons. Other games: it fills the rest of the screen.
      action = teaser
          ? Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Align(alignment: Alignment.topCenter, child: SizedBox(height: 150, child: buzzer)),
            )
          : Padding(
              padding: const EdgeInsets.all(12),
              child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 180), child: buzzer),
            );
    } else if (phase == 'ready') {
      action = _status(faceOff.isEmpty ? 'GET READY…' : 'FACE-OFF: ${faceOff.values.join(' v ')}\nGet ready…');
    } else if (phase == 'answering') {
      action = _status('${answering['name'] ?? ''} is answering…'.toUpperCase());
    } else if (phase == 'open' && faceOff.isNotEmpty && !inFaceOff) {
      action = _status('FACE-OFF: ${faceOff.values.join(' v ')}\nOnly they can buzz');
    } else if (phase == 'open') {
      action = _status(teaser ? 'YOUR TEAM’S HAD ITS GUESS' : 'LOCKED OUT - WAIT FOR THE STEAL');
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
                : 'Hands off - no helping!',
          ),
        ),
      ]);
    }

    final clock = ValueListenableBuilder<double>(
      valueListenable: _left,
      builder: (context, left, _) => TimerBar(fraction: _total == 0 ? 0 : left / _total, seconds: left),
    );

    // The teaser looks like the main phone's: HALF-TIME / THE TEASER, the
    // clock, the question, then the buzzer. Typing an answer, the heading
    // and question fold away so the name suggestions show.
    if (teaser) {
      final qv = asMap(v['question']);
      final clockOn = phase == 'answering' || (phase == 'open' && qv['noClock'] != true);
      return ValueListenableBuilder<bool>(
        valueListenable: answerTyping,
        builder: (context, typing, _) {
          final folded = typing && iAnswer;
          return CustomScrollView(slivers: [
            SliverList(
              delegate: SliverChildListDelegate([
                Collapse(
                  hidden: folded,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                    child: Column(children: [
                      if (qv['halfTime'] == true) Text('HALF-TIME', style: AppText.label(16, color: Palette.gold)),
                      Text('THE TEASER', style: AppText.headline(44, color: Palette.gold)),
                    ]),
                  ),
                ),
                if (clockOn)
                  Padding(
                    padding: EdgeInsets.fromLTRB(18, folded ? 12 : 0, 18, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (phase == 'answering') Text('ANSWER CLOCK', style: AppText.label(15)),
                      clock,
                    ]),
                  ),
                Collapse(hidden: folded, child: question),
              ]),
            ),
            SliverFillRemaining(hasScrollBody: false, child: action),
          ]);
        },
      );
    }

    // Everything above scrolls if it must; the action (the buzzer, the answer
    // box) fills whatever's left of the screen.
    return CustomScrollView(slivers: [
      SliverList(delegate: SliverChildListDelegate([
      _scores(v['teams'], round: '${v['round'] ?? ''}', highlight: (answering['team'] as num?)?.toInt()),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
        child: Row(children: [
          Text('${v['title'] ?? ''}', style: AppText.label(15, color: Palette.yellow)),
          const SizedBox(width: 8),
          if ('${v['n'] ?? ''}'.isNotEmpty) Text('Q ${v['n']}', style: AppText.label(15)),
        ]),
      ),
      // Above the answer box, compact while answering — like the host, so
      // it stays in view over the keyboard.
      question,
      if (phase == 'answering' || (phase == 'open' && asMap(v['question'])['noClock'] != true))
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Same label as the host's ("FINAL CHANCE", "NEXT CLUB IN").
            // Buzzed here, not yet confirmed by the main phone (the box is
            // already up for the keyboard): no label - not "BUZZ IN" over an answer box.
            if ((phase == 'answering'
                    ? 'ANSWER CLOCK'
                    : early
                        ? null
                        : asMap(v['question'])['clock'])
                case final String label)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(label, style: AppText.label(15)),
              ),
            clock,
          ]),
        ),
      ])),
      SliverFillRemaining(hasScrollBody: false, child: action),
    ]);
  }

  /// Someone's turn in XI Bomb, Tic-Tac-Toe, Pointless, 501 or Bidding War,
  /// drawn with the host's own layout for that game: theirs to play on this
  /// phone, or theirs to watch.
  /// The last "try another" nudge shown from the main phone.
  Object? _nudgeSeen;

  Widget _turn(Map<String, Object?> v, int colour) {
    _syncClock(v);
    // "Already used - try another" for this phone's answer: the answer box
    // wiggles and shows it (PlayerPicker), once per nudge.
    final nudge = asMap(v['nudge']);
    if (nudge['n'] != null && nudge['n'] != _nudgeSeen) {
      _nudgeSeen = nudge['n'];
      final text = '${nudge['t'] ?? ''}';
      WidgetsBinding.instance.addPostFrameCallback((_) => nudgeAnswer(text));
    }
    final s = AppScope.of(context);
    final q = '${v['q']}';
    final stage = '${v['stage']}';
    final who = asMap(v['who']);
    final whoName = '${who['name'] ?? ''}';
    final whoTeam = (who['team'] as num?)?.toInt();
    final mine = q.isNotEmpty && who['device'] == widget.room.device;
    final teamsV = asList(v['teams']);
    final whoColour =
        whoTeam != null && whoTeam < teamsV.length ? (asMap(teamsV[whoTeam])['color'] as num?)?.toInt() ?? 0 : colour;
    final board = asMap(v['board']);
    final scores = _scores(v['teams'],
        round: '${v['round'] ?? ''}', highlight: whoTeam, extra: [for (final e in asList(v['extra'])) '$e']);

    Widget clock() => ValueListenableBuilder<double>(
          valueListenable: _left,
          builder: (context, left, _) => TimerBar(fraction: _total == 0 ? 0 : left / _total, seconds: left),
        );

    // The answer box when it's this phone's turn; who's playing otherwise.
    Widget answerBox() {
      if (!mine || stage != 'answer') {
        return whoName.isEmpty ? const SizedBox.shrink() : OnTheirPhone(name: whoName);
      }
      final ids = {for (final a in asList(v['answers'])) '$a'};
      return PlayerPicker(
        key: ValueKey('turn-$q'),
        index: v['clubs'] == true ? s.repo.clubIndex : s.repo.players,
        voice: s.voice,
        accent: Palette.team(whoColour),
        hint: '${v['hint'] ?? 'Say or type a name…'}',
        rapid: v['rapid'] == true,
        showFlags: v['flags'] != false,
        showPositions: v['positions'] != false,
        isAnswer: (p) => ids.contains(p.id),
        onPick: (p) => widget.room.answer(q, p.id),
        onPass: v['rapid'] == true ? null : () => widget.room.pass(q),
      );
    }

    Widget clockAndBox() => Column(children: [
          if (v['left'] != null) clock(),
          const SizedBox(height: 8),
          answerBox(),
        ]);

    switch (v['game']) {
      case 'xi':
        final seconds = (board['seconds'] as num?)?.toDouble() ?? 1;
        return ValueListenableBuilder<double>(
          valueListenable: _left,
          builder: (context, left, _) => XiLayout(
            data: board,
            typing: answerTyping.value && board['phase'] == 'ticking',
            scores: scores,
            left: board['phase'] == 'ticking' && v['left'] != null ? left : seconds,
            startLabel: 'STARTING…',
            passing: false,
            answerBox: answerBox(),
          ),
        );
      case 'ttt':
        final choosing = stage == 'choose';
        Widget bottom;
        if (stage == 'wait') {
          // Round over: tap any square to see its answers (sent by the main phone).
          bottom = board['phase'] == 'finished'
              ? (board['missed'] == null
                  ? const SizedBox.shrink()
                  : Text('TAP A SQUARE TO SEE ITS ANSWERS',
                      textAlign: TextAlign.center, style: AppText.label(13, color: Palette.yellow)))
              : _status('${v['headline'] ?? ''}'.toUpperCase());
        } else if (choosing && !mine) {
          bottom = OnTheirPhone(name: whoName, what: 'is picking a square');
        } else if (choosing) {
          bottom = Column(children: [
            Text('YOUR GO - TAP A SQUARE', textAlign: TextAlign.center, style: AppText.headline(24, color: Palette.yellow)),
            const SizedBox(height: 6),
            if (v['left'] != null) ...[clock(), const SizedBox(height: 8)],
            OutlinedButton.icon(
              onPressed: () => widget.room.pass(q),
              icon: const Icon(Icons.skip_next_rounded),
              label: Text("DON'T KNOW ANY - PASS", style: AppText.label(15, color: Palette.text)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Palette.text,
                side: const BorderSide(color: Palette.line),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ]);
        } else {
          bottom = Column(children: [
            Text('${v['headline'] ?? ''}', textAlign: TextAlign.center, style: AppText.headline(20, color: Palette.yellow)),
            const SizedBox(height: 6),
            clockAndBox(),
          ]);
        }
        // The board stays folded until the keyboard's fully gone (KeyboardSettle).
        return KeyboardSettle(
          active: answerTyping.value && stage == 'answer',
          builder: (context, folded) => Column(children: [
            // Typing: the scores make way, so the suggestions show above the keyboard.
            Collapse(hidden: folded, child: scores),
            Expanded(
              child: TttLayout(
                // At the end, each square shows how many answers it had.
                data: board['missed'] != null ? {...board, 'counts': board['totals']} : board,
                typing: folded,
                bottom: bottom,
                onTap: mine && choosing ? (i) => widget.room.answer(q, 'choice:$i') : null,
                onReveal: board['missed'] == null ? null : (i) => _squareAnswers(board, i),
              ),
            ),
          ]),
        );
      case 'top10':
        return Column(children: [
          // Typing: the scores make way, so the suggestions show above the keyboard.
          Collapse(hidden: answerTyping.value && stage == 'answer', child: scores),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Top10Layout(
                data: board,
                typing: answerTyping.value && stage == 'answer',
                // Round over: the list shows who found how many instead.
                bottom: stage != 'wait'
                    ? clockAndBox()
                    : board['finished'] == true
                        ? const SizedBox.shrink()
                        : _status('${v['headline'] ?? ''}'.toUpperCase()),
              ),
            ),
          ),
        ]);
      case 'pt':
        return Column(children: [
          // Typing: the scores make way, so the suggestions show above the keyboard.
          Collapse(hidden: answerTyping.value && stage == 'answer', child: scores),
          Expanded(child: PtLayout(data: board, typing: answerTyping.value, answerBox: clockAndBox())),
        ]);
      case 'co':
        return Column(children: [
          // Typing: the scores make way, so the suggestions show above the keyboard.
          Collapse(hidden: answerTyping.value && stage == 'answer', child: scores),
          Expanded(child: CoLayout(data: board, typing: answerTyping.value, answerBox: clockAndBox())),
        ]);
      case 'bid':
        final phase = '${board['phase']}';
        return Column(children: [
          if (phase == 'bidding' || phase == 'finished') Collapse(hidden: answerTyping.value && stage == 'answer', child: scores),
          Expanded(
            child: BidLayout(
              data: board,
              controls: mine && stage == 'bid'
                  ? BidControls(
                      data: board,
                      onRaise: (n) => widget.room.answer(q, 'act:raise:$n'),
                      onChallenge: () => widget.room.answer(q, 'act:challenge'),
                      onPass: () => widget.room.answer(q, 'act:pass'),
                    )
                  : whoName.isEmpty
                      ? const SizedBox.shrink()
                      : OnTheirPhone(name: whoName, what: 'is deciding'),
              answerBox: clockAndBox(),
            ),
          ),
        ]);
    }
    return _center('EYES ON THE MAIN SCREEN', '${v['headline'] ?? ''}', scores: v['teams']);
  }

  /// One square's answers at the end of Noughts & Crosses.
  void _squareAnswers(Map<String, Object?> board, int i) {
    final rows = asList(board['rows']), cols = asList(board['cols']);
    final missed = asList(board['missed']);
    final totals = asList(board['totals']);
    final claimed = asList(board['claimed']);
    showSquareAnswers(
      context,
      title: '${i ~/ 3 < rows.length ? rows[i ~/ 3] : ''}  +  ${i % 3 < cols.length ? cols[i % 3] : ''}',
      names: [for (final n in i < missed.length ? asList(missed[i]) : const []) '$n'],
      total: i < totals.length ? (totals[i] as num?)?.toInt() ?? 0 : 0,
      named: i < claimed.length && '${claimed[i]}'.isNotEmpty ? '${claimed[i]}' : null,
    );
  }

  Widget _status(String text) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, textAlign: TextAlign.center, style: AppText.headline(20, color: Palette.muted)),
      );
}

/// iPhone and iPad browsers only: their speech recognition struggles with
/// unusual names, and the app knows every player's name. Shows once the
/// App Store listing is live ([appStoreUrl]). Android browsers are about as
/// good as the app, so they see nothing.
class _AppNudge extends StatelessWidget {
  const _AppNudge();

  static bool get shows => kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && appStoreUrl != null;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => openLink(appStoreUrl!),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: [
            const Icon(Icons.download_rounded, size: 15, color: Palette.gold),
            const SizedBox(width: 4),
            Expanded(
              child: Text('Download the app for better voice recognition on unusual names',
                  style: AppText.label(12, color: Palette.gold)),
            ),
          ]),
        ),
      );
}
