import 'region_merger.dart';

/// Stackchain-owned marker ids for presentation / test scaffolds.
///
/// - [handlers] / [generated]: refreshed on migrate / test refresh
/// - [custom]: **never** overwritten — user logic lives here
abstract final class OwnedRegions {
  static const handlers = 'handlers';
  static const generated = 'generated';
  static const custom = 'custom';

  /// Regions stackchain is allowed to replace.
  static const mergeIds = [handlers, generated];

  static const customPlaceholder =
      '  // Add custom methods here. Preserved across migrate / test refresh.\n';

  static const customTestPlaceholder = '''
  // Add tests for your custom methods / flows here.
  // This file is never overwritten by stackchain.
''';

  static bool hasOwnedMarkers(String source) {
    return RegionMerger.hasRegion(source, generated) ||
        RegionMerger.hasRegion(source, handlers) ||
        RegionMerger.hasRegion(source, custom);
  }

  /// Empty custom region block (indented for class bodies).
  static String customRegionBlock({String body = customPlaceholder}) {
    final open = '${RegionMerger.openPrefix}$custom>';
    final close = '${RegionMerger.closePrefix}$custom>';
    final normalized = body.endsWith('\n') ? body : '$body\n';
    return '$open\n$normalized$close\n';
  }
}
