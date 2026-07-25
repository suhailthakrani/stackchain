import 'dart:io';

import 'package:path/path.dart' as p;

/// Writes generated files and tracks what was created/updated.
class FileWriter {
  FileWriter({
    required this.root,
    this.dryRun = false,
    this.overwrite = false,
  });

  final String root;
  final bool dryRun;
  final bool overwrite;

  final List<String> created = [];
  final List<String> skipped = [];
  final List<String> updated = [];

  Future<void> write(
    String relativePath,
    String contents, {
    bool force = false,
  }) async {
    final file = File(p.join(root, relativePath));
    final exists = await file.exists();

    if (exists && !overwrite && !force) {
      skipped.add(relativePath);
      return;
    }

    if (dryRun) {
      if (exists) {
        updated.add(relativePath);
      } else {
        created.add(relativePath);
      }
      return;
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
    if (exists) {
      updated.add(relativePath);
    } else {
      created.add(relativePath);
    }
  }

  Future<void> ensureDir(String relativePath) async {
    if (dryRun) return;
    await Directory(p.join(root, relativePath)).create(recursive: true);
  }
}

/// Reads host project metadata.
class ProjectContext {
  ProjectContext({
    required this.root,
    required this.packageName,
  });

  final String root;
  final String packageName;

  static Future<ProjectContext> detect(String root) async {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!await pubspec.exists()) {
      throw StateError(
        'No pubspec.yaml found in $root.\n'
        'Run this inside a Flutter project (flutter create my_app).',
      );
    }
    final content = await pubspec.readAsString();
    if (!content.contains(RegExp(r'^flutter\s*:', multiLine: true))) {
      throw StateError(
        'pubspec.yaml has no flutter section. '
        'stackchain must run inside a Flutter app.',
      );
    }
    final nameMatch =
        RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(content);
    if (nameMatch == null) {
      throw StateError('Could not read package name from pubspec.yaml');
    }
    return ProjectContext(root: root, packageName: nameMatch.group(1)!);
  }
}
