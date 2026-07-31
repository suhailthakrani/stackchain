/// Layers produced by `stackchain test`.
enum TestType {
  unit,
  widget,
  integration;

  static const Set<TestType> all = {
    TestType.unit,
    TestType.widget,
    TestType.integration,
  };

  /// Parses a comma/space-separated list (`unit,widget`). Empty → all types.
  static Set<TestType> parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return Set<TestType>.from(all);

    final parts = raw
        .split(RegExp(r'[,|\s]+'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty);

    final result = <TestType>{};
    for (final part in parts) {
      final match = TestType.values.where((t) => t.name == part);
      if (match.isEmpty) {
        throw FormatException(
          'Unknown test type "$part". Use: unit, widget, integration',
        );
      }
      result.add(match.first);
    }
    if (result.isEmpty) return Set<TestType>.from(all);
    return result;
  }
}
