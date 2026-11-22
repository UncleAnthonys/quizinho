import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets/common.dart';

List<Object?> _list(Object? v) => (v as List?) ?? const [];
Map<String, Object?> _map(Object? v) => v is Map ? Map<String, Object?>.from(v) : const {};
int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// The penalty shootout, drawn from a plain snapshot so the main phone and
/// every joined phone show exactly the same thing. The callbacks are the main
/// phone's (null on a joined phone, which shows what's happening instead).
class ShootoutLayout extends StatelessWidget {
  const ShootoutLayout({
    super.key,
    required this.data,
    this.answerBox,
    this.clock,
    this.typing = false,
    this.commentary,
    this.startLabel,
    this.onPens,
    this.onDraw,
    this.onStart,
    this.onChoose,
    this.onNext,
    this.onFinish,
  });

  final Map<String, Object?> data;

  /// The timer + answer box (or "on their phone") while a kick's being taken.
  final Widget? answerBox;
  final Widget? clock;
  final bool typing;
  final String? commentary;
  final String? startLabel;
  final VoidCallback? onPens;
  final VoidCallback? onDraw;
  final VoidCallback? onStart;
  final ValueChanged<int>? onChoose;
  final VoidCallback? onNext;
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    final phase = '${data['phase']}';
    if (phase == 'choice') return _choice();
    if (phase == 'finished') return _finished();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(children: [
        Collapse(
          hidden: typing,
          child: Column(children: [
            CommentaryBanner(
              text: commentary,
              child: Text('PENALTIES', style: AppText.headline(40, color: Palette.yellow)),
            ),
            const SizedBox(height: 6),
            _Tracker(data: data),
            const SizedBox(height: 10),
          ]),
        ),
        Expanded(
          child: switch (phase) {
            'handover' => _handover(),
            'kicking' => _kicking(),
            _ => _result(),
          },
        ),
      ]),
    );
  }

  Map<String, Object?> get _taker => _map(data['taker']);

  Widget _choice() {
    final level = _list(data['level']);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const Spacer(),
        Text('FULL TIME', style: AppText.label(16)),
        FittedBox(fit: BoxFit.scaleDown, child: Text('ALL SQUARE!', style: AppText.headline(60, color: Palette.yellow))),
        const SizedBox(height: 18),
        Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: [
          for (final t in level.map(_map))
            Container(
              width: 140,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border(left: BorderSide(color: Palette.team(_int(t['color'])), width: 5)),
              ),
              child: Column(children: [
                Text('${t['name']}'.toUpperCase(), style: AppText.label(15, color: Palette.team(_int(t['color'])))),
                Text('${t['score']}', style: AppText.headline(56)),
              ]),
            ),
        ]),
        const SizedBox(height: 18),
        if (commentary != null)
          CommentaryBanner(text: commentary, child: const SizedBox(height: 26))
        else
          const SizedBox(height: 26),
        const Spacer(),
        if (onPens != null) ...[
          BigButton(label: 'Go to penalties', icon: Icons.sports_soccer, color: Palette.gold, onPressed: onPens),
          TextButton(onPressed: onDraw, child: Text('END MATCH AS A DRAW', style: AppText.label(15, color: Palette.text))),
        ] else
          Text('THE MAIN PHONE DECIDES: PENALTIES, OR A DRAW',
              textAlign: TextAlign.center, style: AppText.label(14, color: Palette.muted)),
      ]),
    );
  }

  Widget _handover() {
    final colour = _int(_taker['color']);
    final who = '${_taker['player'] ?? _taker['name'] ?? ''}';
    return Column(children: [
      Text('${data['label'] ?? ''}', style: AppText.label(15, color: Palette.yellow)),
      const SizedBox(height: 10),
      Expanded(
        child: GestureDetector(
          onTap: onStart,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(color: Palette.team(colour), borderRadius: BorderRadius.circular(24)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.sports_soccer, size: 48, color: Palette.onTeam(colour)),
              const SizedBox(height: 6),
              Text(onStart == null ? 'UP NEXT' : 'PASS TO', style: AppText.label(18, color: Palette.onTeam(colour))),
              FittedBox(fit: BoxFit.scaleDown, child: Text(who.toUpperCase(), style: AppText.headline(54, color: Palette.onTeam(colour)))),
              if (_taker['player'] != null)
                Text('${_taker['name']}'.toUpperCase(), style: AppText.label(18, color: Palette.onTeam(colour))),
              if (onStart != null) ...[
                const SizedBox(height: 8),
                Text(startLabel ?? 'TAP WHEN READY', style: AppText.label(15, color: Palette.onTeam(colour))),
              ],
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _kicking() {
    final kick = _map(data['kick']);
    final options = [for (final o in _list(kick['options'])) '$o'];
    return SingleChildScrollView(
      child: Column(children: [
        Collapse(
          hidden: typing,
          child: Column(children: [
            TeamChip(
                name: '${_taker['player'] != null ? '${_taker['player']} · ' : ''}${_taker['name']}',
                colorIndex: _int(_taker['color'])),
            const SizedBox(height: 6),
            Text('${data['label'] ?? ''}', style: AppText.label(14)),
            const SizedBox(height: 10),
          ]),
        ),
        KickCard(kick: kick, compact: typing),
        const SizedBox(height: 12),
        if (options.isNotEmpty) ...[
          if (clock != null) clock!,
          const SizedBox(height: 12),
          if (onChoose != null)
            Row(children: [
              for (final (i, o) in options.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: BigButton(
                    label: o,
                    height: 72,
                    color: i == 0 ? Palette.yellow : Palette.blueBright,
                    textColor: i == 0 ? Palette.pitchDeep : Colors.white,
                    onPressed: () => onChoose!(i),
                  ),
                ),
              ],
            ])
          else if (answerBox != null)
            answerBox!,
        ] else if (answerBox != null)
          answerBox!,
      ]),
    );
  }

  Widget _result() {
    final scored = data['scored'] == true;
    return Column(children: [
      const Spacer(),
      Icon(scored ? Icons.sports_soccer : Icons.back_hand_rounded, size: 80, color: scored ? Palette.green : Palette.muted),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(scored ? 'SCORED!' : 'SAVED!', style: AppText.headline(80, color: scored ? Palette.green : Palette.danger)),
      ),
      const SizedBox(height: 8),
      Text(scored ? 'RIGHT ANSWER' : 'THE ANSWER', style: AppText.label(14)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('${data['reveal'] ?? ''}', textAlign: TextAlign.center, style: AppText.headline(30)),
      ),
      const Spacer(),
      if (data['note'] != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('${data['note']}', textAlign: TextAlign.center, style: AppText.label(14, color: Palette.yellow)),
        ),
      if (onNext != null) BigButton(label: 'Next kick', icon: Icons.arrow_forward, onPressed: onNext),
    ]);
  }

  Widget _finished() {
    final w = _map(data['winner']);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const Spacer(),
        const Icon(Icons.emoji_events_rounded, color: Palette.gold, size: 110),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('${w['name']} WIN'.toUpperCase(), style: AppText.headline(56, color: Palette.team(_int(w['color'])))),
        ),
        Text('ON PENALTIES · ${data['pens'] ?? ''}', style: AppText.headline(34)),
        const SizedBox(height: 12),
        if (commentary != null) CommentaryBanner(text: commentary, child: const SizedBox(height: 26)),
        const SizedBox(height: 18),
        _Tracker(data: data),
        const Spacer(),
        if (onFinish != null) BigButton(label: 'Trophy time', icon: Icons.emoji_events, color: Palette.gold, onPressed: onFinish),
      ]),
    );
  }
}

/// The question: a gold-edged card (a career is a column of clubs).
class KickCard extends StatelessWidget {
  const KickCard({super.key, required this.kick, this.compact = false});
  final Map<String, Object?> kick;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final lines = [for (final l in _list(kick['lines'])) '$l'];
    final path = [for (final p in _list(kick['path'])) '$p'];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.gold, width: 2),
      ),
      child: Column(children: [
        Text('${kick['ask'] ?? ''}', textAlign: TextAlign.center, style: AppText.label(13, color: Palette.gold)),
        const SizedBox(height: 6),
        for (final l in lines)
          Text(l,
              textAlign: TextAlign.center,
              style: l == 'AND' || l == 'WHO PLAYED FOR'
                  ? AppText.label(15, color: Palette.muted)
                  : AppText.headline(compact ? 22 : 30)),
        for (final p in path)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
            decoration: BoxDecoration(
              color: p == '?' ? Colors.transparent : Palette.card,
              borderRadius: BorderRadius.circular(12),
              border: p == '?' ? Border.all(color: Palette.yellow, width: 2) : null,
            ),
            child: Text(p,
                textAlign: TextAlign.center,
                style: AppText.headline(compact ? 17 : 21, color: p == '?' ? Palette.yellow : Palette.text)),
          ),
      ]),
    );
  }
}

/// Each team's kicks: green for a goal, red for a save, empty to come.
class _Tracker extends StatelessWidget {
  const _Tracker({required this.data});
  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    final each = _int(data['each']);
    final teams = _list(data['teams']).map(_map).toList();
    final longest = teams.fold<int>(each, (a, t) => _list(t['kicks']).length > a ? _list(t['kicks']).length : a);
    return Column(children: [
      for (final t in teams)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
              width: 90,
              child: Text('${t['name']}'.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: AppText.headline(20, color: Palette.team(_int(t['color'])))),
            ),
            for (var i = 0; i < longest; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _Dot(scored: i < _list(t['kicks']).length ? _list(t['kicks'])[i] == true : null, out: t['out'] == true),
              ),
          ]),
        ),
    ]);
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.scored, this.out = false});
  final bool? scored;
  final bool out;

  @override
  Widget build(BuildContext context) {
    final s = scored;
    return Opacity(
      opacity: out && s == null ? 0.3 : 1,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: s == null ? Colors.transparent : (s ? Palette.green : Palette.danger),
          border: Border.all(color: s == null ? Palette.line : Colors.transparent, width: 2),
        ),
        child: s == null ? null : Icon(s ? Icons.check_rounded : Icons.close_rounded, size: 17, color: Colors.white),
      ),
    );
  }
}
