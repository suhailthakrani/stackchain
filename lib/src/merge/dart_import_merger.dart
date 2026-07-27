/// Lightweight Dart import / URI AST-style merges without the analyzer package.
class DartImportMerger {
  static final _importRe = RegExp(
    r"""^\s*import\s+['"]([^'"]+)['"]\s*;\s*$""",
    multiLine: true,
  );

  /// Merges [toAdd] import URIs into [source], preserving existing order and
  /// inserting new imports after the last existing import (or at file start).
  static String mergeImports(String source, Iterable<String> toAdd) {
    final existing = <String>{};
    for (final m in _importRe.allMatches(source)) {
      existing.add(m.group(1)!);
    }

    final missing = toAdd
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty && !existing.contains(u))
        .toSet()
        .toList()
      ..sort();

    if (missing.isEmpty) return source;

    final lines = missing.map((u) => "import '$u';").join('\n');

    final matches = _importRe.allMatches(source).toList();
    if (matches.isEmpty) {
      // Insert after library/part/part of / comments at top when possible.
      final insertAt = _topInsertOffset(source);
      final before = source.substring(0, insertAt);
      final after = source.substring(insertAt);
      final padBefore = before.isEmpty || before.endsWith('\n') ? '' : '\n';
      final padAfter = after.startsWith('\n') ? '' : '\n';
      return '$before$padBefore$lines\n$padAfter$after';
    }

    final last = matches.last;
    final insertAt = last.end;
    final before = source.substring(0, insertAt);
    final after = source.substring(insertAt);
    final pad = before.endsWith('\n') ? '' : '\n';
    return '$before$pad$lines${after.startsWith('\n') ? '' : '\n'}$after';
  }

  static int _topInsertOffset(String source) {
    final lines = source.split('\n');
    var offset = 0;
    for (final line in lines) {
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty ||
          trimmed.startsWith('//') ||
          trimmed.startsWith('/*') ||
          trimmed.startsWith('*') ||
          trimmed.startsWith('library ') ||
          trimmed.startsWith('part ') ||
          trimmed.startsWith('part of ')) {
        offset += line.length + 1;
        continue;
      }
      break;
    }
    return offset.clamp(0, source.length);
  }

  /// Removes import lines whose URI is in [toRemove].
  static String removeImports(String source, Iterable<String> toRemove) {
    final targets = toRemove
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toSet();
    if (targets.isEmpty) return source;

    final matches = _importRe.allMatches(source).toList();
    if (matches.isEmpty) return source;

    final buffer = StringBuffer();
    var cursor = 0;
    for (final m in matches) {
      final uri = m.group(1)!;
      if (!targets.contains(uri)) continue;
      // Drop the whole line, including the trailing newline when present.
      var start = m.start;
      var end = m.end;
      if (end < source.length && source[end] == '\n') {
        end++;
      } else if (start > 0 && source[start - 1] == '\n') {
        start--;
      }
      buffer.write(source.substring(cursor, start));
      cursor = end;
    }
    buffer.write(source.substring(cursor));
    return buffer.toString();
  }

  /// Collects all import URIs from [source].
  static Set<String> readImports(String source) {
    return {
      for (final m in _importRe.allMatches(source)) m.group(1)!,
    };
  }
}
