import '../models/stackchain_config.dart';
import '../testing/feature_test_templates.dart';
import '../testing/test_types.dart';
import 'recipe_extras.dart';

/// Blueprint extras layered on top of generic feature templates.
///
/// Known recipes (`auth`, `settings`, `onboarding`, …) get richer wiring + tests.
/// Entity list/form: `dart run stackchain crud <entity>`.
abstract final class SliceRecipes {
  static Map<String, String> extras(String feature, StackchainConfig config) {
    return {
      ...FeatureTestTemplates(config).generate(
        feature,
        types: const {TestType.unit},
      ),
      ...FeatureRecipeExtras.extras(feature, config),
    };
  }
}
