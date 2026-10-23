# Quizinho — the football party game

One phone, 2–6 teams, a night of shouting at each other about footballers.
The app is quizmaster, referee, timer and scorekeeper.

**Phase 1 MVP (this build):** team setup · spinning game wheel · Club Connections ·
Career Path · Starting XI Bomb · Wildcard (double points) · buzzers, steals,
lives · sound effects · on-screen commentary · winner screen · offline SQLite
database · unit tests · cloud iOS builds.

➡ **Just want to try it? Play in a browser: [docs/PLAY_IN_BROWSER.md](docs/PLAY_IN_BROWSER.md)**
➡ Later, on a real iPhone via TestFlight: [docs/SETUP_IPHONE.md](docs/SETUP_IPHONE.md)

## Project layout

```
lib/
  main.dart                     startup: settings, database, sounds
  core/                         theme, sound, settings, commentary, service wiring
  data/                         models + repositories (SQLite for the app, in-memory for tests)
  domain/                       pure rules: tournament scoring, game registry, name matching
  games/
    buzz_race_controller.dart   shared buzz / lock-out / steal rules
    buzz_game_view.dart         shared buzzer-game layout
    club_connections/           controller (rules) + screen (UI)
    career_path/
    starting_xi/
  ui/
    match_flow.dart             wheel → intro → game → summary → winner
    screens/  widgets/
assets/
  db/football.db                built by data_pipeline/build_db.py
  sounds/*.wav                  synthesised by scripts/generate_sounds.py (original, licence-free)
  fonts/                        Barlow Condensed + Inter (SIL Open Font Licence)
data_pipeline/                  seed data, DB builder, Wikidata fetcher, licensing notes
test/                           rules, scoring, matching, widget smoke test
codemagic.yaml                  iOS → TestFlight
.github/workflows/              CI (tests + Android APK) and one-off platform bootstrap
```

## Design decisions

- **Rules live in plain Dart controllers** driven by `advance(dt)`, so every rule
  (steals, lock-outs, reveals, lives, bonuses) is unit-tested without a device.
- **Answers are judged by player ID.** Typing 2–3 letters and tapping a name is
  the fast, reliable input today; speech recognition (Phase 2) feeds the same
  `PlayerIndex.resolveConfidently`, which refuses to guess between two
  "Ronaldo"s instead of penalising a team for a transcription error.
- **Data gaps never cost a team.** "Not listed?" lets the room vote on an answer
  the database doesn't know.
- **No backend, no login, no Firebase.** Everything is bundled and offline.
- **Content updates are safe.** The DB is versioned; a new version replaces the
  old file, while settings live separately.

## Adding a game

1. Add a value to `GameModeId` (`lib/domain/game_mode.dart`) with title and rules.
2. Write a controller (extend `BuzzRaceController` if it's a buzzer game) + tests.
3. Write a screen that takes a `RoundContext` and calls `onComplete(RoundResult)`.
4. Add one line to `MatchFlow._gameFor` and a colour/icon in `GameModeStyle`.

## Data status

The bundled football data is a **demo set written from general knowledge and
not yet fact-checked** (`verified = 0`, shown in the app). The verified
Wikidata pipeline is the first Phase 2 job — see `data_pipeline/README.md`.

## Local commands (if you ever have Flutter installed)

```bash
flutter pub get && flutter test
python3 data_pipeline/build_db.py
python3 scripts/generate_sounds.py
```
