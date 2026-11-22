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

  /// The next penalty, or null if nothing at all can be made.
  Future<PenaltyKick?> next() async {
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
      final p = await challenges.careerPath(_level, _used, genders: genders);
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

  Future<PenaltyKick?> _overUnder() async {
    final cat = await challenges.checkout(_level, _used, genders: genders);
    if (cat == null) return null;
    _used.add(cat.id);
    final seen = _history.seenCounts('pens');
    // A player people know, with enough games for a line to make sense.
    final known = [
      for (final e in cat.values.entries)
        if ((_repo.players.byId(e.key)?.fame ?? 0) >= 4 && e.value.$1 >= 40 && !seen.containsKey('ou:${cat.id}:${e.key}'))
          e,
    ];
    if (known.isEmpty) return null;
    final pick = known[_random.nextInt(known.length)];
    final player = _repo.players.byId(pick.key)!;
    final apps = pick.value.$1;
    // The line: 20-35% off the real number, rounded to a nice figure.
    final over = _random.nextBool();
    final f = over ? 0.65 + _random.nextDouble() * 0.15 : 1.2 + _random.nextDouble() * 0.15;
    final step = apps >= 150 ? 25 : 10;
    var line = ((apps * f) / step).round() * step;
    if (line == apps) line += over ? -step : step;
    _history.add('pens', 'ou:${cat.id}:${pick.key}');
    final club = cat.prompt.replaceFirst(RegExp(r'^League apps \+ goals for '), '');
    return PenaltyKick(
      kind: KickKind.overUnder,
      ask: 'LEAGUE GAMES FOR ${_up(club)}',
      lines: [_up(player.name), 'OVER OR UNDER $line?'],
      options: ['OVER $line', 'UNDER $line'],
      correctOption: apps > line ? 0 : 1,
      reveal: '$apps GAMES',
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
