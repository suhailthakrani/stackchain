import '../quality/quality_gate.dart';
import '../slices/feature_remover.dart';
import '../slices/feature_renamer.dart';
import '../slices/vertical_slice.dart';
import '../utils/logger.dart';

/// Adds, removes, or renames a feature as a full vertical slice.
class FeatureCommand {
  FeatureCommand({
    required this.root,
    required this.logger,
    this.overwrite = false,
    this.dryRun = false,
    this.skipAnalyze = false,
  });

  final String root;
  final Logger logger;
  final bool overwrite;
  final bool dryRun;
  final bool skipAnalyze;

  Future<QualityReport> add(String rawName) {
    return VerticalSliceGenerator(
      root: root,
      logger: logger,
      overwrite: overwrite,
      dryRun: dryRun,
      skipAnalyze: skipAnalyze,
    ).add(rawName);
  }

  Future<FeatureRemoveReport> remove(String rawName) {
    return FeatureRemover(
      root: root,
      logger: logger,
      dryRun: dryRun,
      skipAnalyze: skipAnalyze,
    ).remove(rawName);
  }

  Future<FeatureRenameReport> rename(String rawFrom, String rawTo) {
    return FeatureRenamer(
      root: root,
      logger: logger,
      dryRun: dryRun,
      skipAnalyze: skipAnalyze,
    ).rename(rawFrom, rawTo);
  }
}
