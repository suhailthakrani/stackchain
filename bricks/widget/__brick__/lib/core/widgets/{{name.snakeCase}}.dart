import 'package:flutter/material.dart';

class {{name.pascalCase}} extends StatelessWidget {
  const {{name.pascalCase}}({
    super.key,
    required this.label,
    this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
