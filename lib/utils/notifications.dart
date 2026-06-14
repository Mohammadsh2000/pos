import 'dart:async';
import 'package:flutter/material.dart';

void showTopNotification(BuildContext context, String message, {Color? backgroundColor, Duration? duration}) {
  _showTopOverlay(context, message, backgroundColor: backgroundColor, duration: duration);
}

void _showTopOverlay(BuildContext context, String message, {Color? backgroundColor, Duration? duration}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TopNotification(
      message: message,
      backgroundColor: backgroundColor ?? Colors.red.shade700,
      duration: duration ?? const Duration(seconds: 3),
      onDismiss: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _TopNotification extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final Duration duration;
  final VoidCallback onDismiss;

  const _TopNotification({
    required this.message,
    required this.backgroundColor,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_TopNotification> createState() => _TopNotificationState();
}

class _TopNotificationState extends State<_TopNotification> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_controller);
    _controller.forward();
    Timer(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    return Positioned(
      top: padding.top + 10,
      left: 20,
      right: 20,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
