// Renders each turn game's shared layout (as a joined phone draws it — the
// host draws the same layout) to PNGs in docs/shots/, so they can be looked
// at without a phone. Only runs in the "Screenshots" workflow (SHOTS=1):
//   SHOTS=1 flutter test test/screenshots_test.dart --update-goldens
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quizinho/core/app_services.dart';
import 'package:quizinho/core/app_settings.dart';
import 'package:quizinho/core/sound_service.dart';
import 'package:quizinho/core/theme.dart';
import 'package:quizinho/core/voice_service.dart';
import 'package:quizinho/data/in_memory_football_repository.dart';
import 'package:quizinho/domain/player_index.dart';
import 'package:quizinho/games/bidding_war/bidding_war_screen.dart';
import 'package:quizinho/games/checkout_501/checkout_screen.dart';
import 'package:quizinho/games/buzz_game_view.dart';
import 'package:quizinho/games/club_connections/club_connections_controller.dart';
import 'package:quizinho/games/club_connections/club_connections_screen.dart';
import 'package:quizinho/games/hat_trick/hat_trick_controller.dart';
import 'package:quizinho/games/hat_trick/hat_trick_screen.dart';
import 'package:quizinho/games/career_path/career_path_controller.dart';
import 'package:quizinho/games/career_path/career_path_screen.dart';
import 'package:quizinho/games/game_screen_support.dart';
import 'package:quizinho/games/pointless/pointless_screen.dart';
import 'package:quizinho/games/starting_xi/starting_xi_screen.dart';
import 'package:quizinho/games/tic_tac_toe/tic_tac_toe_screen.dart';
import 'package:quizinho/domain/tournament.dart';
import 'package:quizinho/ui/screens/round_intro_screen.dart';
import 'package:quizinho/domain/game_mode.dart';
import 'package:quizinho/ui/screens/free_kick_screen.dart';
import 'package:quizinho/ui/screens/home_screen.dart';
import 'package:quizinho/ui/screens/setup_screen.dart';
import 'package:quizinho/ui/screens/solo_screen.dart';
import 'package:quizinho/ui/teaser/teaser_widgets.dart';
import 'package:quizinho/ui/widgets/common.dart';
import 'package:quizinho/ui/widgets/logo.dart';
import 'package:quizinho/ui/widgets/match_table.dart';
import 'package:quizinho/ui/widgets/player_picker.dart';
import 'package:quizinho/multiplayer/guest_screen.dart' show guestGamePreview;
import 'package:quizinho/ui/match_flow.dart' show GameModeStyle;
import 'package:quizinho/multiplayer/host_lobby.dart' show RoomSheet;
import 'package:quizinho/multiplayer/memory_room_link.dart';
import 'package:quizinho/multiplayer/room.dart' show GuestRoom, HostRoom, RoomMember;

import 'package:quizinho/data/json_football_repository.dart';
import 'package:quizinho/data/models.dart' show CareerPath, CareerSpell, Club, Difficulty, HatTrickSet, Player;
import 'package:quizinho/games/tic_tac_toe/tic_tac_toe_controller.dart';
import 'package:quizinho/ui/screens/round_summary_screen.dart';
import 'package:quizinho/domain/warm_up_cup.dart';
import 'package:quizinho/games/penalties/shootout_layout.dart';
import 'fixtures.dart';

final _shots = Platform.environment['SHOTS'] == '1';

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }

  await family('BarlowCondensed', [
    'BarlowCondensed_600SemiBold.ttf',
    'BarlowCondensed_700Bold.ttf',
    'BarlowCondensed_800ExtraBold.ttf',
    'BarlowCondensed_900Black.ttf',
  ]);
  await family('Inter', [
    'Inter_400Regular.ttf',
    'Inter_500Medium.ttf',
    'Inter_600SemiBold.ttf',
    'Inter_700Bold.ttf',
    'Inter_800ExtraBold.ttf',
  ]);
  // ♥ and ▢ (lives, squares): the game fonts lack them and the renderer has
  // no system fallback, so they came out as boxes.
  final dejavu = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
  if (dejavu.existsSync()) {
    await (FontLoader('QuizinhoSymbols')..addFont(Future.value(ByteData.sublistView(dejavu.readAsBytesSync())))).load();
  }
  // Flags (the names list shows each player's country).
  for (final path in ['/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf', '/usr/share/fonts/noto/NotoColorEmoji.ttf']) {
    final emoji = File(path);
    if (emoji.existsSync()) {
      await (FontLoader('QuizinhoEmoji')..addFont(Future.value(ByteData.sublistView(emoji.readAsBytesSync())))).load();
      break;
    }
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  }
}

const _teams = [
  {'name': 'Home', 'color': 0, 'score': 7},
  {'name': 'Away', 'color': 1, 'score': 4},
];

Widget _scores({List<String> extra = const []}) => ScoreStrip(
      round: '3/6',
      highlightTeam: 0,
      teams: const [('Home', 0, 7), ('Away', 1, 4)],
      extra: extra.isEmpty ? null : (i) => extra[i],
    );

Widget _timer() => const TimerBar(fraction: 0.6, seconds: 12);

Widget _picker({VoiceService? voice}) => PlayerPicker(
    // A fresh box each shot (otherwise it keeps the last shot's state).
    key: UniqueKey(),
    index: PlayerIndex(allPlayers),
    voice: voice,
    onPick: (_) {},
    onPass: () {});

/// A mic for the shots: on, and (with [heard]) hearing those words at once.
class _ShotVoice extends VoiceService {
  _ShotVoice(super.settings, {this.heard});
  final String? heard;

  @override
  bool get enabled => true;

  @override
  Future<bool> listen({
    required void Function(String words) onWords,
    required void Function(List<String> alternatives) onDone,
    List<String> hints = const [],
  }) async {
    if (heard case final h?) onWords(h);
    return true;
  }

  @override
  void stop() {}

  @override
  void reportMiss(List<String> heard, {String? playerId, List<String> answers = const []}) {}
}

void main() {
  late AppServices services;

  setUpAll(() async {
    if (!_shots) return;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    services = AppServices(
      repo: InMemoryFootballRepository(players: allPlayers, connections: [arsenalBarca()]),
      settings: settings,
      sound: SoundService(settings),
    );
  });

  Future<void> shot(WidgetTester tester, String name, Widget body, {Future<void> Function()? then}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: Scaffold(body: PitchBackground(child: SafeArea(child: body))),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    if (then != null) {
      await then();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/shots/$name.png'));
  }

  testWidgets('Home', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: const HomeScreen()),
    ));
    await tester.pump(const Duration(seconds: 2));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/shots/home.png'));
  }, skip: !_shots);

  testWidgets('Setup', (tester) async {
    await services.settings.saveConfig(TournamentConfig(teams: [
      TeamSetup(name: 'Home', colorIndex: 0, players: ['Alex', 'Sam']),
      TeamSetup(name: 'Away', colorIndex: 1, players: ['Gav']),
    ]));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: const SetupScreen()),
    ));
    await tester.pump(const Duration(seconds: 2));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/shots/setup.png'));
  }, skip: !_shots);

  testWidgets('Solo', (tester) async {
    services.settings.recordSolo('cup', 'medium', 412);
    services.settings.recordSolo('clubConnections', 'medium', 86);
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: const SoloScreen()),
    ));
    await tester.pump(const Duration(seconds: 2));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/shots/solo.png'));
  }, skip: !_shots);

  // The app icon: the crest on the pitch green, square, no transparency
  // (Apple rounds the corners itself). Written to assets/icon/icon.png.
  testWidgets('App icon', (tester) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(colors: [Color(0xFF17573A), Palette.pitchDeep], radius: 0.9),
        ),
        alignment: Alignment.center,
        child: const QuizinhoBadge(size: 880),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../assets/icon/icon.png'));
  }, skip: !_shots);

  Widget column(Widget scores, Widget layout) => Column(children: [scores, Expanded(child: layout)]);

  const lineup = [
    {'p': 'GK', 'n': 'Jens Lehmann', 'i': 'lehmann'}, // (Seaman had left by 2004)
    {'p': 'RB', 'n': 'Lauren', 'i': 'lauren'},
    {'p': 'CB', 'n': 'Sol Campbell', 'i': 'campbell'},
    {'p': 'CB', 'n': 'Kolo Touré', 'i': 'toure'},
    {'p': 'LB', 'n': 'Ashley Cole', 'i': 'cole'},
    {'p': 'RM', 'n': 'Freddie Ljungberg', 'i': 'ljungberg'},
    {'p': 'CM', 'n': 'Patrick Vieira', 'i': 'vieira'},
    {'p': 'CM', 'n': 'Gilberto Silva', 'i': 'gilberto'},
    {'p': 'LM', 'n': 'Robert Pirès', 'i': 'pires'},
    {'p': 'ST', 'n': 'Dennis Bergkamp', 'i': 'bergkamp'},
    {'p': 'ST', 'n': 'Thierry Henry', 'i': 'henry'},
  ];
  Map<String, Object?> xi(String phase) => {
        'phase': phase,
        'target': 'Arsenal',
        'match': 'Arsenal v Leicester · 2–1 · 2004',
        'title': 'The Invincibles seal the season',
        'lineup': lineup,
        'named': {'henry': 0, 'vieira': 1, 'cole': 0},
        'colours': [0, 1],
        'team': 1,
        'teamName': 'Away',
        'who': 'Sam',
        'seconds': 20,
        'lost': 'Away',
        'out': false,
        'complete': false,
        'bonus': const [],
        'bonusPts': 3,
      };

  testWidgets('XI Bomb', (tester) async {
    for (final phase in ['ticking', 'exploded']) {
      await shot(
        tester,
        'xi_$phase',
        XiLayout(
          data: xi(phase),
          scores: _scores(extra: const ['♥♥♥  2 named', '♥♥  1 named']),
          left: 12,
          answerBox: _picker(),
        ),
      );
    }
  }, skip: !_shots);

  Map<String, Object?> ttt(String phase) => {
        'rows': ['Arsenal', 'Chelsea', 'Manchester United'],
        'cols': ['Barcelona', 'Real Madrid', 'Juventus'],
        'owner': [0, null, null, null, 1, null, null, null, null],
        'claimed': ['Thierry Henry', null, null, null, 'Ángel Di María', null, null, null, null],
        if (phase == 'answering') 'selected': 2,
        'colours': [0, 1],
        'choosing': phase == 'choosing',
        'phase': phase,
        'team': 0,
        'who': 'Alex',
      };

  testWidgets('Tic-Tac-Toe', (tester) async {
    await shot(
      tester,
      'ttt_choosing',
      column(_scores(extra: const ['1 ▢', '1 ▢']),
          TttLayout(data: ttt('choosing'), onTap: (_) {}, bottom: const Text('Tap an empty square…', textAlign: TextAlign.center))),
    );
    await shot(
      tester,
      'ttt_answering',
      column(
          _scores(extra: const ['1 ▢', '1 ▢']),
          TttLayout(
            data: ttt('answering'),
            bottom: Column(children: [
              Text('ARSENAL  +  JUVENTUS', textAlign: TextAlign.center, style: AppText.headline(20, color: Palette.yellow)),
              _timer(),
              _picker(),
            ]),
          )),
    );
  }, skip: !_shots);

  // A wrong answer: the question card shakes red with the name crossed out.
  testWidgets('Wrong answer shake', (tester) async {
    final miss = ValueNotifier<int?>(null);
    await shot(
      tester,
      'miss_shake',
      Column(children: [
        _scores(),
        const SizedBox(height: 40),
        ValueListenableBuilder<int?>(
          valueListenable: miss,
          builder: (context, n, _) => MissShake(
            trigger: n,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Palette.pitchDeep, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                Text('MANCHESTER CITY', textAlign: TextAlign.center, style: AppText.headline(44)),
                const Icon(Icons.swap_vert_rounded, color: Palette.yellow, size: 36),
                Text('BARCELONA', textAlign: TextAlign.center, style: AppText.headline(44)),
              ]),
            ),
          ),
        ),
      ]),
      then: () async {
        miss.value = 1;
        await tester.pump(); // starts the animation
        await tester.pump(const Duration(milliseconds: 150));
      },
    );
  }, skip: !_shots);

  // The longest headers a grid can have, to check they fit their squares.
  testWidgets('Tic-Tac-Toe long headers', (tester) async {
    await shot(
      tester,
      'ttt_long_headers',
      TttLayout(
        data: {
          ...ttt('choosing'),
          'rows': ['Managed by Pochettino (club)', 'Villarreal', 'Managed by Luis Enrique (club)'],
          'cols': ['Club teammate of Owen', 'Manchester United', 'Managed by Guardiola (club)'],
        },
        onTap: (_) {},
        bottom: const SizedBox.shrink(),
      ),
    );
  }, skip: !_shots);

  // The answer box with the mic on: listening, hearing words, and the
  // player who's chosen the keyboard (box ready to type, mic waits for a tap).
  testWidgets('Answer box', (tester) async {
    Widget answering({VoiceService? voice, bool typing = false}) => column(
        _scores(extra: const ['1 ▢', '1 ▢']),
        TttLayout(
          data: ttt('answering'),
          typing: typing,
          bottom: Column(children: [
            Text('ARSENAL  +  JUVENTUS', textAlign: TextAlign.center, style: AppText.headline(20, color: Palette.yellow)),
            _timer(),
            _picker(voice: voice),
          ]),
        ));
    services.settings.typeAnswers = false;
    await shot(tester, 'answer_mic_listening', answering(voice: _ShotVoice(services.settings)));
    await shot(tester, 'answer_mic_hearing', answering(voice: _ShotVoice(services.settings, heard: 'says a fab')));
    services.settings.typeAnswers = true;
    await shot(tester, 'answer_keyboard_chosen', answering(voice: _ShotVoice(services.settings)));
    await shot(tester, 'answer_keyboard_typing', answering(voice: _ShotVoice(services.settings), typing: true),
        then: () => tester.enterText(find.byType(TextField), 'Fabregas'));
    services.settings.typeAnswers = false;
  }, skip: !_shots);

  // The free kick on a joined phone: waiting for the kick, then the result.
  testWidgets('Free kick (joined phone)', (tester) async {
    Map<String, Object?> fk(String phase) => {
          'kind': 'freekick',
          'n': 2,
          'wall': [
            for (final m in GameModeId.values)
              if (m.playable && m != GameModeId.wildcard) m.name,
          ],
          'phase': phase,
          if (phase != 'ready') 'target': 3,
          'curl': 1,
          if (phase == 'landed') 'landed': GameModeId.values.where((m) => m.playable && m != GameModeId.wildcard).elementAt(3).name,
          'round': '3/6',
          'teams': _teams,
        };
    for (final phase in ['ready', 'landed']) {
      await shot(
          tester,
          'freekick_joined_$phase',
          FreeKickMirror(key: UniqueKey(), data: fk(phase), scores: _scores()),
          then: () async {
            await tester.pump(const Duration(seconds: 1));
            await tester.pump(const Duration(seconds: 1));
          });
    }
  }, skip: !_shots);

  // Hat-Trick: three clubs, every team's answer under them as it goes in.
  testWidgets('Hat-Trick', (tester) async {
    final t = Tournament(TournamentConfig(teams: [
      TeamSetup(name: 'Gav', colorIndex: 0),
      TeamSetup(name: 'Alex', colorIndex: 1),
      TeamSetup(name: 'Sam', colorIndex: 2),
    ]));
    final round = RoundContext(tournament: t, multiplier: 1, onComplete: (_) {});
    const set = HatTrickSet(
      id: 'milan|city|chelsea',
      clubs: [
        Club(id: 'milan', name: 'AC Milan', fame: 5),
        Club(id: 'city', name: 'Manchester City', fame: 5),
        Club(id: 'chelsea', name: 'Chelsea', fame: 5),
      ],
      played: {'weah': 7, 'lampard': 6, 'torres': 5, 'kane': 0},
      difficulty: 1,
    );
    const lampard = Player(id: 'lampard', name: 'Frank Lampard', fame: 5);
    const weah = Player(id: 'weah', name: 'George Weah', fame: 5);
    const torres = Player(id: 'torres', name: 'Fernando Torres', fame: 5);
    Widget view(HatTrickController c, {Widget? header}) => BuzzGameView(
          round: round,
          controller: c,
          question: (compact) => HatTrickCard(
            clubs: [for (final club in set.clubs) club.name],
            compact: compact,
            picks: [
              for (final e in c.picks.entries)
                HatTrickPickView(
                  team: t.teamName(e.key),
                  colorIndex: t.config.teams[e.key].colorIndex,
                  player: e.value.player.name,
                  hits: e.value.clubs,
                  points: e.value.points,
                ),
            ],
          ),
          resolvedHeader: header,
          resolvedDetail: Column(children: [
            Text('THE HAT-TRICK ANSWER', style: AppText.label(13, color: Palette.gold)),
            const SizedBox(height: 6),
            const Chip(label: Text('George Weah')),
          ]),
          timerLabel: 'YOUR GO',
          commentary: null,
          onFinished: () {},
        );
    final c = HatTrickController(teamCount: 3, questions: [set])
      ..buzz(0)
      ..submit(lampard);
    await shot(tester, 'hattrick_one_in', view(c));
    // Alex buzzes: the clubs drop to one row over the answer box.
    c.buzz(1);
    await shot(tester, 'hattrick_answering', view(c));
    c
      ..submit(torres)
      ..buzz(2)
      ..submit(weah);
    await shot(tester, 'hattrick_all_in',
        view(c, header: Text('HAT-TRICK!', style: AppText.headline(34, color: Palette.yellow))));
    final soloT = Tournament(TournamentConfig(teams: [TeamSetup(name: 'You', colorIndex: 0)]));
    await shot(
        tester,
        'hattrick_solo',
        BuzzGameView(
          round: RoundContext(tournament: soloT, multiplier: 1, onComplete: (_) {}),
          controller: HatTrickController(teamCount: 1, questions: [set]),
          question: (compact) =>
              HatTrickCard(clubs: [for (final club in set.clubs) club.name], compact: compact),
          resolvedDetail: const SizedBox(),
          timerLabel: 'CLOCK',
          commentary: null,
          onFinished: () {},
        ));
  }, skip: !_shots);

  // The pundit's line in place of the game's title, and the answering
  // screen with the question on top.
  testWidgets('Commentary and answering', (tester) async {
    final t = Tournament(TournamentConfig(teams: [
      TeamSetup(name: 'Home', colorIndex: 0),
      TeamSetup(name: 'Away', colorIndex: 1),
    ]));
    final round = RoundContext(tournament: t, multiplier: 1, onComplete: (_) {});
    Widget view(ClubConnectionsController c, String? commentary) => BuzzGameView(
          round: round,
          controller: c,
          question: (compact) => ClubsCard(a: 'AC Milan', b: 'Chelsea', compact: compact),
          resolvedDetail: const SizedBox(),
          timerLabel: 'STEAL IT',
          commentary: commentary,
          onFinished: () {},
        );
    await shot(tester, 'cc_title', view(ClubConnectionsController(teamCount: 2, questions: [arsenalBarca()]), null));
    // Solo: the full-size question and one Answer button.
    final soloT = Tournament(TournamentConfig(teams: [TeamSetup(name: 'You', colorIndex: 0)]));
    await shot(
        tester,
        'cc_solo',
        BuzzGameView(
          round: RoundContext(tournament: soloT, multiplier: 1, onComplete: (_) {}),
          controller: ClubConnectionsController(teamCount: 1, questions: [arsenalBarca()]),
          question: (compact) => ClubsCard(a: 'AC Milan', b: 'Chelsea', compact: compact),
          resolvedDetail: const SizedBox(),
          timerLabel: 'CLOCK',
          commentary: null,
          onFinished: () {},
        ));
    await shot(tester, 'cc_commentary',
        view(ClubConnectionsController(teamCount: 2, questions: [arsenalBarca()]), 'Not even in the same postcode.'));
    await shot(
        tester,
        'table_commentary',
        Column(children: [
          RoundTableHeader(
              data: const {'round': 6, 'of': 6, 'game': 'Penalties', 'colour': 0xFFFFCC29},
              commentary: 'They think it’s all over… it is now!'),
        ]));
    services.settings.typeAnswers = true;
    final answering = ClubConnectionsController(teamCount: 2, questions: [arsenalBarca()])..buzz(0);
    await shot(tester, 'cc_answering', view(answering, null));
    await shot(tester, 'cc_answering_typing', view(answering, null),
        then: () => tester.enterText(find.byType(TextField), 'Desa'));
    // Score strips with three and five teams and a long "extra": every box the same height.
    await shot(
        tester,
        'score_strip_teams',
        Column(children: [
          ScoreStrip(
            round: '3/4',
            highlightTeam: 0,
            teams: const [('Home', 0, 4), ('Away', 1, 7), ('Ultras', 2, 2)],
            extra: (i) => const ['♥♥  4 named', '♥  2 named', '♥  2 named'][i],
          ),
          ScoreStrip(
            round: '3/4',
            highlightTeam: 3,
            teams: const [('Home', 0, 4), ('Away', 1, 7), ('Ultras', 2, 2), ('Barmy Army', 3, 9), ('Kop', 4, 1)],
            extra: (i) => const ['♥♥♥  4 named', '♥  2 named', '♥  2 named', '♥♥  10 named', '1 ▢'][i],
          ),
        ]));
    // Career Path typing: the clubs squeeze up so the names under the box show.
    // Zlatan's real eight clubs: the most a trail has to squeeze up.
    const zlatanFull = CareerPath(player: zlatan, difficulty: 1, spells: [
      CareerSpell(club: Club(id: 'malmo', name: 'Malmö FF', fame: 3), startYear: 1999, endYear: 2001),
      CareerSpell(club: ajax, startYear: 2001, endYear: 2004),
      CareerSpell(club: juventus, startYear: 2004, endYear: 2006),
      CareerSpell(club: inter, startYear: 2006, endYear: 2009),
      CareerSpell(club: barcelona, startYear: 2009, endYear: 2011),
      CareerSpell(club: Club(id: 'milan', name: 'AC Milan', fame: 5), startYear: 2010, endYear: 2012),
      CareerSpell(club: Club(id: 'psg', name: 'Paris Saint-Germain', fame: 5), startYear: 2012, endYear: 2016),
      CareerSpell(club: Club(id: 'manutd', name: 'Manchester United', fame: 5), startYear: 2016, endYear: 2018),
    ]);
    final careerTyping = CareerPathController(teamCount: 2, questions: [zlatanFull])
      ..revealed = 8
      ..buzz(0);
    await shot(
        tester,
        'career_answering_typing',
        BuzzGameView(
          round: round,
          controller: careerTyping,
          question: (compact) => CareerTrail(
              spells: careerTyping.current.spells,
              shown: careerTyping.revealed,
              highlight: careerTyping.revealed - 1,
              maxHeight: compact ? 190 : 250),
          resolvedDetail: const SizedBox(),
          timerLabel: 'NEXT CLUB IN',
          commentary: null,
          onFinished: () {},
        ),
        then: () => tester.enterText(find.byType(TextField), 'Zla'));
    services.settings.typeAnswers = false;
    await shot(
      tester,
      'ttt_steal_tags',
      column(
          _scores(extra: const ['1 ▢', '1 ▢']),
          TttLayout(
              data: {
                ...ttt('choosing'),
                'claimed': ['Luka Modrić', null, null, null, 'Divock Origi', null, null, null, null],
                'stealable': [0, 4],
              },
              onTap: (_) {},
              bottom: const SizedBox.shrink())),
    );
    await shot(
      tester,
      'ttt_commentary',
      column(
          _scores(extra: const ['1 ▢', '1 ▢']),
          TttLayout(
              data: ttt('choosing'),
              commentary: 'Swing and a miss.',
              onTap: (_) {},
              bottom: const Text('Tap an empty square…', textAlign: TextAlign.center))),
    );
  }, skip: !_shots);

  // The rules before a game, as the main phone shows them (points in yellow).
  testWidgets('Rules', (tester) async {
    final t = Tournament(TournamentConfig(teams: [
      TeamSetup(name: 'Home', colorIndex: 0),
      TeamSetup(name: 'Away', colorIndex: 1),
    ]));
    for (final (name, mode) in [('rules_under_the_radar', GameModeId.pointless), ('rules_noughts_crosses', GameModeId.ticTacToe), ('rules_501', GameModeId.checkout501)]) {
      await shot(tester, name, RoundIntroScreen(key: UniqueKey(), tournament: t, mode: mode, multiplier: 1));
    }
  }, skip: !_shots);

  final answers = [
    {'team': 0, 'label': 'Thierry Henry', 'score': 12, 'valid': true},
    {'team': 1, 'label': 'Cesc Fàbregas', 'score': 31, 'valid': true},
    {'team': 0, 'label': 'Gilles Grimandi', 'score': 0, 'valid': true},
  ];
  Map<String, Object?> pt(String phase) => {
        'phase': phase,
        'prompt': 'French players who played for Arsenal',
        'team': 1,
        'teams': _teams,
        'totals': [12, 31],
        'answers': answers,
        'go': 2,
        'per': 2,
        'tie': false,
        'points': [3, 0],
        'all': [
          {'n': 'Gilles Grimandi', 's': 0, 'said': true},
          {'n': 'Thierry Henry', 's': 12, 'said': true},
          {'n': 'Robert Pirès', 's': 20, 'said': false},
        ],
      };

  testWidgets('Pointless', (tester) async {
    await shot(tester, 'pt_answering', column(_scores(), PtLayout(data: pt('answering'), answerBox: Column(children: [_timer(), _picker()]))));
    await shot(tester, 'pt_reveal', column(_scores(), PtLayout(data: pt('reveal'), answerBox: const SizedBox())),
        then: () => tester.pump(const Duration(seconds: 3)));
    await shot(tester, 'pt_finished', column(_scores(), PtLayout(data: pt('finished'), answerBox: const SizedBox())));
  }, skip: !_shots);

  Map<String, Object?> co(String phase) => {
        'phase': phase,
        'prompt': 'Premier League apps + goals for Arsenal',
        'team': 0,
        'teams': _teams,
        'remaining': [137, 260],
        'history': [
          [
            {'s': 'Henry −228', 'ok': true},
            {'s': 'Pass ✗', 'ok': false},
          ],
          [
            {'s': 'Adams BUST', 'ok': false},
          ],
        ],
        'dart': 3,
        'maxDarts': 6,
        'checkedOut': false,
        'last': {'team': 0, 'label': 'Robert Pirès', 'outcome': 'scored', 'apps': 189, 'goals': 62, 'value': 251, 'before': 388, 'after': 137},
        'winners': [0],
        'winPoints': 3,
        'unused': [
          {'n': 'Patrick Vieira', 'v': 308},
          {'n': 'Freddie Ljungberg', 'v': 216},
        ],
      };

  testWidgets('501', (tester) async {
    await shot(tester, 'co_answering', column(_scores(), CoLayout(data: co('answering'), answerBox: Column(children: [_timer(), _picker()]))));
    await shot(tester, 'co_reveal', column(_scores(), CoLayout(data: co('reveal'), answerBox: const SizedBox())));
    await shot(tester, 'co_finished', column(_scores(), CoLayout(data: co('finished'), answerBox: const SizedBox())));
  }, skip: !_shots);

  Map<String, Object?> bid(String phase) => {
        'phase': phase,
        'prompt': 'French players at Arsenal',
        'teams': _teams,
        'team': 1,
        'holder': 0,
        'bid': 7,
        'max': 31,
        'min': 8,
        'seconds': 60,
        'canRaise': true,
        'canChallenge': true,
        'canPass': false,
        'out': const [],
        'count': 3,
        'correct': 4,
        'named': ['Thierry Henry', 'Robert Pirès', 'Patrick Vieira', 'Sylvain Wiltord'],
        'done': false,
        'winner': 1,
        'points': 3,
        'full': ['Thierry Henry', 'Patrick Vieira', 'Robert Pirès', 'Olivier Giroud'],
      };

  testWidgets('Bidding War', (tester) async {
    await shot(
      tester,
      'bid_bidding',
      column(
          _scores(),
          BidLayout(
            data: bid('bidding'),
            controls: BidControls(data: bid('bidding'), onRaise: (_) {}, onChallenge: () {}, onPass: () {}),
            answerBox: const SizedBox(),
          )),
    );
    await shot(
      tester,
      'bid_answering',
      BidLayout(data: bid('answering'), controls: const SizedBox(), answerBox: Column(children: [_timer(), _picker()])),
    );
    await shot(tester, 'bid_result', column(_scores(), BidLayout(data: bid('finished'), controls: const SizedBox(), answerBox: const SizedBox())));
  }, skip: !_shots);

  // Half-Time Teaser mock-ups.
  const teaserQ = 'played in El Clásico, the Manchester derby AND the North London derby';
  const teaserTeams = [('Home', 0), ('Away', 1)];

  testWidgets('Teaser', (tester) async {
    await shot(
        tester,
        'teaser_halftime',
        TeaserHalfTime(
            question: teaserQ,
            fraction: 0.7,
            seconds: 63,
            onLater: () {},
            bottom: TeaserTeams(teams: teaserTeams, onPick: (_) {})));
    await shot(
        tester,
        'teaser_answering',
        TeaserHalfTime(
            question: teaserQ,
            fraction: 0.55,
            seconds: 49,
            bottom: TeaserBuzzed(team: 'Home', colorIndex: 0, secondsLeft: 11, answerBox: _picker())));
    await shot(
        tester,
        'teaser_phone',
        TeaserHalfTime(
            question: teaserQ,
            fraction: 0.7,
            seconds: 63,
            bottom: TeaserPhoneBuzzer(team: 'Away', colorIndex: 1, onBuzz: () {})));
    await shot(
        tester,
        'teaser_reveal',
        Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: TeaserReveal(
                question: teaserQ,
                answers: const ['Emmanuel Adebayor', 'Alexis Sánchez', 'Nicolas Anelka', 'Gabriel Jesus']),
          ),
        ));

    // Between games: the table after a round, with the teaser still open.
    Widget summary({required bool open}) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text('ROUND 4 OF 6', style: AppText.label(16)),
            Text('BIDDING WAR', style: AppText.headline(40, color: Palette.gold)),
            const SizedBox(height: 24),
            Text('THE TABLE', style: AppText.label(14)),
            const SizedBox(height: 8),
            for (final (pos, (name, color, score, plus)) in const [('Home', 0, 9, 2), ('Away', 1, 6, 0)].indexed)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(14),
                  border: Border(left: BorderSide(color: Palette.team(color), width: 6)),
                ),
                child: Row(children: [
                  SizedBox(width: 28, child: Text('${pos + 1}', style: AppText.headline(26, color: Palette.muted))),
                  Expanded(child: Text(name.toUpperCase(), style: AppText.headline(28))),
                  if (plus > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text('+$plus', style: AppText.headline(24, color: Palette.yellow)),
                    ),
                  Text('$score', style: AppText.headline(36)),
                ]),
              ),
            const Spacer(),
            if (open) ...[
              const SizedBox(height: 12),
              TeaserChip(onPressed: () {}),
              const SizedBox(height: 16),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Palette.gold, width: 2),
                  ),
                  child: Column(children: [
                    const TeaserPrompt(question: teaserQ, compact: true),
                    const SizedBox(height: 14),
                    TeaserTeams(teams: teaserTeams, locked: const {1}, onPick: (_) {}),
                  ]),
                ),
              ),
            // While the teaser's open, Next Challenge waits a few seconds so a
            // team that's locked out can't skip past it before the others buzz.
            BigButton(label: open ? 'Next challenge in 5' : 'Next challenge', icon: Icons.casino, onPressed: open ? null : () {}),
          ]),
        );
    await shot(tester, 'teaser_between_games', summary(open: true));
    await shot(tester, 'teaser_tapped', summary(open: false));
  }, skip: !_shots);

  // ---------------------------------------------------------------------------
  // Store listing: phone screenshots (a caption over a real screen) and the
  // Play feature graphic. Written to docs/store/.
  Future<void> storeShot(WidgetTester tester, String name, String caption, Widget screen,
      {bool wrap = true, Future<void> Function()? then, String? sub}) async {
    // 1080 x 1920 (9:16), drawn at 3x.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const phone = Size(390, 844);
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: Builder(
          // Material: the app's text styling (no yellow underline on the caption).
          builder: (context) => Material(
            type: MaterialType.transparency,
            child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF17573A), Palette.pitchDeep],
              ),
            ),
            child: Column(children: [
              const SizedBox(height: 34),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: SizedBox(
                  height: 92,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(caption,
                            textAlign: TextAlign.center,
                            style: AppText.headline(31, color: Palette.yellow).copyWith(height: 1.02)),
                        // A smaller second line in white, so it backs up the headline
                        // instead of competing with it.
                        if (sub != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(sub, textAlign: TextAlign.center, style: AppText.label(17, color: Palette.text)),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: phone.width / phone.height,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 26),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: Colors.white24, width: 1.5),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 10))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(25),
                        child: FittedBox(
                          child: SizedBox.fromSize(
                            size: phone,
                            child: MediaQuery(
                              data: MediaQuery.of(context).copyWith(size: phone, padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
                              child: wrap ? Scaffold(body: PitchBackground(child: SafeArea(child: screen))) : screen,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    if (then != null) {
      await then();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/store/$name.png'));
  }

  testWidgets('Store screenshots', (tester) async {
    await services.settings.saveConfig(TournamentConfig(teams: [
      TeamSetup(name: 'Home', colorIndex: 0, players: ['Gav', 'Sam']),
      TeamSetup(name: 'Away', colorIndex: 1, players: ['Alex', 'Jo']),
    ]));
    await storeShot(tester, 'phone_1_home', 'THE FOOTBALL\nPARTY GAME', const HomeScreen(), wrap: false, sub: 'NO WI-FI NEEDED');

    final t = Tournament(TournamentConfig(teams: [
      TeamSetup(name: 'Home', colorIndex: 0),
      TeamSetup(name: 'Away', colorIndex: 1),
    ]));
    await storeShot(
      tester,
      'phone_2_buzz',
      'NAME A PLAYER WHO\nPLAYED FOR BOTH',
      BuzzGameView(
        round: RoundContext(tournament: t, multiplier: 1, onComplete: (_) {}),
        controller: ClubConnectionsController(teamCount: 2, questions: [arsenalBarca()]),
        question: (compact) => ClubsCard(a: 'Southampton', b: 'Bayern Munich', compact: compact),
        resolvedDetail: const SizedBox(),
        timerLabel: 'BUZZ IN',
        commentary: null,
        onFinished: () {},
      ),
      wrap: false,
      sub: 'EVERY PAIR HAS AN ANSWER. BUZZ IN FIRST.',
    );
    services.settings.typeAnswers = false; // the mic, for the noughts shot
    // Friends join from the QR code: three phones in, one still to come.
    final joinTeams = [
      TeamSetup(name: 'Home', colorIndex: 0, players: ['Gav', 'Sam']),
      TeamSetup(name: 'Away', colorIndex: 1, players: ['Alex', 'Jo']),
    ];
    final joinRoom = (await tester.runAsync(() async {
      final link = MemoryRoomLink();
      final host = await HostRoom.open(link, joinTeams);
      for (final (device, team, name) in [('g', 0, 'Gav'), ('s', 0, 'Sam'), ('a', 1, 'Alex')]) {
        final g = GuestRoom(link, host.code, device)..start();
        await g.claim(team, name);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return host;
    }))!;
    await storeShot(
      tester,
      'phone_3_join',
      'FRIENDS JOIN ON THEIR OWN PHONES.\nNO DOWNLOAD NEEDED.',
      Center(child: RoomSheet(room: joinRoom, teams: joinTeams)),
    );
    await tester.runAsync(() async => joinRoom.dispose());
    await storeShot(
      tester,
      'phone_5_noughts',
      'NOUGHTS & CROSSES,\nFOOTBALL STYLE',
      // Mid-answer, mic on and hearing it: shows off voice answers too.
      column(
          _scores(extra: const ['1 ▢', '1 ▢']),
          TttLayout(
            // Clubs, a country, a manager and a trophy: the mix the real grids use.
            data: {
              ...ttt('answering'),
              'rows': ['Arsenal', 'Chelsea', 'Managed by Mourinho'],
              'cols': ['Barcelona', 'Brazil', 'World Cup winner'],
              'claimed': ['Thierry Henry', null, null, null, 'Willian', null, null, null, null],
            },
            bottom: Column(children: [
              Text('ARSENAL  +  WORLD CUP WINNER', textAlign: TextAlign.center, style: AppText.headline(20, color: Palette.yellow)),
              _timer(),
              _picker(voice: _ShotVoice(services.settings, heard: 'patrick vieira')),
            ]),
          )),
      sub: 'SAY YOUR ANSWER OUT LOUD',
    );
    // Solo XI: the lineup in full, an ANSWER button where the box goes.
    await shot(
      tester,
      'xi_solo_answer',
      XiLayout(
        data: {...xi('ticking'), 'named': {'henry': 0, 'lehmann': 0}},
        scores: const Text(''),
        left: 9,
        answerBox: PlayerPicker(key: UniqueKey(), gateFor: 'xi-shot', index: PlayerIndex(allPlayers), onPick: (_) {}, onPass: () {}),
      ),
    );
    services.settings.typeAnswers = true;
    await storeShot(
      tester,
      'phone_6_xi',
      'NAME THE XI BEFORE\nTHE BOMB GOES OFF',
      XiLayout(
        data: {
          ...xi('ticking'),
          'named': {'henry': 0, 'vieira': 1, 'cole': 0, 'lehmann': 1},
        },
        scores: _scores(extra: const ['♥♥♥  2 named', '♥♥  2 named']),
        left: 12,
        // Typing a starter, the list of names popping up under the box.
        answerBox: PlayerPicker(
          key: UniqueKey(),
          index: PlayerIndex(const [
            ...allPlayers,
            Player(id: 'bergkamp', name: 'Dennis Bergkamp', fame: 5, nationality: 'NED', position: 'FW'),
            Player(id: 'bergwijn', name: 'Steven Bergwijn', fame: 3, nationality: 'NED', position: 'FW'),
            Player(id: 'berbatov', name: 'Dimitar Berbatov', fame: 5, nationality: 'BUL', position: 'FW'),
          ]),
          onPick: (_) {},
          onPass: () {},
        ),
      ),
      then: () => tester.enterText(find.byType(TextField), 'Dennis Bergkam'),
    );
    // Not one of the free Warm-Up Cup's careers (Yaya Touré, Crouch, Keane).
    final career = CareerPathController(teamCount: 2, questions: [zlatanPath()])..revealed = 3;
    await storeShot(
      tester,
      'phone_4_career',
      'GUESS THE PLAYER\nFROM THEIR CLUBS',
      BuzzGameView(
        round: RoundContext(tournament: t, multiplier: 1, onComplete: (_) {}),
        controller: career,
        question: (compact) => Column(children: [
          Text('WORTH ${career.pointsAvailable} POINTS', style: AppText.headline(compact ? 18 : 24, color: Palette.gold)),
          CareerTrail(spells: career.current.spells, shown: career.revealed, highlight: career.revealed - 1, maxHeight: compact ? 190 : 250),
        ]),
        resolvedDetail: const SizedBox(),
        timerLabel: 'NEXT CLUB IN',
        commentary: null,
        onFinished: () {},
      ),
      wrap: false,
    );
    await storeShot(
      tester,
      'phone_7_bidding',
      'HOW MANY CAN\nYOU NAME? PROVE IT.',
      column(
          _scores(),
          BidLayout(
            // Not the free Warm-Up Cup's question: a real category, its real count.
            data: {...bid('bidding'), 'prompt': 'Players from Brazil who have played for Barcelona', 'max': 33},
            controls: BidControls(data: bid('bidding'), onRaise: (_) {}, onChallenge: () {}, onPass: () {}),
            answerBox: const SizedBox(),
          )),
    );
    services.settings.recordSolo('cup', 'medium', 412);
    await storeShot(tester, 'phone_8_solo', 'OR PLAY SOLO AND\nBEAT YOUR BEST', const SoloScreen(), wrap: false, sub: 'NO ADS. EVER.');
  }, skip: !_shots);

  testWidgets('Store feature graphic', (tester) async {
    tester.view.physicalSize = const Size(1024, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Material(
        type: MaterialType.transparency,
        child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(-0.45, 0), radius: 1.1, colors: [Color(0xFF17573A), Palette.pitchDeep]),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 70),
        child: Row(children: [
          const QuizinhoBadge(size: 330),
          const SizedBox(width: 50),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const QuizinhoWordmark(size: 92),
              const SizedBox(height: 26),
              Text('THE FOOTBALL\nPARTY QUIZ', style: AppText.headline(50).copyWith(height: 1.0)),
              const SizedBox(height: 16),
              Text('Buzz in · Name the player · Lift the cup', style: AppText.label(22, color: Palette.yellow)),
            ]),
          ),
        ]),
      ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/store/feature_graphic.png'));
  }, skip: !_shots);

  // 40 Medium grids from the real database and the game's own settings (as
  // consecutive games: each avoids the ones before), for checking by eye.
  test('Medium grids sample', () async {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    int fame(String id) => repo.players.byId(id)?.fame ?? 0;
    final conns = [...await repo.allClubConnections(), ...await repo.categoryClubPairs()];
    final rnd = Random(20261119);
    final seen = <String>{};
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < 40; i++) {
      final g = generateTicTacToeGrid(conns,
          random: rnd,
          minFame: 4,
          maxLevel: 2,
          minKnownAnswers: 2,
          answerFame: fame,
          avoid: seen,
          trophies: trophiesFor(Difficulty.medium))!;
      seen.add(g.id);
      out.add({
        'rows': [for (final c in g.rows) c.name],
        'cols': [for (final c in g.cols) c.name],
        'squares': [
          for (final a in g.answers)
            {
              'count': a.length,
              'top': [
                for (final id in (a.toList()..sort((x, y) => fame(y).compareTo(fame(x)))).take(4))
                  repo.players.byId(id)?.name ?? id,
              ],
            },
        ],
      });
    }
    File('docs/shots/grids_medium.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  }, skip: !_shots);

  // A joined phone: the rules, and the teaser laid out like the main phone's.
  testWidgets('Joined phone', (tester) async {
    const me = RoomMember(device: 'me', name: 'Alex', team: 0);
    Widget phone(Map<String, Object?> view) => guestGamePreview(
        GuestRoom(MemoryRoomLink(), 'ABCD', 'me')
          ..teams = [TeamSetup(name: 'Home', colorIndex: 0, players: ['Alex']), TeamSetup(name: 'Away', colorIndex: 1)]
          ..view = view,
        me);
    const mode = GameModeId.pointless;
    await shot(
        tester,
        'guest_rules',
        phone({
          'kind': 'rules',
          'title': mode.title,
          'tagline': mode.tagline,
          'rules': mode.rules,
          'who': mode.whoPlays,
          'color': mode.color.toARGB32(),
          'round': '3/6',
          'teams': _teams,
        }));
    Map<String, Object?> teaser(String phase) => {
          'kind': 'buzz',
          'mode': 'teaser',
          'q': '3-T0',
          'phase': phase,
          'title': 'HALF-TIME TEASER',
          'round': '3/6',
          'teams': _teams,
          'canBuzz': [0, 1],
          'question': {
            'teaser': 'played in El Clásico, the Manchester derby AND the North London derby',
            'prefix': 'NAME A PLAYER WHO…',
            'worth': 5,
            'halfTime': true,
            'clock': 'BUZZ IN',
          },
          if (phase == 'answering') 'answering': {'team': 0, 'name': 'Alex', 'device': 'me'},
          if (phase == 'answering') 'answers': <String>[],
          'left': phase == 'answering' ? 11 : 62,
          'total': phase == 'answering' ? 15 : 90,
        };
    await shot(tester, 'guest_teaser', phone(teaser('open')));
    await shot(tester, 'guest_teaser_answering', phone(teaser('answering')));
    answerTyping.value = true;
    await shot(tester, 'guest_teaser_typing', phone(teaser('answering')));
    answerTyping.value = false;
    await shot(
        tester,
        'guest_teaser_reveal',
        phone({
          ...teaser('resolved'),
          'question': {'teaser': 'played in El Clásico, the Manchester derby AND the North London derby', 'prefix': 'NAME A PLAYER WHO…', 'worth': 3, 'noClock': true},
          'result': {'scored': false, 'reveal': ['Emmanuel Adebayor', 'Carlos Tevez']},
        }));
    // Between games: the table, with the teaser for any phone to open.
    final table = {
      'kind': 'table',
      'round': 3,
      'of': 6,
      'game': GameModeId.clubConnections.title,
      'colour': GameModeId.clubConnections.color.toARGB32(),
      'rows': [
        {'name': 'Home', 'colour': 0, 'score': 8, 'plus': 3},
        {'name': 'Away', 'colour': 1, 'score': 6, 'plus': 0},
      ],
      'teaser': {
        ...teaser('open'),
        'question': {'teaser': 'played in El Clásico, the Manchester derby AND the North London derby', 'prefix': 'NAME A PLAYER WHO…', 'worth': 3, 'noClock': true},
      }..remove('left')..remove('total'),
    };
    await shot(tester, 'guest_table_teaser', phone(table));
  }, skip: !_shots);

  // Full time with the teaser unsolved: one last go, or straight to the answers.
  testWidgets('Full time teaser', (tester) async {
    await tester.runAsync(() => services.teasers);
    Tournament finished() {
      final t = Tournament(TournamentConfig(
        teams: [TeamSetup(name: 'Home', colorIndex: 0), TeamSetup(name: 'Away', colorIndex: 1)],
        rounds: 4,
      ));
      for (final (h, a) in const [(3, 1), (0, 3), (2, 2), (3, 0)]) {
        t.recordRound(RoundResult(mode: GameModeId.clubConnections, points: {0: h, 1: a}));
      }
      t.teaser = TeaserState(WarmUpCup.teaser)..halfTimeDone = true;
      return t;
    }

    // Final round won by the team already ahead: the pundit over the game's name.
    final allOver = Tournament(TournamentConfig(
      teams: [TeamSetup(name: 'Home', colorIndex: 0), TeamSetup(name: 'Away', colorIndex: 1)],
      rounds: 4,
    ));
    for (final (h, a) in const [(3, 0), (0, 3), (3, 0), (3, 0)]) {
      allOver.recordRound(RoundResult(mode: GameModeId.clubConnections, points: {0: h, 1: a}));
    }
    await shot(tester, 'summary_commentary', RoundSummaryScreen(tournament: allOver),
        then: () => tester.pump(const Duration(milliseconds: 400)));
    // Between games (round 3 of 6): the question under the table.
    final mid = Tournament(TournamentConfig(
      teams: [TeamSetup(name: 'Home', colorIndex: 0), TeamSetup(name: 'Away', colorIndex: 1)],
      rounds: 6,
    ));
    for (final (h, a) in const [(3, 1), (0, 3), (3, 0)]) {
      mid.recordRound(RoundResult(mode: GameModeId.clubConnections, points: {0: h, 1: a}));
    }
    mid.teaser = TeaserState(WarmUpCup.teaser)..halfTimeDone = true;
    await shot(tester, 'teaser_between_games_live', RoundSummaryScreen(tournament: mid), then: () async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 500));
    });
    await shot(tester, 'fulltime_teaser', RoundSummaryScreen(tournament: finished()));
    await shot(tester, 'fulltime_teaser_last_chance', RoundSummaryScreen(tournament: finished()), then: () async {
      await tester.tap(find.text('LAST CHANCE AT THE TEASER'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 500));
    });
  }, skip: !_shots);

  // Penalties: a drawn match at full time, the kicks, a save, the winner.
  testWidgets('Penalties', (tester) async {
    final teams = [
      {'name': 'Home', 'color': 0, 'kicks': [true, false, true]},
      {'name': 'Away', 'color': 1, 'kicks': [true, true]},
    ];
    Widget pens(Map<String, Object?> data, {Widget? box, bool tap = false, String? line}) => ShootoutLayout(
          data: data,
          answerBox: box,
          clock: const TimerBar(fraction: 0.6, seconds: 9),
          onPens: () {},
          onDraw: () {},
          onNext: () {},
          onFinish: () {},
          onChoose: tap ? (_) {} : null,
          commentary: line ?? (data['phase'] == 'choice' ? 'Put the kettle on, we’re going to penalties.' : null),
        );
    final box = Column(children: [
      const TimerBar(fraction: 0.6, seconds: 9),
      const SizedBox(height: 10),
      PlayerPicker(index: services.repo.players, onPick: (_) {}, hint: 'Say or type a player…'),
    ]);
    await shot(
        tester,
        'pens_choice',
        pens({
          'phase': 'choice',
          'level': [
            {'name': 'Home', 'color': 0, 'score': 12},
            {'name': 'Away', 'color': 1, 'score': 12},
          ],
        }));
    final kicking = {
      'phase': 'kicking',
      'each': 5,
      'teams': teams,
      'taker': {'name': 'Away', 'color': 1, 'player': 'Sam'},
      'label': 'KICK 3 OF 5',
    };
    await shot(
        tester,
        'pens_two_clubs',
        pens({
          ...kicking,
          'kick': {
            'ask': 'NAME A PLAYER WHO PLAYED FOR',
            'lines': ['LEEDS UNITED', 'AND', 'MANCHESTER UNITED'],
          },
        }, box: box));
    await shot(
        tester,
        'pens_missing_club',
        pens({
          ...kicking,
          'kick': {
            'ask': 'ÁNGEL DI MARÍA · NAME THE MISSING CLUB',
            'path': ['ROSARIO CENTRAL', 'BENFICA', '?', 'MANCHESTER UNITED', 'PARIS SAINT-GERMAIN', 'JUVENTUS', 'BENFICA', 'ROSARIO CENTRAL'],
          },
        }, box: box));
    await shot(
        tester,
        'pens_lineup',
        pens({
          ...kicking,
          'kick': {
            'ask': 'LIVERPOOL V BARCELONA · 4–0 · 2019',
            'lines': ['NAME LIVERPOOL’S MISSING PLAYER'],
            'lineup': [
              ['GK', 'ALISSON', 0],
              ['RB', 'ALEXANDER-ARNOLD', 1], ['CB', 'MATIP', 1], ['CB', 'VAN DIJK', 1], ['LB', 'MILNER', 1],
              ['CM', 'FABINHO', 2], ['CM', 'HENDERSON', 2], ['CM', '?', 2],
              ['RW', 'SHAQIRI', 3], ['ST', 'ORIGI', 3], ['LW', 'MANÉ', 3],
            ],
          },
        }, box: box));
    // Typing: the pitch shrinks so the suggestions fit above the keyboard.
    answerTyping.value = true;
    await shot(
        tester,
        'pens_lineup_typing',
        ShootoutLayout(
          typing: true,
          data: {
            ...kicking,
            'kick': {
              'ask': 'LIVERPOOL V BARCELONA · 4–0 · 2019',
              'lines': ['NAME LIVERPOOL’S MISSING PLAYER'],
              'lineup': [
                ['GK', 'ALISSON', 0],
                ['RB', 'ALEXANDER-ARNOLD', 1], ['CB', 'MATIP', 1], ['CB', 'VAN DIJK', 1], ['LB', 'MILNER', 1],
                ['CM', 'FABINHO', 2], ['CM', 'HENDERSON', 2], ['CM', '?', 2],
                ['RW', 'SHAQIRI', 3], ['ST', 'ORIGI', 3], ['LW', 'MANÉ', 3],
              ],
            },
          },
          answerBox: box,
        ),
        then: () async {
          await tester.enterText(find.byType(TextField), 'Wijn');
          await tester.pump(const Duration(milliseconds: 500));
        });
    answerTyping.value = false;
    await shot(
        tester,
        'pens_over_under',
        pens({
          ...kicking,
          'kick': {
            'ask': 'LEAGUE GAMES FOR STOKE CITY',
            'lines': ['PETER CROUCH', 'OVER OR UNDER 175?'],
            'options': ['OVER 175', 'UNDER 175'],
          },
        }, tap: true));
    await shot(
        tester,
        'pens_who_more',
        pens({
          ...kicking,
          'kick': {
            'ask': 'MORE LEAGUE GOALS IN THEIR CAREER',
            'options': ['JOHN TERRY', 'TRENT ALEXANDER-ARNOLD'],
          },
        }, tap: true));
    await shot(
        tester,
        'pens_sudden_death',
        pens({
          'phase': 'result',
          'each': 5,
          'teams': [
            {'name': 'Home', 'color': 0, 'kicks': [true, false, false, true, true, false, true, true, false, true, true, true]},
            {'name': 'Away', 'color': 1, 'kicks': [true, true, false, false, true, false, true, true, false, true, true, false]},
          ],
          'taker': {'name': 'Away', 'color': 1},
          'label': 'SUDDEN DEATH',
          'scored': false,
          'kick': {
            'ask': 'NAME A PLAYER WHO PLAYED FOR',
            'lines': ['SAMPDORIA', 'AND', 'SOUTHAMPTON'],
          },
          'reveal': 'MAYA YOSHIDA · GRAZIANO PELLÈ',
        }, line: 'Like a keeper rooted to the line.'));
    await shot(
        tester,
        'pens_saved',
        pens({
          'phase': 'result',
          'each': 5,
          'teams': [
            {'name': 'Home', 'color': 0, 'kicks': [true, false, true]},
            {'name': 'Away', 'color': 1, 'kicks': [true, true, false]},
          ],
          'taker': {'name': 'Away', 'color': 1},
          'label': 'KICK 3 OF 5',
          'scored': false,
          'kick': {
            'ask': 'ENGLAND V GERMANY · 1–1 · 1996',
            'lines': ['WHO WAS ENGLAND’S KEEPER?'],
          },
          'reveal': 'DAVID SEAMAN',
        }));
    await shot(
        tester,
        'pens_won',
        pens({
          'phase': 'finished',
          'each': 5,
          'teams': [
            {'name': 'Home', 'color': 0, 'kicks': [true, false, true, true, true]},
            {'name': 'Away', 'color': 1, 'kicks': [true, true, false, false]},
          ],
          'winner': {'name': 'Home', 'color': 0},
          'pens': '4–2',
        }));
  }, skip: !_shots);
}
