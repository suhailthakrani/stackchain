import 'package:stackchain/src/models/stackchain_config.dart';
import 'package:stackchain/src/utils/pubspec_merger.dart';
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
    expect(RegExp(r'^dependencies:', multiLine: true).allMatches(merged).length,
        1);
  });

  test('localization adds flutter_localizations and drops stale intl pin', () {
    const existing = '''
name: demo
dependencies:
  flutter:
    sdk: flutter
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter

flutter:
  uses-material-design: true
''';

    final merged = PubspecMerger.merge(
      existing: existing,
      config: StackchainConfig(
        packageName: 'demo',
        modules: const ModulesConfig(localization: true),
      ),
    );

    expect(merged, contains('flutter_localizations:'));
    expect(merged, contains(RegExp(r'flutter_localizations:\s*\n\s+sdk: flutter')));
    expect(merged, contains('generate: true'));
    expect(merged, isNot(contains('intl:')));
  });
}
