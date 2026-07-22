import 'package:ansicolor/ansicolor.dart';

/// Lightweight CLI logger.
class Logger {
  Logger({this.verbose = false});

  final bool verbose;

  final _green = AnsiPen()..green(bold: true);
  final _cyan = AnsiPen()..cyan(bold: true);
  final _yellow = AnsiPen()..yellow(bold: true);
  final _red = AnsiPen()..red(bold: true);
  final _dim = AnsiPen()..gray();

  void info(String message) => print(message);

  void success(String message) => print(_green('✓ $message'));

  void step(String message) => print(_cyan('→ $message'));

  void warn(String message) => print(_yellow('⚠ $message'));

  void error(String message) => print(_red('✗ $message'));

  void detail(String message) {
    if (verbose) print(_dim('  $message'));
  }

  void banner(String title) {
    print('');
    print(_cyan('╭──────────────────────────────────────╮'));
    print(_cyan('│  $title'));
    print(_cyan('╰──────────────────────────────────────╯'));
    print('');
  }
}
