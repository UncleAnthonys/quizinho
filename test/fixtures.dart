import 'package:quizinho/data/models.dart';

const arsenal = Club(id: 'arsenal', name: 'Arsenal', fame: 5);
const barcelona = Club(id: 'barcelona', name: 'Barcelona', fame: 5);
const juventus = Club(id: 'juventus', name: 'Juventus', fame: 5);
const ajax = Club(id: 'ajax', name: 'Ajax', fame: 4);
const inter = Club(id: 'inter', name: 'Inter Milan', fame: 5);

const henry = Player(id: 'thierry-henry', name: 'Thierry Henry', fame: 5, aliases: ['Titi']);
const fabregas = Player(id: 'cesc-fabregas', name: 'Cesc Fàbregas', fame: 5, aliases: ['Cesc']);
const zlatan = Player(id: 'zlatan-ibrahimovic', name: 'Zlatan Ibrahimović', fame: 5, aliases: ['Zlatan', 'Ibra']);
const cr7 = Player(id: 'cristiano-ronaldo', name: 'Cristiano Ronaldo', fame: 5, aliases: ['Ronaldo', 'CR7']);
const r9 = Player(id: 'ronaldo-nazario', name: 'Ronaldo Nazário', fame: 5, aliases: ['Ronaldo', 'R9']);
const gallas = Player(id: 'william-gallas', name: 'William Gallas', fame: 3);
const taa = Player(id: 'trent-alexander-arnold', name: 'Trent Alexander-Arnold', fame: 4, aliases: ['Trent']);
const etoo = Player(id: 'samuel-etoo', name: "Samuel Eto'o", fame: 4);

const allPlayers = [henry, fabregas, zlatan, cr7, r9, gallas, taa, etoo];

ClubConnection arsenalBarca() => const ClubConnection(
      id: 'arsenal|barcelona',
      clubA: arsenal,
      clubB: barcelona,
      answerIds: {'thierry-henry', 'cesc-fabregas'},
      difficulty: 1,
    );

ClubConnection arsenalJuve() => const ClubConnection(
      id: 'arsenal|juventus',
      clubA: arsenal,
      clubB: juventus,
      answerIds: {'thierry-henry', 'william-gallas'},
      difficulty: 2,
    );

CareerPath zlatanPath() => const CareerPath(
      player: zlatan,
      difficulty: 1,
      spells: [
        CareerSpell(club: ajax, startYear: 2001, endYear: 2004),
        CareerSpell(club: juventus, startYear: 2004, endYear: 2006),
        CareerSpell(club: inter, startYear: 2006, endYear: 2009),
        CareerSpell(club: barcelona, startYear: 2009, endYear: 2011),
      ],
    );

HistoricMatch tinyMatch() => HistoricMatch(
      id: 'test-match',
      title: 'Test Final',
      competition: 'Test Cup',
      date: '2012-05-19',
      home: 'A',
      away: 'B',
      score: '1–0',
      targetTeam: 'A',
      difficulty: 1,
      lineup: [
        for (final (i, p) in [henry, fabregas, zlatan].indexed)
          LineupSlot(index: i, playerId: p.id, playerName: p.name, position: i == 0 ? 'GK' : 'ST'),
      ],
    );
