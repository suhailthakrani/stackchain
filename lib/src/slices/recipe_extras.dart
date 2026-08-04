import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../utils/stack_paths.dart';

/// Extra widgets / barrel files for known shippable feature recipes.
abstract final class FeatureRecipeExtras {
  /// Features that get recipe extras beyond the generic vertical slice.
  static const known = {
    'auth',
    'settings',
    'profile',
    'onboarding',
    'notifications',
    'search',
  };

  static Map<String, String> extras(
    String feature,
    StackchainConfig config,
  ) {
    switch (feature) {
      case 'auth':
        return _authExtras(config);
      case 'settings':
        return _settingsExtras(config);
      case 'profile':
        return _profileExtras(config);
      case 'onboarding':
        return _onboardingExtras(config);
      case 'notifications':
        return _notificationsExtras(config);
      case 'search':
        return _searchExtras(config);
      default:
        return const {};
    }
  }

  static String widgetsDir(StackchainConfig config, String feature) {
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
    final widgets = widgetsDir(config, 'auth');
    final pageImport = StackPaths.pageImport(config, 'auth');
    return {
      '$widgets/auth_form.dart': '''
import 'package:flutter/material.dart';

/// Email/password form — wire [onSubmit] to SessionService + API login.
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
            key: const Key('auth_email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) =>
                (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('auth_password'),
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            validator: (v) =>
                (v == null || v.length < 6) ? 'Min 6 characters' : null,
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('auth_submit'),
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
      'test/features/auth_form_test.dart': '''
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:$pkg/${widgets.replaceFirst('lib/', '')}/auth_form.dart';

void main() {
  // <stackchain:generated>
  testWidgets('AuthForm validates and submits', (tester) async {
    String? email;
    String? password;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthForm(
            onSubmit: (e, p) {
              email = e;
              password = p;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('auth_submit')));
    await tester.pump();
    expect(find.text('Enter a valid email'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('auth_email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('auth_password')), 'secret1');
    await tester.tap(find.byKey(const Key('auth_submit')));
    await tester.pump();

    expect(email, 'a@b.com');
    expect(password, 'secret1');
  });
  // </stackchain:generated>
}
''',
      'lib/features/auth/auth.dart': '''
/// Auth vertical slice — wired by stackchain.
///
/// Flow:
/// 1. Validate via [AuthForm]
/// 2. Call API login via ApiClient
/// 3. Persist tokens with SessionService.saveSession
/// 4. RouteGuards + router redirect keep the session honest
library;

export 'package:$pkg/$pageImport';
export 'package:$pkg/${widgets.replaceFirst('lib/', '')}/auth_form.dart';
''',
    };
  }

  static Map<String, String> _settingsExtras(StackchainConfig config) {
    final pkg = config.packageName ?? 'app';
    final widgets = widgetsDir(config, 'settings');
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
      'lib/features/settings/data/settings_preferences.dart': '''
import 'package:shared_preferences/shared_preferences.dart';

/// Local settings persistence (theme, notifications opt-in, etc.).
class SettingsPreferences {
  SettingsPreferences(this._prefs);

  final SharedPreferences _prefs;

  static const _darkKey = 'settings.dark_mode';
  static const _notifyKey = 'settings.notifications';

  bool get darkMode => _prefs.getBool(_darkKey) ?? false;
  Future<void> setDarkMode(bool value) => _prefs.setBool(_darkKey, value);

  bool get notificationsEnabled => _prefs.getBool(_notifyKey) ?? true;
  Future<void> setNotificationsEnabled(bool value) =>
      _prefs.setBool(_notifyKey, value);
}
''',
      'test/features/settings_preferences_test.dart': '''
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:$pkg/features/settings/data/settings_preferences.dart';

void main() {
  // <stackchain:generated>
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SettingsPreferences persists dark mode', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsPreferences(prefs);

    expect(settings.darkMode, isFalse);
    await settings.setDarkMode(true);
    expect(settings.darkMode, isTrue);
  });
  // </stackchain:generated>
}
''',
      'lib/features/settings/settings.dart': '''
library;

export 'package:$pkg/$pageImport';
export 'package:$pkg/${widgets.replaceFirst('lib/', '')}/settings_tile.dart';
export 'package:$pkg/features/settings/data/settings_preferences.dart';
''',
    };
  }

  static Map<String, String> _profileExtras(StackchainConfig config) {
    final pkg = config.packageName ?? 'app';
    final widgets = widgetsDir(config, 'profile');
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

  static Map<String, String> _onboardingExtras(StackchainConfig config) {
    final pkg = config.packageName ?? 'app';
    final widgets = widgetsDir(config, 'onboarding');
    final pageImport = StackPaths.pageImport(config, 'onboarding');
    return {
      '$widgets/onboarding_page_view.dart': '''
import 'package:flutter/material.dart';

class OnboardingSlide {
  const OnboardingSlide({required this.title, required this.body});
  final String title;
  final String body;
}

/// Swipeable first-run experience. Persist completion via SharedPreferences.
class OnboardingPageView extends StatefulWidget {
  const OnboardingPageView({
    super.key,
    required this.slides,
    required this.onFinished,
  });

  final List<OnboardingSlide> slides;
  final VoidCallback onFinished;

  @override
  State<OnboardingPageView> createState() => _OnboardingPageViewState();
}

class _OnboardingPageViewState extends State<OnboardingPageView> {
  final _controller = PageController();
  var _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _index >= widget.slides.length - 1;
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final slide = widget.slides[i];
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(slide.title, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(slide.body, textAlign: TextAlign.center),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const Key('onboarding_next'),
            onPressed: () {
              if (last) {
                widget.onFinished();
              } else {
                _controller.nextPage(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              }
            },
            child: Text(last ? 'Get started' : 'Next'),
          ),
        ),
      ],
    );
  }
}
''',
      'lib/features/onboarding/onboarding.dart': '''
library;

export 'package:$pkg/$pageImport';
export 'package:$pkg/${widgets.replaceFirst('lib/', '')}/onboarding_page_view.dart';
''',
    };
  }

  static Map<String, String> _notificationsExtras(StackchainConfig config) {
    final pkg = config.packageName ?? 'app';
    final widgets = widgetsDir(config, 'notifications');
    final pageImport = StackPaths.pageImport(config, 'notifications');
    return {
      '$widgets/notification_tile.dart': '''
import 'package:flutter/material.dart';

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final bool read;
}

class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.item, this.onTap});

  final NotificationItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(item.read ? Icons.notifications_none : Icons.notifications_active),
      title: Text(item.title),
      subtitle: Text(item.body),
      onTap: onTap,
    );
  }
}
''',
      'lib/features/notifications/notifications.dart': '''
library;

export 'package:$pkg/$pageImport';
export 'package:$pkg/${widgets.replaceFirst('lib/', '')}/notification_tile.dart';
''',
    };
  }

  static Map<String, String> _searchExtras(StackchainConfig config) {
    final pkg = config.packageName ?? 'app';
    final widgets = widgetsDir(config, 'search');
    final pageImport = StackPaths.pageImport(config, 'search');
    return {
      '$widgets/search_box.dart': '''
import 'package:flutter/material.dart';

class SearchBox extends StatelessWidget {
  const SearchBox({
    super.key,
    required this.onChanged,
    this.hintText = 'Search',
    this.controller,
  });

  final ValueChanged<String> onChanged;
  final String hintText;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('search_box'),
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: hintText,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
''',
      'lib/features/search/search.dart': '''
library;

export 'package:$pkg/$pageImport';
export 'package:$pkg/${widgets.replaceFirst('lib/', '')}/search_box.dart';
''',
    };
  }
}
