import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/activation_service.dart';
import 'main_page.dart';
import 'login_screen.dart';
import 'activation_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final CurvedAnimation _textFade;
  late final CurvedAnimation _logoFade;
  late final CurvedAnimation _glowFade;
  late final CurvedAnimation _logoScale;

  static const double _impactAt = 0.32;
  static const double _jellyAmp = 0.07;
  static const double _jellyFreq = 15.0;
  static const double _jellyDecay = 7.0;
  static const double _dragY = 0.12;
  static const double _dragX = 0.06;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _textFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.58, 0.78, curve: Curves.easeOut),
    );

    _logoFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, _impactAt * 0.7, curve: Curves.easeIn),
    );

    _logoScale = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, _impactAt, curve: Curves.easeOutBack),
    );

    _glowFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.08, 0.48, curve: Curves.easeOut),
    );

    _ctrl.addListener(() => setState(() {}));
    _ctrl.addStatusListener((status) async {
      if (status == AnimationStatus.completed) await _checkAuth();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), _tryStart);
    });
  }

  void _tryStart() {
    if (!mounted) return;
    _ctrl.forward(from: 0.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _textFade.dispose();
    _logoFade.dispose();
    _logoScale.dispose();
    _glowFade.dispose();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    User? user;
    if (isLoggedIn) {
      user = AuthService.instance.currentUser;
      if (user != null) {
        if (!mounted) return;
        await _checkActivationAndNavigate(user);
        return;
      }
      await prefs.remove('isLoggedIn');
      await prefs.remove('uid');
    }

    user = AuthService.instance.currentUser;
    if (user != null) {
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('uid', user.uid);
      if (!mounted) return;
      await _checkActivationAndNavigate(user);
    } else {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Future<void> _checkActivationAndNavigate(User user) async {
    try {
      final status =
          await ActivationService.instance.checkActivation(user.uid);
      if (!mounted) return;
      _navigateBasedOnStatus(status);
    } catch (_) {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final isActivated = prefs.getBool('isActivated') ?? false;
      if (!isActivated) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ActivationScreen()),
        );
        return;
      }
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
    }
  }

  void _navigateBasedOnStatus(ActivationStatus status) {
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
          MaterialPageRoute(builder: (_) => const ActivationScreen()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _ctrl.value;
    return Scaffold(
      body: SizedBox.expand(
        child: Stack(
          children: [
            _buildBackground(),
            _buildGlow(),
            _buildLogo(p),
            _buildLoadingDots(p),
          ],
        ),
      ),
    );
  }
  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF0F4FF),
            Color(0xFFF8FAFC),
            Color(0xFFFFFFFF),
          ],
          stops: [0.0, 0.4, 1.0],
        ),
      ),
    );
  }

  Widget _buildGlow() {
    return Positioned.fill(
      child: Center(
        child: FadeTransition(
          opacity: _glowFade,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF4285F4).withValues(alpha: 0.06),
                  const Color(0xFF4285F4).withValues(alpha: 0.015),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(double p) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.width <= 0 || size.height <= 0) return const SizedBox.shrink();
        double tx, sx, sy;
        final scale = 0.35 + _logoScale.value * 0.65;

        if (p < _impactAt) {
          final t = p / _impactAt;
          final e = _easeOutQuart(t);
          final spd = 1.0 - e;
          tx = size.width * 1.6 * (1.0 - e);
          sx = (1.0 - spd * _dragX) * scale;
          sy = (1.0 + spd * _dragY) * scale;
        } else {
          final t = (p - _impactAt) / (1.0 - _impactAt);
          final d = math.exp(-_jellyDecay * t) * math.sin(_jellyFreq * t);
          tx = 0.0;
          sx = (1.0 + d * _jellyAmp) * scale;
          sy = (1.0 - d * _jellyAmp * 0.7) * scale;
        }

        return SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setTranslationRaw(tx, 0.0, 0.0)
                  ..setEntry(0, 0, sx)
                  ..setEntry(1, 1, sy),
                child: FadeTransition(
                  opacity: _logoFade,
                  child: Image.asset(
                    'assets/image/logo2.png',
                    width: 100,
                    height: 100,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FadeTransition(
                opacity: _textFade,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(_textFade),
                  child: Text(
                    'Cashier',
                    style: TextStyle(
                      color: const Color(0xFF1A1A2E).withValues(alpha: 0.88),
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadingDots(double p) {
    return Positioned(
      bottom: 48,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _textFade,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final delay = 0.65 + i * 0.06;
            final rp = ((p - delay) / (1.0 - delay)).clamp(0.0, 1.0);
            final ease = _easeInOutCubic(rp);
            final dotScale = 0.5 + ease * 0.5;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.scale(
                scale: dotScale,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4285F4)
                        .withValues(alpha: 0.25 + ease * 0.35),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  double _easeOutQuart(double t) => 1.0 - math.pow(1.0 - t, 4).toDouble();
  double _easeOutCubic(double t) => 1.0 - math.pow(1.0 - t, 3).toDouble();
  double _easeInOutCubic(double t) {
    return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
  }
}