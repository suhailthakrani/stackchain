import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain/src/bricks/brick_engine.dart';
import 'package:stackchain/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('stripTemplateSuffix', () {
    test('drops trailing .tpl only', () {
      expect(stripTemplateSuffix('lib/app_chip.dart.tpl'), 'lib/app_chip.dart');
      expect(stripTemplateSuffix('lib/app_chip.dart'), 'lib/app_chip.dart');
      expect(stripTemplateSuffix('lib/tpl_helper.dart'), 'lib/tpl_helper.dart');
    });
  });

  group('BrickEngine.make', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('stackchain_brick_');
      final brickRoot = p.join(temp.path, 'bricks', 'demo');
      await File(p.join(brickRoot, 'brick.yaml')).create(recursive: true);
      await File(p.join(brickRoot, 'brick.yaml')).writeAsString('''
name: demo
description: Demo brick
vars:
  name:
    type: string
    description: Name
''');
      final file = File(
        p.join(brickRoot, '__brick__', 'lib', '{{name.snakeCase}}.dart.tpl'),
      );
      await file.create(recursive: true);
      await file.writeAsString('''
class {{name.pascalCase}} {
  const {{name.pascalCase}}();
}
''');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('renders .tpl template to a .dart file', () async {
      final count = await BrickEngine(
        projectRoot: temp.path,
        logger: Logger(),
      ).make('demo', vars: {'name': 'app_chip'});

      expect(count, 1);
      final generated = File(p.join(temp.path, 'lib', 'app_chip.dart'));
      expect(await generated.exists(), isTrue);
      expect(await generated.readAsString(), contains('class AppChip'));
      expect(
        await File(p.join(temp.path, 'lib', 'app_chip.dart.tpl')).exists(),
        isFalse,
      );
    });
  });
}
