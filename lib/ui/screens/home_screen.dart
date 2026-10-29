import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../domain/game_mode.dart';
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
                        'One-on-one or the whole room in teams. A new game every round. Shout, steal, argue — the app keeps score.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Palette.muted, fontSize: 16, height: 1.4),
                      ),
                    ]),
                  ),
                ),
              ),
              const Spacer(flex: 2),
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
                  label: 'Join a game',
                  icon: Icons.qr_code_scanner_rounded,
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

