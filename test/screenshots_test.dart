// Renders each turn game's shared layout (as a joined phone draws it — the
// host draws the same layout) to PNGs in docs/shots/, so they can be looked
// at without a phone. Only runs in the "Screenshots" workflow (SHOTS=1):
//   SHOTS=1 flutter test test/screenshots_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quizinho/core/app_services.dart';
import 'package:quizinho/core/app_settings.dart';
import 'package:quizinho/core/sound_service.dart';
import 'package:quizinho/core/theme.dart';
import 'package:quizinho/data/in_memory_football_repository.dart';
import 'package:quizinho/domain/player_index.dart';
import 'package:quizinho/games/bidding_war/bidding_war_screen.dart';
import 'package:quizinho/games/checkout_501/checkout_screen.dart';
import 'package:quizinho/games/pointless/pointless_screen.dart';
import 'package:quizinho/games/starting_xi/starting_xi_screen.dart';
import 'package:quizinho/games/tic_tac_toe/tic_tac_toe_screen.dart';
import 'package:quizinho/domain/tournament.dart';
import 'package:quizinho/ui/screens/home_screen.dart';
import 'package:quizinho/ui/screens/setup_screen.dart';
import 'package:quizinho/ui/screens/solo_screen.dart';
import 'package:quizinho/ui/widgets/common.dart';
import 'package:quizinho/ui/widgets/logo.dart';
import 'package:quizinho/ui/widgets/player_picker.dart';

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

Widget _picker() => PlayerPicker(index: PlayerIndex(allPlayers), onPick: (_) {}, onPass: () {});

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

  Future<void> shot(WidgetTester tester, String name, Widget body) async {
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

  testWidgets('App icon, Brazil on the right (preview)', (tester) async {
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
        child: const QuizinhoBadge(size: 880, brazilRight: true),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/shots/icon_brazil_right.png'));
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
}
