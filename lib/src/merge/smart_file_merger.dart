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
  ///
  /// Also syncs imports: adds imports from [fullGenerated], and drops relative
  /// state-layer imports (`../bloc/`, `../cubit/`, …) that are no longer present
  /// in the generated file (so pages update cleanly on soft merge).
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
    final existingImports = DartImportMerger.readImports(result);

    // Drop stale relative presentation imports not in the new template.
    final staleRelative = existingImports.where((uri) {
      if (!uri.startsWith('../')) return false;
      if (!_stateLayerImport.hasMatch(uri)) return false;
      return !generatedImports.contains(uri);
    });
    result = DartImportMerger.removeImports(result, staleRelative);
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

  static final _stateLayerImport = RegExp(
    r'^\.\./(bloc|cubit|providers|controllers|viewmodels)/',
  );
}
