import 'dart:io';

import 'package:stackchain/src/cli/cli.dart' as cli;
import 'package:test/test.dart';

void main() {
  group('help command', () {
    test('help prints usage and exits 0', () async {
      exitCode = 0;
      await cli.run(const ['help']);
      expect(exitCode, 0);
    });

    test('help migrate prints migrate usage', () async {
      exitCode = 0;
      await cli.run(const ['help', 'migrate']);
      expect(exitCode, 0);
    });

    test('help unknown topic sets exit 64', () async {
      exitCode = 0;
      await cli.run(const ['help', 'not-a-command']);
      expect(exitCode, 64);
    });
  });
}
