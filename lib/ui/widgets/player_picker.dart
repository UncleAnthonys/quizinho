import 'package:flutter/material.dart';

import '../../core/flags.dart';
import '../../core/theme.dart';
import '../../core/voice_service.dart';
import '../../data/models.dart';
import '../../domain/player_index.dart';

/// Answer entry: say the name, or type it. Like 501: no suggestions for a
/// fragment, so it never gives the answer away — once a full surname is typed,
/// the players it could mean drop down to tap.
///
/// With [voice], the mic opens straight away. A right answer ([isAnswer]) is
/// accepted even from a sound-alike; a wrong one only if a real name was
/// clearly said. Anything unclear ("Ronaldo", a mishearing, chatter) shows
/// the likely players to tap — talking never costs a life by accident. If the player isn't in the database the room can vote, so a gap in
/// our data never costs a team a correct answer.
/// True while someone is typing an answer. Game screens listen to this and
/// collapse to a compact layout so the question stays visible above the
/// keyboard (the answer box sits near the top, not behind the keyboard).
final ValueNotifier<bool> answerTyping = ValueNotifier(false);

class PlayerPicker extends StatefulWidget {
  const PlayerPicker({
    super.key,
    required this.index,
    required this.onPick,
    this.onPass,
    this.onDisputed,
    this.accent = Palette.yellow,
    this.hint = 'Type the full name…',
    this.voice,
    this.isAnswer,
    this.showFlags = true,
    this.showPositions = true,
    this.rapid = false,
  });

  /// Rapid fire (Bidding War): keep going after each answer. The mic stays
  /// open and picks out every name in a run of speech ("Rooney Giggs
  /// Scholes"); typing clears the box and keeps the keyboard up.
  final bool rapid;

  final PlayerIndex index;
  final ValueChanged<Player> onPick;
  final VoidCallback? onPass;

  /// When set, offers "Not listed? Let the room decide".
  final void Function(String typed, bool allowed)? onDisputed;
  final Color accent;
  final String hint;

  /// Spoken answers; null or disabled = typing only.
  final VoiceService? voice;

  /// Right answers to the current question — voice leans towards these.
  final bool Function(Player)? isAnswer;

  /// Off when they'd give the answer away ("French players who played for
  /// Chelsea" — every right answer would show a French flag).
  final bool showFlags;
  final bool showPositions;

  @override
  State<PlayerPicker> createState() => _PlayerPickerState();
}

class _PlayerPickerState extends State<PlayerPicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<PlayerMatch> _results = const [];
  bool _voting = false;
  bool _listening = false;
  String? _voiceNote;

  /// What the recogniser last heard, word for word — shown small, so it's
  /// clear the mic is working and what it made of the name.
  String _heardWords = '';

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
    _focus.addListener(_onFocus);
    if (_voiceOn) WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  /// Tapping the box = typing: the mic stops at once so it can't fight the keyboard.
  void _onFocus() {
    answerTyping.value = _focus.hasFocus;
    if (_focus.hasFocus && !_typing) {
      _typing = true;
      widget.voice?.stop();
      setState(() {
        _listening = false;
        _voiceNote = null;
      });
    }
  }

  @override
  void dispose() {
    _picked = true;
    widget.voice?.stop();
    _focus.removeListener(_onFocus);
    _focus.dispose();
    answerTyping.value = false;
    _controller.dispose();
    super.dispose();
  }

  void _pick(Player p) {
    if (_picked) return;
    if (widget.rapid) {
      widget.onPick(p);
      _controller.clear();
      setState(() {
        _results = const [];
        _typedNote = null;
      });
      return;
    }
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
      _voiceNote ??= widget.rapid ? 'Listening… keep the names coming (or tap the box to type)' : 'Listening… say the player (or tap the box to type)';
    });
    _consumed = 0;
    final started = await voice.listen(
      hints: _hints,
      onWords: (words) {
        if (!_keepListening || words.trim().isEmpty) return;
        if (words != _heardWords) setState(() => _heardWords = words);
        if (widget.rapid) {
          _scanRapid(words, partial: true);
          return;
        }
        if (_voiceNote != 'Hearing you…') setState(() => _voiceNote = 'Hearing you…');
        // Names are checked as the words arrive — a clear match goes straight in.
        final p = widget.index.resolveSpoken([words], partial: true, isAnswer: widget.isAnswer);
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

  /// After a pause: offer real player names only (never the raw transcript,
  /// which is often nonsense for unusual names), merged across alternatives.
  void _suggestFrom(List<String> alternatives) {
    final seen = <String>{};
    final merged = <PlayerMatch>[];
    for (final alt in alternatives) {
      for (final m in widget.index.searchSpoken(alt, limit: 4, isAnswer: widget.isAnswer)) {
        if (seen.add(m.player.id)) merged.add(m);
      }
    }
    // Only players that fully match what was said — never hints from a fragment.
    merged.removeWhere((m) => m.base < 88);
    merged.sort((a, b) => b.score.compareTo(a.score));
    setState(() => _results = merged.take(4).toList());
  }

  /// The right answers' names (and surnames), for recognisers that can be
  /// told what to listen for. Worked out once per answer box.
  late final List<String> _hints = () {
    final isAnswer = widget.isAnswer;
    if (isAnswer == null) return const <String>[];
    final out = <String>{};
    for (final p in widget.index.all.where(isAnswer).take(100)) {
      out.add(p.name);
      final last = p.name.split(' ').last;
      if (last.length > 3) out.add(last);
    }
    return out.toList();
  }();

  /// Words of the current stretch of speech already used for a name.
  int _consumed = 0;

  /// Rapid fire: every name in the speech so far that hasn't been used yet,
  /// longest match first ("Wayne Rooney" before "Wayne").
  void _scanRapid(String transcript, {required bool partial}) {
    final words = transcript.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (_consumed > words.length) _consumed = words.length; // the recogniser revised itself
    var i = _consumed;
    while (i < words.length) {
      Player? found;
      var used = 0;
      for (var len = 3; len >= 1 && found == null; len--) {
        if (i + len > words.length) continue;
        found = widget.index.resolveSpoken([words.sublist(i, i + len).join(' ')],
            partial: partial, isAnswer: widget.isAnswer);
        used = len;
      }
      if (found != null) {
        i += used;
        _consumed = i;
        if (_voiceNote != 'Got it — next!') setState(() => _voiceNote = 'Got it — next!');
        widget.onPick(found);
      } else {
        i++;
      }
    }
  }

  void _heard(List<String> alternatives) {
    if (!mounted || _picked) return;
    if (widget.rapid) {
      if (alternatives.isNotEmpty) _scanRapid(alternatives.first, partial: false);
      _silentRestarts = alternatives.isEmpty ? _silentRestarts + 1 : 0;
      setState(() => _listening = false);
      if (_silentRestarts < 10) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_keepListening) _listen();
        });
      }
      return;
    }
    final p = widget.index.resolveSpoken(alternatives, isAnswer: widget.isAnswer);
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
      _suggestFrom(alternatives);
      _voiceNote = _results.isEmpty ? 'Didn’t recognise that — say it again or type' : 'Did you mean…? Tap it, or say it again';
    }
    setState(() => _listening = false);
    // Keep the mic open for the whole answer clock.
    Future.delayed(const Duration(milliseconds: 250), () {
      if (_keepListening) _listen();
    });
  }

  /// Typing in the box takes over from the mic. Nothing is suggested while
  /// typing — that would hand the answer to someone who only half knows it.
  void _onTyped(String q) {
    if (!_typing && _voiceOn) {
      _typing = true;
      widget.voice?.stop();
      _listening = false;
      _voiceNote = null;
    }
    // 501-style: nothing shows for a fragment, but once a full surname, full
    // name or nickname is typed, every player it could mean drops down.
    final matches = widget.index.matchTyped(q);
    setState(() {
      _results = [for (final p in matches.take(5)) PlayerMatch(p, 0)];
      _typedNote = null;
    });
  }

  /// Enter / Go: judge the full answer.
  void _submitTyped() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final matches = widget.index.matchTyped(text);
    if (matches.length == 1) {
      _pick(matches.first);
      return;
    }
    setState(() {
      _results = [for (final p in matches.take(4)) PlayerMatch(p, 0)];
      _typedNote = matches.isNotEmpty
          ? 'More than one “$text” — which one?'
          : widget.index.isFirstNameOnly(text)
              ? 'Surname needed — first names don’t count'
              : 'Not recognised — check the spelling, or use “Not listed?”';
    });
  }

  String? _typedNote;

  @override
  Widget build(BuildContext context) {
    final typed = _controller.text.trim();
    if (_voting) return _vote(typed);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: _controller,
        focusNode: _focus,
        autofocus: !_voiceOn, // keyboard would cover the screen while speaking
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const <String>[], // stops Safari offering contacts
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
                          _focus.unfocus();
                          _typing = false;
                          _silentRestarts = 0;
                          _voiceNote = null;
                          _listen();
                        },
                )
              : Icon(Icons.search, color: widget.accent),
          suffixIcon: typed.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.all(6),
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: widget.accent, minimumSize: const Size(56, 40)),
                    onPressed: _submitTyped,
                    child: Text('GO', style: AppText.headline(18, color: Palette.pitchDeep)),
                  ),
                ),
        ),
        onChanged: _onTyped,
        onSubmitted: (_) => _submitTyped(),
      ),
      if (_typedNote != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: Palette.gold),
            const SizedBox(width: 6),
            Expanded(child: Text(_typedNote!, style: AppText.label(14, color: Palette.gold))),
          ]),
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
      if (_heardWords.isNotEmpty && _voiceOn && !_typing)
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Heard: “$_heardWords”',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(12, color: Palette.muted)),
          ),
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
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(r.player.name, style: AppText.headline(24, weight: FontWeight.w800)),
                    ),
                  ),
                  // Tells namesakes apart at a glance (Luis Suárez 🇺🇾 ST vs Denis Suárez 🇪🇸 CM).
                  if (widget.showPositions && r.player.position != null)
                    Text(r.player.position!, style: AppText.label(14)),
                  if (widget.showFlags) if (nationalityLabel(r.player.nationality) case final flag?)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(flag, style: TextStyle(fontSize: flagFor(r.player.nationality) != null ? 26 : 14)),
                    ),
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
