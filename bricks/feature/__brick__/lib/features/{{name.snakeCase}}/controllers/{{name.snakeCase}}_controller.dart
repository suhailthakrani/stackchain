import 'package:get/get.dart';

class {{name.pascalCase}}Controller extends GetxController {
  final loading = false.obs;
  final title = '{{name.pascalCase}}'.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    title.value = '{{name.pascalCase}}';
    loading.value = false;
  }
}
