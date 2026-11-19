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
import 'package:quizinho/ui/widgets/player_picker.dart';

import 'package:quizinho/data/json_football_repository.dart';
import 'package:quizinho/games/tic_tac_toe/tic_tac_toe_controller.dart';
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
    {'p': 'GK', 'n': 'David Seaman', 'i': 'seaman'},
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
    await shot(tester, 'cc_commentary',
        view(ClubConnectionsController(teamCount: 2, questions: [arsenalBarca()]), 'Not even in the same postcode.'));
    services.settings.typeAnswers = true;
    final answering = ClubConnectionsController(teamCount: 2, questions: [arsenalBarca()])..buzz(0);
    await shot(tester, 'cc_answering', view(answering, null));
    await shot(tester, 'cc_answering_typing', view(answering, null),
        then: () => tester.enterText(find.byType(TextField), 'Desa'));
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
    for (final (name, mode) in [('rules_under_the_radar', GameModeId.pointless), ('rules_noughts_crosses', GameModeId.ticTacToe)]) {
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
    await shot(tester, 'pt_reveal', column(_scores(), PtLayout(data: pt('reveal'), answerBox: const SizedBox())));
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
      {bool wrap = true, Future<void> Function()? then}) async {
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
                    child: Text(caption,
                        textAlign: TextAlign.center,
                        style: AppText.headline(31, color: Palette.yellow).copyWith(height: 1.02)),
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
      TeamSetup(name: 'Home', colorIndex: 0, players: ['Alex', 'Sam']),
      TeamSetup(name: 'Away', colorIndex: 1, players: ['Gav', 'Jo']),
    ]));
    await storeShot(tester, 'phone_1_home', 'THE FOOTBALL\nPARTY GAME', const HomeScreen(), wrap: false);

    final t = Tournament(TournamentConfig(teams: [
      TeamSetup(name: 'Home', colorIndex: 0),
      TeamSetup(name: 'Away', colorIndex: 1),
    ]));
    await storeShot(
      tester,
      'phone_2_buzz',
      'BUZZ IN FIRST.\nNAME THE PLAYER.',
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
    );
    await storeShot(
      tester,
      'phone_3_noughts',
      'NOUGHTS & CROSSES,\nFOOTBALL STYLE',
      column(_scores(extra: const ['1 ▢', '1 ▢']),
          TttLayout(data: ttt('choosing'), onTap: (_) {}, bottom: const Text('Tap an empty square…', textAlign: TextAlign.center))),
    );
    await storeShot(
      tester,
      'phone_4_bidding',
      'HOW MANY CAN\nYOU NAME? PROVE IT.',
      column(
          _scores(),
          BidLayout(
            // Not the free Warm-Up Cup's question: a real category, its real count.
            data: {...bid('bidding'), 'prompt': 'Players from Brazil who played for Barcelona', 'max': 33},
            controls: BidControls(data: bid('bidding'), onRaise: (_) {}, onChallenge: () {}, onPass: () {}),
            answerBox: const SizedBox(),
          )),
    );
    await storeShot(
      tester,
      'phone_5_xi',
      'NAME THE XI BEFORE\nTHE BOMB GOES OFF',
      XiLayout(
        data: xi('ticking'),
        scores: _scores(extra: const ['♥♥♥  2 named', '♥♥  1 named']),
        left: 12,
        answerBox: _picker(),
      ),
    );
    // Not one of the free Warm-Up Cup's careers (Yaya Touré, Crouch, Keane).
    final career = CareerPathController(teamCount: 2, questions: [zlatanPath()])..revealed = 3;
    await storeShot(
      tester,
      'phone_6_career',
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
    await storeShot(tester, 'phone_7_setup', 'TEAMS, FACE-OFFS AND\nEVERYONE\'S OWN PHONE', const SetupScreen(), wrap: false);
    services.settings.recordSolo('cup', 'medium', 412);
    await storeShot(tester, 'phone_8_solo', 'OR PLAY SOLO AND\nBEAT YOUR BEST', const SoloScreen(), wrap: false);
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
          random: rnd, minFame: 4, maxLevel: 2, minKnownAnswers: 2, answerFame: fame, avoid: seen)!;
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
}
