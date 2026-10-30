import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../../games/survival/survival_screen.dart';
import '../../multiplayer/guest_screen.dart';
import '../../multiplayer/rooms_config.dart';
import '../match_access.dart';
import '../match_flow.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final demo = services.repo.dataStatus == 'demo_unverified';
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.settings_rounded, color: Palette.muted, size: 28),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                ),
              ),
              const Spacer(flex: 1),
              // Logo block shrinks to fit short screens rather than overflowing.
              Flexible(
                flex: 12,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 360,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const QuizinhoBadge(size: 140),
                      const SizedBox(height: 18),
                      const QuizinhoWordmark(),
                      const SizedBox(height: 6),
                      Text('THE FOOTBALL PARTY GAME', style: AppText.label(18, color: Palette.yellow)),
                      const SizedBox(height: 18),
                      const Text(
                        'One-on-one or split into teams. A different game every round — buzz in, steal points, and Quizinho keeps the score.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Palette.muted, fontSize: 16, height: 1.4),
                      ),
                    ]),
                  ),
                ),
              ),
              const Spacer(flex: 2),
              const _ResumeMatch(),
              BigButton(
                label: 'Head to head',
                icon: Icons.groups_rounded,
                height: 72,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetupScreen())),
              ),
              const SizedBox(height: 6),
              Text('2 players or up to 6 teams', style: AppText.label(13)),
              const SizedBox(height: 10),
              // Solo is the side door: smaller and outlined, so the party game leads.
              SizedBox(
                height: 46,
                width: 240,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Palette.line, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.person_rounded, color: Palette.yellow, size: 20),
                  label: Text('PLAY SOLO · SURVIVAL', style: AppText.headline(18)),
                  onPressed: () async {
                    if (!await MatchAccess.allowed(context) || !context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SurvivalScreen()));
                  },
                ),
              ),
              const SizedBox(height: 4),
              if (roomsEnabled)
                GhostButton(
                  label: 'Join a friend’s game',
                  icon: Icons.login_rounded,
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const JoinScreen())),
                ),
              GhostButton(label: 'How to play', icon: Icons.menu_book_rounded, onPressed: () => _howToPlay(context)),
              if (demo)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Football data: early demo set — not yet fact-checked.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Palette.muted, fontSize: 12),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  void _howToPlay(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Palette.pitch,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), children: [
            Text('HOW TO PLAY', style: AppText.headline(34)),
            const SizedBox(height: 8),
            const Text(
              '1. Split into 2–6 teams and name them.\n'
              '2. Each round, the app picks a game at random.\n'
              '3. The app explains the rules, runs the clock and keeps score.\n'
              '4. Most points after the last round lifts the trophy.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 16),
            for (final m in GameModeId.values.where((m) => m.playable)) ...[
              Row(children: [
                Icon(m.icon, color: m.color),
                const SizedBox(width: 8),
                Text(m.title.toUpperCase(), style: AppText.headline(24, color: m.color)),
              ]),
              const SizedBox(height: 4),
              for (final r in m.rules) Text('• $r', style: const TextStyle(fontSize: 15, height: 1.45)),
              const SizedBox(height: 14),
            ],
          ]),
        ),
      );
}

/// A match that was going when the app closed: carry on, or bin it.
class _ResumeMatch extends StatefulWidget {
  const _ResumeMatch();

  @override
  State<_ResumeMatch> createState() => _ResumeMatchState();
}

class _ResumeMatchState extends State<_ResumeMatch> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(listenable: s.settings, builder: (context, _) => _card(context, s));
  }

  Widget _card(BuildContext context, AppServices s) {
    final saved = s.settings.savedMatch;
    final t = saved == null ? null : asTournament(saved);
    if (saved == null || t == null) return const SizedBox.shrink();
    final score = [for (var i = 0; i < t.teamCount; i++) '${t.teamName(i)} ${t.scores[i]}'].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.yellow, width: 2),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MATCH IN PROGRESS', style: AppText.label(13, color: Palette.yellow)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(score.toUpperCase(), style: AppText.headline(20)),
              ),
              Text('Round ${t.roundNumber.clamp(1, t.totalRounds)} of ${t.totalRounds}', style: AppText.label(13)),
            ]),
          ),
          FilledButton(
            onPressed: () async {
              MatchFlow.resume(context, saved);
              if (mounted) setState(() {});
            },
            child: const Text('RESUME'),
          ),
          IconButton(
            tooltip: 'Discard',
            icon: const Icon(Icons.close_rounded, color: Palette.muted),
            onPressed: () {
              s.settings.clearMatch();
              setState(() {});
            },
          ),
        ]),
      ),
    );
  }
}

Tournament? asTournament(Map<String, Object?> saved) =>
    saved['t'] is Map ? Tournament.fromJson(Map<String, Object?>.from(saved['t']! as Map)) : null;
