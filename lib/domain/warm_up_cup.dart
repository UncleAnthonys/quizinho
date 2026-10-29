import 'game_mode.dart';

/// The free Warm-Up Cup: one short tournament, the same hand-picked
/// challenges for everyone (so a second phone doesn't get a new free game),
/// then the full game is a one-off unlock.
abstract final class WarmUpCup {
  /// Rounds in order.
  static const games = [GameModeId.clubConnections, GameModeId.careerPath, GameModeId.biddingWar];

  /// An English club and a big European one — gettable, but a race to think of one.
  static const connections = [
    'Q5794|Q7156', // Everton + Barcelona: Lineker, Eto'o, Arteta, Digne…
    'Q132885|Q9616', // Chelsea + Marseille: Drogba, Desailly, Makélélé…
    'Q18711|Q7156', // Aston Villa + Barcelona: Coutinho, Rashford, Reina…
  ];

  /// Premier League names hidden behind early clubs nobody remembers.
  static const careers = ['yaya-toure', 'peter-crouch', 'robbie-keane'];

  /// 28 answers: Henry, Vieira, Pires, Giroud, Saliba…
  static const bidding = 'nat:Q9617:FRA';
}
