import 'game_mode.dart';

/// The free Warm-Up Cup: one short tournament, the same hand-picked
/// challenges for everyone (so a second phone doesn't get a new free game),
/// then the full game is a one-off unlock.
abstract final class WarmUpCup {
  /// Rounds in order.
  static const games = [GameModeId.clubConnections, GameModeId.careerPath, GameModeId.biddingWar];

  /// Big, familiar clubs with plenty of answers.
  static const connections = [
    'Q9616|Q9617', // Chelsea + Arsenal
    'Q18656|Q8682', // Manchester United + Real Madrid
    'Q1130849|Q50602', // Liverpool + Manchester City
  ];

  /// Easiest first.
  static const careers = ['david-beckham', 'fernando-torres', 'zlatan-ibrahimovic'];

  /// 28 answers: Henry, Vieira, Pires, Giroud, Saliba…
  static const bidding = 'nat:Q9617:FRA';
}
