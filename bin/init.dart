import 'package:stackchain_flutter/src/cli/cli.dart' as cli;

/// `dart run stackchain_flutter:init` — same as `stackchain init`.
Future<void> main(List<String> args) => cli.run(args);
