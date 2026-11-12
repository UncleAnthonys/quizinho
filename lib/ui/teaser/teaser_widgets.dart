import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../widgets/common.dart';

/// The Half-Time Teaser: one slow-burn question per tournament. Shown full
/// screen at half-time with a 90-second clock (5 points), then kept open
/// between games (never during one) behind [TeaserChip] for 3 points, until
/// someone gets it, every team has had its one guess, or full time. A team
/// buzzes, then has 15 seconds to answer.

/// The question itself, as a card.
class TeaserPrompt extends StatelessWidget {
  const TeaserPrompt({super.key, required this.question, this.prefix = 'NAME A PLAYER WHO…', this.halfTime = false, this.compact = false});

  /// "Name a player who…" — the rest of the sentence.
  final String question;

  /// "NAME A PLAYER WHO…", or "NAME A MANAGER WHO…".
  final String prefix;

  /// During the half-time clock: 5 points now, 3 later.
  final bool halfTime;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(18, compact ? 14 : 20, 18, compact ? 14 : 20),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Palette.gold.withValues(alpha: 0.7), width: 2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(prefix, style: AppText.label(compact ? 13 : 15, color: Palette.gold)),
          SizedBox(height: compact ? 6 : 10),
          Text(question.toUpperCase(),
              textAlign: TextAlign.center, style: AppText.headline(compact ? 24 : 32, weight: FontWeight.w800)),
          SizedBox(height: compact ? 8 : 12),
          Text(halfTime ? 'WORTH 5 POINTS · DROPS TO 3 WHEN THE CLOCK RUNS OUT' : 'WORTH 3 POINTS · ONE GUESS PER TEAM',
              textAlign: TextAlign.center, style: AppText.label(compact ? 12 : 14, color: Palette.yellow)),
        ]),
      );
}

/// Who's buzzing in. Each team gets one guess: a wrong one locks them out.
class TeaserTeams extends StatelessWidget {
  const TeaserTeams({super.key, required this.teams, this.locked = const {}, this.onPick});

  /// (name, colour index).
  final List<(String, int)> teams;
  final Set<int> locked;
  final ValueChanged<int>? onPick;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('GOT IT? BUZZ IN', style: AppText.label(15, color: Palette.text)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
          for (final (i, (name, color)) in teams.indexed)
            Opacity(
              opacity: locked.contains(i) ? 0.35 : 1,
              child: Material(
                color: Palette.team(color),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: locked.contains(i) ? null : () => onPick?.call(i),
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(children: [
                      Text(name.toUpperCase(), style: AppText.headline(26, color: Palette.onTeam(color))),
                      if (locked.contains(i))
                        Text('LOCKED OUT', style: AppText.label(12, color: Palette.onTeam(color))),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ]);
}

/// Between games only: the teaser's still open. Tap to have a go.
class TeaserChip extends StatelessWidget {
  const TeaserChip({super.key, required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Palette.gold, width: 2),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(color: Palette.gold, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('?', style: AppText.headline(24, color: Palette.pitchDeep)),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('HALF-TIME TEASER', style: AppText.headline(20, color: Palette.gold)),
                Text('STILL UNSOLVED · TAP TO ANSWER', style: AppText.label(11, color: Palette.text)),
              ]),
            ]),
          ),
        ),
      );
}

/// The half-time screen: the question, the clock, and who's answering.
class TeaserHalfTime extends StatelessWidget {
  const TeaserHalfTime({
    super.key,
    required this.question,
    required this.fraction,
    required this.seconds,
    required this.bottom,
    this.onLater,
  });

  final String question;
  final double fraction;
  final double seconds;

  /// Team buttons, or the answer box once a team's answering.
  final Widget bottom;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(children: [
          Text('HALF-TIME', style: AppText.label(16, color: Palette.gold)),
          Text('THE TEASER', style: AppText.headline(48, color: Palette.gold)),
          const SizedBox(height: 14),
          TimerBar(fraction: fraction, seconds: seconds),
          const SizedBox(height: 16),
          TeaserPrompt(question: question, halfTime: true),
          const SizedBox(height: 18),
          Expanded(child: SingleChildScrollView(child: bottom)),
          if (onLater != null)
            GhostButton(label: 'Keep thinking – second half', icon: Icons.sports_soccer, onPressed: onLater),
          Text('It stays open between games until someone gets it', style: AppText.label(12)),
        ]),
      );
}

/// A team has buzzed: 15 seconds to give a name.
class TeaserBuzzed extends StatelessWidget {
  const TeaserBuzzed({super.key, required this.team, required this.colorIndex, required this.secondsLeft, required this.answerBox});
  final String team;
  final int colorIndex;
  final double secondsLeft;
  final Widget answerBox;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        TeamChip(name: '$team buzzed', colorIndex: colorIndex, size: 20),
        const SizedBox(height: 10),
        TimerBar(fraction: secondsLeft / 15, seconds: secondsLeft, height: 10),
        const SizedBox(height: 10),
        answerBox,
      ]);
}

/// Nobody got it (every team guessed wrong, or full time): the answers.
class TeaserReveal extends StatelessWidget {
  const TeaserReveal(
      {super.key, required this.question, required this.answers, this.headline = 'NOBODY GOT IT', this.showQuestion = true});
  final String question;

  /// False where the question is already on screen (half-time).
  final bool showQuestion;
  final List<String> answers;
  final String headline;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(headline, style: AppText.headline(34, color: Palette.gold)),
        const SizedBox(height: 10),
        if (showQuestion) ...[
          TeaserPrompt(question: question, compact: true),
          const SizedBox(height: 14),
        ],
        Text(answers.length == 1 ? 'THE ANSWER' : 'ANY OF THESE', style: AppText.label(14)),
        const SizedBox(height: 6),
        for (final a in answers) Text(a.toUpperCase(), style: AppText.headline(28)),
      ]);
}

/// A joined phone: its own buzzer for the teaser.
class TeaserPhoneBuzzer extends StatelessWidget {
  const TeaserPhoneBuzzer({super.key, required this.team, required this.colorIndex, this.onBuzz});
  final String team;
  final int colorIndex;
  final VoidCallback? onBuzz;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(team.toUpperCase(), style: AppText.label(15, color: Palette.team(colorIndex))),
        const SizedBox(height: 8),
        BigButton(label: 'I know it!', icon: Icons.front_hand, height: 96, color: Palette.team(colorIndex),
            textColor: Palette.onTeam(colorIndex), onPressed: onBuzz),
      ]);
}
