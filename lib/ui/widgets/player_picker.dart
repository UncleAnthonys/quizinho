import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/voice_service.dart';
import '../../data/models.dart';
import '../../domain/player_index.dart';

/// Answer entry: say the name, or type 2–3 letters and tap it.
///
/// With [voice], the mic opens straight away. A clear match is accepted
/// automatically; an unclear one ("Ronaldo") shows the likely players to tap.
/// A mishearing never counts as a wrong answer — it just falls back to the
/// list. If the player isn't in the database the room can vote, so a gap in
/// our data never costs a team a correct answer.
class PlayerPicker extends StatefulWidget {
  const PlayerPicker({
    super.key,
    required this.index,
    required this.onPick,
    this.onPass,
    this.onDisputed,
    this.accent = Palette.yellow,
    this.hint = 'Start typing a player…',
    this.voice,
  });

  final PlayerIndex index;
  final ValueChanged<Player> onPick;
  final VoidCallback? onPass;

  /// When set, offers "Not listed? Let the room decide".
  final void Function(String typed, bool allowed)? onDisputed;
  final Color accent;
  final String hint;

  /// Spoken answers; null or disabled = typing only.
  final VoiceService? voice;

  @override
  State<PlayerPicker> createState() => _PlayerPickerState();
}

class _PlayerPickerState extends State<PlayerPicker> {
  final _controller = TextEditingController();
  List<PlayerMatch> _results = const [];
  bool _voting = false;
  bool _listening = false;
  String? _voiceNote;

  /// Answer already chosen — ignore any further speech.
  bool _picked = false;

  /// The player started typing — stop listening and leave the box to them.
  bool _typing = false;

  /// Back-to-back listens that heard nothing; stops a broken mic looping forever.
  int _silentRestarts = 0;

  bool get _voiceOn => widget.voice?.enabled ?? false;
  bool get _keepListening => mounted && _voiceOn && !_picked && !_typing && !_voting;

  @override
  void initState() {
    super.initState();
    if (_voiceOn) WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  @override
  void dispose() {
    _picked = true;
    widget.voice?.stop();
    _controller.dispose();
    super.dispose();
  }

  void _pick(Player p) {
    if (_picked) return;
    _picked = true;
    widget.voice?.stop();
    widget.onPick(p);
  }

  /// Listens continuously until an answer is picked, the player types, or
  /// this box goes away (answer clock ran out). Speech recognisers stop after
  /// a pause, so each time one stops we simply start another.
  Future<void> _listen() async {
    final voice = widget.voice;
    if (voice == null || !_keepListening) return;
    setState(() {
      _listening = true;
      _voiceNote ??= 'Listening… say the player';
    });
    final started = await voice.listen(
      onWords: (words) {
        if (!_keepListening || words.trim().isEmpty) return;
        _showSpoken(words);
        // Names are checked as the words arrive — a clear match goes straight in.
        final p = widget.index.resolveSpoken([words], partial: true);
        if (p != null) _pick(p);
      },
      onDone: _heard,
    );
    if (!started && mounted) {
      setState(() {
        _listening = false;
        _voiceNote = 'Mic not available — type the name';
      });
    }
  }

  void _showSpoken(String words) {
    _controller.text = words;
    setState(() => _results = widget.index.searchSpoken(words));
  }

  void _heard(List<String> alternatives) {
    if (!mounted || _picked) return;
    final p = widget.index.resolveSpoken(alternatives);
    if (p != null) {
      _pick(p);
      return;
    }
    _silentRestarts = alternatives.isEmpty ? _silentRestarts + 1 : 0;
    if (_silentRestarts >= 10) {
      setState(() {
        _listening = false;
        _voiceNote = 'Mic not hearing anything — tap it to retry, or type';
      });
      return;
    }
    if (alternatives.isNotEmpty) {
      _showSpoken(alternatives.first);
      _voiceNote = _results.isEmpty
          ? 'Heard “${alternatives.first}” — still listening…'
          : 'Tap the right player — or say it again';
    }
    setState(() => _listening = false);
    // Keep the mic open for the whole answer clock.
    Future.delayed(const Duration(milliseconds: 250), () {
      if (_keepListening) _listen();
    });
  }

  /// Typing in the box takes over from the mic.
  void _onTyped(String q) {
    if (!_typing && _voiceOn) {
      _typing = true;
      widget.voice?.stop();
      _listening = false;
      _voiceNote = 'Typing — tap the mic to talk instead';
    }
    _onChanged(q);
  }

  void _onChanged(String q) => setState(() => _results = widget.index.search(q, limit: 6));

  @override
  Widget build(BuildContext context) {
    final typed = _controller.text.trim();
    if (_voting) return _vote(typed);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: _controller,
        autofocus: !_voiceOn, // keyboard would cover the screen while speaking
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.words,
        style: AppText.headline(26, weight: FontWeight.w800),
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: _voiceOn
              ? IconButton(
                  icon: Icon(_listening ? Icons.graphic_eq_rounded : Icons.mic_rounded, color: widget.accent),
                  onPressed: _listening
                      ? null
                      : () {
                          _typing = false;
                          _silentRestarts = 0;
                          _voiceNote = null;
                          _listen();
                        },
                )
              : Icon(Icons.search, color: widget.accent),
          suffixIcon: typed.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: Palette.muted),
                  onPressed: () {
                    _controller.clear();
                    _onChanged('');
                  },
                ),
        ),
        onChanged: _onTyped,
        onSubmitted: (_) {
          if (_results.isNotEmpty) _pick(_results.first.player);
        },
      ),
      if (_voiceNote != null && _voiceOn)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                size: 18, color: _listening ? Palette.danger : Palette.muted),
            const SizedBox(width: 6),
            Expanded(child: Text(_voiceNote!, style: AppText.label(14, color: _listening ? Palette.text : Palette.muted))),
          ]),
        ),
      const SizedBox(height: 8),
      for (final r in _results)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: Palette.cardHigh,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _pick(r.player),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Expanded(child: Text(r.player.name, style: AppText.headline(24, weight: FontWeight.w800))),
                  if (r.player.position != null) Text(r.player.position!, style: AppText.label(14)),
                ]),
              ),
            ),
          ),
        ),
      Row(children: [
        if (widget.onDisputed != null && typed.length >= 3)
          TextButton(
            onPressed: () => setState(() => _voting = true),
            child: Text('NOT LISTED?', style: AppText.label(15, color: Palette.gold)),
          ),
        const Spacer(),
        if (widget.onPass != null)
          TextButton(
            onPressed: widget.onPass,
            child: Text('PASS', style: AppText.label(15, color: Palette.danger)),
          ),
      ]),
    ]);
  }

  Widget _vote(String typed) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('ROOM VOTE', style: AppText.label(15, color: Palette.gold)),
          const SizedBox(height: 6),
          Text('“$typed”', textAlign: TextAlign.center, style: AppText.headline(30)),
          const SizedBox(height: 6),
          const Text(
            'Not in our database. Everyone else — is it right?',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.muted),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Palette.danger, minimumSize: const Size(0, 56)),
                onPressed: () => widget.onDisputed!(typed, false),
                child: Text('NO', style: AppText.headline(24, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Palette.yellow, minimumSize: const Size(0, 56)),
                onPressed: () => widget.onDisputed!(typed, true),
                child: Text('ALLOW IT', style: AppText.headline(24, color: Palette.pitchDeep)),
              ),
            ),
          ]),
          TextButton(
            onPressed: () => setState(() => _voting = false),
            child: Text('BACK TO LIST', style: AppText.label(14)),
          ),
        ]),
      );
}
