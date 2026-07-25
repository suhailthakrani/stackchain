import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/{{name.snakeCase}}_controller.dart';

class {{name.pascalCase}}Page extends GetView<{{name.pascalCase}}Controller> {
  const {{name.pascalCase}}Page({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('{{name.titleCase}}')),
      body: Obx(() {
        if (controller.loading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(child: Text(controller.title.value));
      }),
    );
  }
}
