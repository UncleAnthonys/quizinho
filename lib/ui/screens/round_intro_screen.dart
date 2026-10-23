import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../match_flow.dart';
import '../widgets/common.dart';

/// Ten-second rules card before each game. No long tutorials.
class RoundIntroScreen extends StatelessWidget {
  const RoundIntroScreen({super.key, required this.tournament, required this.mode, required this.multiplier});
  final Tournament tournament;
  final GameModeId mode;
  final int multiplier;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: Column(children: [
            Scoreboard(tournament: tournament),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 12), children: [
                Icon(mode.icon, color: mode.color, size: 56),
                const SizedBox(height: 8),
                Text(mode.title.toUpperCase(), textAlign: TextAlign.center, style: AppText.headline(48, color: mode.color)),
                Text(mode.tagline, textAlign: TextAlign.center, style: const TextStyle(color: Palette.muted, fontSize: 16)),
                if (multiplier > 1) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: Palette.gold, borderRadius: BorderRadius.circular(10)),
                      child: Text('WILDCARD · DOUBLE POINTS', style: AppText.headline(20, color: Palette.pitchDeep)),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                for (final (i, rule) in mode.rules.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: mode.color, shape: BoxShape.circle),
                        child: Text('${i + 1}', style: AppText.headline(18, color: Palette.pitchDeep)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(rule, style: const TextStyle(fontSize: 18, height: 1.35))),
                    ]),
                  ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.people_alt_rounded, color: Palette.gold),
                    const SizedBox(width: 10),
                    Expanded(child: Text(mode.whoPlays, style: const TextStyle(fontSize: 16, color: Palette.text))),
                  ]),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: BigButton(
                label: 'Kick off',
                icon: Icons.sports_soccer,
                onPressed: () {
                  final s = AppScope.read(context);
                  s.sound.play(Sfx.whistle);
                  s.haptic(HapticStrength.medium);
                  MatchFlow.toGame(context, tournament, mode, multiplier);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
