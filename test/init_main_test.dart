import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain/src/generators/project_generator.dart';
import 'package:stackchain/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('init replaces stock Flutter main.dart', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('stackchain_init_');
      await File(p.join(temp.path, 'pubspec.yaml')).writeAsString('''
name: demo_app
description: test
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter

flutter:
  uses-material-design: true
''');
      await Directory(p.join(temp.path, 'lib')).create();
      await File(p.join(temp.path, 'lib/main.dart')).writeAsString('''
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() => _counter++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(child: Text('\$_counter')),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        child: const Icon(Icons.add),
      ),
    );
  }
}
''');
      await File(p.join(temp.path, 'test/widget_test.dart'))
          .create(recursive: true);
      await File(p.join(temp.path, 'test/widget_test.dart')).writeAsString('''
import 'package:flutter_test/flutter_test.dart';
import 'package:demo_app/main.dart';

void main() {
  testWidgets('Counter increments', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('0'), findsOneWidget);
  });
}
''');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('overwrites counter main.dart without --overwrite', () async {
      await ProjectGenerator(
        root: temp.path,
        logger: Logger(),
      ).run();

      final main = await File(p.join(temp.path, 'lib/main.dart')).readAsString();
      expect(main, contains('configureDependencies'));
      expect(main, contains('/app/app.dart'));
      expect(main, isNot(contains('_counter')));
      expect(main, isNot(contains('MyHomePage')));

      expect(
        await File(p.join(temp.path, 'test/widget_test.dart')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(temp.path, 'lib/app/app.dart')).exists(),
        isTrue,
      );
    });
  });
}
