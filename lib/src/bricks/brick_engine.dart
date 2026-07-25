import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../utils/file_writer.dart';
import '../utils/logger.dart';
import 'brick_manifest.dart';
import 'template_renderer.dart';

/// Mason-like brick generator: file templates + vars + hooks.
class BrickEngine {
  BrickEngine({
    required this.projectRoot,
    Logger? logger,
    this.overwrite = false,
    this.dryRun = false,
  }) : logger = logger ?? Logger();

  final String projectRoot;
  final Logger logger;
  final bool overwrite;
  final bool dryRun;

  /// Discovers built-in + project bricks (`.stackchain/bricks`, `bricks`).
  Future<Map<String, String>> discoverBricks() async {
    final found = <String, String>{};

    final packageBricks = await _packageBricksDir();
    if (packageBricks != null) {
      await _scan(packageBricks, found);
    }

    for (final rel in ['.stackchain/bricks', 'bricks']) {
      final dir = Directory(p.join(projectRoot, rel));
      if (await dir.exists()) {
        await _scan(dir.path, found);
      }
    }
    return found;
  }

  Future<void> _scan(String root, Map<String, String> into) async {
    final dir = Directory(root);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final manifest = File(p.join(entity.path, 'brick.yaml'));
      if (await manifest.exists()) {
        into[p.basename(entity.path)] = entity.path;
      }
    }
  }

  Future<String?> _packageBricksDir() async {
    try {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:stackchain/stackchain.dart'),
      );
      if (uri == null) return null;
      final packageRoot = p.dirname(p.dirname(uri.toFilePath()));
      final bricks = p.join(packageRoot, 'bricks');
      if (await Directory(bricks).exists()) return bricks;
    } catch (_) {/* path package during tests */}
    // Fallback: walk up from this script location is unreliable; try CWD package.
    final local = p.join(Directory.current.path, 'bricks');
    if (await Directory(local).exists()) return local;
    return null;
  }

  Future<BrickManifest> load(String brickName) async {
    final all = await discoverBricks();
    final path = all[brickName];
    if (path == null) {
      throw StateError(
        'Brick "$brickName" not found. Run `stackchain list` to see available bricks.',
      );
    }
    return BrickManifest.load(path);
  }

  /// Generates a brick into [projectRoot] with [vars].
  Future<int> make(
    String brickName, {
    required Map<String, dynamic> vars,
  }) async {
    final manifest = await load(brickName);
    final resolved = <String, dynamic>{...vars};

    for (final entry in manifest.vars.entries) {
      resolved.putIfAbsent(
        entry.key,
        () => entry.value.defaultValue ?? '',
      );
    }

    await _runHooks(manifest, 'pre_gen', resolved);

    final brickDir = Directory(manifest.brickDir);
    if (!await brickDir.exists()) {
      throw StateError('Brick "${manifest.name}" has no __brick__ directory');
    }

    final writer = FileWriter(
      root: projectRoot,
      dryRun: dryRun,
      overwrite: overwrite,
    );

    var count = 0;
    await for (final entity in brickDir.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: brickDir.path);
      final renderedPath = TemplateRenderer.render(relative, resolved)
          .replaceAll(r'\', '/');
      // Skip mustache "partial" helpers if any
      if (renderedPath.contains('{{')) {
        logger.warn('Unresolved path vars in $relative — skipped');
        continue;
      }
      final content = TemplateRenderer.render(
        await entity.readAsString(),
        resolved,
      );
      await writer.write(renderedPath, content);
      count++;
      logger.detail(renderedPath);
    }

    await _runHooks(manifest, 'post_gen', resolved);
    logger.success('Generated brick "$brickName" ($count files)');
    return count;
  }

  Future<void> _runHooks(
    BrickManifest manifest,
    String name,
    Map<String, dynamic> vars,
  ) async {
    final commands = manifest.hooks[name];
    if (commands == null || commands.isEmpty) return;
    for (final raw in commands) {
      final command = TemplateRenderer.render(raw, vars);
      logger.step('hook:$name → $command');
      if (dryRun) continue;
      final result = await Process.run(
        'bash',
        ['-c', command],
        workingDirectory: projectRoot,
        runInShell: true,
      );
      if (result.exitCode != 0) {
        logger.warn('Hook failed (${result.exitCode}): ${result.stderr}');
      }
    }
  }
}
