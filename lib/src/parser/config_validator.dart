import '../models/enums.dart';
import '../models/stackchain_config.dart';

/// Validates a [StackchainConfig] and returns human-readable warnings/errors.
class ConfigValidator {
  const ConfigValidator();

  /// Throws [FormatException] on hard errors; returns soft warnings.
  List<String> validate(StackchainConfig config) {
    final warnings = <String>[];

    final seen = <String>{};
    for (final f in config.features) {
      final name = f.toLowerCase();
      if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
        throw FormatException(
          'Invalid feature name "$f". Use snake_case (e.g. user_profile).',
        );
      }
      if (!seen.add(name)) {
        warnings.add('Duplicate feature "$f" ignored.');
      }
    }

    if (config.modules.crashlytics && !config.modules.firebase) {
      warnings.add(
        'crashlytics requires firebase — enabling firebase module.',
      );
    }

    if (config.di == DiType.injectable &&
        config.stateManagement == StateManagement.riverpod) {
      warnings.add(
        'injectable + riverpod works, but Riverpod often uses its own providers. '
        'GetIt is still useful for non-UI services.',
      );
    }

    if (config.routing == Routing.autoRoute) {
      warnings.add(
        'auto_route requires a follow-up `dart run build_runner build` '
        'after generation.',
      );
    }

    return warnings;
  }
}
