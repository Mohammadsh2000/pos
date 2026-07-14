import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/activation_service.dart';
import '../utils/notifications.dart';
import 'main_page.dart';
import 'activation_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      final result = await AuthService.instance.signInWithGoogle();
      if (!mounted) return;
      setState(() => _loading = false);

      if (result != null && result.user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('uid', result.user!.uid);
        if (!mounted) return;

        final status = await ActivationService.instance
            .checkActivation(result.user!.uid);
        if (!mounted) return;

        switch (status) {
          case ActivationStatus.active:
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainPage()),
            );
          case ActivationStatus.expired:
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                  builder: (_) => const ActivationScreen(expired: true)),
            );
          case ActivationStatus.notActivated:
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                  builder: (_) => const ActivationScreen()),
            );
        }
      } else {
        final err = AuthService.instance.lastError;
        if (err != null && mounted) {
          showTopNotification(context, 'فشل تسجيل الدخول: $err');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final prefs = await SharedPreferences.getInstance();
      final isActivated = prefs.getBool('isActivated') ?? false;
      if (isActivated) {
        final cachedUntil = prefs.getInt('activated_until');
        if (cachedUntil != null &&
            DateTime.now().millisecondsSinceEpoch > cachedUntil) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (_) => const ActivationScreen(expired: true)),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainPage()),
          );
        }
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ActivationScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.point_of_sale,
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
                const SizedBox(height: 8),
                Text(
                  'سجل الدخول بحساب Google للمتابعة',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _signIn,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF7C3AED),
                            ),
                          )
                        : const Icon(
                            Icons.login,
                            color: Colors.black54,
                            size: 22,
                          ),
                    label: Text(
                      _loading ? 'جارٍ تسجيل الدخول...' : 'تسجيل الدخول بحساب Google',
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
