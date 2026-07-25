import 'package:stackchain/src/cli/cli.dart' as cli;

/// `dart run stackchain:init` — same as `dart run stackchain init`.
Future<void> main(List<String> args) => cli.run(['init', ...args]);
