import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/tournament.dart';

/// One big buzzer per team. Fires on touch-down for zero-lag racing.
class BuzzerPad extends StatelessWidget {
  const BuzzerPad({
    super.key,
    required this.tournament,
    required this.canBuzz,
    required this.onBuzz,
    this.lockedOut = const {},
    this.faceOff,
  });

  final Tournament tournament;

  /// When set, buzzers show the named player instead of just the team.
  final FaceOff? faceOff;
  final bool Function(int team) canBuzz;
  final void Function(int team) onBuzz;
  final Set<int> lockedOut;

  @override
  Widget build(BuildContext context) {
    final n = tournament.teamCount;
    final perRow = n <= 2 ? n : (n <= 4 ? 2 : 3);
    final rows = <List<int>>[];
    for (var i = 0; i < n; i += perRow) {
      rows.add([for (var j = i; j < i + perRow && j < n; j++) j]);
    }
    return Column(
      children: [
        for (final row in rows)
          Expanded(
            child: Row(children: [
              for (final team in row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: TeamBuzzer(
                      name: faceOff == null
                          ? tournament.teamName(team)
                          : '${faceOff!.nameFor(team)} · ${tournament.teamName(team)}',
                      colorIndex: tournament.config.teams[team].colorIndex,
                      enabled: canBuzz(team),
                      locked: lockedOut.contains(team),
                      onBuzz: () => onBuzz(team),
                    ),
                  ),
                ),
            ]),
          ),
      ],
    );
  }
}

/// One team's buzzer. Fires on touch-down for zero-lag racing.
class TeamBuzzer extends StatefulWidget {
  const TeamBuzzer({
    super.key,
    required this.name,
    required this.colorIndex,
    required this.enabled,
    required this.locked,
    required this.onBuzz,
    this.quarterTurns = 0,
  });

  /// Rotates the label to face a player sitting at the end of the table.
  final int quarterTurns;
  final String name;
  final int colorIndex;
  final bool enabled;
  final bool locked;
  final VoidCallback onBuzz;

  @override
  State<TeamBuzzer> createState() => TeamBuzzerState();
}

class TeamBuzzerState extends State<TeamBuzzer> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final color = Palette.team(widget.colorIndex);
    final on = Palette.onTeam(widget.colorIndex);
    final active = widget.enabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: active
          ? (_) {
              setState(() => _down = true);
              widget.onBuzz();
            }
          : null,
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 80),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: active ? color : color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(28),
            boxShadow: active
                ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 22, spreadRadius: 1)]
                : null,
            border: Border.all(color: Colors.white.withValues(alpha: active ? 0.5 : 0.1), width: 3),
          ),
          child: Center(
            child: RotatedBox(
              quarterTurns: widget.quarterTurns,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.locked ? Icons.lock : Icons.touch_app, color: active ? on : Palette.muted, size: 34),
              const SizedBox(height: 4),
              Text(widget.locked ? 'LOCKED OUT' : 'BUZZ',
                  style: AppText.headline(34, color: active ? on : Palette.muted)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(widget.name.toUpperCase(), style: AppText.label(15, color: active ? on : Palette.muted)),
                ),
              ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
