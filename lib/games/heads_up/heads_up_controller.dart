import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';

class HeadsUpPack {
  const HeadsUpPack({required this.id, required this.title, required this.cards, this.eras = 31});
  final String id;
  final String title;
  final List<String> cards;

  /// Era bit flags the pack belongs to (see Era in models.dart).
  final int eras;
}

List<HeadsUpPack> parseHeadsUpPacks(String source) {
  final doc = jsonDecode(source) as Map<String, dynamic>;
  return [
    for (final p in doc['packs'] as List)
      HeadsUpPack(
        id: p['id'] as String,
        title: p['title'] as String,
        eras: (p['eras'] as int?) ?? 31,
        cards: [for (final c in p['cards'] as List) c as String],
      ),
  ];
}

enum HeadsUpPhase {
  /// Pass the phone; pick a pack; tap start.
  ready,
  countdown,
  playing,

  /// Show this turn's cards before the next team.
  turnOver,
  finished,
}

class CardResult {
  const CardResult(this.card, this.correct);
  final String card;
  final bool correct;
}

/// Football Heads Up: one player holds the phone to their forehead, their
/// team describes the name, tilt down for correct, up to pass. Each team
/// gets one timed turn per round; 1 point per correct card.
class HeadsUpController extends ChangeNotifier {
  HeadsUpController({
    required this.teamCount,
    this.turnSeconds = 60,
    this.countdownSeconds = 3,
    int startTeam = 0,
  }) : currentTeam = startTeam % teamCount {
    for (var t = 0; t < teamCount; t++) {
      correctByTeam[t] = 0;
    }
  }

  final int teamCount;
  final int turnSeconds;
  final int countdownSeconds;

  HeadsUpPhase phase = HeadsUpPhase.ready;
  int currentTeam;
  int turnsTaken = 0;
  double secondsLeft = 0;
  String? currentCard;
  final Map<int, int> correctByTeam = {};
  List<CardResult> turnResults = [];

  /// Every card shown this round (so the screen can mark them used).
  final Set<String> shown = {};

  List<String> _deck = const [];
  int _next = 0;

  int get turnCorrect => turnResults.where((r) => r.correct).length;
  double get fractionLeft => turnSeconds == 0 ? 0 : (secondsLeft / turnSeconds).clamp(0.0, 1.0);
  bool get isLastTurn => turnsTaken >= teamCount;

  /// Begin the 3-2-1 countdown with this shuffled deck.
  void startTurn(List<String> deck) {
    if (phase != HeadsUpPhase.ready) return;
    _deck = deck;
    _next = 0;
    turnResults = [];
    currentCard = null;
    phase = HeadsUpPhase.countdown;
    secondsLeft = countdownSeconds.toDouble();
    notifyListeners();
  }

  void advance(Duration elapsed) {
    final dt = elapsed.inMicroseconds / 1e6;
    if (phase == HeadsUpPhase.countdown) {
      secondsLeft -= dt;
      if (secondsLeft <= 0) {
        phase = HeadsUpPhase.playing;
        secondsLeft = turnSeconds.toDouble();
        _draw();
      }
      notifyListeners();
    } else if (phase == HeadsUpPhase.playing) {
      secondsLeft -= dt;
      if (secondsLeft <= 0) {
        secondsLeft = 0;
        _endTurn();
      }
      notifyListeners();
    }
  }

  void correct() => _answer(true);
  void pass() => _answer(false);

  void _answer(bool ok) {
    if (phase != HeadsUpPhase.playing || currentCard == null) return;
    turnResults.add(CardResult(currentCard!, ok));
    if (ok) correctByTeam[currentTeam] = correctByTeam[currentTeam]! + 1;
    _draw();
    notifyListeners();
  }

  void _draw() {
    if (_next >= _deck.length) {
      _endTurn(); // ran out of cards
      return;
    }
    currentCard = _deck[_next++];
    shown.add(currentCard!);
  }

  void _endTurn() {
    phase = HeadsUpPhase.turnOver;
    currentCard = null;
    turnsTaken++;
  }

  /// From the turn summary: next team, or finish the round.
  void nextTurn() {
    if (phase != HeadsUpPhase.turnOver) return;
    if (isLastTurn) {
      phase = HeadsUpPhase.finished;
    } else {
      currentTeam = (currentTeam + 1) % teamCount;
      phase = HeadsUpPhase.ready;
    }
    notifyListeners();
  }

  RoundResult result() => RoundResult(mode: GameModeId.headsUp, points: Map.of(correctByTeam));
}
