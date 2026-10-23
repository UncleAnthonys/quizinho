import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: Palette.pitch, title: Text('SETTINGS', style: AppText.headline(26))),
      body: PitchBackground(
        child: ListenableBuilder(
          listenable: s.settings,
          builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
            SwitchListTile(
              title: const Text('Sound effects'),
              value: s.settings.soundOn,
              onChanged: (v) {
                s.settings.soundOn = v;
                if (v) s.sound.play(Sfx.whistle);
              },
            ),
            SwitchListTile(
              title: const Text('Commentary'),
              subtitle: const Text('On-screen one-liners after big moments'),
              value: s.settings.commentaryOn,
              onChanged: (v) => s.settings.commentaryOn = v,
            ),
            SwitchListTile(
              title: const Text('Haptics'),
              value: s.settings.hapticsOn,
              onChanged: (v) => s.settings.hapticsOn = v,
            ),
            const Divider(color: Palette.line, height: 32),
            Text('FOOTBALL DATA', style: AppText.label(14, color: Palette.yellow)),
            const SizedBox(height: 8),
            Text('${s.repo.players.length} players in the offline database.'),
            const SizedBox(height: 4),
            Text(
              s.repo.dataStatus == 'verified'
                  ? 'All challenges checked against sources.'
                  : 'This is an early demo set written from general knowledge and not yet fact-checked. '
                      'If the app says you’re wrong and you’re sure you’re right, use “Not listed?” and let the room vote.',
              style: const TextStyle(color: Palette.muted, height: 1.4),
            ),
          ]),
        ),
      ),
    );
  }
}
