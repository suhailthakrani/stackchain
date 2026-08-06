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
///
/// Markers must be the only content on their line (leading whitespace ok).
/// Mentions inside doc comments like `// - // <stackchain:core> …` are ignored.
class RegionMerger {
  static const openPrefix = '// <stackchain:';
  static const closePrefix = '// </stackchain:';

  /// Returns true if [source] already has a managed region [id].
  static bool hasRegion(String source, String id) {
    return _markerIndex(source, '$openPrefix$id>') >= 0 &&
        _markerIndex(source, '$closePrefix$id>') >= 0;
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

    final openIndex = _markerIndex(source, open);
    final closeIndex = _markerIndex(source, close);

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
    final openIndex = _markerIndex(source, open);
    final closeIndex = _markerIndex(source, close);
    if (openIndex < 0 || closeIndex <= openIndex) return null;
    var body = source.substring(openIndex + open.length, closeIndex);
    // Drop the newline immediately after the open marker only — keep indent.
    if (body.startsWith('\r\n')) {
      body = body.substring(2);
    } else if (body.startsWith('\n')) {
      body = body.substring(1);
    }
    if (body.endsWith('\r\n')) {
      body = body.substring(0, body.length - 2);
    } else if (body.endsWith('\n')) {
      body = body.substring(0, body.length - 1);
    }
    return body;
  }

  /// Index of a marker that sits alone on its line (optional leading indent).
  static int _markerIndex(String source, String marker) {
    final re = RegExp(
      '^\\s*${RegExp.escape(marker)}\\s*\$',
      multiLine: true,
    );
    final match = re.firstMatch(source);
    if (match == null) return -1;
    // Prefer the start of the marker token itself (after indent).
    final line = match.group(0)!;
    final indent = line.indexOf(marker);
    return match.start + (indent < 0 ? 0 : indent);
  }

  static String _normalizeBody(String body) {
    if (body.isEmpty) return '';
    var b = body.replaceAll('\r\n', '\n');
    if (!b.endsWith('\n')) b = '$b\n';
    // Indent non-empty lines that aren't already indented when used in lists.
    return b;
  }
}
