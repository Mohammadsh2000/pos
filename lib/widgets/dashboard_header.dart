import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/pos_provider.dart';
import '../screens/sale_tab.dart';
import 'settings_sheet.dart';

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, p, _) {
        return ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: EdgeInsetsDirectional.fromSTEB(
                16,
                MediaQuery.of(context).padding.top + 8,
                16,
                8,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
              ),
              child: Row(
                children: [
                  Text(
                    kStoreName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),

                  const Spacer(),
                  IconButton(
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.history),
                        if (p.parkedCartCount > 0)
                          Positioned(
                            top: -4,
                            right: -10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE63946),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              constraints: const BoxConstraints(minWidth: 16),
                              child: Text(
                                '${p.parkedCartCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    tooltip: 'الفواتير المعلقة',
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        useSafeArea: true,
                        builder: (ctx) => const ParkedCartsList(),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings),
                          onPressed: () {
                            Navigator.of(context).push(
                              PageRouteBuilder(
                                opaque: false,
                                barrierDismissible: true,
                                barrierColor: Colors.black54,
                                transitionDuration: const Duration(milliseconds: 250),
                                reverseTransitionDuration: const Duration(milliseconds: 200),
                                pageBuilder: (context, a, b) {
                                  final screenW = MediaQuery.of(context).size.width;
                                  final screenH = MediaQuery.of(context).size.height;
                                  return Stack(
                                    children: [
                                      GestureDetector(
                                        onTap: () => Navigator.pop(context),
                                        child: Container(color: Colors.black54),
                                      ),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Material(
                                          elevation: 16,
                                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                                          clipBehavior: Clip.antiAlias,
                                          child: SizedBox(
                                            width: screenW * 0.8,
                                            height: screenH,
                                            child: const SettingsSheet(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                                transitionsBuilder: (context, animation, _, child) {
                                  return SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(-1, 0),
                                      end: Offset.zero,
                                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                                    child: child,
                                  );
                                },
                              ),
                            );
                          },
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE63946),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
