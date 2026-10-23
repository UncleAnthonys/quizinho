import 'package:flutter/material.dart';

import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../buzz_game_view.dart';
import '../game_screen_support.dart';
import 'club_connections_controller.dart';

class ClubConnectionsScreen extends StatefulWidget {
  const ClubConnectionsScreen({super.key, required this.round});
  final RoundContext round;

  @override
  State<ClubConnectionsScreen> createState() => _ClubConnectionsScreenState();
}

class _ClubConnectionsScreenState extends State<ClubConnectionsScreen>
    with TickerProviderStateMixin<ClubConnectionsScreen>, GameScreenSupport<ClubConnectionsScreen> {
  static const _mode = GameModeId.clubConnections;
  ClubConnectionsController? _c;
  late final FaceOffTracker _faces = FaceOffTracker(widget.round);
  bool _empty = false;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = widget.round.tournament;
    final source = services.challenges;
    final qs = <ClubConnection>[];
    for (var i = 0; i < t.config.questionsPerRound; i++) {
      final q = await source.clubConnection(t.config.difficulty, t.usedIds(_mode), eras: t.config.eraMask);
      if (q == null) break;
      t.markUsed(_mode, q.id);
      qs.add(q);
    }
    if (!mounted) return;
    if (qs.isEmpty) {
      setState(() => _empty = true);
      return;
    }
    final c = ClubConnectionsController(teamCount: t.teamCount, questions: qs, answerSeconds: t.config.answerSeconds);
    _faces.sync(c);
    c.addListener(() {
      _faces.sync(c);
      handleEvent(c.eventSerial, c.lastEvent);
      if (c.questionIndex != _lastQuestion) {
        _lastQuestion = c.questionIndex;
        _showAll = false;
      }
      if (mounted) setState(() {});
    });
    setState(() => _c = c);
    startClock((dt) {
      if (!_faces.awaitingReady) c.advance(dt);
    });
  }

  int _lastQuestion = 0;

  @override
  void dispose() {
    disposeGameSupport();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_empty) {
      return OutOfChallenges(
        mode: _mode,
        onContinue: () => widget.round.onComplete(RoundResult.empty(_mode, widget.round.tournament.teamCount)),
      );
    }
    final c = _c;
    if (c == null) return const LoadingRound();
    final q = c.current;
    final players = services.repo.players;
    final answers = [for (final id in q.answerIds) players.byId(id)?.name ?? id]..sort();

    return BuzzGameView(
      round: widget.round,
      controller: c,
      commentary: commentaryText,
      timerLabel: c.lockedOut.isEmpty ? 'BUZZ IN' : 'STEAL IT',
      allowDispute: true,
      onFinished: () => widget.round.onComplete(c.result()),
      faceOff: _faces.current,
      awaitingFaceOff: _faces.awaitingReady,
      onFaceOffReady: () {
        services.sound.play(Sfx.whistle);
        setState(_faces.ready);
      },
      question: _ClubsCard(a: q.clubA.name, b: q.clubB.name),
      resolvedDetail: Column(children: [
        Text(
          answers.length == 1 ? 'THE ONLY ANSWER IN OUR DATABASE' : '${answers.length} ANSWERS IN OUR DATABASE',
          style: AppText.label(13),
        ),
        const SizedBox(height: 8),
        if (_showAll || answers.length <= 6)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [for (final a in answers) Chip(label: Text(a), backgroundColor: Palette.card)],
          )
        else
          TextButton(
            onPressed: () => setState(() => _showAll = true),
            child: Text('SHOW ALL ANSWERS', style: AppText.label(15, color: Palette.yellow)),
          ),
      ]),
    );
  }

}

class _ClubsCard extends StatelessWidget {
  const _ClubsCard({required this.a, required this.b});
  final String a;
  final String b;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Palette.line),
          ),
          child: Column(children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(a.toUpperCase(), style: AppText.headline(46))),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Icon(Icons.swap_vert_rounded, color: Palette.yellow, size: 34),
            ),
            FittedBox(fit: BoxFit.scaleDown, child: Text(b.toUpperCase(), style: AppText.headline(46))),
          ]),
        ),
      );
}
