import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class BlockService {
  static final BlockService instance = BlockService._();
  BlockService._();

  StreamSubscription<DatabaseEvent>? _rtdbSubscription;
  StreamSubscription<User?>? _authSubscription;
  String? _lastUid;

  String? get currentUid => _lastUid;

  void _setupRtdbListener(String uid, {
    required void Function() onBlocked,
    required void Function() onUnblocked,
  }) {
    _rtdbSubscription?.cancel();
    _rtdbSubscription = FirebaseDatabase.instance
        .ref('app_status/users/$uid')
        .onValue
        .listen((event) {
      final value = event.snapshot.value;
      if (value is bool) {
        if (!value) {
          onBlocked();
        } else {
          onUnblocked();
        }
      }
    });
  }

  void start({
    required void Function() onBlocked,
    required void Function() onUnblocked,
  }) async {
    String? uid;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      uid = currentUser.uid;
    } else {
      uid = (await SharedPreferences.getInstance()).getString('uid');
    }
    if (uid != null) {
      _lastUid = uid;
      _setupRtdbListener(uid, onBlocked: onBlocked, onUnblocked: onUnblocked);
    }

    _authSubscription?.cancel();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      final newUid = user?.uid;
      if (newUid == null) return;
      _lastUid = newUid;
      _setupRtdbListener(newUid, onBlocked: onBlocked, onUnblocked: onUnblocked);
    });
  }

  static Future<void> verifyBlockStatus() async {}

  void stop() {
    _rtdbSubscription?.cancel();
    _rtdbSubscription = null;
    _authSubscription?.cancel();
    _authSubscription = null;
    _lastUid = null;
  }
}

class MaintenanceScreen extends StatefulWidget {
  final String? uid;
  final VoidCallback? onUnblocked;
  const MaintenanceScreen({super.key, this.uid, this.onUnblocked});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  StreamSubscription<DatabaseEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _handleBlocked();
    if (widget.uid != null) {
      _subscription = FirebaseDatabase.instance
          .ref('app_status/users/${widget.uid}')
          .onValue
          .listen((event) {
        final value = event.snapshot.value;
        if (value is bool && value) {
          widget.onUnblocked?.call();
        }
      });
    }
  }

  Future<void> _handleBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('uid');
    try {
      final auth = FirebaseAuth.instance;
      await auth.signOut();
    } catch (_) {}
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.construction,
                  size: 100,
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                ),
                const SizedBox(height: 24),
                Text(
                  'نظام نقاط البيع',
                  style: GoogleFonts.cairo(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF7C3AED),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'التطبيق قيد الصيانة حالياً',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'يرجى المحاولة لاحقاً',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
