import 'dart:math';

import '../../data/football_repository.dart';
import '../../data/models.dart';

/// The kinds of question a penalty can be: one quick question, one go.
enum KickKind {
  twoClubs,
  missingClub,
  lineupSpot,
  wholeCareer,
  firstClub,
  lastClub,
  fromList,
  countryClub,
  overUnder,
  whoPlayedMore,
  whoScoredMore,
  careerGoals,
  matchScore,
}

/// One penalty: a quick question with a single answer to give (or, for
/// over/under, a button to tap).
class PenaltyKick {
  const PenaltyKick({
    required this.kind,
    required this.ask,
    this.lines = const [],
    this.path = const [],
    this.lineup = const [],
    this.answers = const {},
    this.clubs = false,
    required this.reveal,
    this.options = const [],
    this.correctOption,
  });

  final KickKind kind;

  /// The small gold line over the question ("NAME A PLAYER WHO PLAYED FOR").
  final String ask;

  /// The question itself, a line each ("LEEDS UNITED", "AND", "MANCHESTER UNITED").
  final List<String> lines;

  /// A career, club by club; "?" marks the club to name.
  final List<String> path;

  /// A starting XI: [position, surname, line (0 GK - 3 attack)]; "?" for the one to name.
  final List<List<Object>> lineup;

  /// Right answers (player ids, or club ids when [clubs]).
  final Set<String> answers;
  final bool clubs;

  /// Shown after the kick: the answer ("DAVID SEAMAN", "BARCELONA").
  final String reveal;

  /// Over/under: the buttons, and which is right.
  final List<String> options;
  final int? correctOption;

  bool get tap => options.isNotEmpty;

  /// For the phones and the screen: everything needed to draw it.
  Map<String, Object?> toView() => {
        'kind': kind.name,
        'ask': ask,
        if (lines.isNotEmpty) 'lines': lines,
        if (path.isNotEmpty) 'path': path,
        if (lineup.isNotEmpty) 'lineup': lineup,
        if (options.isNotEmpty) 'options': options,
      };
}

/// Makes penalties from the database, always at Easy level (penalties should
/// mostly go in - the misses are the drama), each kind in turn so no two in a
/// row are alike. Remembers what's been asked like every game does: a pairing,
/// career, line-up or list used here counts as seen for its own game too.
class KickSource {
  KickSource(this.challenges, {Random? random, this.genders = 1}) : _random = random ?? Random();
  final ChallengeSource challenges;
  final Random _random;
  final int genders;

  FootballRepository get _repo => challenges.repo;
  QuestionHistory get _history => challenges.history;

  /// Used this match (by any game), so a penalty never repeats one.
  final Set<String> _used = {};
  List<KickKind> _order = [];

  static const _level = Difficulty.easy;

  /// Careers come from Easy and Medium: Easy alone is too few to go round
  /// four kinds of kick (and Career Path itself) without repeats.
  static const _careerLevel = Difficulty.medium;

  /// The next penalty, or null if nothing at all can be made. [kind]: the
  /// same kind as the round's first kick, so every team gets a like question
  /// (one gets "Terry or Gerrard?", so does the other).
  Future<PenaltyKick?> next({KickKind? kind}) async {
    if (kind != null) {
      for (var tries = 0; tries < 4; tries++) {
        final k = await _make(kind);
        if (k != null) return k;
      }
    }
    for (var tries = 0; tries < KickKind.values.length * 2; tries++) {
      if (_order.isEmpty) _order = [...KickKind.values]..shuffle(_random);
      final kind = _order.removeAt(0);
      final k = await _make(kind);
      if (k != null) return k;
    }
    return null;
  }

  Future<PenaltyKick?> _make(KickKind kind) => switch (kind) {
        KickKind.twoClubs => _twoClubs(),
        KickKind.missingClub => _missingClub(),
        KickKind.lineupSpot => _lineupSpot(),
        KickKind.wholeCareer => _wholeCareer(),
        KickKind.firstClub => _endClub(first: true),
        KickKind.lastClub => _endClub(first: false),
        KickKind.fromList => _fromList(),
        KickKind.countryClub => _countryClub(),
        KickKind.overUnder => _overUnder(),
        KickKind.whoPlayedMore => _whoMore(goals: false),
        KickKind.whoScoredMore => _whoMore(goals: true),
        KickKind.careerGoals => _careerGoals(),
        KickKind.matchScore => _matchScore(),
      };

  String _up(String s) => s.toUpperCase();

  Future<PenaltyKick?> _twoClubs() async {
    final c = await challenges.clubConnection(_level, _used, genders: genders);
    if (c == null) return null;
    _used.add(c.id);
    return PenaltyKick(
      kind: KickKind.twoClubs,
      ask: 'NAME A PLAYER WHO PLAYED FOR',
      lines: [_up(c.clubA.name), 'AND', _up(c.clubB.name)],
      answers: c.answerIds,
      reveal: _names(c.answerIds),
    );
  }

  /// A well-known club spell in [p]'s career (not a loan), or null.
  List<CareerSpell> _spells(CareerPath p) {
    final out = <CareerSpell>[];
    for (final s in p.spells) {
      if (s.isLoan) continue;
      // The same club twice in a row (two spells): once is enough.
      if (out.isNotEmpty && out.last.club.id == s.club.id) continue;
      out.add(s);
    }
    return out;
  }

  Future<CareerPath?> _career() async {
    for (var i = 0; i < 6; i++) {
      final p = await challenges.careerPath(_careerLevel, _used, genders: genders);
      if (p == null) return null;
      _used.add(p.id);
      if (_spells(p).length >= 3) return p;
    }
    return null;
  }

  Future<PenaltyKick?> _missingClub() async {
    final p = await _career();
    if (p == null) return null;
    final spells = _spells(p);
    // A club in the middle that people know, only once in the career.
    final options = [
      for (var i = 1; i < spells.length - 1; i++)
        if (spells[i].club.fame >= 4 && spells.where((s) => s.club.id == spells[i].club.id).length == 1) i,
    ];
    if (options.isEmpty) return null;
    final gap = options[_random.nextInt(options.length)];
    return PenaltyKick(
      kind: KickKind.missingClub,
      ask: '${_up(p.player.name)} · NAME THE MISSING CLUB',
      path: [for (var i = 0; i < spells.length; i++) i == gap ? '?' : _up(spells[i].club.name)],
      answers: {spells[gap].club.id},
      clubs: true,
      reveal: _up(spells[gap].club.name),
    );
  }

  Future<PenaltyKick?> _wholeCareer() async {
    final p = await _career();
    if (p == null) return null;
    return PenaltyKick(
      kind: KickKind.wholeCareer,
      ask: 'WHOSE CAREER?',
      path: [for (final s in _spells(p)) _up(s.club.name)],
      answers: {p.player.id},
      reveal: _up(p.player.name),
    );
  }

  Future<PenaltyKick?> _endClub({required bool first}) async {
    final p = await _career();
    if (p == null) return null;
    final spells = _spells(p);
    final s = first ? spells.first : spells.last;
    // A club people know: not Grenoble for Giroud, not Stuttgarter Kickers.
    if (s.club.fame < 4) return null;
    final now = !first && s.endYear == null;
    return PenaltyKick(
      kind: first ? KickKind.firstClub : KickKind.lastClub,
      ask: first ? 'WHERE DID HE START HIS CAREER?' : (now ? 'WHO DOES HE PLAY FOR NOW?' : 'WHERE DID HE FINISH HIS CAREER?'),
      lines: [_up(p.player.name)],
      answers: {s.club.id},
      clubs: true,
      reveal: _up(s.club.name),
    );
  }

  /// The whole XI on the pitch, one name missing: no "which striker?".
  Future<PenaltyKick?> _lineupSpot() async {
    final m = await challenges.match(_level, _used, genders: genders);
    if (m == null) return null;
    _used.add(m.id);
    // The one to name: a well-known player (the best-known few, at random).
    final ranked = [...m.lineup]
      ..sort((a, b) => (_repo.players.byId(b.playerId)?.fame ?? 0).compareTo(_repo.players.byId(a.playerId)?.fame ?? 0));
    if (ranked.isEmpty) return null;
    final gap = ranked[_random.nextInt(min(4, ranked.length))];
    String surname(String n) => n.split(' ').last.toUpperCase();
    return PenaltyKick(
      kind: KickKind.lineupSpot,
      ask: _up('${m.home} v ${m.away} · ${m.score} · ${m.year}'),
      lines: ['NAME ${_up(m.targetTeam)}’S MISSING PLAYER'],
      lineup: [
        for (final s in m.lineup) [s.position, s.playerId == gap.playerId ? '?' : surname(s.playerName), s.line],
      ],
      answers: {gap.playerId},
      reveal: _up(gap.playerName),
    );
  }

  Future<PenaltyKick?> _fromList() async {
    final b = await challenges.bidding(_level, _used,
        genders: genders, where: (b) => b.answerIds.length >= 5 && b.prompt.length <= 70);
    if (b == null) return null;
    _used.add(b.id);
    return PenaltyKick(
      kind: KickKind.fromList,
      ask: 'NAME ONE',
      lines: [_up(b.prompt)],
      answers: b.answerIds,
      clubs: b.answersAreClubs,
      reveal: _names(b.answerIds, clubs: b.answersAreClubs),
    );
  }

  List<ClubConnection>? _grid;

  Future<PenaltyKick?> _countryClub() async {
    _grid ??= [
      for (final c in await _repo.categoryClubPairs(genders: genders))
        if (c.clubA.id.startsWith('nat:') && c.clubB.fame >= 4 && c.answerIds.length >= 3) c,
    ];
    final seen = _history.seenCounts('pens');
    final fresh = [for (final c in _grid!) if (!_used.contains(c.id) && !seen.containsKey(c.id)) c];
    final pool = fresh.isNotEmpty ? fresh : [for (final c in _grid!) if (!_used.contains(c.id)) c];
    if (pool.isEmpty) return null;
    final c = pool[_random.nextInt(pool.length)];
    _used.add(c.id);
    _history.add('pens', c.id);
    final country = c.clubA.name;
    return PenaltyKick(
      kind: KickKind.countryClub,
      ask: 'NAME A PLAYER FROM',
      lines: [_up(country), 'WHO PLAYED FOR', _up(c.clubB.name)],
      answers: c.answerIds,
      reveal: _names(c.answerIds),
    );
  }

  /// A club's 501 numbers: players people know, with enough games to compare.
  Future<(CheckoutCategory, List<(Player, int, int)>)?> _clubNumbers() async {
    final cat = await challenges.checkout(_level, _used, genders: genders);
    if (cat == null) return null;
    _used.add(cat.id);
    final known = [
      for (final e in cat.values.entries)
        if (_repo.players.byId(e.key) case final p? when p.fame >= 4 && e.value.$1 >= (_national(cat) ? 20 : 40))
          (p, e.value.$1, e.value.$2),
    ];
    return known.isEmpty ? null : (cat, known);
  }

  String _clubOf(CheckoutCategory cat) => _up(cat.prompt.replaceFirst(RegExp(r'^League apps \+ goals for '), ''));

  /// A national team's 501 ("England caps + goals"): caps, not league games.
  bool _national(CheckoutCategory cat) => !cat.id.startsWith('501:Q');
  String _country(CheckoutCategory cat) => _up(cat.prompt.split(' caps').first);

  /// "LEAGUE GAMES FOR STOKE CITY" / "ENGLAND CAPS"; goals likewise.
  String _stat(CheckoutCategory cat, {required bool goals}) => _national(cat)
      ? '${_country(cat)} ${goals ? 'GOALS' : 'CAPS'}'
      : '${goals ? 'LEAGUE GOALS' : 'LEAGUE GAMES'} FOR ${_clubOf(cat)}';

  Future<PenaltyKick?> _overUnder() async {
    final found = await _clubNumbers();
    if (found == null) return null;
    final (cat, players) = found;
    final seen = _history.seenCounts('pens');
    // Games, or goals (for someone who scored a few).
    final goals = _random.nextBool();
    final pool = [
      for (final p in players)
        if (!seen.containsKey('ou:${cat.id}:${p.$1.id}:${goals ? 'g' : 'a'}') && (!goals || p.$3 >= 10)) p,
    ];
    if (pool.isEmpty) return null;
    final (player, apps, scored) = pool[_random.nextInt(pool.length)];
    final real = goals ? scored : apps;
    // The line: 20-35% off the real number, rounded to a nice figure.
    final over = _random.nextBool();
    final f = over ? 0.65 + _random.nextDouble() * 0.15 : 1.2 + _random.nextDouble() * 0.15;
    final step = real >= 150 ? 25 : (real >= 40 ? 10 : 5);
    var line = ((real * f) / step).round() * step;
    if (line == real) line += over ? -step : step;
    if (line <= 0) return null;
    _history.add('pens', 'ou:${cat.id}:${player.id}:${goals ? 'g' : 'a'}');
    return PenaltyKick(
      kind: KickKind.overUnder,
      ask: _stat(cat, goals: goals),
      lines: [_up(player.name), 'OVER OR UNDER $line?'],
      options: ['OVER $line', 'UNDER $line'],
      correctOption: real > line ? 0 : 1,
      reveal: goals ? '$real GOALS' : (_national(cat) ? '$real CAPS' : '$real GAMES'),
    );
  }

  /// "Who played more league games for Man United: Scholes or Giggs?"
  Future<PenaltyKick?> _whoMore({required bool goals}) async {
    final found = await _clubNumbers();
    if (found == null) return null;
    final (cat, players) = found;
    if (players.length < 2) return null;
    final seen = _history.seenCounts('pens');
    for (var i = 0; i < 12; i++) {
      final a = players[_random.nextInt(players.length)];
      final b = players[_random.nextInt(players.length)];
      final va = goals ? a.$3 : a.$2, vb = goals ? b.$3 : b.$2;
      if (a.$1.id == b.$1.id || va == vb || (goals && va + vb < 5)) continue;
      final key = 'who:${goals ? 'g' : 'a'}:${cat.id}:${([a.$1.id, b.$1.id]..sort()).join(':')}';
      if (seen.containsKey(key)) continue;
      _history.add('pens', key);
      return _either(
        goals ? KickKind.whoScoredMore : KickKind.whoPlayedMore,
        'MORE ${_stat(cat, goals: goals)}',
        a.$1,
        va,
        b.$1,
        vb,
        goals ? 'GOALS' : (_national(cat) ? 'CAPS' : 'GAMES'),
      );
    }
    return null;
  }

  List<Player>? _withTotals;

  /// "More league goals in their career: Crouch or Defoe?" Any two players
  /// people know - strikers or not.
  Future<PenaltyKick?> _careerGoals() async {
    _withTotals ??= [
      for (final p in _repo.players.all)
        if (p.fame >= 4 && p.leagueGoals != null && p.women == (genders == 2)) p,
    ];
    final pool = _withTotals!;
    if (pool.length < 2) return null;
    final seen = _history.seenCounts('pens');
    for (var i = 0; i < 12; i++) {
      final a = pool[_random.nextInt(pool.length)];
      final b = pool[_random.nextInt(pool.length)];
      if (a.id == b.id || a.leagueGoals == b.leagueGoals) continue;
      final key = 'tot:${([a.id, b.id]..sort()).join(':')}';
      if (seen.containsKey(key)) continue;
      _history.add('pens', key);
      return _either(KickKind.careerGoals, 'MORE LEAGUE GOALS IN THEIR CAREER', a, a.leagueGoals!, b, b.leagueGoals!, 'GOALS');
    }
    return null;
  }

  /// Two players to tap between; the reveal gives both numbers.
  PenaltyKick _either(KickKind kind, String ask, Player a, int va, Player b, int vb, String unit) {
    String short(Player p) => _up(p.name.split(' ').last);
    // Same surname (the Nevilles): full names.
    final full = short(a) == short(b);
    final na = full ? _up(a.name) : short(a), nb = full ? _up(b.name) : short(b);
    return PenaltyKick(
      kind: kind,
      ask: ask,
      lines: [_up(a.name), 'OR', _up(b.name)],
      options: [na, nb],
      correctOption: va > vb ? 0 : 1,
      reveal: '$na $va · $nb $vb $unit',
    );
  }

  /// "Liverpool v Barcelona, 2019: what was the score?" Three to pick from.
  Future<PenaltyKick?> _matchScore() async {
    final m = await challenges.match(_level, _used, genders: genders);
    if (m == null) return null;
    _used.add(m.id);
    // "3–3 (Liverpool won 3–2 on pens)": the score itself.
    final parts = m.score.split(' ').first.split(RegExp('[–-]'));
    final h = int.tryParse(parts.first), a = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (h == null || a == null) return null;
    final real = '$h–$a';
    final others = <String>{
      for (final (x, y) in [(h + 1, a), (h, a + 1), (h - 1, a), (h, a - 1), (a, h), (h + 1, a + 1)])
        if (x >= 0 && y >= 0 && '$x–$y' != real) '$x–$y',
    }.toList()
      ..shuffle(_random);
    if (others.length < 2) return null;
    final options = [real, ...others.take(2)]..shuffle(_random);
    return PenaltyKick(
      kind: KickKind.matchScore,
      ask: _up('${m.competition} · ${m.year}'),
      lines: [_up('${m.home} v ${m.away}'), 'WHAT WAS THE SCORE?'],
      options: options,
      correctOption: options.indexOf(real),
      reveal: _up(m.score),
    );
  }

  /// A few of the best-known answers, for the reveal.
  String _names(Set<String> ids, {bool clubs = false}) {
    final index = clubs ? _repo.clubIndex : _repo.players;
    final ps = [for (final id in ids) if (index.byId(id) case final p?) p]..sort((a, b) => b.fame.compareTo(a.fame));
    final top = ps.take(3).map((p) => _up(p.name)).toList();
    return top.join(' · ');
  }
}
