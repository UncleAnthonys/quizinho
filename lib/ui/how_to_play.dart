import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../domain/game_mode.dart';

/// The rules for the whole game and every round — from Settings.
void showHowToPlay(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.pitch,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), children: [
          Text('HOW TO PLAY', style: AppText.headline(34)),
          const SizedBox(height: 8),
          const Text(
            '1. Split into 2–6 teams and name them.\n'
            '2. Each round, the app picks a game at random.\n'
            '3. The app explains the rules, runs the clock and keeps score.\n'
            '4. Most points after the last round lifts the trophy.',
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 16),
          for (final m in GameModeId.values.where((m) => m.playable)) ...[
            Row(children: [
              Icon(m.icon, color: m.color),
              const SizedBox(width: 8),
              Text(m.title.toUpperCase(), style: AppText.headline(24, color: m.color)),
            ]),
            const SizedBox(height: 4),
            for (final r in m.rules) Text('• $r', style: const TextStyle(fontSize: 15, height: 1.45)),
            const SizedBox(height: 14),
          ],
        ]),
      ),
    );
