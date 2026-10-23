import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/theme.dart';
import '../domain/game_mode.dart';
import '../ui/widgets/buzzer_pad.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/player_picker.dart';
import 'buzz_race_controller.dart';
import 'game_screen_support.dart';

/// Layout shared by buzzer games (Club Connections, Career Path):
/// scoreboard → question → timer → buzzers / answer box / result.
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
  });

  final RoundContext round;
  final BuzzRaceController controller;
  final Widget question;
  final Widget resolvedDetail;
  final String timerLabel;
  final String? commentary;
  final VoidCallback onFinished;
  final bool allowDispute;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = round.tournament;
    final services = AppScope.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: PitchBackground(
        child: SafeArea(
          child: Column(children: [
            Scoreboard(tournament: t, highlightTeam: c.answeringTeam),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: Row(children: [
                Text(c.mode.title.toUpperCase(), style: AppText.label(16, color: Palette.lime)),
                const SizedBox(width: 10),
                Text('Q ${c.questionIndex + 1}/${c.questions.length}', style: AppText.label(16)),
                const Spacer(),
                if (round.multiplier > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: Palette.gold, borderRadius: BorderRadius.circular(8)),
                    child: Text('x${round.multiplier} POINTS', style: AppText.headline(16, color: Palette.pitchDeep)),
                  ),
              ]),
            ),
            CommentaryBanner(text: commentary),
            question,
            if (c.phase == BuzzPhase.open || c.phase == BuzzPhase.answering)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.phase == BuzzPhase.answering ? 'ANSWER CLOCK' : timerLabel, style: AppText.label(12)),
                  const SizedBox(height: 4),
                  TimerBar(fraction: c.secondsLeft / c.phaseSeconds, seconds: c.secondsLeft),
                ]),
              ),
            Expanded(child: _bottom(context, services)),
          ]),
        ),
      ),
    );
  }

  Widget _bottom(BuildContext context, AppServices services) {
    final c = controller;
    final t = round.tournament;
    if (c.phase == BuzzPhase.open) {
        return Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: BuzzerPad(tournament: t, canBuzz: c.canBuzz, onBuzz: c.buzz, lockedOut: c.lockedOut),
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
              TeamChip(name: t.teamName(team), colorIndex: colour, size: 20),
              const SizedBox(width: 10),
              Text('YOUR ANSWER', style: AppText.headline(22)),
            ]),
            const SizedBox(height: 10),
            PlayerPicker(
              key: ValueKey('pick-${c.questionIndex}-$team-${c.lockedOut.length}'),
              index: services.repo.players,
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
              TeamChip(name: t.teamName(o.team!), colorIndex: t.config.teams[o.team!].colorIndex, size: 22),
              const SizedBox(height: 8),
              Text('+${o.points * round.multiplier}', style: AppText.headline(64, color: Palette.lime)),
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
        body: PitchBackground(child: Center(child: CircularProgressIndicator(color: Palette.lime))),
      );
}
