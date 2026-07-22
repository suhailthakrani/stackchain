import 'package:stackchain_flutter/src/models/stackchain_config.dart';
import 'package:stackchain_flutter/src/utils/pubspec_merger.dart';
import 'package:test/test.dart';

void main() {
  test('PubspecMerger inserts deps without breaking YAML', () {
    const existing = '''
name: demo
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
''';

    final merged = PubspecMerger.merge(
      existing: existing,
      config: StackchainConfig.defaults(packageName: 'demo'),
    );

    expect(merged, contains('dio:'));
    expect(merged, contains('flutter_bloc:'));
    expect(merged, contains('\ndev_dependencies:\n'));
    expect(merged, isNot(contains('0dev_dependencies')));
    expect(merged, contains('bloc_test:'));
    // Still only one of each section header
    expect('dev_dependencies:'.allMatches(merged).length, 1);
    expect(RegExp(r'^dependencies:', multiLine: true).allMatches(merged).length, 1);
  });
}
