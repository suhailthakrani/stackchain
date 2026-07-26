/// Marker-based smart merges for Stackchain-managed Dart regions.
///
/// Regions look like:
/// ```dart
/// // <stackchain:routes>
/// ...generated...
/// // </stackchain:routes>
/// ```
///
/// Hand-written code outside markers is preserved. Content inside is replaced
/// on sync / upgrade / feature add.
class RegionMerger {
  static const openPrefix = '// <stackchain:';
  static const closePrefix = '// </stackchain:';

  /// Returns true if [source] already has a managed region [id].
  static bool hasRegion(String source, String id) {
    return source.contains('$openPrefix$id>') &&
        source.contains('$closePrefix$id>');
  }

  /// Replaces the body of region [id], or appends a new region at [fallbackAnchor]
  /// (regex) / end of file when the region is missing.
  static String replaceRegion({
    required String source,
    required String id,
    required String body,
    String? insertBeforePattern,
  }) {
    final open = '$openPrefix$id>';
    final close = '$closePrefix$id>';
    final normalizedBody = _normalizeBody(body);

    final openIndex = source.indexOf(open);
    final closeIndex = source.indexOf(close);

    if (openIndex >= 0 && closeIndex > openIndex) {
      final before = source.substring(0, openIndex + open.length);
      final after = source.substring(closeIndex);
      final gap = before.endsWith('\n') ? '' : '\n';
      final mid = normalizedBody.isEmpty
          ? ''
          : '$gap$normalizedBody${normalizedBody.endsWith('\n') ? '' : '\n'}';
      return '$before$mid$after';
    }

    final block = StringBuffer()
      ..writeln(open)
      ..write(normalizedBody)
      ..writeln(close);

    if (insertBeforePattern != null) {
      final re = RegExp(insertBeforePattern, multiLine: true);
      final match = re.firstMatch(source);
      if (match != null) {
        return '${source.substring(0, match.start)}'
            '$block'
            '${source.substring(match.start)}';
      }
    }

    final trimmed = source.trimRight();
    final sep = trimmed.isEmpty || trimmed.endsWith('\n') ? '' : '\n';
    return '$trimmed$sep\n$block\n';
  }

  /// Ensures region [id] exists; if missing, wraps [defaultBody] into a new region.
  static String ensureRegion({
    required String source,
    required String id,
    required String defaultBody,
    String? insertBeforePattern,
  }) {
    if (hasRegion(source, id)) return source;
    return replaceRegion(
      source: source,
      id: id,
      body: defaultBody,
      insertBeforePattern: insertBeforePattern,
    );
  }

  /// Extracts region body (without markers), or null if absent.
  static String? readRegion(String source, String id) {
    final open = '$openPrefix$id>';
    final close = '$closePrefix$id>';
    final openIndex = source.indexOf(open);
    final closeIndex = source.indexOf(close);
    if (openIndex < 0 || closeIndex <= openIndex) return null;
    return source.substring(openIndex + open.length, closeIndex).trim();
  }

  static String _normalizeBody(String body) {
    if (body.isEmpty) return '';
    var b = body.replaceAll('\r\n', '\n');
    if (!b.endsWith('\n')) b = '$b\n';
    // Indent non-empty lines that aren't already indented when used in lists.
    return b;
  }
}
