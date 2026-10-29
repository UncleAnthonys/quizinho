import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/football_repository.dart';
import '../multiplayer/rest_room_link.dart';
import '../multiplayer/room.dart';
import '../multiplayer/room_link.dart';
import '../multiplayer/rooms_config.dart';
import 'app_settings.dart';
import 'commentary.dart';
import 'purchases.dart';
import 'sound_service.dart';
import 'voice_service.dart';

/// Everything screens need, created once at startup.
class AppServices {
  AppServices(
      {required this.repo, required this.settings, required this.sound, this.voice, this.purchases, Commentary? commentary})
      : commentary = commentary ?? Commentary();

  final FootballRepository repo;
  final AppSettings settings;
  final SoundService sound;

  /// Spoken answers. Null in tests.
  final VoiceService? voice;
  final Commentary commentary;

  /// Shared rooms for playing on several phones (null = not set up).
  late final RoomLink? roomLink = roomsEnabled ? RestRoomLink(roomsDatabaseUrl) : null;

  /// The room this phone is hosting, if any.
  HostRoom? room;

  /// The full-game unlock. Null in tests (= full game).
  final Purchases? purchases;
  bool get fullGame => purchases?.unlocked ?? true;

  late final ChallengeSource challenges = ChallengeSource(repo, history: settings.history);

  void haptic(HapticStrength s) {
    if (!settings.hapticsOn) return;
    switch (s) {
      case HapticStrength.light:
        HapticFeedback.lightImpact();
      case HapticStrength.medium:
        HapticFeedback.mediumImpact();
      case HapticStrength.heavy:
        HapticFeedback.heavyImpact();
      case HapticStrength.tick:
        HapticFeedback.selectionClick();
    }
  }
}

enum HapticStrength { tick, light, medium, heavy }

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});
  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing');
    return scope!.services;
  }

  /// Like [of] but without subscribing — safe to call from initState.
  static AppServices read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.services != services;
}
