import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/purchases.dart';
import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';
import 'paywall_screen.dart';
import 'voice_test_screen.dart';

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
              title: const Text('Voice answers'),
              subtitle: const Text('Say the player’s name after buzzing. You can always type instead.'),
              value: s.settings.voiceOn,
              onChanged: (v) => s.settings.voiceOn = v,
            ),
            ListTile(
              leading: const Icon(Icons.record_voice_over, color: Palette.yellow),
              title: const Text('Voice test'),
              subtitle: const Text('Say tricky names and see what the phone hears'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const VoiceTestScreen())),
            ),
            SwitchListTile(
              title: const Text('Haptics'),
              value: s.settings.hapticsOn,
              onChanged: (v) => s.settings.hapticsOn = v,
            ),
            if (Purchases.enabled) if (s.purchases case final p?)
              ListenableBuilder(
                listenable: p,
                builder: (context, _) => Column(children: [
                  const Divider(color: Palette.line, height: 32),
                  ListTile(
                    leading: Icon(p.unlocked ? Icons.verified_rounded : Icons.lock_open_rounded, color: Palette.yellow),
                    title: Text(p.unlocked ? 'Full game unlocked' : 'Unlock the full game'),
                    subtitle: Text(p.unlocked ? 'Thanks for supporting Quizinho!' : '${p.price} one-off. No subscription, no ads.'),
                    trailing: p.unlocked ? null : const Icon(Icons.chevron_right),
                    onTap: p.unlocked ? null : () => PaywallScreen.show(context),
                  ),
                  if (!p.unlocked)
                    ListTile(
                      leading: const Icon(Icons.restore_rounded, color: Palette.muted),
                      title: const Text('Restore purchase'),
                      subtitle: p.error != null ? Text(p.error!) : (p.busy ? const Text('Checking…') : null),
                      onTap: p.busy ? null : p.restore,
                    ),
                ]),
              ),
            const Divider(color: Palette.line, height: 32),
            Text('FOOTBALL DATA', style: AppText.label(14, color: Palette.yellow)),
            const SizedBox(height: 8),
            Text('${s.repo.players.length} players in the offline database.'),
            const SizedBox(height: 4),
            Text(
              s.repo.dataStatus == 'wikidata'
                  ? 'Club careers from Wikidata (free, open football data). It isn’t perfect — if you’re sure an answer is right, use “Not listed?” and let the room vote.'
                  : s.repo.dataStatus == 'verified'
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
