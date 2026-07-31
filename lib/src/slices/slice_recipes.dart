import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../testing/feature_test_templates.dart';
import '../testing/test_types.dart';
import '../utils/stack_paths.dart';

/// Blueprint extras layered on top of generic feature templates.
///
/// Known recipes (`auth`, `settings`, `profile`) get richer wiring + tests.
abstract final class SliceRecipes {
  static Map<String, String> extras(String feature, StackchainConfig config) {
    final files = <String, String>{
      // Default unit scaffold on `feature add`. Full suite: `stackchain test`.
      ...FeatureTestTemplates(config).generate(
        feature,
        types: const {TestType.unit},
      ),
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
