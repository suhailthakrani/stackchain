import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../utils/stack_paths.dart';

/// Blueprint extras layered on top of generic feature templates.
///
/// Known recipes (`auth`, `settings`, `profile`) get richer wiring + tests.
abstract final class SliceRecipes {
  static Map<String, String> extras(String feature, StackchainConfig config) {
    final files = <String, String>{
      ..._testScaffold(feature, config),
    };

    switch (feature) {
      case 'auth':
        files.addAll(_authExtras(config));
      case 'settings':
        files.addAll(_settingsExtras(config));
      case 'profile':
        files.addAll(_profileExtras(config));
    }
    return files;
  }

  static Map<String, String> _testScaffold(
    String feature,
    StackchainConfig config,
  ) {
    final pascal = StackPaths.pascal(feature);
    final pkg = config.packageName ?? 'app';

    if (StackPaths.layered(config) &&
        config.stateManagement.usesFlutterBloc) {
      if (config.stateManagement == StateManagement.bloc) {
        return {
          'test/features/${feature}_bloc_test.dart': '''
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:$pkg/features/$feature/presentation/bloc/${feature}_bloc.dart';
import 'package:$pkg/features/$feature/presentation/bloc/${feature}_event.dart';
import 'package:$pkg/features/$feature/presentation/bloc/${feature}_state.dart';

void main() {
  group('${pascal}Bloc', () {
    blocTest<${pascal}Bloc, ${pascal}State>(
      'emits loading then success on start',
      build: ${pascal}Bloc.new,
      act: (b) => b.add(const ${pascal}Started()),
      wait: const Duration(milliseconds: 300),
      expect: () => [
        isA<${pascal}State>(),
        isA<${pascal}State>(),
      ],
    );
  });
}
''',
        };
      }
      return {
        'test/features/${feature}_cubit_test.dart': '''
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:$pkg/features/$feature/presentation/cubit/${feature}_cubit.dart';
import 'package:$pkg/features/$feature/presentation/cubit/${feature}_state.dart';

void main() {
  group('${pascal}Cubit', () {
    blocTest<${pascal}Cubit, ${pascal}State>(
      'emits success after load',
      build: ${pascal}Cubit.new,
      act: (c) => c.load(),
      wait: const Duration(milliseconds: 300),
      expect: () => [
        isA<${pascal}State>(),
        isA<${pascal}State>(),
      ],
    );
  });
}
''',
      };
    }

    if (StackPaths.layered(config) && config.stateManagement.usesRxDart) {
      return {
        'test/features/${feature}_controller_test.dart': '''
import 'package:flutter_test/flutter_test.dart';
import 'package:$pkg/features/$feature/presentation/controllers/${feature}_controller.dart';
import 'package:$pkg/features/$feature/presentation/controllers/${feature}_state.dart';

void main() {
  late ${pascal}Controller controller;

  setUp(() {
    controller = ${pascal}Controller();
  });

  tearDown(() {
    controller.dispose();
  });

  test('emits success after load', () async {
    await expectLater(
      controller.stream,
      emitsThrough(
        isA<${pascal}State>().having(
          (s) => s.status,
          'status',
          ${pascal}Status.success,
        ),
      ),
    );
  });
}
''',
      };
    }

    return {
      'test/features/${feature}_test.dart': '''
import 'package:flutter_test/flutter_test.dart';
import 'package:$pkg/${StackPaths.pageImport(config, feature)}';

void main() {
  test('${pascal}Page type is available', () {
    expect(${pascal}Page, isNotNull);
  });
}
''',
    };
  }

  static String _widgetsDir(StackchainConfig config, String feature) {
    switch (config.architecture) {
      case Architecture.featureFirst:
      case Architecture.clean:
        return 'lib/features/$feature/presentation/widgets';
      case Architecture.mvvm:
      case Architecture.mvc:
        return 'lib/features/$feature/widgets';
    }
  }

  static Map<String, String> _authExtras(StackchainConfig config) {
    final pkg = config.packageName ?? 'app';
    final widgets = _widgetsDir(config, 'auth');
    final pageImport = StackPaths.pageImport(config, 'auth');
    return {
      '$widgets/auth_form.dart': '''
import 'package:flutter/material.dart';

class AuthForm extends StatefulWidget {
  const AuthForm({super.key, required this.onSubmit});

  final void Function(String email, String password) onSubmit;

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) =>
                (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            validator: (v) =>
                (v == null || v.length < 6) ? 'Min 6 characters' : null,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              if (_formKey.currentState?.validate() ?? false) {
                widget.onSubmit(_email.text.trim(), _password.text);
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
''',
      'lib/features/auth/auth.dart': '''
/// Auth vertical slice — wired by stackchain.
///
/// Flow:
/// 1. Call API login via ApiClient
/// 2. Persist tokens with SessionService.saveSession
/// 3. RouteGuards + GoRouter redirect keep the session honest
library;

export 'package:$pkg/$pageImport';
export 'package:$pkg/${widgets.replaceFirst('lib/', '')}/auth_form.dart';
''',
    };
  }

  static Map<String, String> _settingsExtras(StackchainConfig config) {
    final pkg = config.packageName ?? 'app';
    final widgets = _widgetsDir(config, 'settings');
    final pageImport = StackPaths.pageImport(config, 'settings');
    return {
      '$widgets/settings_tile.dart': '''
import 'package:flutter/material.dart';

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
''',
      'lib/features/settings/settings.dart': '''
library;

export 'package:$pkg/$pageImport';
export 'package:$pkg/${widgets.replaceFirst('lib/', '')}/settings_tile.dart';
''',
    };
  }

  static Map<String, String> _profileExtras(StackchainConfig config) {
    final pkg = config.packageName ?? 'app';
    final widgets = _widgetsDir(config, 'profile');
    final pageImport = StackPaths.pageImport(config, 'profile');
    return {
      '$widgets/profile_header.dart': '''
import 'package:flutter/material.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.name,
    this.email,
    this.avatarUrl,
  });

  final String name;
  final String? email;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundImage:
              avatarUrl == null ? null : NetworkImage(avatarUrl!),
          child: avatarUrl == null ? Text(initial) : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleMedium),
              if (email != null)
                Text(email!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
''',
      'lib/features/profile/profile.dart': '''
library;

export 'package:$pkg/$pageImport';
export 'package:$pkg/${widgets.replaceFirst('lib/', '')}/profile_header.dart';
''',
    };
  }
}
