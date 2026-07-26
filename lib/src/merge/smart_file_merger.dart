import 'dart_import_merger.dart';
import 'region_merger.dart';

/// High-level smart merge API used by sync / upgrade / vertical slices.
class SmartFileMerger {
  const SmartFileMerger();

  /// Replace a managed region and optionally merge imports.
  String merge({
    required String existing,
    required String regionId,
    required String regionBody,
    Iterable<String> imports = const [],
    String? insertBeforePattern,
  }) {
    var result = existing;
    if (imports.isNotEmpty) {
      result = DartImportMerger.mergeImports(result, imports);
    }
    result = RegionMerger.replaceRegion(
      source: result,
      id: regionId,
      body: regionBody,
      insertBeforePattern: insertBeforePattern,
    );
    return result;
  }

  /// Writes [fullGenerated] only when the file does not exist; otherwise merges
  /// every known region present in [fullGenerated] into [existing].
  String mergeGeneratedFile({
    required String? existing,
    required String fullGenerated,
    required List<String> regionIds,
  }) {
    if (existing == null || existing.trim().isEmpty) {
      return fullGenerated;
    }

    var result = existing;
    final generatedImports = DartImportMerger.readImports(fullGenerated);
    result = DartImportMerger.mergeImports(result, generatedImports);

    for (final id in regionIds) {
      final body = RegionMerger.readRegion(fullGenerated, id);
      if (body == null) continue;
      result = RegionMerger.replaceRegion(
        source: result,
        id: id,
        body: body,
      );
    }
    return result;
  }
}
