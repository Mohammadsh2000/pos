import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui;
import '../providers/pos_provider.dart';
import '../widgets/dashboard_header.dart';
import '../widgets/data_management_sheet.dart';
import 'sale_tab.dart';
import 'products_tab.dart';
import 'history_tab.dart';
import 'debt_tab.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final MobileScannerController _scannerCtrl = MobileScannerController(
    autoStart: false,
    cameraResolution: const Size(1280, 720),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBackupReminder());
  }

  Future<void> _checkBackupReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final lastBackupStr = prefs.getString('last_backup_date');
    if (lastBackupStr == null) return;
    final lastBackup = DateTime.tryParse(lastBackupStr);
    if (lastBackup == null) return;
    if (DateTime.now().difference(lastBackup).inDays >= 7) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تنبيه أمان'),
            content: const Text('لم تقم بعمل نسخة احتياطية منذ أسبوع. لحماية أرباحك وإحصائياتك من الضياع، يرجى إجراء التصدير الآن.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('تذكير لاحقاً'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const DataManagementSheet(),
                  );
                },
                child: const Text('تصدير الآن'),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _scannerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, p, _) {
        return Scaffold(
          body: Column(
            children: [
              const DashboardHeader(),
              Expanded(
                child: IndexedStack(
                  index: p.currentTab,
                  children: [
                    SaleTab(scannerCtrl: _scannerCtrl),
                    const ProductsTab(),
                    const HistoryTab(),
                    const DebtTab(),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: p.currentTab,
            onDestinationSelected: (i) {
              if (i != 0) {
                _scannerCtrl.stop();
                p.setCameraActive(false);
              }
              p.setTab(i);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.point_of_sale),
                label: 'بيع',
              ),
              NavigationDestination(
                icon: Icon(Icons.inventory_2),
                label: 'المخزون',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long),
                label: 'السجل',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet),
                label: 'الدين',
              ),
            ],
          ),
        );
      },
    );
  }
}
