import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../widgets/common.dart';

/// Say tricky names into the phone and see what the speech recogniser hears
/// and whether the app would accept it. "Copy results" gives a text report to
/// paste back, so the sound-alike rules can be tuned on real phones.
class VoiceTestScreen extends StatefulWidget {
  const VoiceTestScreen({super.key});

  @override
  State<VoiceTestScreen> createState() => _VoiceTestScreenState();
}

/// The hard ones first — Polish, Scandinavian, Balkan, French, German, Dutch,
/// Italian, Spanish, Portuguese, Turkish and others. After these, random
/// well-known players with names from other languages.
const _testIds = [
  'wojciech-szczesny', 'martin-odegaard', 'pierre-emile-hojbjerg', 'dusan-tadic', 'robert-lewandowski',
  'jakub-blaszczykowski', 'lukasz-piszczek', 'luka-modric', 'ivan-rakitic', 'mateo-kovacic', 'nemanja-vidic',
  'branislav-ivanovic', 'nemanja-matic', 'aleksandar-mitrovic', 'dejan-lovren', 'tomas-rosicky', 'petr-cech',
  'erling-haaland', 'rasmus-hojlund', 'christian-eriksen', 'kasper-schmeichel', 'ole-gunnar-solskjaer',
  'zlatan-ibrahimovic', 'victor-lindelof', 'dominik-szoboszlai', 'kylian-mbappe', 'ngolo-kante', 'olivier-giroud',
  'thierry-henry', 'antoine-griezmann', 'aurelien-tchouameni', 'eduardo-camavinga', 'robert-pires', 'mesut-ozil',
  'bastian-schweinsteiger', 'joshua-kimmich', 'ilkay-gundogan', 'thomas-muller', 'ruud-van-nistelrooy',
  'virgil-van-dijk', 'frenkie-de-jong', 'jaap-stam', 'dennis-bergkamp', 'matthijs-de-ligt', 'gianluigi-buffon',
  'giorgio-chiellini', 'andrea-pirlo', 'sandro-tonali', 'xabi-alonso', 'xavi-hernandez', 'cesc-fabregas',
  'santi-cazorla', 'iker-casillas', 'joao-felix', 'bernardo-silva', 'ruben-dias', 'gabriel-jesus',
  'hakan-calhanoglu', 'khvicha-kvaratskhelia', 'sokratis-papastathopoulos', 'cheick-tiote', 'moussa-dembele',
  'kalidou-koulibaly', 'riyad-mahrez', 'mohamed-salah', 'yaya-toure', 'shinji-okazaki', 'son-heung-min',
];

class _Result {
  _Result(this.player, this.heard, this.matched, this.unhinted);
  final Player player;
  final List<String> heard;

  /// What it counted as in a game where this player is the right answer.
  final Player? matched;

  /// What it counted as with no hint (e.g. said as a wrong answer).
  final Player? unhinted;
  bool get ok => matched?.id == player.id;
}

class _VoiceTestScreenState extends State<VoiceTestScreen> {
  final _random = Random();
  final List<_Result> _results = [];
  late List<Player> _queue;
  int _index = 0;
  bool _listening = false;
  String _live = '';
  _Result? _last;

  late AppServices _s;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _s = AppScope.of(context);
    if (_ready) return;
    _ready = true;
    _queue = [
      for (final id in _testIds)
        if (_s.repo.players.byId(id) case final p?) p,
    ];
  }

  Player get _current {
    while (_index >= _queue.length) {
      _queue.add(_randomForeignName());
    }
    return _queue[_index];
  }

  /// A well-known player whose name follows another language's rules.
  Player _randomForeignName() {
    final pool = _s.repo.players.all.where((p) => p.fame >= 3 && p.spoken.isNotEmpty && !_queue.contains(p)).toList();
    return pool[_random.nextInt(pool.length)];
  }

  Future<void> _listen() async {
    final target = _current;
    setState(() {
      _listening = true;
      _live = '';
      _last = null;
    });
    final started = await _s.voice?.listen(
      onWords: (w) => setState(() => _live = w),
      onDone: (alts) {
        if (!mounted) return;
        final players = _s.repo.players;
        final matched = alts.isEmpty ? null : players.resolveSpoken(alts, isAnswer: (p) => p.id == target.id);
        final unhinted = alts.isEmpty ? null : players.resolveSpoken(alts);
        setState(() {
          _listening = false;
          _last = _Result(target, alts, matched, unhinted);
          _results.add(_last!);
        });
      },
    );
    if (started != true && mounted) {
      setState(() => _listening = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Voice isn’t available — turn on Voice answers in Settings and allow the microphone.')));
    }
  }

  void _next() {
    _s.voice?.stop();
    setState(() {
      _index++;
      _live = '';
      _last = null;
      _listening = false;
    });
  }

  String _report() {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    final good = _results.where((r) => r.ok).length;
    final b = StringBuffer('Quizinho voice test — $platform — $good/${_results.length} recognised\n');
    for (final r in _results) {
      b.writeln('${r.ok ? 'OK  ' : 'MISS'} ${r.player.name} [${r.player.id}] | heard: '
          '${r.heard.isEmpty ? '(nothing)' : r.heard.join(' / ')} | as answer: ${r.matched?.name ?? '-'}'
          ' | no hint: ${r.unhinted?.name ?? '-'}');
    }
    return b.toString();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _report()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Results copied — paste them into the chat with Claude.')));
  }

  @override
  void dispose() {
    _s.voice?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _current;
    final done = _results.length;
    final good = _results.where((r) => r.ok).length;
    final last = _last;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.pitch,
        title: Text('VOICE TEST', style: AppText.headline(26)),
        actions: [
          TextButton.icon(
            onPressed: done == 0 ? null : _copy,
            icon: const Icon(Icons.copy, color: Palette.yellow),
            label: Text('Copy results', style: AppText.label(13, color: Palette.yellow)),
          ),
        ],
      ),
      body: PitchBackground(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(
            'Say each name the way you would in a game — no need to say it "properly". '
            'Then copy the results and paste them to Claude.',
            style: AppText.label(14),
          ),
          const SizedBox(height: 8),
          Text('Name ${_index + 1}${_index < _testIds.length ? ' of ${_testIds.length}' : ' (bonus round)'}'
              ' · $good/$done recognised', style: AppText.label(13, color: Palette.yellow)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: Palette.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Palette.line),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(p.name.toUpperCase(), style: AppText.headline(40)),
            ),
          ),
          const SizedBox(height: 16),
          if (_listening)
            Text(_live.isEmpty ? 'Listening…' : '“$_live”',
                textAlign: TextAlign.center, style: AppText.headline(24, color: Palette.muted)),
          if (last != null) ...[
            Text(last.ok ? 'GOT IT' : 'MISSED', textAlign: TextAlign.center,
                style: AppText.headline(34, color: last.ok ? Palette.green : Palette.danger)),
            const SizedBox(height: 6),
            Text('Heard: ${last.heard.isEmpty ? '(nothing)' : last.heard.join('  /  ')}',
                textAlign: TextAlign.center, style: AppText.label(15, color: Palette.text)),
            if (!last.ok)
              Text('Matched: ${last.matched?.name ?? 'nobody'}',
                  textAlign: TextAlign.center, style: AppText.label(14)),
          ],
          const SizedBox(height: 20),
          BigButton(
            label: _listening ? 'Listening…' : (last == null ? 'Tap and say it' : 'Say it again'),
            icon: Icons.mic,
            onPressed: _listening ? null : _listen,
          ),
          const SizedBox(height: 10),
          BigButton(
            label: last == null ? 'Skip' : 'Next name',
            icon: Icons.arrow_forward,
            color: Palette.cardHigh,
            textColor: Palette.text,
            onPressed: _next,
          ),
        ]),
      ),
    );
  }
}
