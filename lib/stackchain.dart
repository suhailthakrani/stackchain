/// Stackchain — config-driven Flutter project scaffolding that evolves.
///
/// ```bash
/// dart run stackchain init
/// dart run stackchain feature auth
/// dart run stackchain test auth
/// dart run stackchain sync
/// dart run stackchain upgrade
/// dart run stackchain migrate --state cubit
/// ```
library;

export 'src/bricks/brick_engine.dart';
export 'src/bricks/template_renderer.dart';
export 'src/generators/project_generator.dart';
export 'src/merge/owned_regions.dart';
export 'src/merge/preserving_file_writer.dart';
export 'src/merge/region_merger.dart';
export 'src/merge/smart_file_merger.dart';
export 'src/migrate/migration_engine.dart';
export 'src/migrate/upgrade_engine.dart';
export 'src/models/stackchain_config.dart';
export 'src/parser/yaml_parser.dart';
export 'src/presets/preset_registry.dart';
export 'src/quality/quality_gate.dart';
export 'src/slices/feature_remover.dart';
export 'src/slices/feature_renamer.dart';
export 'src/slices/vertical_slice.dart';
export 'src/sync/project_sync.dart';
export 'src/testing/feature_test_generator.dart';
export 'src/testing/feature_test_templates.dart';
export 'src/testing/test_types.dart';
export 'src/version.dart';
