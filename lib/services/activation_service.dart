import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ActivationStatus { active, expired, notActivated }

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double _parseDurationDays(dynamic value) {
  if (value == null) return -1;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? -1;
  return -1;
}

String _formatDateTime(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
        .toIso8601String();

int? _parseExpiryMs(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    final dt = DateTime.tryParse(value);
    return dt?.millisecondsSinceEpoch;
  }
  if (value is num) return value.toInt();
  return null;
}

class ActivationService {
  static final ActivationService instance = ActivationService._();
  ActivationService._();

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  final ValueNotifier<ActivationStatus> statusNotifier =
      ValueNotifier(ActivationStatus.notActivated);

  StreamSubscription<DatabaseEvent>? _rtdbSub;
  StreamSubscription<User?>? _authSub;
  void Function()? _onExpired;
  void Function()? _onActive;

  void _setupListener(String uid) {
    _rtdbSub?.cancel();
    _rtdbSub = _db
        .child('activated_users/$uid')
        .onValue
        .listen((event) async {
      try {
        final data = event.snapshot.value;
        final prefs = await SharedPreferences.getInstance();

        if (data is! Map) {
          await prefs.remove('isActivated');
          await prefs.remove('activated_until');
          statusNotifier.value = ActivationStatus.notActivated;
          _onExpired?.call();
          return;
        }

        final activatedUntil = _parseExpiryMs(data['activated_until']);
        final serverTime = await _getServerTimeMs();

        if (activatedUntil != null && serverTime > activatedUntil) {
          await prefs.remove('isActivated');
          await prefs.remove('activated_until');
          statusNotifier.value = ActivationStatus.expired;
          _onExpired?.call();
        } else {
          await prefs.setBool('isActivated', true);
          if (activatedUntil != null) {
            await prefs.setInt('activated_until', activatedUntil);
          } else {
            await prefs.remove('activated_until');
          }
          statusNotifier.value = ActivationStatus.active;
          _onActive?.call();
        }
      } catch (_) {}
    });
  }

  void startListening({
    required void Function() onExpired,
    void Function()? onActive,
  }) {
    _onExpired = onExpired;
    _onActive = onActive;

    String? uid;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      uid = currentUser.uid;
    }

    if (uid != null) {
      _setupListener(uid);
    }

    _authSub?.cancel();
    _authSub =
        FirebaseAuth.instance.authStateChanges().listen((user) {
      final newUid = user?.uid;
      if (newUid == null) return;
      _setupListener(newUid);
    });
  }

  void stopListening() {
    _rtdbSub?.cancel();
    _rtdbSub = null;
    _authSub?.cancel();
    _authSub = null;
  }

  Future<int> _getServerTimeMs() async {
    try {
      final offset =
          await _db.child('.info/serverTimeOffset').once();
      final offsetValue = _parseInt(offset.snapshot.value) ?? 0;
      return DateTime.now().millisecondsSinceEpoch + offsetValue;
    } catch (_) {
      return DateTime.now().millisecondsSinceEpoch;
    }
  }

  Future<ActivationStatus> checkActivation(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final isActivated = prefs.getBool('isActivated') ?? false;

    try {
      Object? data;
      try {
        final snapshot = await _db
            .child('activated_users/$uid')
            .once()
            .timeout(const Duration(seconds: 5));
        data = snapshot.snapshot.value;
      } catch (_) {
        data = null;
      }

      // نت مقطوع — اعتماد على الكاش المحلي
      if (data is! Map) {
        if (!isActivated) return ActivationStatus.notActivated;
        final cachedUntil = prefs.getInt('activated_until');
        if (cachedUntil == null) return ActivationStatus.active;
        if (DateTime.now().millisecondsSinceEpoch > cachedUntil) {
          await prefs.remove('isActivated');
          await prefs.remove('activated_until');
          return ActivationStatus.expired;
        }
        return ActivationStatus.active;
      }

      // في نت — فحص وتحديث الكاش
      final activatedUntil = _parseExpiryMs(data['activated_until']);
      final serverTime = await _getServerTimeMs();

      if (activatedUntil != null && serverTime > activatedUntil) {
        await prefs.remove('isActivated');
        await prefs.remove('activated_until');
        statusNotifier.value = ActivationStatus.expired;
        return ActivationStatus.expired;
      }

      await prefs.setBool('isActivated', true);
      if (activatedUntil != null) {
        await prefs.setInt('activated_until', activatedUntil);
      } else {
        await prefs.remove('activated_until');
      }

      statusNotifier.value = ActivationStatus.active;
      return ActivationStatus.active;
    } catch (e) {
      dev.log('checkActivation error: $e');
      if (!isActivated) return ActivationStatus.notActivated;
      final cachedUntil = prefs.getInt('activated_until');
      if (cachedUntil == null) return ActivationStatus.active;
      if (DateTime.now().millisecondsSinceEpoch > cachedUntil) {
        await prefs.remove('isActivated');
        await prefs.remove('activated_until');
        return ActivationStatus.expired;
      }
      return ActivationStatus.active;
    }
  }

  Future<String> activateAccount(
      String uid, String email, String code) async {
    try {
      final snapshot =
          await _db.child('activation_codes/$code').once();
      final raw = snapshot.snapshot.value;

      if (raw is! Map) return 'كود التفعيل غير صحيح';

      if (raw['used'] == true) return 'هذا الكود مستخدم من قبل';

      final durationDays = _parseDurationDays(raw['duration_days']);
      final serverTime = await _getServerTimeMs();

      final int? activatedUntil = durationDays < 0
          ? null
          : serverTime + (durationDays * 86400000).round();

      final updates = <String, dynamic>{};
      updates['activation_codes/$code/used'] = true;
      updates['activation_codes/$code/used_by'] = email;
      updates['activation_codes/$code/used_at'] = _formatDateTime(serverTime);
      updates['activated_users/$uid'] = {
        'email': email,
        'activated_at': _formatDateTime(serverTime),
        'activated_until':
            activatedUntil != null ? _formatDateTime(activatedUntil) : null,
        'code': code,
        'duration_days': durationDays == durationDays.roundToDouble()
            ? durationDays.toInt().toString()
            : durationDays.toString(),
      };

      await _db.update(updates);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isActivated', true);
      if (activatedUntil != null) {
        await prefs.setInt('activated_until', activatedUntil);
      }

      return '';
    } catch (e) {
      dev.log('activateAccount error: $e');
      final msg = e.toString();
      if (msg.contains('permission-denied') ||
          msg.contains('Permission denied') ||
          msg.contains('PERMISSION_DENIED')) {
        return 'ليس لديك صلاحية للتفعيل';
      }
      return 'حدث خطأ غير متوقع. تأكد من اتصالك بالإنترنت';
    }
  }
}
