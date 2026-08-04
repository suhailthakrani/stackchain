import '../models/stackchain_config.dart';
import '../utils/stack_paths.dart';
import 'recipe_extras.dart';

/// List + form extras for `stackchain crud <entity>`.
abstract final class CrudRecipe {
  static Map<String, String> extras(String entity, StackchainConfig config) {
    final pascal = StackPaths.pascal(entity);
    final pkg = config.packageName ?? 'app';
    final widgets = FeatureRecipeExtras.widgetsDir(config, entity);
    final pageImport = StackPaths.pageImport(config, entity);

    return {
      '$widgets/${entity}_list_tile.dart': '''
import 'package:flutter/material.dart';

class ${pascal}ListTile extends StatelessWidget {
  const ${pascal}ListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.onTap,
    this.onDelete,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: onTap,
      trailing: onDelete == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              key: Key('${entity}_delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
    );
  }
}
''',
      '$widgets/${entity}_form.dart': '''
import 'package:flutter/material.dart';

/// Create / edit form for $pascal. Wire save to your repository.
class ${pascal}Form extends StatefulWidget {
  const ${pascal}Form({
    super.key,
    this.initialTitle = '',
    required this.onSave,
  });

  final String initialTitle;
  final void Function(String title) onSave;

  @override
  State<${pascal}Form> createState() => _${pascal}FormState();
}

class _${pascal}FormState extends State<${pascal}Form> {
  late final TextEditingController _title;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const Key('${entity}_title'),
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('${entity}_save'),
            onPressed: () {
              if (_formKey.currentState?.validate() ?? false) {
                widget.onSave(_title.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
''',
      'test/features/${entity}_form_test.dart': '''
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:$pkg/${widgets.replaceFirst('lib/', '')}/${entity}_form.dart';

void main() {
  // <stackchain:generated>
  testWidgets('${pascal}Form validates and saves', (tester) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ${pascal}Form(onSave: (t) => saved = t),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('${entity}_save')));
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('${entity}_title')), 'Demo');
    await tester.tap(find.byKey(const Key('${entity}_save')));
    await tester.pump();
    expect(saved, 'Demo');
  });
  // </stackchain:generated>
}
''',
      'lib/features/$entity/$entity.dart': '''
/// CRUD slice for $pascal — list tile + form + page.
///
/// Suggested flow:
/// 1. Load list via repository.fetch()
/// 2. Create/edit with ${pascal}Form
/// 3. Delete via repository (add methods in // <stackchain:custom>)
library;

export 'package:$pkg/$pageImport';
export 'package:$pkg/${widgets.replaceFirst('lib/', '')}/${entity}_list_tile.dart';
export 'package:$pkg/${widgets.replaceFirst('lib/', '')}/${entity}_form.dart';
''',
    };
  }
}
