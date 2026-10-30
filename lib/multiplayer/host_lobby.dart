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
        builder: (context, _) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 20, 20, 12), children: [
          Text('SCAN FOR YOUR OWN BUZZER',
              textAlign: TextAlign.center, style: AppText.headline(28, color: Palette.yellow)),
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(data: joinLink(room.code), size: 230, backgroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text('Got the app? Join a friend’s game · ${room.code}',
              textAlign: TextAlign.center, style: AppText.label(13)),
          const SizedBox(height: 16),
          // Who's in: a tick per player whose phone has joined.
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            for (final (i, t) in teams.indexed)
              for (final n in t.players)
                Chip(
                  avatar: Icon(
                    room.memberFor(i, n) != null ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 18,
                    color: room.memberFor(i, n) != null ? Palette.green : Palette.muted,
                  ),
                  label: Text(n),
                  backgroundColor: Palette.team(t.colorIndex).withValues(alpha: 0.25),
                  side: BorderSide(color: Palette.team(t.colorIndex)),
                ),
          ]),
          const SizedBox(height: 16),
          BigButton(label: 'Done', icon: Icons.check_rounded, onPressed: () => Navigator.of(context).pop()),
        ]),
      );
}
