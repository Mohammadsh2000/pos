import 'package:flutter/material.dart';

class CompactIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onPressed;

  const CompactIconButton({super.key, required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      icon: icon,
      onPressed: onPressed,
    );
  }
}
