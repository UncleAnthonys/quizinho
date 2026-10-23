/// Every game the wheel can land on. Adding a game = add a value here, a
/// controller + screen under lib/games/, and a case in GameLauncher.
enum GameModeId {
  clubConnections(
    title: 'Club Connections',
    tagline: 'Name a player who played for both clubs',
    playable: true,
    rules: [
      'Two clubs appear. Hit your buzzer as soon as you know a player who played for both.',
      'Get it right: 2 points. Get it wrong: you’re locked out and the others can steal.',
      'Name a deep cut nobody expected for a bonus point.',
    ],
    whoPlays: 'Anyone can buzz — unless it says FACE-OFF, then only the two named players.',
  ),
  careerPath(
    title: 'Career Path',
    tagline: 'Guess the player from their clubs',
    playable: true,
    rules: [
      'Clubs appear one at a time, in career order.',
      'Buzz as early as you dare: 5 points on the first clue, dropping each reveal.',
      'Wrong answers lock your team out of that player.',
    ],
    whoPlays: 'Teams can confer — except on FACE-OFF questions, where it’s just the named players.',
  ),
  startingXi(
    title: 'Starting XI Bomb',
    tagline: 'Name the line-up before the bomb goes off',
    playable: true,
    rules: [
      'Name one player from the starting XI, then pass the phone.',
      'Wrong answer or time up: the bomb goes off and you lose a life.',
      '1 point per player named. Last team standing (or most named) takes a 3-point bonus.',
    ],
    whoPlays: 'Teams take turns. Pass the phone to whoever is named.',
  ),
  wildcard(
    title: 'Wildcard',
    tagline: 'Random game. Double points.',
    playable: true,
    rules: ['A random game, worth DOUBLE points.'],
    whoPlays: 'Whatever the wildcard decides.',
  ),
  ticTacToe(
    title: 'Tic-Tac-Toe',
    tagline: 'Name a player for both clubs to claim the square',
    playable: true,
    rules: [
      'Three clubs across, three down. Pick a square, then name a player who played for both clubs.',
      'Right: the square is yours. Wrong or too slow: your turn’s over.',
      'Three in a row = 3 bonus points. Every square you own is worth 1. Each player once per grid.',
    ],
    whoPlays: 'Teams take turns — the named player picks the square and answers.',
  ),
  whoAmI(title: 'Who Am I?', tagline: 'Coming soon', playable: false),
  headsUp(
    title: 'Football Heads Up',
    tagline: 'Phone on your forehead — your team describes',
    playable: true,
    rules: [
      'One player holds the phone to their forehead. Their team describes the name on screen.',
      'Tilt DOWN when you get it, UP to pass. Or use the buttons.',
      '1 point per correct card. Every team gets one go.',
    ],
    whoPlays: 'The named player guesses; their teammates describe. Other teams keep quiet!',
  ),
  taboo(title: 'Football Taboo', tagline: 'Coming soon', playable: false);

  const GameModeId({
    required this.title,
    required this.tagline,
    required this.playable,
    this.rules = const [],
    this.whoPlays = '',
  });

  final String title;
  final String tagline;
  final bool playable;
  final List<String> rules;
  final String whoPlays;

  /// Real games (not the wildcard wrapper) available today.
  static List<GameModeId> get concreteGames =>
      values.where((m) => m.playable && m != GameModeId.wildcard).toList();

  static GameModeId? fromName(String name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}
