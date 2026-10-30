import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/core/voice_service.dart';

void main() {
  test('Android Chrome repeats are tidied before matching', () {
    expect(dedupeSpeech('jamesjames milner'), 'james milner');
    expect(dedupeSpeech('zlatanzlatan ibrahimovic'), 'zlatan ibrahimovic');
    expect(dedupeSpeech('dwight dwight yorke'), 'dwight yorke');
    expect(dedupeSpeech('jordan jordan henderson jordan henderson'), 'jordan henderson');
    expect(dedupeSpeech('Boudewijn Zenden'), 'Boudewijn Zenden');
    expect(dedupeSpeech('rooney giggs scholes'), 'rooney giggs scholes');
  });
}
