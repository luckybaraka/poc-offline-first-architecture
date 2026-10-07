import 'package:flutter_test/flutter_test.dart';
import 'package:offline_poc_mobile/theme.dart';

// Kept so `flutter create .` doesn't generate a default test that references a missing MyApp.
void main() {
  test('ago() describes recent times in plain words', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    expect(ago(null), 'never');
    expect(ago(now), 'just now');
    expect(ago(now - 5 * 60 * 1000), '5 min ago');
  });
}
