import 'dart:io';

import 'package:path/path.dart' as p;

import '../generators/project_generator.dart';
import '../models/stackchain_config.dart';
import '../templates/app/app_templates.dart';

/// Paths migrate refreshes for the target stack (bootstrap / mains / app).
const appShellPaths = [
  'lib/bootstrap.dart',
  'lib/main.dart',
  'lib/app/app.dart',
  'lib/main_dev.dart',
  'lib/main_staging.dart',
  'lib/main_prod.dart',
];

/// Required shell files — always expected after init.
const requiredAppShellPaths = [
  'lib/bootstrap.dart',
  'lib/main.dart',
  'lib/app/app.dart',
];

/// Decides whether migrate may overwrite an app-shell file.
///
/// Virgin stackchain shells (exact match of the previous or next template)
/// are safe to swap. Stock Flutter / leftover init stubs for `main.dart` are
/// also safe. Hand-customized shells are refused unless [forceShell].
class AppShellSafety {
  /// Returns relative paths that would be clobbered (customized + not forced).
  static Future<List<String>> blockedPaths({
    required String root,
    required StackchainConfig before,
    required StackchainConfig after,
    bool forceShell = false,
  }) async {
    if (forceShell) return const [];

    final beforeFiles = AppTemplates(before).generate();
    final afterFiles = AppTemplates(after).generate();
    final blocked = <String>[];

    for (final path in appShellPaths) {
      final next = afterFiles[path];
      if (next == null) continue;

      final file = File(p.join(root, path));
      final isRequired = requiredAppShellPaths.contains(path);
      if (!isRequired && !await file.exists()) continue;
      if (!await file.exists()) continue;

      final existing = await file.readAsString();
      if (isVirginShell(
        relativePath: path,
        existing: existing,
        beforeTemplate: beforeFiles[path],
        afterTemplate: next,
      )) {
        continue;
      }
      blocked.add(path);
    }
    return blocked;
  }

  /// True when [existing] still matches a stock stackchain shell template,
  /// or is a leftover Flutter / init stub for `main.dart`.
  static bool isVirginShell({
    required String existing,
    required String? beforeTemplate,
    required String afterTemplate,
    String relativePath = '',
  }) {
    final normalized = normalize(existing);
    if (normalized == normalize(afterTemplate)) return true;
    if (beforeTemplate != null && normalized == normalize(beforeTemplate)) {
      return true;
    }
    // Init may skip replacing a non-counter main; still allow migrate to
    // install the stackchain entrypoint when it is clearly not customized.
    if (relativePath == 'lib/main.dart' || relativePath.endsWith('/main.dart')) {
      if (ProjectGenerator.isStockFlutterCounterMain(existing)) return true;
      if (_isLeftoverInitMainStub(existing)) return true;
    }
    return false;
  }

  /// Minimal mains used in tests / unfinished inits (no bootstrap, no app).
  static bool _isLeftoverInitMainStub(String content) {
    if (content.contains('bootstrap()')) return false;
    if (content.contains('/app/app.dart')) return false;
    // Very small MaterialApp stub — not real product logic.
    final lines = content
        .split('\n')
        .map((l) => l.trim())
        .where(
          (l) =>
              l.isNotEmpty && !l.startsWith('//') && !l.startsWith('import '),
        )
        .toList();
    if (lines.length > 6) return false;
    return content.contains('MaterialApp') && content.contains('void main(');
  }

  static String normalize(String source) {
    return source
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .trim();
  }

  static String refuseMessage(List<String> paths) {
    final list = paths.map((p) => '  - $p').join('\n');
    return 'Refusing to overwrite customized app shell:\n$list\n'
        'Move irreplaceable logic out of bootstrap/main/app.dart '
        '(or into a service), then re-run migrate.\n'
        'To force-clobber the shell: dart run stackchain migrate '
        '... --force-shell';
  }
}
