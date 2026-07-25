import 'package:stackchain/src/bricks/template_renderer.dart';
import 'package:test/test.dart';

void main() {
  test('renders cases and sections', () {
    const template = '''
class {{name.pascalCase}} {
  static const id = '{{name.snakeCase}}';
  {{#withGetx}}
  // getx
  {{/withGetx}}
  {{^withGetx}}
  // no getx
  {{/withGetx}}
}
''';
    final out = TemplateRenderer.render(template, {
      'name': 'user_profile',
      'withGetx': true,
    });
    expect(out, contains('class UserProfile'));
    expect(out, contains("id = 'user_profile'"));
    expect(out, contains('// getx'));
    expect(out, isNot(contains('// no getx')));
  });
}
