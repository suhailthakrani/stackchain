import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/file_writer.dart';
import '../utils/logger.dart';
import 'owned_regions.dart';
import 'region_merger.dart';
import 'smart_file_merger.dart';

/// Writes stackchain-owned files while preserving `// <stackchain:custom>` code.
class PreservingFileWriter {
  PreservingFileWriter({
    required this.writer,
    Logger? logger,
  }) : logger = logger ?? Logger();

  final FileWriter writer;
  final Logger logger;
  final _merger = const SmartFileMerger();

  final List<String> preserved = [];
  final List<String> backedUp = [];
  final List<String> merged = [];

  /// Writes [fullGenerated], merging owned regions when the file already exists.
  ///
  /// [previousPath] — when the owned file moves (e.g. bloc → cubit), custom
  /// code is ported from that path into the new file's `custom` region.
  Future<void> writeOwned({
    required String relativePath,
    required String fullGenerated,
    String? previousPath,
  }) async {
    final file = File(p.join(writer.root, relativePath));
    final exists = await file.exists();
    final existing = exists ? await file.readAsString() : null;

    var customBody = _readCustom(existing);
    if ((customBody == null || customBody.trim().isEmpty) &&
        previousPath != null &&
        previousPath != relativePath) {
      final prev = File(p.join(writer.root, previousPath));
      if (await prev.exists()) {
        customBody = _readCustom(await prev.readAsString());
      }
    }

    late String output;
    if (existing == null || existing.trim().isEmpty) {
      output = _applyCustom(fullGenerated, customBody);
      await writer.write(relativePath, output, force: true);
      return;
    }

    if (OwnedRegions.hasOwnedMarkers(existing)) {
      output = _merger.mergeGeneratedFile(
        existing: existing,
        fullGenerated: fullGenerated,
        regionIds: OwnedRegions.mergeIds,
      );
      // Test scaffolds use *_custom_test.dart instead — never inject/keep
      // custom regions on scaffold files.
      final isLibSource = relativePath.startsWith('lib/');
      final isTestScaffold = relativePath.startsWith('test/') ||
          relativePath.startsWith('integration_test/');
      if (isLibSource) {
        final currentCustom =
            RegionMerger.readRegion(output, OwnedRegions.custom);
        if ((currentCustom == null || currentCustom.trim().isEmpty) &&
            customBody != null &&
            customBody.trim().isNotEmpty) {
          output = RegionMerger.replaceRegion(
            source: output,
            id: OwnedRegions.custom,
            body: customBody,
          );
        } else if (!RegionMerger.hasRegion(output, OwnedRegions.custom)) {
          output = RegionMerger.replaceRegion(
            source: output,
            id: OwnedRegions.custom,
            body: customBody ?? OwnedRegions.customPlaceholder,
          );
        }
      } else if (isTestScaffold) {
        output = _stripRegion(output, OwnedRegions.custom);
      }
      merged.add(relativePath);
      preserved.add(relativePath);
      await writer.write(relativePath, output, force: true);
      return;
    }

    // Legacy file without markers.
    if (!writer.overwrite) {
      writer.skipped.add(relativePath);
      logger.warn(
        'Skipped $relativePath (customized, no stackchain markers). '
        'Pass --overwrite to replace (a .stackchain.bak backup is kept).',
      );
      return;
    }

    if (!writer.dryRun) {
      final bak = '$relativePath.stackchain.bak';
      await File(p.join(writer.root, bak)).writeAsString(existing);
      backedUp.add(bak);
      logger.warn('Backed up customized $relativePath → $bak');
    }

    output = _applyCustom(fullGenerated, customBody);
    await writer.write(relativePath, output, force: true);
  }

  /// Never overwrites; creates only when missing.
  Future<void> writeIfAbsent(String relativePath, String contents) async {
    final file = File(p.join(writer.root, relativePath));
    if (await file.exists()) {
      writer.skipped.add(relativePath);
      preserved.add(relativePath);
      return;
    }
    await writer.write(relativePath, contents, force: true);
  }

  /// Merges scaffold tests (`generated` region) without touching user edits
  /// outside markers; refuses blind overwrite of unmarked customized files
  /// unless [writer.overwrite] is true (then backs up).
  Future<void> writeScaffold({
    required String relativePath,
    required String fullGenerated,
  }) async {
    await writeOwned(relativePath: relativePath, fullGenerated: fullGenerated);
  }

  String? _readCustom(String? source) {
    if (source == null) return null;
    return RegionMerger.readRegion(source, OwnedRegions.custom);
  }

  String _applyCustom(String generated, String? customBody) {
    if (customBody == null || customBody.trim().isEmpty) return generated;
    if (!RegionMerger.hasRegion(generated, OwnedRegions.custom)) {
      return '$generated\n${OwnedRegions.customRegionBlock(body: customBody)}';
    }
    return RegionMerger.replaceRegion(
      source: generated,
      id: OwnedRegions.custom,
      body: customBody,
    );
  }

  String _stripRegion(String source, String id) {
    final open = '${RegionMerger.openPrefix}$id>';
    final close = '${RegionMerger.closePrefix}$id>';
    var result = source;
    while (true) {
      final openIndex = result.indexOf(open);
      final closeIndex = result.indexOf(close);
      if (openIndex < 0 || closeIndex <= openIndex) break;
      var end = closeIndex + close.length;
      if (end < result.length && result[end] == '\n') end++;
      var start = openIndex;
      if (start > 0 && result[start - 1] == '\n') start--;
      result = '${result.substring(0, start)}${result.substring(end)}';
    }
    return result;
  }
}
