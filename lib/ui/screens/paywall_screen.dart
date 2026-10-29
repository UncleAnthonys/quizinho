import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/purchases.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';

/// The one-off unlock. Pops with true once the full game is unlocked, false
/// if dismissed. [afterWarmUp] = shown on "Rematch" after the free cup.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.afterWarmUp = false});
  final bool afterWarmUp;

  /// Shows the paywall; true if the full game is unlocked afterwards.
  static Future<bool> show(BuildContext context, {bool afterWarmUp = false}) async {
    final unlocked = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => PaywallScreen(afterWarmUp: afterWarmUp), fullscreenDialog: true));
    return unlocked ?? false;
  }

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Purchases? _p;
  bool _closed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_p != null) return;
    _p = AppScope.read(context).purchases?..addListener(_changed);
    _p?.init(); // refresh the price if it didn't load at launch
  }

  void _changed() {
    if (!mounted || _closed) return;
    if (_p?.unlocked ?? true) {
      _closed = true;
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _p?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final busy = p?.busy ?? false;
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Not now',
                icon: const Icon(Icons.close_rounded, color: Palette.muted),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 16), children: [
                const Icon(Icons.emoji_events_rounded, color: Palette.gold, size: 84),
                Text(widget.afterWarmUp ? 'FANCY A REMATCH?' : 'UNLOCK QUIZINHO',
                    textAlign: TextAlign.center, style: AppText.headline(40, color: Palette.yellow)),
                const SizedBox(height: 6),
                Text(
                  widget.afterWarmUp
                      ? 'That was the Warm-Up Cup — the same challenges for everyone. '
                          'The full game is a fresh match every time.'
                      : 'The Warm-Up Cup is free. The full game is a fresh match every time.',
                  textAlign: TextAlign.center,
                  style: AppText.label(15, color: Palette.text),
                ),
                const SizedBox(height: 22),
                const _Perk(Icons.all_inclusive_rounded, 'Unlimited matches', 'Every one different — nothing repeats for ages'),
                const _Perk(Icons.shuffle_rounded, 'Random challenges', 'From 24,000+ players, 4,000 clubs and every era'),
                const _Perk(Icons.sports_esports_rounded, 'All 8 games', 'Plus Solo Survival, wildcards and face-offs'),
                const _Perk(Icons.tune_rounded, 'Your rules', 'Easy to Expert, match length, men’s and women’s'),
                const SizedBox(height: 18),
                Text('One payment. No subscription. No ads.',
                    textAlign: TextAlign.center, style: AppText.label(15, color: Palette.yellow)),
                if (p?.error != null) ...[
                  const SizedBox(height: 10),
                  Text(p!.error!, textAlign: TextAlign.center, style: AppText.label(14, color: Palette.danger)),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(children: [
                busy
                    ? const SizedBox(height: 64, child: Center(child: CircularProgressIndicator(color: Palette.yellow)))
                    : BigButton(
                        label: 'Unlock for ${p?.price ?? '£2.99'}',
                        icon: Icons.lock_open_rounded,
                        onPressed: p?.buy,
                      ),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TextButton(
                    onPressed: busy || p == null ? null : p.restore,
                    child: Text('RESTORE PURCHASE', style: AppText.label(14)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('NOT NOW', style: AppText.label(14)),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk(this.icon, this.title, this.detail);
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Palette.yellow),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.toUpperCase(), style: AppText.headline(22)),
              Text(detail, style: const TextStyle(color: Palette.muted, fontSize: 14)),
            ]),
          ),
        ]),
      );
}
