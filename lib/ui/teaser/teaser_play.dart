import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../domain/player_index.dart';
import '../../domain/tournament.dart';
import '../../games/buzz_race_controller.dart';
import '../../games/teaser/teaser_controller.dart';
import '../widgets/common.dart';
import '../widgets/player_picker.dart';
import 'teaser_widgets.dart';

/// The working part of the teaser, used at half-time and between games:
/// team buzzers, the answer box, the host's calls, and the result.
class TeaserPlay extends StatelessWidget {
  const TeaserPlay({super.key, required this.controller, this.remoteAnswerer, this.showQuestion = true});
  final TeaserController controller;

  /// False where the question is already on screen above (half-time).
  final bool showQuestion;

  /// Answering on their own phone (null = on this one).
  final String? remoteAnswerer;

  Tournament get t => controller.tournament;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.state;
    if (c.phase == BuzzPhase.resolved) {
      return s.status == TeaserStatus.solved ? _solved() : _revealed(context);
    }
    if (c.phase == BuzzPhase.answering) {
      final team = c.answeringTeam!;
      final colour = t.config.teams[team].colorIndex;
      if (remoteAnswerer != null) return OnTheirPhone(name: remoteAnswerer!);
      final call = c.hostCall;
      if (call != null) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text('HOST’S CALL', style: AppText.label(14, color: Palette.gold)),
          const SizedBox(height: 6),
          Text(call.name.toUpperCase(), textAlign: TextAlign.center, style: AppText.headline(30)),
          const SizedBox(height: 4),
          Text('Fits on paper, but we couldn’t confirm it. Does it count?',
              textAlign: TextAlign.center, style: AppText.label(14, color: Palette.text)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: BigButton(label: 'Counts', icon: Icons.check, height: 54, onPressed: () => c.decide(counts: true))),
            const SizedBox(width: 10),
            Expanded(
                child: BigButton(
                    label: 'Doesn’t',
                    icon: Icons.close,
                    height: 54,
                    color: Palette.danger,
                    textColor: Colors.white,
                    onPressed: () => c.decide(counts: false))),
          ]),
        ]);
      }
      final services = AppScope.read(context);
      return TeaserBuzzed(
        team: t.teamName(team),
        colorIndex: colour,
        secondsLeft: c.secondsLeft,
        answerBox: PlayerPicker(
          key: ValueKey('teaser-$team-${c.lockedOut.length}'),
          index: services.repo.players,
          voice: services.voice,
          accent: Palette.team(colour),
          onPick: c.submit,
          isAnswer: c.isRightAnswer,
          onPass: c.pass,
          onDisputed: (typed, allowed) => c.submitDisputed(allowed: allowed, typed: typed),
        ),
      );
    }
    // Open: who's buzzing?
    final teams = [for (var i = 0; i < t.teamCount; i++) (t.teamName(i), t.config.teams[i].colorIndex)];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (c.lastMiss != null) _miss(),
      if (c.clockDone)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('TIME! IT STAYS OPEN BETWEEN GAMES - FOR 3 POINTS',
              textAlign: TextAlign.center, style: AppText.headline(22, color: Palette.gold)),
        )
      else
        TeaserTeams(teams: teams, locked: c.lockedOut, onPick: c.buzz),
    ]);
  }

  /// "✗ Gary Cahill — HOME have had their guess", with the host's overrule.
  Widget _miss() {
    final c = controller;
    final team = c.lastWrongTeam;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('✗ ${c.lastMiss}${team == null ? '' : ' - ${t.teamName(team).toUpperCase()} HAVE HAD THEIR GUESS'}',
            textAlign: TextAlign.center, style: AppText.label(14, color: Palette.danger)),
        if (c.canOverrule) _countIt(),
      ]),
    );
  }

  /// "We missed Gary Cahill? Count it": small, for when our data is missing a
  /// right answer. The host taps it to give the points.
  Widget _countIt() {
    final c = controller;
    return TextButton(
      onPressed: c.overrule,
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: 'We missed ${c.lastMiss}? ', style: const TextStyle(color: Palette.muted, fontSize: 12)),
          const TextSpan(
              text: 'Count it',
              style: TextStyle(color: Palette.muted, fontSize: 12, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
        ]),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _solved() {
    final s = controller.state;
    final team = s.winner ?? 0;
    final others = [
      for (final n in controller.teaser.answerNames)
        if (n.toLowerCase() != s.winningAnswer.toLowerCase()) n,
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      TeamChip(name: t.teamName(team), colorIndex: t.config.teams[team].colorIndex, size: 22),
      const SizedBox(height: 6),
      Text('+${s.points}', style: AppText.headline(60, color: Palette.yellow)),
      Text(s.winningAnswer.toUpperCase(), textAlign: TextAlign.center, style: AppText.headline(30)),
      if (others.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(others.length == 1 ? 'THE OTHER ANSWER' : 'ALSO RIGHT', style: AppText.label(13)),
        const SizedBox(height: 4),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          for (final n in others) Chip(label: Text(n), backgroundColor: Palette.card),
        ]),
      ],
    ]);
  }

  Widget _revealed(BuildContext context) {
    final c = controller;
    final herrings = _herrings(c, AppScope.read(context).repo.players);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      TeaserReveal(question: c.teaser.question, answers: c.teaser.answerNames, showQuestion: showQuestion),
      if (herrings.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('NOT THESE', style: AppText.label(13)),
        const SizedBox(height: 4),
        for (final (name, why) in herrings)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('$name - $why', textAlign: TextAlign.center, style: AppText.label(13, color: Palette.text)),
          ),
      ],
      // The last wrong guess, in case our data missed it: small, under the answer.
      if (c.lastMiss != null && c.canOverrule) ...[const SizedBox(height: 12), _countIt()],
    ]);
  }

  /// Red herrings worth showing: (name, why not), a few at most.
  List<(String, String)> _herrings(TeaserController c, PlayerIndex players) => [
        for (final e in c.teaser.herrings.entries.take(3))
          if (players.byId(e.key) case final p?)
            (p.name, e.value.length > 140 ? '${e.value.substring(0, 137)}…' : e.value),
      ];
}
