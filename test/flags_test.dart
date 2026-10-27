import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/core/flags.dart';

void main() {
  test('country codes become flag emoji', () {
    expect(flagFor('POR'), '🇵🇹');
    expect(flagFor('BRA'), '🇧🇷');
    expect(flagFor('GER'), '🇩🇪');
    expect(flagFor('ENG'), '🏴󠁧󠁢󠁥󠁮󠁧󠁿');
  });

  test('no flag falls back to the code', () {
    expect(flagFor('SUN'), isNull);
    expect(nationalityLabel('SUN'), 'SUN');
    expect(nationalityLabel(null), isNull);
  });
}
