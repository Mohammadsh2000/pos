import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_config.dart';
import 'constants.dart';
import 'providers/pos_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/activation_screen.dart';
import 'services/feedback_service.dart';
import 'services/block_service.dart';
import 'services/activation_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> bootApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPreferences.getInstance();
  await AppConfig.load();
  await Firebase.initializeApp(options: AppConfig.instance.firebaseOptions);
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity,
    appleProvider: AppleProvider.deviceCheck,
  );
  await FeedbackService.instance.init();
  runApp(const POSApp());
}

void main() async {
  await bootApp();
}

class POSApp extends StatefulWidget {
  const POSApp({super.key});

  @override
  State<POSApp> createState() => _POSAppState();
}

class _POSAppState extends State<POSApp> {
  @override
  void initState() {
    super.initState();
    BlockService.instance.start(
      onBlocked: () {
        final uid = BlockService.instance.currentUid;
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MaintenanceScreen(
              uid: uid,
              onUnblocked: () {
                navigatorKey.currentState?.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              },
            ),
          ),
          (_) => false,
        );
      },
      onUnblocked: () {},
    );
    ActivationService.instance.startListening(
      onExpired: () {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (_) => const ActivationScreen(expired: true)),
          (_) => false,
        );
      },
      onActive: () {},
    );
  }

  @override
  void dispose() {
    BlockService.instance.stop();
    ActivationService.instance.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => POSProvider()
        ..loadDashboard()
        ..loadProducts()
        ..loadStats()
        ..loadParkedCarts()
        ..loadCurrencySymbol()
        ..loadStoreInfo(),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Cashier',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ar'),
          Locale('en'),
        ],
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF7C3AED),
            primary: const Color(0xFF7C3AED),
            secondary: const Color(0xFF8B5CF6),
            surface: const Color(0xFFF8FAFC),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF8FAFC),
          navigationBarTheme: NavigationBarThemeData(
            indicatorColor: const Color(0xFF7C3AED).withValues(alpha: 0.15),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: Color(0xFF7C3AED));
              }
              return IconThemeData(color: Colors.grey[400]!);
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7C3AED),
                );
              }
              return const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF9CA3AF),
              );
            }),
          ),
          textTheme: GoogleFonts.cairoTextTheme(
            ThemeData.light().textTheme,
          ),
        ),
        home: Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: Colors.white,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: const SplashScreen(),
        ),
      ),
      ),
    );
  }
}
