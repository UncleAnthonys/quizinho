import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/theme.dart';
import '../domain/game_mode.dart';
import '../domain/tournament.dart';
import '../ui/widgets/buzzer_pad.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/player_picker.dart';
import 'buzz_race_controller.dart';
import 'game_screen_support.dart';

/// Layout shared by buzzer games (Club Connections, Career Path).
///
/// Portrait: scoreboard → question → timer → buzzers / answer box / result.
/// Landscape ("table mode"): phone flat between two players — each team's
/// buzzer runs down a short end facing its player, the question sits in the
/// middle. Switches automatically when the phone is turned.
class BuzzGameView extends StatelessWidget {
  const BuzzGameView({
    super.key,
    required this.round,
    required this.controller,
    required this.question,
    required this.resolvedDetail,
    required this.timerLabel,
    required this.commentary,
    required this.onFinished,
    this.allowDispute = false,
    this.faceOff,
    this.awaitingFaceOff = false,
    this.onFaceOffReady,
  });

  final RoundContext round;
  final BuzzRaceController controller;
  /// The question, drawn [compact] in table mode where height is tight.
  final Widget Function(bool compact) question;
  final Widget resolvedDetail;
  final String timerLabel;
  final String? commentary;
  final VoidCallback onFinished;
  final bool allowDispute;

  /// Set when this question is a head-to-head between named players.
  final FaceOff? faceOff;

  /// Show the face-off intro instead of the question until [onFaceOffReady].
  final bool awaitingFaceOff;
  final VoidCallback? onFaceOffReady;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(
        listenable: Listenable.merge([round.tournament, answerTyping]),
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final c = controller;
    final t = round.tournament;
    final services = AppScope.of(context);
    final size = MediaQuery.sizeOf(context);
    final deviceSideways = size.width > size.height;
    // Answering: the clock, the answer box and the question — always upright.
    // In table mode the answer box must not be drawn sideways: phone browsers
    // can't type into a rotated box (keyboard glitches), so the answering
    // player gets an upright screen, then it flips back to table mode.
    final answeringUpright = c.phase == BuzzPhase.answering && (answerTyping.value || t.tableMode || deviceSideways);
    if (answeringUpright) {
      return Scaffold(
        resizeToAvoidBottomInset: true,
        body: PitchBackground(
          child: SafeArea(
            // Answer box and its drop-down go first, right under the clock, so
            // the keyboard can only ever cover the question, never what you type.
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TimerBar(fraction: c.secondsLeft / c.phaseSeconds, seconds: c.secondsLeft, height: 10),
              ),
              Flexible(fit: FlexFit.loose, child: _bottom(context, services)),
              Expanded(child: SingleChildScrollView(child: question(true))),
            ]),
          ),
        ),
      );
    }
    if (deviceSideways || t.tableMode) {
      // Phone turned sideways: draw as-is. Table mode chosen on an upright
      // phone (rotation lock, browser tab): draw it turned for them.
      return Scaffold(
        resizeToAvoidBottomInset: true,
        body: PitchBackground(
          child: SafeArea(
            child: RotatedBox(
              quarterTurns: deviceSideways ? 0 : 1,
              child: _tableMode(context, services, canExit: !deviceSideways),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: PitchBackground(
        child: SafeArea(
          child: Column(children: [
            Scoreboard(tournament: t, highlightTeam: c.answeringTeam),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: Row(children: [
                Text(c.mode.title.toUpperCase(), style: AppText.label(16, color: Palette.yellow)),
                const SizedBox(width: 10),
                Text('Q ${c.questionIndex + 1}/${c.questions.length}', style: AppText.label(16)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => t.tableMode = true,
                  icon: const Icon(Icons.table_restaurant_rounded, color: Palette.yellow, size: 20),
                  label: Text('TABLE MODE', style: AppText.label(13, color: Palette.yellow)),
                ),
                if (round.multiplier > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: Palette.gold, borderRadius: BorderRadius.circular(8)),
                    child: Text('x${round.multiplier} POINTS', style: AppText.headline(16, color: Palette.pitchDeep)),
                  ),
              ]),
            ),
            if (awaitingFaceOff && faceOff != null)
              Expanded(
                child: _FaceOffIntro(
                  faceOff: faceOff!,
                  tournament: t,
                  questionNumber: c.questionIndex + 1,
                  onReady: onFaceOffReady,
                ),
              )
            else ...[
            CommentaryBanner(text: commentary),
            if (faceOff != null && (c.phase == BuzzPhase.open || c.phase == BuzzPhase.answering))
              _FaceOffBanner(faceOff: faceOff!, tournament: t),
            question(false),
            if (c.phase == BuzzPhase.open || c.phase == BuzzPhase.answering)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.phase == BuzzPhase.answering ? 'ANSWER CLOCK' : timerLabel, style: AppText.label(15)),
                  const SizedBox(height: 4),
                  TimerBar(fraction: c.secondsLeft / c.phaseSeconds, seconds: c.secondsLeft),
                ]),
              ),
            Expanded(child: _bottom(context, services)),
            ],
          ]),
        ),
      ),
    );
  }

  /// Landscape: buzzers down both short ends, everything else in the middle.
  Widget _tableMode(BuildContext context, AppServices services, {required bool canExit}) {
    final c = controller;
    final t = round.tournament;
    final left = [for (var i = 0; i < t.teamCount; i += 2) i];
    final right = [for (var i = 1; i < t.teamCount; i += 2) i];

    Widget side(List<int> teams, int quarterTurns) => SizedBox(
          width: 118,
          child: Column(children: [
            for (final team in teams)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: TeamBuzzer(
                    name: faceOff == null
                        ? t.teamName(team)
                        : '${faceOff!.nameFor(team)} · ${t.teamName(team)}',
                    colorIndex: t.config.teams[team].colorIndex,
                    enabled: c.canBuzz(team) && !awaitingFaceOff,
                    locked: c.lockedOut.contains(team),
                    onBuzz: () => c.buzz(team),
                    quarterTurns: quarterTurns,
                  ),
                ),
              ),
          ]),
        );

    Widget centre() {
      if (awaitingFaceOff && faceOff != null) {
        return _TableFaceOffIntro(
          faceOff: faceOff!,
          tournament: t,
          left: left,
          right: right,
          questionNumber: c.questionIndex + 1,
          onReady: onFaceOffReady,
        );
      }
      return Column(children: [
        // compact score line
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
          child: Row(children: [
            Text(c.mode.title.toUpperCase(), style: AppText.label(13, color: Palette.yellow)),
            const SizedBox(width: 8),
            Text('Q ${c.questionIndex + 1}/${c.questions.length}', style: AppText.label(13)),
            if (canExit)
              IconButton(
                tooltip: 'Leave table mode',
                visualDensity: VisualDensity.compact,
                onPressed: () => t.tableMode = false,
                icon: const Icon(Icons.stay_current_portrait_rounded, color: Palette.muted, size: 20),
              ),
            if (round.multiplier > 1) ...[
              const SizedBox(width: 8),
              Text('x${round.multiplier}', style: AppText.label(13, color: Palette.gold)),
            ],
            const Spacer(),
            for (var i = 0; i < t.teamCount; i++)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: TeamChip(name: '${t.teamName(i)} ${t.scores[i]}', colorIndex: t.config.teams[i].colorIndex, size: 13),
              ),
          ]),
        ),
        CommentaryBanner(text: commentary),
        if (faceOff != null && (c.phase == BuzzPhase.open || c.phase == BuzzPhase.answering))
          _FaceOffBanner(faceOff: faceOff!, tournament: t),
        Expanded(
          child: c.phase == BuzzPhase.open
              ? SingleChildScrollView(
                  child: Column(children: [
                    question(true),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                      child: TimerBar(fraction: c.secondsLeft / c.phaseSeconds, seconds: c.secondsLeft, height: 10),
                    ),
                    TextButton(onPressed: c.giveUp, child: Text('NOBODY KNOWS — SKIP', style: AppText.label(13))),
                  ]),
                )
              : Column(children: [
                  if (c.phase == BuzzPhase.answering)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                      child: TimerBar(fraction: c.secondsLeft / c.phaseSeconds, seconds: c.secondsLeft, height: 10),
                    ),
                  Expanded(child: _bottom(context, services)),
                ]),
        ),
      ]);
    }

    return Row(children: [
      side(left, 1),
      Expanded(child: centre()),
      if (right.isNotEmpty) side(right, 3),
    ]);
  }

  Widget _bottom(BuildContext context, AppServices services) {
    final c = controller;
    final t = round.tournament;
    if (c.phase == BuzzPhase.open) {
        return Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: BuzzerPad(
                tournament: t,
                canBuzz: c.canBuzz,
                onBuzz: c.buzz,
                lockedOut: c.lockedOut,
                faceOff: faceOff,
              ),
            ),
          ),
          TextButton(onPressed: c.giveUp, child: Text('NOBODY KNOWS — SKIP', style: AppText.label(14))),
        ]);
    }
    if (c.phase == BuzzPhase.answering) {
        final team = c.answeringTeam!;
        final colour = t.config.teams[team].colorIndex;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: Column(children: [
            Row(children: [
              TeamChip(
                name: faceOff == null ? t.teamName(team) : faceOff!.nameFor(team),
                colorIndex: colour,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text('YOUR ANSWER', style: AppText.headline(22)),
            ]),
            const SizedBox(height: 10),
            PlayerPicker(
              key: ValueKey('pick-${c.questionIndex}-$team-${c.lockedOut.length}'),
              index: services.repo.players,
              voice: services.voice,
              accent: Palette.team(colour),
              onPick: c.submit,
              onPass: c.pass,
              onDisputed: allowDispute ? (_, allowed) => c.submitDisputed(allowed: allowed) : null,
            ),
          ]),
        );
    }
    {
        final o = c.outcome;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(children: [
            if (o != null && o.scored) ...[
              TeamChip(
                name: faceOff == null ? t.teamName(o.team!) : '${faceOff!.nameFor(o.team!)} · ${t.teamName(o.team!)}',
                colorIndex: t.config.teams[o.team!].colorIndex,
                size: 22,
              ),
              const SizedBox(height: 8),
              Text('+${o.points * round.multiplier}', style: AppText.headline(64, color: Palette.yellow)),
              Text(
                o.disputed ? 'Room-approved answer' : o.player!.name,
                textAlign: TextAlign.center,
                style: AppText.headline(30),
              ),
              if (o.bonus) Text('DEEP CUT BONUS', style: AppText.label(15, color: Palette.gold)),
            ] else
              Text('NOBODY GOT IT', style: AppText.headline(40, color: Palette.danger)),
            const SizedBox(height: 12),
            resolvedDetail,
            const SizedBox(height: 16),
            BigButton(
              label: c.isLastQuestion ? 'Finish round' : 'Next question',
              icon: c.isLastQuestion ? Icons.flag : Icons.arrow_forward,
              onPressed: () {
                if (c.isLastQuestion) {
                  c.next();
                  onFinished();
                } else {
                  c.next();
                }
              },
            ),
          ]),
        );
    }
  }
}

/// "FACE-OFF: SAM v JORDAN — only you two".
class _FaceOffBanner extends StatelessWidget {
  const _FaceOffBanner({required this.faceOff, required this.tournament});
  final FaceOff faceOff;
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final teams = faceOff.players.keys.toList()..sort();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.danger.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Text('FACE-OFF', style: AppText.label(16, color: Colors.white)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final (i, team) in teams.indexed) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('v', style: AppText.headline(20, color: Colors.white)),
                ),
              TeamChip(name: faceOff.nameFor(team), colorIndex: tournament.config.teams[team].colorIndex, size: 26),
            ],
          ]),
        ),
        Text('Only these players can answer', style: AppText.label(15, color: Colors.white)),
      ]),
    );
  }
}

/// Full-screen warning before a face-off question, so the two named players
/// can step up before anything is revealed.
class _FaceOffIntro extends StatelessWidget {
  const _FaceOffIntro({
    required this.faceOff,
    required this.tournament,
    required this.questionNumber,
    required this.onReady,
  });
  final FaceOff faceOff;
  final Tournament tournament;
  final int questionNumber;
  final VoidCallback? onReady;

  @override
  Widget build(BuildContext context) {
    final teams = faceOff.players.keys.toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(children: [
        const Spacer(),
        Flexible(
          flex: 8,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (context, v, child) => Transform.scale(scale: v, child: child),
          child: Column(children: [
            const Icon(Icons.flash_on_rounded, color: Palette.danger, size: 56),
            Text('FACE-OFF', style: AppText.headline(64, color: Palette.danger)),
          ]),
        ),
        Text('QUESTION $questionNumber', style: AppText.label(20)),
        const SizedBox(height: 24),
        for (final (i, team) in teams.indexed) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('V', style: AppText.headline(34, color: Palette.muted)),
            ),
          TeamChip(name: faceOff.nameFor(team), colorIndex: tournament.config.teams[team].colorIndex, size: 54),
          const SizedBox(height: 4),
          Text(tournament.teamName(team).toUpperCase(), style: AppText.label(20)),
        ],
        const SizedBox(height: 24),
        const Text(
          'Step up to the phone.\nEveryone else — hands off, no helping!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 23, height: 1.35, color: Palette.text, fontWeight: FontWeight.w600),
        ),
            ]),
          ),
        ),
        const Spacer(),
        BigButton(label: 'Ready — show question', icon: Icons.visibility_rounded, onPressed: onReady),
      ]),
    );
  }
}

/// Table-mode face-off: each named player's name sits big on their own
/// team's side (next to their buzzer), same way up as everything else so the
/// group can read it; FACE-OFF and Ready fill the middle.
class _TableFaceOffIntro extends StatelessWidget {
  const _TableFaceOffIntro({
    required this.faceOff,
    required this.tournament,
    required this.left,
    required this.right,
    required this.questionNumber,
    required this.onReady,
  });
  final FaceOff faceOff;
  final Tournament tournament;
  final List<int> left;
  final List<int> right;
  final int questionNumber;
  final VoidCallback? onReady;

  Widget _names(List<int> teams) => Expanded(
        flex: 2,
        child: Column(children: [
          for (final team in teams)
            if (faceOff.players.containsKey(team))
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        TeamChip(
                          name: faceOff.nameFor(team),
                          colorIndex: tournament.config.teams[team].colorIndex,
                          size: 56,
                        ),
                        const SizedBox(height: 4),
                        Text(tournament.teamName(team).toUpperCase(), style: AppText.label(18)),
                      ]),
                    ),
                  ),
                ),
              ),
        ]),
      );

  @override
  Widget build(BuildContext context) => Row(children: [
        _names(left),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.flash_on_rounded, color: Palette.danger, size: 64),
                    Text('FACE-OFF', style: AppText.headline(96, color: Palette.danger)),
                    Text('QUESTION $questionNumber', style: AppText.label(22)),
                    const SizedBox(height: 10),
                    Text('Everyone else — hands off!', style: AppText.headline(30, weight: FontWeight.w700)),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              BigButton(label: 'Ready — show question', icon: Icons.visibility_rounded, onPressed: onReady, height: 72),
            ]),
          ),
        ),
        if (right.isNotEmpty) _names(right),
      ]);
}

/// Per-question face-off state for buzzer games: rolls a face-off when a new
/// question starts and credits the named player who scores.
class FaceOffTracker {
  FaceOffTracker(this.round);
  final RoundContext round;
  FaceOff? current;
  int _question = -1;
  int _credited = -1;

  /// True while the face-off intro is showing: question hidden, clock frozen.
  bool awaitingReady = false;

  void ready() => awaitingReady = false;

  /// Call once after creating the controller, then on every change.
  void sync(BuzzRaceController c) {
    if (c.questionIndex != _question) {
      _question = c.questionIndex;
      current = round.tournament.maybeFaceOff();
      awaitingReady = current != null;
    }
    final o = c.outcome;
    final f = current;
    if (f != null && o != null && o.scored && c.eventSerial != _credited) {
      _credited = c.eventSerial;
      round.tournament.creditPlayer(o.team!, f.nameFor(o.team!), o.points * round.multiplier);
    }
  }
}

/// Shown when the database has run out of fresh challenges for this mode.
class OutOfChallenges extends StatelessWidget {
  const OutOfChallenges({super.key, required this.mode, required this.onContinue});
  final GameModeId mode;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PitchBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('OUT OF FRESH ${mode.title.toUpperCase()}', textAlign: TextAlign.center, style: AppText.headline(34)),
                const SizedBox(height: 12),
                const Text(
                  'You’ve played every challenge we have for this game in this match. More are coming with the full database.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Palette.muted),
                ),
                const SizedBox(height: 24),
                BigButton(label: 'Spin again', onPressed: onContinue),
              ]),
            ),
          ),
        ),
      );
}

class LoadingRound extends StatelessWidget {
  const LoadingRound({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: PitchBackground(child: Center(child: CircularProgressIndicator(color: Palette.yellow))),
      );
}
