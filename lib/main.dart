import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'app_status_service.dart';
import 'constants.dart';
import 'providers/pos_provider.dart';
import 'screens/main_page.dart';
import 'services/feedback_service.dart';

Future<void> bootApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FeedbackService.instance.init();
  runApp(const POSApp());
  AppStatusService.instance.init();
}

void main() async {
  await bootApp();
}

class POSApp extends StatelessWidget {
  const POSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppStatus>(
      valueListenable: AppStatusService.instance.statusNotifier,
      builder: (context, status, _) {
        if (status == AppStatus.blocked) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: AnnotatedRegion<SystemUiOverlayStyle>(
              value: const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
              ),
              child: Scaffold(
                backgroundColor: const Color(0xFF1A1A1A),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.report_problem,
                          size: 90,
                          color: Colors.amber,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          '⚠️ النظام قيد الصيانة المؤقتة',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'تم إيقاف تشغيل التطبيق مؤقتاً من قبل المطور لإجراء تحسينات وتحديثات على نظام الـ POS.',
                          style: TextStyle(fontSize: 15, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return ChangeNotifierProvider(
          create: (_) => POSProvider()
            ..loadDashboard()
            ..loadProducts()
            ..loadStats()
            ..loadParkedCarts()
            ..loadCurrencySymbol(),
          child: MaterialApp(
            title: kStoreName,
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
              child: const MainPage(),
            ),
          ),
        ),
      );
      },
    );
  }
}
