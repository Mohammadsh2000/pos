import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    torchEnabled: false,
    cameraResolution: const Size(1280, 720),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBackupReminder());
    _scannerCtrl.startArguments.addListener(_onScannerStarted);
  }

  void _onScannerStarted() {
    if (_scannerCtrl.startArguments.value != null) {
      _scannerCtrl.hasTorchState.value = true;
      _scannerCtrl.startArguments.removeListener(_onScannerStarted);
    }
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
        builder: (ctx) => AlertDialog(
          title: const Text('تنبيه أمان'),
          content: const Text(
            'لم تقم بعمل نسخة احتياطية منذ أسبوع. لحماية أرباحك وإحصائياتك من الضياع، يرجى إجراء التصدير الآن.',
          ),
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
      );
    }
  }

  @override
  void dispose() {
    _scannerCtrl.startArguments.removeListener(_onScannerStarted);
    _scannerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, p, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
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
          bottomNavigationBar: _BottomNav(selectedIndex: p.currentTab, onTap: (i) {
            if (i != 0) {
              _scannerCtrl.stop();
              p.setCameraActive(false);
            }
            p.setTab(i);
          }),
        );
      },
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.selectedIndex, required this.onTap});

  static const _tabs = [
    (icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale, label: 'بيع'),
    (icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, label: 'المخزون'),
    (icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: 'السجل'),
    (icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet, label: 'الدين'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: const Color(0xFFFFFFFF),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final tab = _tabs[i];
              final isSelected = selectedIndex == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? theme.colorScheme.primaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected ? tab.selectedIcon : tab.icon,
                          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                          size: 22,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
