import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';

enum AppStatus { active, blocked }

class AppStatusService {
  static final AppStatusService instance = AppStatusService._();
  AppStatusService._();

  AppStatus _cachedStatus = AppStatus.active;
  StreamSubscription<DatabaseEvent>? _subscription;
  final ValueNotifier<AppStatus> statusNotifier = ValueNotifier(AppStatus.active);

  AppStatus get cachedStatus => _cachedStatus;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedStatus = (prefs.getBool('is_app_active') ?? true)
        ? AppStatus.active
        : AppStatus.blocked;
    statusNotifier.value = _cachedStatus;

    try {
      _subscription = FirebaseDatabase.instance
          .ref('app_status/app_active/Abdullah_AlAstal2')
          .onValue
          .listen((event) {
        final value = event.snapshot.value;
        if (value is bool) {
          _cachedStatus = value ? AppStatus.active : AppStatus.blocked;
          statusNotifier.value = _cachedStatus;
          prefs.setBool('is_app_active', value);
        }
      });
    } catch (_) {}
  }

  void dispose() {
    _subscription?.cancel();
  }
}
