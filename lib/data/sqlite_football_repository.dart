import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/player_index.dart';
import 'football_repository.dart';
import 'models.dart';

/// Reads the bundled, versioned SQLite database (built by
/// data_pipeline/build_db.py). Works fully offline.
///
/// The bundled file is copied to app storage as `football_<version>.db`. When
/// a new app build ships a new version, the new file is copied and old ones
/// are deleted. User data (settings, history) lives elsewhere, so content
/// updates never wipe it.
class SqliteFootballRepository implements FootballRepository {
  SqliteFootballRepository._(this._db, this._clubs, this.players, this.dataStatus);

  final _random = Random();

  /// A connection is from the women's game when its clubs are.
  static const _connWomen = '(SELECT women FROM clubs WHERE clubs.id = club_a)';

  @override
  late final PlayerIndex clubIndex = PlayerIndex([for (final c in _clubs.values) c.asAnswer]);

  final Database _db;
  final Map<String, Club> _clubs;
  @override
  final PlayerIndex players;
  @override
  final String dataStatus;

  static Future<SqliteFootballRepository> open() async {
    final version = (await rootBundle.loadString('assets/db/football_db_version.txt')).trim();
    final dir = await getDatabasesPath();
    final file = File(p.join(dir, 'football_$version.db'));

    if (!await file.exists()) {
      await Directory(dir).create(recursive: true);
      final data = await rootBundle.load('assets/db/football.db');
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      await tmp.rename(file.path);
      await for (final entity in Directory(dir).list()) {
        final name = p.basename(entity.path);
        if (entity is File && name.startsWith('football_') && entity.path != file.path) {
          await entity.delete();
        }
      }
    }

    final db = await openDatabase(file.path, readOnly: true);

    final clubAliases = <String, List<String>>{};
    for (final r in await db.rawQuery('SELECT club_id, alias FROM club_aliases')) {
      clubAliases.putIfAbsent(r['club_id'] as String, () => []).add(r['alias'] as String);
    }
    final clubs = <String, Club>{};
    for (final r in await db.rawQuery('SELECT id, name, country, fame, women FROM clubs')) {
      final c = Club(
        id: r['id'] as String,
        name: r['name'] as String,
        country: r['country'] as String?,
        fame: r['fame'] as int,
        aliases: clubAliases[r['id']] ?? const [],
        women: r['women'] == 1,
      );
      clubs[c.id] = c;
    }

    final aliases = <String, List<String>>{};
    for (final r in await db.rawQuery('SELECT player_id, alias FROM player_aliases')) {
      aliases.putIfAbsent(r['player_id'] as String, () => []).add(r['alias'] as String);
    }
    final playerList = <Player>[
      for (final r in await db.rawQuery('SELECT id, name, nationality, position, fame, verified, women FROM players'))
        Player(
          id: r['id'] as String,
          name: r['name'] as String,
          nationality: r['nationality'] as String?,
          position: r['position'] as String?,
          fame: r['fame'] as int,
          verified: (r['verified'] as int) == 1,
          women: r['women'] == 1,
          aliases: aliases[r['id'] as String] ?? const [],
        ),
    ];

    final metaRows = await db.rawQuery("SELECT value FROM meta WHERE key = 'data_status'");
    final status = metaRows.isEmpty ? 'unknown' : metaRows.first['value'] as String;

    return SqliteFootballRepository._(db, clubs, PlayerIndex(playerList), status);
  }

  /// Builds "WHERE difficulty IN (?,?) AND id NOT IN (?,?)".
  /// [womenCol]: SQL giving 1 for a women's challenge; filtered by [genders].
  (String, List<Object?>) _filter(String idCol, Set<int>? levels, Set<String> exclude, int eras,
      {int genders = 3, String? womenCol}) {
    final clauses = <String>[];
    final args = <Object?>[];
    if (womenCol != null && genders != 3) {
      clauses.add('$womenCol = ?');
      args.add(genders == FootballGender.womenBit ? 1 : 0);
    }
    if (eras != Era.allMask) {
      clauses.add('(eras & ?) != 0');
      args.add(eras);
    }
    if (levels != null && levels.isNotEmpty) {
      clauses.add('difficulty IN (${List.filled(levels.length, '?').join(',')})');
      args.addAll(levels);
    }
    if (exclude.isNotEmpty) {
      clauses.add('$idCol NOT IN (${List.filled(exclude.length, '?').join(',')})');
      args.addAll(exclude);
    }
    return (clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}', args);
  }

  Club _club(String id) => _clubs[id] ?? Club(id: id, name: id, fame: 1);

  @override
  Future<ClubConnection?> pickClubConnection(
      {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1}) async {
    final (where, args) = _filter('id', levels, exclude, eras, genders: genders, womenCol: _connWomen);
    final rows = await _db.rawQuery(
      'SELECT id, club_a, club_b, difficulty, eras FROM club_connections $where ORDER BY RANDOM() LIMIT 1',
      args,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final id = r['id'] as String;
    final answers = await _db.rawQuery('SELECT player_id FROM connection_answers WHERE connection_id = ?', [id]);
    return ClubConnection(
      id: id,
      clubA: _club(r['club_a'] as String),
      clubB: _club(r['club_b'] as String),
      answerIds: {for (final a in answers) a['player_id'] as String},
      difficulty: r['difficulty'] as int,
      eras: r['eras'] as int,
    );
  }

  @override
  Future<BiddingCategory?> pickBiddingCategory(
      {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1}) async {
    // Choose the kind of category by weight first, then one of that kind.
    final (where, args) = _filter('id', levels, exclude, eras, genders: genders, womenCol: 'women');
    final counts = await _db.rawQuery('SELECT id FROM bidding_categories $where', args);
    final kind = BiddingKind.choose({for (final r in counts) BiddingKind.ofId(r['id'] as String)}, _random);
    if (kind == null) return null;
    final ofKind = [for (final r in counts) if (BiddingKind.ofId(r['id'] as String) == kind) r['id'] as String];
    final pickedId = ofKind[_random.nextInt(ofKind.length)];
    final rows = await _db.rawQuery(
        'SELECT id, prompt, difficulty, eras, women FROM bidding_categories WHERE id = ?', [pickedId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final answers = await _db.rawQuery('SELECT player_id, score FROM bidding_answers WHERE category_id = ?', [r['id']]);
    return BiddingCategory(
      id: r['id'] as String,
      prompt: r['prompt'] as String,
      difficulty: r['difficulty'] as int,
      eras: r['eras'] as int,
      answerIds: {for (final a in answers) a['player_id'] as String},
      scores: {for (final a in answers) a['player_id'] as String: a['score'] as int},
      women: r['women'] == 1,
    );
  }

  @override
  Future<CheckoutCategory?> pickCheckout(
      {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1}) async {
    final (where, args) = _filter('id', levels, exclude, eras, genders: genders, womenCol: 'women');
    final rows = await _db.rawQuery(
        'SELECT id, prompt, difficulty, eras, women FROM checkout_categories $where ORDER BY RANDOM() LIMIT 1', args);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final answers =
        await _db.rawQuery('SELECT player_id, apps, goals FROM checkout_answers WHERE category_id = ?', [r['id']]);
    return CheckoutCategory(
      id: r['id'] as String,
      prompt: r['prompt'] as String,
      difficulty: r['difficulty'] as int,
      eras: r['eras'] as int,
      women: r['women'] == 1,
      values: {
        for (final a in answers)
          if (a['apps'] != null) a['player_id'] as String: (a['apps'] as int, (a['goals'] as int?) ?? 0),
      },
      noStats: {for (final a in answers) if (a['apps'] == null) a['player_id'] as String},
    );
  }

  @override
  Future<List<ClubConnection>> allClubConnections({int eras = Era.allMask, int genders = 1}) async {
    final (where, args) = _filter('id', null, const {}, eras, genders: genders, womenCol: _connWomen);
    final rows = await _db.rawQuery('SELECT id, club_a, club_b, difficulty, eras FROM club_connections $where', args);
    final answers = <String, Set<String>>{};
    for (final a in await _db.rawQuery('SELECT connection_id, player_id FROM connection_answers')) {
      answers.putIfAbsent(a['connection_id'] as String, () => {}).add(a['player_id'] as String);
    }
    return [
      for (final r in rows)
        ClubConnection(
          id: r['id'] as String,
          clubA: _club(r['club_a'] as String),
          clubB: _club(r['club_b'] as String),
          answerIds: answers[r['id']] ?? const {},
          difficulty: r['difficulty'] as int,
          eras: r['eras'] as int,
        ),
    ];
  }

  @override
  Future<CareerPath?> pickCareerPath(
      {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1}) async {
    final (where, args) = _filter('player_id', levels, exclude, eras,
        genders: genders, womenCol: '(SELECT women FROM players WHERE players.id = player_id)');
    final rows = await _db.rawQuery(
      'SELECT player_id, difficulty, eras FROM career_challenges $where ORDER BY RANDOM() LIMIT 1',
      args,
    );
    if (rows.isEmpty) return null;
    final playerId = rows.first['player_id'] as String;
    final player = players.byId(playerId);
    if (player == null) return null;
    final spells = await _db.rawQuery(
      'SELECT club_id, start_year, end_year, is_loan FROM career_spells WHERE player_id = ? ORDER BY seq',
      [playerId],
    );
    return CareerPath(
      player: player,
      difficulty: rows.first['difficulty'] as int,
      eras: rows.first['eras'] as int,
      spells: [
        for (final s in spells)
          CareerSpell(
            club: _club(s['club_id'] as String),
            startYear: s['start_year'] as int?,
            endYear: s['end_year'] as int?,
            isLoan: (s['is_loan'] as int) == 1,
          ),
      ],
    );
  }

  @override
  Future<HistoricMatch?> pickMatch(
      {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1}) async {
    if (!FootballGender.allows(genders, false)) return null; // line-ups are men's only so far
    final (where, args) = _filter('id', levels, exclude, eras);
    final rows = await _db.rawQuery('SELECT * FROM matches $where', args);
    if (rows.isEmpty) return null;
    final m = HistoricMatch.weightedPick(rows, (r) => (r['weight'] as num).toDouble(), _random);
    final id = m['id'] as String;
    final slots = await _db.rawQuery(
      'SELECT slot, player_id, position FROM lineup_slots WHERE match_id = ? ORDER BY slot',
      [id],
    );
    return HistoricMatch(
      id: id,
      title: m['title'] as String,
      competition: (m['competition'] as String?) ?? '',
      date: (m['match_date'] as String?) ?? '',
      home: m['home'] as String,
      away: m['away'] as String,
      score: (m['score'] as String?) ?? '',
      targetTeam: m['target_team'] as String,
      difficulty: m['difficulty'] as int,
      verified: (m['verified'] as int) == 1,
      eras: m['eras'] as int,
      weight: (m['weight'] as num).toDouble(),
      lineup: [
        for (final s in slots)
          LineupSlot(
            index: s['slot'] as int,
            playerId: s['player_id'] as String,
            playerName: players.byId(s['player_id'] as String)?.name ?? s['player_id'] as String,
            position: s['position'] as String,
          ),
      ],
    );
  }
}
