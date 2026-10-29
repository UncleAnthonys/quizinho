import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../domain/tournament.dart';
import 'match_flow.dart';
import 'screens/paywall_screen.dart';

/// What "kick off" leads to on this phone: the full game once unlocked; before
/// that, the free Warm-Up Cup once; after it, the paywall.
abstract final class MatchAccess {
  /// The free cup is next (setup shows it instead of the full options).
  static bool warmUpNext(AppServices s) => !s.fullGame && !s.settings.warmUpPlayed;

  /// Starts a match from [config] (replacing the current screen), or shows
  /// the paywall. [rematch] = asked from the final whistle.
  static Future<void> start(BuildContext context, TournamentConfig config, {bool rematch = false}) async {
    final s = AppScope.read(context);
    if (s.fullGame) {
      MatchFlow.toWheel(context, Tournament(config));
    } else if (!s.settings.warmUpPlayed) {
      MatchFlow.toWheel(context, Tournament(config.asWarmUp()));
    } else if (await PaywallScreen.show(context, afterWarmUp: rematch) && context.mounted) {
      MatchFlow.toWheel(context, Tournament(config));
    }
  }

  /// For screens outside a match (Solo Survival): true if they may open it.
  static Future<bool> allowed(BuildContext context) async =>
      AppScope.read(context).fullGame || await PaywallScreen.show(context);
}
