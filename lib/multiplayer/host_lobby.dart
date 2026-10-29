import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/theme.dart';
import '../domain/tournament.dart';
import '../ui/widgets/common.dart';
import 'room.dart';
import 'rooms_config.dart';

/// The link a phone's camera opens to join [code] (the web game, no download).
String joinLink(String code) => '$joinPageUrl?join=$code';

/// QR code, room code and who's joined — shown from the team sheet.
Future<void> showRoomSheet(BuildContext context, HostRoom room, List<TeamSetup> teams) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.pitch,
      builder: (_) => SafeArea(child: _RoomSheet(room: room, teams: teams)),
    );

class _RoomSheet extends StatelessWidget {
  const _RoomSheet({required this.room, required this.teams});
  final HostRoom room;
  final List<TeamSetup> teams;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: room,
        builder: (context, _) => ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
          Text('PLAY ON YOUR PHONES', textAlign: TextAlign.center, style: AppText.headline(30, color: Palette.yellow)),
          const SizedBox(height: 4),
          Text('Scan with the phone camera — no download needed',
              textAlign: TextAlign.center, style: AppText.label(14, color: Palette.text)),
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(data: joinLink(room.code), size: 220, backgroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Text('or Quizinho → Join a game →', textAlign: TextAlign.center, style: AppText.label(13)),
          Text(room.code, textAlign: TextAlign.center, style: AppText.headline(56, color: Palette.text)),
          const SizedBox(height: 10),
          for (final (i, t) in teams.indexed) ...[
            TeamChip(name: t.name, colorIndex: t.colorIndex, size: 18),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (j, n) in t.players.indexed)
                Chip(
                  avatar: Icon(
                    room.memberFor(i, n) != null ? Icons.phone_iphone_rounded : Icons.hourglass_empty_rounded,
                    size: 18,
                    color: room.memberFor(i, n) != null ? Palette.green : Palette.muted,
                  ),
                  label: Text(j == 0 ? '$n (C)' : n),
                  backgroundColor: Palette.card,
                ),
            ]),
            const SizedBox(height: 12),
          ],
          Text('Anyone without a phone joined plays on this one, as normal.',
              textAlign: TextAlign.center, style: AppText.label(13)),
          const SizedBox(height: 12),
          BigButton(label: 'Done', icon: Icons.check_rounded, onPressed: () => Navigator.of(context).pop()),
        ]),
      );
}
