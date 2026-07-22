import 'package:recase/recase.dart';

import '../../architecture/architecture_registry.dart';
import '../../models/enums.dart';
import '../../models/stackchain_config.dart';

/// Generates per-feature source files.
class FeatureTemplates {
  FeatureTemplates(
    this.config, {
    ArchitectureRegistry? registry,
  }) : _registry = registry ?? ArchitectureRegistry();

  final StackchainConfig config;
  final ArchitectureRegistry _registry;

  String get pkg => config.packageName ?? 'app';

  Map<String, String> generate() {
    final files = <String, String>{};
    for (final raw in config.features) {
      final feature = ReCase(raw).snakeCase;
      files.addAll(_forFeature(feature));
    }
    return files;
  }

  Map<String, String> _forFeature(String feature) {
    final layout = _registry.layoutFor(feature, config);
    final pascal = ReCase(feature).pascalCase;

    return switch (config.architecture) {
      Architecture.featureFirst || Architecture.clean =>
        _layered(feature, pascal, layout),
      Architecture.mvvm => _mvvm(feature, pascal, layout),
      Architecture.mvc => _mvc(feature, pascal, layout),
    };
  }

  Map<String, String> _layered(
    String feature,
    String pascal,
    FeatureLayout layout,
  ) {
    final files = <String, String>{
      '${layout.root}/domain/entities/${feature}_entity.dart': '''
import 'package:equatable/equatable.dart';

class ${pascal}Entity extends Equatable {
  const ${pascal}Entity({required this.id, required this.title});

  final String id;
  final String title;

  @override
  List<Object?> get props => [id, title];
}
''',
      '${layout.root}/domain/repositories/${feature}_repository.dart': '''
import '../entities/${feature}_entity.dart';

abstract class ${pascal}Repository {
  Future<${pascal}Entity> fetch();
}
''',
      '${layout.root}/domain/usecases/get_$feature.dart': '''
import '../entities/${feature}_entity.dart';
import '../repositories/${feature}_repository.dart';

class Get$pascal {
  Get$pascal(this._repository);

  final ${pascal}Repository _repository;

  Future<${pascal}Entity> call() => _repository.fetch();
}
''',
      '${layout.root}/data/models/${feature}_model.dart': '''
import '../../domain/entities/${feature}_entity.dart';

class ${pascal}Model extends ${pascal}Entity {
  const ${pascal}Model({required super.id, required super.title});

  factory ${pascal}Model.fromJson(Map<String, dynamic> json) {
    return ${pascal}Model(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '$pascal',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'title': title};
}
''',
      '${layout.root}/data/datasources/${feature}_remote_datasource.dart': '''
import '../models/${feature}_model.dart';

abstract class ${pascal}RemoteDataSource {
  Future<${pascal}Model> fetch();
}

class ${pascal}RemoteDataSourceImpl implements ${pascal}RemoteDataSource {
  @override
  Future<${pascal}Model> fetch() async {
    // Replace with ApiClient call.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const ${pascal}Model(id: '1', title: '$pascal');
  }
}
''',
      '${layout.root}/data/repositories/${feature}_repository_impl.dart': '''
import '../../domain/entities/${feature}_entity.dart';
import '../../domain/repositories/${feature}_repository.dart';
import '../datasources/${feature}_remote_datasource.dart';

class ${pascal}RepositoryImpl implements ${pascal}Repository {
  ${pascal}RepositoryImpl(this._remote);

  final ${pascal}RemoteDataSource _remote;

  @override
  Future<${pascal}Entity> fetch() => _remote.fetch();
}
''',
      '${layout.pagesDir}/${feature}_page.dart': _page(feature, pascal),
      '${layout.widgetsDir}/${feature}_header.dart': '''
import 'package:flutter/material.dart';

class ${pascal}Header extends StatelessWidget {
  const ${pascal}Header({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.headlineSmall);
  }
}
''',
    };

    files.addAll(_stateFiles(feature, pascal, layout));
    return files;
  }

  Map<String, String> _stateFiles(
    String feature,
    String pascal,
    FeatureLayout layout,
  ) {
    switch (config.stateManagement) {
      case StateManagement.bloc:
        return {
          '${layout.stateDir}/${feature}_event.dart': '''
import 'package:equatable/equatable.dart';

sealed class ${pascal}Event extends Equatable {
  const ${pascal}Event();

  @override
  List<Object?> get props => [];
}

final class ${pascal}Started extends ${pascal}Event {
  const ${pascal}Started();
}
''',
          '${layout.stateDir}/${feature}_state.dart': '''
import 'package:equatable/equatable.dart';

enum ${pascal}Status { initial, loading, success, failure }

class ${pascal}State extends Equatable {
  const ${pascal}State({
    this.status = ${pascal}Status.initial,
    this.title = '',
    this.message,
  });

  final ${pascal}Status status;
  final String title;
  final String? message;

  ${pascal}State copyWith({
    ${pascal}Status? status,
    String? title,
    String? message,
  }) {
    return ${pascal}State(
      status: status ?? this.status,
      title: title ?? this.title,
      message: message,
    );
  }

  @override
  List<Object?> get props => [status, title, message];
}
''',
          '${layout.stateDir}/${feature}_bloc.dart': '''
import 'package:flutter_bloc/flutter_bloc.dart';

import '${feature}_event.dart';
import '${feature}_state.dart';

class ${pascal}Bloc extends Bloc<${pascal}Event, ${pascal}State> {
  ${pascal}Bloc() : super(const ${pascal}State()) {
    on<${pascal}Started>(_onStarted);
  }

  Future<void> _onStarted(
    ${pascal}Started event,
    Emitter<${pascal}State> emit,
  ) async {
    emit(state.copyWith(status: ${pascal}Status.loading));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    emit(
      state.copyWith(
        status: ${pascal}Status.success,
        title: '$pascal',
      ),
    );
  }
}
''',
        };
      case StateManagement.cubit:
        return {
          '${layout.stateDir}/${feature}_state.dart': '''
import 'package:equatable/equatable.dart';

enum ${pascal}Status { initial, loading, success, failure }

class ${pascal}State extends Equatable {
  const ${pascal}State({
    this.status = ${pascal}Status.initial,
    this.title = '',
    this.message,
  });

  final ${pascal}Status status;
  final String title;
  final String? message;

  ${pascal}State copyWith({
    ${pascal}Status? status,
    String? title,
    String? message,
  }) {
    return ${pascal}State(
      status: status ?? this.status,
      title: title ?? this.title,
      message: message,
    );
  }

  @override
  List<Object?> get props => [status, title, message];
}
''',
          '${layout.stateDir}/${feature}_cubit.dart': '''
import 'package:flutter_bloc/flutter_bloc.dart';

import '${feature}_state.dart';

class ${pascal}Cubit extends Cubit<${pascal}State> {
  ${pascal}Cubit() : super(const ${pascal}State());

  Future<void> load() async {
    emit(state.copyWith(status: ${pascal}Status.loading));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    emit(
      state.copyWith(
        status: ${pascal}Status.success,
        title: '$pascal',
      ),
    );
  }
}
''',
        };
      case StateManagement.riverpod:
        return {
          '${layout.stateDir}/${feature}_provider.dart': '''
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ${pascal}State {
  const ${pascal}State({this.loading = false, this.title = '$pascal'});

  final bool loading;
  final String title;

  ${pascal}State copyWith({bool? loading, String? title}) {
    return ${pascal}State(
      loading: loading ?? this.loading,
      title: title ?? this.title,
    );
  }
}

class ${pascal}Notifier extends StateNotifier<${pascal}State> {
  ${pascal}Notifier() : super(const ${pascal}State());

  Future<void> load() async {
    state = state.copyWith(loading: true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    state = state.copyWith(loading: false, title: '$pascal');
  }
}

final ${feature}Provider =
    StateNotifierProvider<${pascal}Notifier, ${pascal}State>(
  (ref) => ${pascal}Notifier()..load(),
);
''',
        };
      case StateManagement.provider:
        return {
          '${layout.stateDir}/${feature}_provider.dart': '''
import 'package:flutter/foundation.dart';

class ${pascal}Provider extends ChangeNotifier {
  bool loading = false;
  String title = '$pascal';

  Future<void> load() async {
    loading = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    loading = false;
    title = '$pascal';
    notifyListeners();
  }
}
''',
        };
      case StateManagement.getx:
        final controllerImport = switch (config.architecture) {
          Architecture.mvc || Architecture.mvvm =>
            "../controllers/${feature}_controller.dart",
          Architecture.featureFirst || Architecture.clean =>
            "../presentation/controllers/${feature}_controller.dart",
        };
        // MVVM+GetX still uses a GetxController file in viewmodels folder.
        final controllerPath = config.architecture == Architecture.mvvm
            ? '${layout.stateDir}/${feature}_controller.dart'
            : '${layout.stateDir}/${feature}_controller.dart';
        return {
          controllerPath: '''
import 'package:get/get.dart';

class ${pascal}Controller extends GetxController {
  final loading = false.obs;
  final title = '$pascal'.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    title.value = '$pascal';
    loading.value = false;
  }
}
''',
          '${layout.root}/bindings/${feature}_binding.dart': '''
import 'package:get/get.dart';

import '$controllerImport';

class ${pascal}Binding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<${pascal}Controller>(${pascal}Controller.new);
  }
}
''',
        };
    }
  }

  String _page(String feature, String pascal) {
    final navLinks = config.features
        .where((f) => f != feature && config.routing == Routing.goRouter)
        .map((f) {
          final label = ReCase(f).pascalCase;
          return '''
            ListTile(
              title: const Text('$label'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.$f),
            ),''';
        })
        .join();

    final packageImports = <String>[
      "import 'package:flutter/material.dart';",
    ];
    if (config.stateManagement == StateManagement.bloc ||
        config.stateManagement == StateManagement.cubit) {
      packageImports.add("import 'package:flutter_bloc/flutter_bloc.dart';");
    } else if (config.stateManagement == StateManagement.riverpod) {
      packageImports
          .add("import 'package:flutter_riverpod/flutter_riverpod.dart';");
    } else if (config.stateManagement == StateManagement.provider) {
      packageImports.add("import 'package:provider/provider.dart';");
    } else if (config.stateManagement == StateManagement.getx) {
      packageImports.add("import 'package:get/get.dart';");
    }
    if (config.routing == Routing.goRouter) {
      packageImports.add("import 'package:go_router/go_router.dart';");
      packageImports.add("import 'package:$pkg/app/router/app_routes.dart';");
    }
    if (config.routing == Routing.getx) {
      packageImports.add("import 'package:get/get.dart';");
      packageImports.add("import 'package:$pkg/app/router/app_routes.dart';");
    }
    if (config.stateManagement == StateManagement.bloc ||
        config.stateManagement == StateManagement.cubit) {
      packageImports
        ..add("import 'package:$pkg/core/widgets/app_error_widget.dart';")
        ..add("import 'package:$pkg/core/widgets/app_loader.dart';");
    } else {
      packageImports.add("import 'package:$pkg/core/widgets/app_loader.dart';");
    }
    final pkgBlock = ({...packageImports}.toList()..sort()).join('\n');

    switch (config.stateManagement) {
      case StateManagement.bloc:
        return '''
$pkgBlock

import '../bloc/${feature}_bloc.dart';
import '../bloc/${feature}_event.dart';
import '../bloc/${feature}_state.dart';
import '../widgets/${feature}_header.dart';

class ${pascal}Page extends StatelessWidget {
  const ${pascal}Page({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ${pascal}Bloc()..add(const ${pascal}Started()),
      child: Scaffold(
        appBar: AppBar(title: const Text('$pascal')),
        body: BlocBuilder<${pascal}Bloc, ${pascal}State>(
          builder: (context, state) {
            return switch (state.status) {
              ${pascal}Status.initial || ${pascal}Status.loading =>
                const AppLoader(message: 'Loading...'),
              ${pascal}Status.failure => AppErrorWidget(
                  message: state.message ?? 'Something went wrong',
                  onRetry: () => context
                      .read<${pascal}Bloc>()
                      .add(const ${pascal}Started()),
                ),
              ${pascal}Status.success => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ${pascal}Header(title: state.title),
                    const SizedBox(height: 16),
                    Text(
                      'Generated by stackchain_flutter',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
${navLinks.isEmpty ? '' : '''
                    const SizedBox(height: 24),
                    Text('Navigate', style: Theme.of(context).textTheme.titleMedium),
                    $navLinks
'''}
                  ],
                ),
            };
          },
        ),
      ),
    );
  }
}
''';
      case StateManagement.cubit:
        return '''
$pkgBlock

import '../cubit/${feature}_cubit.dart';
import '../cubit/${feature}_state.dart';
import '../widgets/${feature}_header.dart';

class ${pascal}Page extends StatelessWidget {
  const ${pascal}Page({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ${pascal}Cubit()..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('$pascal')),
        body: BlocBuilder<${pascal}Cubit, ${pascal}State>(
          builder: (context, state) {
            return switch (state.status) {
              ${pascal}Status.initial || ${pascal}Status.loading =>
                const AppLoader(message: 'Loading...'),
              ${pascal}Status.failure => AppErrorWidget(
                  message: state.message ?? 'Something went wrong',
                  onRetry: () => context.read<${pascal}Cubit>().load(),
                ),
              ${pascal}Status.success => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ${pascal}Header(title: state.title),
                    const SizedBox(height: 16),
                    Text(
                      'Generated by stackchain_flutter',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
${navLinks.isEmpty ? '' : '''
                    const SizedBox(height: 24),
                    Text('Navigate', style: Theme.of(context).textTheme.titleMedium),
                    $navLinks
'''}
                  ],
                ),
            };
          },
        ),
      ),
    );
  }
}
''';
      case StateManagement.riverpod:
        return '''
$pkgBlock

import '../providers/${feature}_provider.dart';
import '../widgets/${feature}_header.dart';

class ${pascal}Page extends ConsumerWidget {
  const ${pascal}Page({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(${feature}Provider);
    return Scaffold(
      appBar: AppBar(title: const Text('$pascal')),
      body: state.loading
          ? const AppLoader()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ${pascal}Header(title: state.title),
                const SizedBox(height: 16),
                const Text('Generated by stackchain_flutter'),
              ],
            ),
    );
  }
}
''';
      case StateManagement.provider:
        return '''
$pkgBlock

import '../providers/${feature}_provider.dart';
import '../widgets/${feature}_header.dart';

class ${pascal}Page extends StatelessWidget {
  const ${pascal}Page({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ${pascal}Provider()..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('$pascal')),
        body: Consumer<${pascal}Provider>(
          builder: (context, state, _) {
            if (state.loading) return const AppLoader();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ${pascal}Header(title: state.title),
                const SizedBox(height: 16),
                const Text('Generated by stackchain_flutter'),
              ],
            );
          },
        ),
      ),
    );
  }
}
''';
      case StateManagement.getx:
        final controllerRel = switch (config.architecture) {
          Architecture.mvc => '../controllers/${feature}_controller.dart',
          Architecture.mvvm => '../viewmodels/${feature}_controller.dart',
          Architecture.featureFirst || Architecture.clean =>
            '../controllers/${feature}_controller.dart',
        };
        final navGetx = config.routing == Routing.getx
            ? config.features
                .where((f) => f != feature)
                .map((f) {
                  final label = ReCase(f).pascalCase;
                  return '''
            ListTile(
              title: const Text('$label'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed(AppRoutes.$f),
            ),''';
                })
                .join()
            : navLinks;
        return '''
$pkgBlock

import '$controllerRel';
import '../widgets/${feature}_header.dart';

class ${pascal}Page extends GetView<${pascal}Controller> {
  const ${pascal}Page({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('$pascal')),
      body: Obx(() {
        if (controller.loading.value) {
          return const AppLoader();
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ${pascal}Header(title: controller.title.value),
            const SizedBox(height: 16),
            const Text('Generated by stackchain_flutter'),
${navGetx.isEmpty ? '' : '''
            const SizedBox(height: 24),
            Text('Navigate', style: Theme.of(context).textTheme.titleMedium),
            $navGetx
'''}
          ],
        );
      }),
    );
  }
}
''';
    }
  }

  Map<String, String> _mvvm(
    String feature,
    String pascal,
    FeatureLayout layout,
  ) {
    return {
      '${layout.root}/models/${feature}_model.dart': '''
class ${pascal}Model {
  const ${pascal}Model({required this.title});
  final String title;
}
''',
      '${layout.stateDir}/${feature}_view_model.dart': '''
import 'package:flutter/foundation.dart';

import '../models/${feature}_model.dart';

class ${pascal}ViewModel extends ChangeNotifier {
  ${pascal}Model? model;
  bool loading = false;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    model = const ${pascal}Model(title: '$pascal');
    loading = false;
    notifyListeners();
  }
}
''',
      '${layout.pagesDir}/${feature}_page.dart': '''
import 'package:flutter/material.dart';

import '../viewmodels/${feature}_view_model.dart';

class ${pascal}Page extends StatefulWidget {
  const ${pascal}Page({super.key});

  @override
  State<${pascal}Page> createState() => _${pascal}PageState();
}

class _${pascal}PageState extends State<${pascal}Page> {
  late final ${pascal}ViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = ${pascal}ViewModel()..load();
    _vm.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _vm.removeListener(_onChange);
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('$pascal')),
      body: _vm.loading
          ? const Center(child: CircularProgressIndicator())
          : Center(child: Text(_vm.model?.title ?? '')),
    );
  }
}
''',
    };
  }

  Map<String, String> _mvc(
    String feature,
    String pascal,
    FeatureLayout layout,
  ) {
    if (config.stateManagement == StateManagement.getx) {
      return {
        '${layout.root}/models/${feature}_model.dart': '''
class ${pascal}Model {
  const ${pascal}Model({required this.title});
  final String title;
}
''',
        '${layout.stateDir}/${feature}_controller.dart': '''
import 'package:get/get.dart';

import '../models/${feature}_model.dart';

class ${pascal}Controller extends GetxController {
  final loading = false.obs;
  final model = Rxn<${pascal}Model>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    model.value = const ${pascal}Model(title: '$pascal');
    loading.value = false;
  }
}
''',
        '${layout.root}/bindings/${feature}_binding.dart': '''
import 'package:get/get.dart';

import '../controllers/${feature}_controller.dart';

class ${pascal}Binding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<${pascal}Controller>(${pascal}Controller.new);
  }
}
''',
        '${layout.pagesDir}/${feature}_page.dart': '''
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/${feature}_controller.dart';

class ${pascal}Page extends GetView<${pascal}Controller> {
  const ${pascal}Page({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('$pascal')),
      body: Obx(() {
        if (controller.loading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(
          child: Text(controller.model.value?.title ?? ''),
        );
      }),
    );
  }
}
''',
        '${layout.widgetsDir}/${feature}_header.dart': '''
import 'package:flutter/material.dart';

class ${pascal}Header extends StatelessWidget {
  const ${pascal}Header({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.headlineSmall);
  }
}
''',
      };
    }

    return {
      '${layout.root}/models/${feature}_model.dart': '''
class ${pascal}Model {
  const ${pascal}Model({required this.title});
  final String title;
}
''',
      '${layout.stateDir}/${feature}_controller.dart': '''
import '../models/${feature}_model.dart';

class ${pascal}Controller {
  ${pascal}Model? model;

  Future<${pascal}Model> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    model = const ${pascal}Model(title: '$pascal');
    return model!;
  }
}
''',
      '${layout.pagesDir}/${feature}_page.dart': '''
import 'package:flutter/material.dart';

import '../controllers/${feature}_controller.dart';
import '../models/${feature}_model.dart';

class ${pascal}Page extends StatefulWidget {
  const ${pascal}Page({super.key});

  @override
  State<${pascal}Page> createState() => _${pascal}PageState();
}

class _${pascal}PageState extends State<${pascal}Page> {
  final _controller = ${pascal}Controller();
  late Future<${pascal}Model> _future;

  @override
  void initState() {
    super.initState();
    _future = _controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('$pascal')),
      body: FutureBuilder<${pascal}Model>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(child: Text(snapshot.data!.title));
        },
      ),
    );
  }
}
''',
    };
  }
}
