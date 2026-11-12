import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../buzz_game_view.dart' show LoadingRound, OutOfChallenges;
import '../game_screen_support.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/player_picker.dart';
import 'top10_controller.dart';

/// Top 10 (solo): a record-book list, ten slots, name as many as you can.
class Top10Screen extends StatefulWidget {
  const Top10Screen({super.key, required this.round});
  final RoundContext round;

  @override
  State<Top10Screen> createState() => _Top10ScreenState();
}

class _Top10ScreenState extends State<Top10Screen> with TickerProviderStateMixin<Top10Screen>, GameScreenSupport<Top10Screen> {
  static const _mode = GameModeId.top10;
  Top10Controller? _c;
  bool _empty = false;
  int _pickerKey = 0;

  Tournament get _t => widget.round.tournament;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final bank = await services.top10;
    if (!mounted) return;
    final list = bank.pick(difficulty: _t.config.difficulty, history: services.settings.history);
    if (list == null) {
      setState(() => _empty = true);
      return;
    }
    final c = Top10Controller(list: list)
      ..addListener(() {
        final c = _c!;
        handleEvent(c.eventSerial, c.lastEvent, miss: c.misses.isEmpty ? null : c.misses.last);
        if (mounted) setState(() {});
      });
    setState(() => _c = c);
  }

  void _submit(Top10Controller c, Player player) {
    final r = c.submit(player);
    if (r == Top10Answer.alreadyFound) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Already got ${player.name}'), duration: const Duration(milliseconds: 1400)));
    }
    setState(() => _pickerKey++);
  }

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
          mode: _mode, onContinue: () => widget.round.onComplete(RoundResult(mode: _mode, points: {0: 0}, solo: 0)));
    }
    final c = _c;
    if (c == null) return const LoadingRound();
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: ValueListenableBuilder<bool>(
            valueListenable: answerTyping,
            builder: (context, typing, _) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(children: [
                Row(children: [
                  const ExitMatchButton(),
                  const Spacer(),
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(i < c.lives ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: i < c.lives ? Palette.danger : Palette.muted, size: 24),
                    ),
                ]),
                Text('TOP 10', style: AppText.label(15, color: _mode.color)),
                const SizedBox(height: 2),
                Text(c.list.prompt.toUpperCase(),
                    textAlign: TextAlign.center, style: AppText.headline(typing ? 22 : 28).copyWith(height: 1.05)),
                if (c.list.asOf.isNotEmpty && !typing)
                  Text('As of ${c.list.asOf}', style: AppText.label(12)),
                const SizedBox(height: 10),
                Expanded(child: _board(c)),
                const SizedBox(height: 8),
                if (!c.finished) ...[
                  PlayerPicker(
                    key: ValueKey('top10-$_pickerKey'),
                    index: services.repo.players,
                    voice: services.voice,
                    accent: _mode.color,
                    hint: 'Name one of the ten…',
                    onPick: (p) => _submit(c, p),
                    isAnswer: (p) => c.list.indexOf(p.id) != null,
                  ),
                  if (!typing)
                    TextButton(
                      onPressed: c.giveUp,
                      child: Text("I'M OUT - SHOW THE REST", style: AppText.label(13)),
                    ),
                ] else ...[
                  SoloScore(score: c.score, color: _mode.color),
                  const SizedBox(height: 8),
                  BigButton(label: 'Finish', icon: Icons.flag, onPressed: () => widget.round.onComplete(c.result())),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _board(Top10Controller c) => ListView.separated(
        itemCount: c.list.entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 5),
        itemBuilder: (context, i) {
          final e = c.list.entries[i];
          final got = c.found.contains(i);
          final shown = got || c.finished;
          final fresh = c.lastFound == i;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: got ? _mode.color.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: fresh ? _mode.color : Palette.line, width: fresh ? 2 : 1),
            ),
            child: Row(children: [
              SizedBox(
                width: 30,
                child: Text('${e.rank}', style: AppText.headline(20, color: got ? _mode.color : Palette.muted)),
              ),
              Expanded(
                child: Text(
                  shown ? e.name.toUpperCase() : '',
                  overflow: TextOverflow.ellipsis,
                  style: AppText.headline(20, color: got ? Palette.text : Palette.muted),
                ),
              ),
              if (shown && e.figure.isNotEmpty)
                Text(e.figure, style: AppText.label(13, color: got ? Palette.text : Palette.muted)),
            ]),
          );
        },
      );
}
