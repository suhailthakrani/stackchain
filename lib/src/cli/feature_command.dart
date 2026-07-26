import '../quality/quality_gate.dart';
import '../slices/vertical_slice.dart';
import '../utils/logger.dart';

/// Adds a single feature as a full vertical slice (files + router + DI + tests).
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
}
