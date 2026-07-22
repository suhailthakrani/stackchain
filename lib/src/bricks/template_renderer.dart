import 'package:recase/recase.dart';

/// Lightweight Mustache-style renderer (Mason-like `{{var}}` / `{{var.case}}`).
class TemplateRenderer {
  /// Renders [template] with [vars].
  ///
  /// Supported forms:
  /// - `{{name}}`
  /// - `{{name.snakeCase}}` / `pascalCase` / `camelCase` / `paramCase`
  /// - `{{#key}}...{{/key}}` truthy sections
  /// - `{{^key}}...{{/key}}` inverted sections
  static String render(String template, Map<String, dynamic> vars) {
    var out = template;

    // Inverted sections first
    out = out.replaceAllMapped(
      RegExp(r'\{\{\^(\w+)\}\}([\s\S]*?)\{\{/\1\}\}'),
      (m) {
        final key = m.group(1)!;
        final body = m.group(2)!;
        return _isTruthy(vars[key]) ? '' : render(body, vars);
      },
    );

    // Positive sections
    out = out.replaceAllMapped(
      RegExp(r'\{\{#(\w+)\}\}([\s\S]*?)\{\{/\1\}\}'),
      (m) {
        final key = m.group(1)!;
        final body = m.group(2)!;
        return _isTruthy(vars[key]) ? render(body, vars) : '';
      },
    );

    // {{key.case}} and {{key}}
    out = out.replaceAllMapped(
      RegExp(r'\{\{(\w+)(?:\.(\w+))?\}\}'),
      (m) {
        final key = m.group(1)!;
        final modifier = m.group(2);
        final value = vars[key];
        if (value == null) return m.group(0)!;
        final text = '$value';
        if (modifier == null) return text;
        final re = ReCase(text);
        return switch (modifier) {
          'snakeCase' || 'snake' => re.snakeCase,
          'pascalCase' || 'pascal' => re.pascalCase,
          'camelCase' || 'camel' => re.camelCase,
          'paramCase' || 'param' || 'kebabCase' => re.paramCase,
          'constantCase' || 'constant' => re.constantCase,
          'titleCase' || 'title' => re.titleCase,
          _ => text,
        };
      },
    );

    return out;
  }

  static bool _isTruthy(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) return value.isNotEmpty && value != 'false';
    if (value is num) return value != 0;
    return true;
  }
}
