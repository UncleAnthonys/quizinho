import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../domain/game_mode.dart';
import '../domain/tournament.dart';
import '../games/career_path/career_path_screen.dart';
import '../games/club_connections/club_connections_screen.dart';
import '../games/game_screen_support.dart';
import '../games/heads_up/heads_up_screen.dart';
import '../games/starting_xi/starting_xi_screen.dart';
import 'screens/round_intro_screen.dart';
import 'screens/round_summary_screen.dart';
import 'screens/wheel_screen.dart';
import 'screens/winner_screen.dart';

/// Moves a match through: wheel → intro → game → summary → … → winner.
/// Each step replaces the previous route so "back" never lands mid-game.
abstract final class MatchFlow {
  static Route<void> _route(Widget page) => PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondary) => page,
        transitionsBuilder: (context, animation, secondary, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  static void toWheel(BuildContext context, Tournament t) =>
      Navigator.of(context).pushReplacement(_route(_Guard(child: WheelScreen(tournament: t))));

  static void toIntro(BuildContext context, Tournament t, GameModeId mode, int multiplier) =>
      Navigator.of(context).pushReplacement(
          _route(_Guard(child: RoundIntroScreen(tournament: t, mode: mode, multiplier: multiplier))));

  static void toGame(BuildContext context, Tournament t, GameModeId mode, int multiplier) {
    final nav = Navigator.of(context);
    final round = RoundContext(
      tournament: t,
      multiplier: multiplier,
      onComplete: (result) {
        t.recordRound(result, multiplier: multiplier);
        nav.pushReplacement(_route(_Guard(child: RoundSummaryScreen(tournament: t))));
      },
    );
    nav.pushReplacement(_route(_Guard(child: _gameFor(mode, round))));
  }

  static void toWinner(BuildContext context, Tournament t) =>
      Navigator.of(context).pushReplacement(_route(WinnerScreen(tournament: t)));

  static Widget _gameFor(GameModeId mode, RoundContext round) => switch (mode) {
        GameModeId.clubConnections => ClubConnectionsScreen(round: round),
        GameModeId.careerPath => CareerPathScreen(round: round),
        GameModeId.startingXi => StartingXiScreen(round: round),
        GameModeId.headsUp => HeadsUpScreen(round: round),
        _ => throw ArgumentError('${mode.title} is not playable yet'),
      };
}

/// Stops an accidental back-swipe from wiping a match.
class _Guard extends StatelessWidget {
  const _Guard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final nav = Navigator.of(context);
          final quit = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Palette.pitch,
              title: Text('ABANDON MATCH?', style: AppText.headline(26)),
              content: const Text('Scores will be lost.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep playing')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Abandon', style: TextStyle(color: Palette.danger)),
                ),
              ],
            ),
          );
          if (quit == true) nav.popUntil((r) => r.isFirst);
        },
        child: child,
      );
}

/// Colour + icon for each game, used on the wheel and intro cards.
extension GameModeStyle on GameModeId {
  Color get color => switch (this) {
        GameModeId.clubConnections => Palette.yellow,
        GameModeId.careerPath => Palette.blueBright,
        GameModeId.startingXi => const Color(0xFFFF4B6E),
        GameModeId.wildcard => Colors.white,
        GameModeId.whoAmI => const Color(0xFFB57CFF),
        GameModeId.headsUp => const Color(0xFF3DFFB0), // mint
        GameModeId.taboo => const Color(0xFFFF8A3D),
      };

  IconData get icon => switch (this) {
        GameModeId.clubConnections => Icons.compare_arrows_rounded,
        GameModeId.careerPath => Icons.timeline_rounded,
        GameModeId.startingXi => Icons.groups_rounded,
        GameModeId.wildcard => Icons.auto_awesome_rounded,
        GameModeId.whoAmI => Icons.help_outline_rounded,
        GameModeId.headsUp => Icons.screen_rotation_rounded,
        GameModeId.taboo => Icons.block_rounded,
      };

  /// Short label that fits on a wheel segment.
  String get wheelLabel => switch (this) {
        GameModeId.clubConnections => 'CONNECTIONS',
        GameModeId.careerPath => 'CAREER PATH',
        GameModeId.startingXi => 'XI BOMB',
        GameModeId.wildcard => 'WILDCARD',
        GameModeId.whoAmI => 'WHO AM I',
        GameModeId.headsUp => 'HEADS UP',
        GameModeId.taboo => 'TABOO',
      };
}
