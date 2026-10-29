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
      'Name a less obvious player — one most people wouldn’t think of — for a bonus point.',
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
  biddingWar(
    title: 'Bidding War',
    tagline: 'How many can you name? Prove it.',
    playable: true,
    rules: [
      'A category appears. Teams take turns bidding how many answers they can name.',
      'Raise the bid — or think they’re bluffing? Hit CHALLENGE.',
      'The top bidder gets 60 seconds to name that many. Do it: +3. Fail: +3 to the challenger.',
    ],
    whoPlays: 'Bid out loud as a team. When challenged, the whole team can shout answers.',
  ),
  pointless(
    title: 'Pointless',
    tagline: 'Think of the answers nobody else would',
    playable: true,
    rules: [
      'A category appears. Teams take turns — confer, then give ONE answer.',
      'A right answer scores how many of 100 people would have said it. The more obscure, the lower.',
      'A wrong answer or running out of time scores 100. Two answers each — lowest total wins +3, and every POINTLESS answer is +1.',
    ],
    whoPlays: 'Each team confers, then one person types or says the answer.',
  ),
  checkout501(
    title: 'Football 501',
    tagline: 'Check out from 501 with players’ apps + goals',
    playable: true,
    rules: [
      'Every team starts on 501. Take turns naming a player — their league apps + goals for the club come off your score.',
      'Over 180 is a BUST: your score stays.',
      'Finish anywhere from 0 to −10 to check out; further below is a bust. Everyone gets the same number of darts — if two teams check out on the same dart, closest to 0 wins +3.',
      'Once a player is named they’re gone for everyone — steal the one they wanted!',
    ],
    whoPlays: 'Each team confers, then names one player per turn.',
  ),
  whoAmI(title: 'Who Am I?', tagline: 'Coming soon', playable: false),
  headsUp(
    title: 'Football Heads Up',
    tagline: 'Phone on your forehead — your team describes',
    playable: true,
    rules: [
      'One player holds the phone to their forehead. Their team describes the name on screen.',
      'Tilt DOWN when you get it, UP to pass. Or use the buttons.',
      'Every team gets one go. Most correct cards wins 3 points.',
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

  /// Has women's questions. Line-ups and Heads Up packs are men's only so far.
  bool get hasWomensGame => this != GameModeId.startingXi && this != GameModeId.headsUp;

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
