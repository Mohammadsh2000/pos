import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../providers/pos_provider.dart';
import 'invoice_preview_screen.dart';
import '../widgets/sale_detail_sheet.dart';
import '../utils/notifications.dart';

final DateFormat _dateFmt = DateFormat('dd/MM/yyyy', 'en');
final DateFormat _timeFmt = DateFormat('HH:mm:ss', 'en');

enum _SortBy { newest, oldest, highest, lowest }

const _sortLabels = {
  _SortBy.newest: 'الأحدث',
  _SortBy.oldest: 'الأقدم',
  _SortBy.highest: 'الأعلى مبلغاً',
  _SortBy.lowest: 'الأقل مبلغاً',
};

List<Color> _badgeGradient() {
  return const [Color(0xFF7C3AED), Color(0xFF4F46E5)];
}

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  _SortBy _sortBy = _SortBy.newest;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<POSProvider>().loadSales();
    });
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> sales) {
    var result = sales.toList();

    if (_searchQuery.isNotEmpty) {
      result = result.where((s) {
        final name = (s['customer_name'] as String? ?? '').toLowerCase();
        return name.contains(_searchQuery);
      }).toList();
    }

    if (_startDate != null) {
      final start = _startDate!;
      result = result.where((s) {
        final dt = DateTime.parse(s['created_at'] as String);
        return dt.isAfter(start.subtract(const Duration(days: 1)));
      }).toList();
    }

    if (_endDate != null) {
      final end = _endDate!;
      result = result.where((s) {
        final dt = DateTime.parse(s['created_at'] as String);
        return dt.isBefore(end.add(const Duration(days: 1)));
      }).toList();
    }

    result.sort((a, b) {
      switch (_sortBy) {
        case _SortBy.newest:
          return (b['created_at'] as String).compareTo(a['created_at'] as String);
        case _SortBy.oldest:
          return (a['created_at'] as String).compareTo(b['created_at'] as String);
        case _SortBy.highest:
          return (b['total'] as num).compareTo(a['total'] as num);
        case _SortBy.lowest:
          return (a['total'] as num).compareTo(b['total'] as num);
      }
    });

    return result;
  }

  int _activeFilterCount() {
    int n = 0;
    if (_startDate != null) n++;
    if (_endDate != null) n++;
    if (_sortBy != _SortBy.newest) n++;
    return n;
  }

  void _clearFilters() {
    setState(() {
      _searchCtrl.clear();
      _searchQuery = '';
      _startDate = null;
      _endDate = null;
      _sortBy = _SortBy.newest;
    });
  }

  void _showFilterSheet() {
    DateTime? tempStart = _startDate;
    DateTime? tempEnd = _endDate;
    _SortBy tempSort = _sortBy;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('تصفية السجل', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Text('نطاق التاريخ', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _DatePickTile(
                        label: 'من تاريخ',
                        value: tempStart,
                        onPick: (d) => setSheetState(() => tempStart = d),
                        onClear: () => setSheetState(() => tempStart = null),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DatePickTile(
                        label: 'إلى تاريخ',
                        value: tempEnd,
                        onPick: (d) => setSheetState(() => tempEnd = d),
                        onClear: () => setSheetState(() => tempEnd = null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('الترتيب', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _SortBy.values.map((s) {
                    final selected = tempSort == s;
                    return ChoiceChip(
                      label: Text(_sortLabels[s]!),
                      selected: selected,
                      onSelected: (_) => setSheetState(() => tempSort = s),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setSheetState(() {
                            tempStart = null;
                            tempEnd = null;
                            tempSort = _SortBy.newest;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('إعادة تعيين'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _startDate = tempStart;
                            _endDate = tempEnd;
                            _sortBy = tempSort;
                          });
                          Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('تطبيق التصفية'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showInvoicePreview(Map<String, dynamic> sale) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoicePreviewScreen(sale: sale),
      ),
    );
  }

  void _showSaleDetail(Map<String, dynamic> sale) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SaleDetailSheet(
        sale: sale,
        onPrint: () {
          Navigator.pop(ctx);
          _showInvoicePreview(sale);
        },
      ),
    );
  }

  void _toggleArchived() {
    setState(() => _showArchived = !_showArchived);
    if (_showArchived) {
      context.read<POSProvider>().loadArchivedSales();
    }
  }

  Future<void> _archiveSingleSale(Map<String, dynamic> sale) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('أرشفة الفاتورة'),
          content: Text('أرشفة الفاتورة #${sale['id']} بمبلغ ${sale['total']}؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('أرشفة'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final p = context.read<POSProvider>();
    final err = await p.archiveSingleSale(sale['id'] as int);
    if (!mounted) return;
    if (err != null) {
      showTopNotification(context, err);
    }
  }

  Future<void> _unarchiveSingleSale(Map<String, dynamic> sale) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إلغاء أرشفة الفاتورة'),
          content: Text('استعادة الفاتورة #${sale['id']} إلى السجل الحالي؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استعادة'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final p = context.read<POSProvider>();
    final err = await p.unarchiveSingleSale(sale['id'] as int);
    if (!mounted) return;
    if (err != null) {
      showTopNotification(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<POSProvider>(
      builder: (context, p, _) {
        final activeSales = _showArchived ? p.archivedSalesList : p.sales;
        final sales = _filtered(activeSales);
        final totalSales = activeSales.length;
        return Column(
          children: [
            _FilterBar(
              searchCtrl: _searchCtrl,
              searchQuery: _searchQuery,
              filterCount: _activeFilterCount(),
              onOpenFilter: _showFilterSheet,
              onClearAll: _clearFilters,
              resultCount: sales.length,
              totalCount: totalSales,
              theme: theme,
              showArchived: _showArchived,
              onToggleArchived: _toggleArchived,
            ),
            Expanded(
              child: sales.isEmpty
                  ? _buildEmpty(theme, activeSales.isEmpty, _showArchived)
                  : RefreshIndicator(
                      onRefresh: _showArchived
                          ? () => p.loadArchivedSales()
                          : () => p.loadSales(),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        itemCount: sales.length,
                        itemBuilder: (context, i) => _SaleCard(
                          sale: sales[i],
                          theme: theme,
                          onTap: () => _showSaleDetail(sales[i]),
                          onPrint: () => _showInvoicePreview(sales[i]),
                          onArchive: _showArchived ? null : () => _archiveSingleSale(sales[i]),
                          onUnarchive: _showArchived ? () => _unarchiveSingleSale(sales[i]) : null,
                        ),
                      ),
                  ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmpty(ThemeData theme, bool noData, bool isArchived) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            noData
                ? (isArchived ? Icons.archive_outlined : Icons.receipt_long_outlined)
                : Icons.search_off,
            size: 64,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 8),
          Text(
            noData
                ? (isArchived ? 'لا توجد فواتير في الأرشيف' : 'لا توجد فواتير سابقة')
                : 'لا توجد نتائج للتصفية',
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline),
          ),
          if (!noData) ...[
            const SizedBox(height: 4),
            Text(
              'حاول تغيير معايير التصفية',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String searchQuery;
  final int filterCount;
  final VoidCallback onOpenFilter;
  final VoidCallback onClearAll;
  final int resultCount;
  final int totalCount;
  final ThemeData theme;
  final bool showArchived;
  final VoidCallback onToggleArchived;

  const _FilterBar({
    required this.searchCtrl,
    required this.searchQuery,
    required this.filterCount,
    required this.onOpenFilter,
    required this.onClearAll,
    required this.resultCount,
    required this.totalCount,
    required this.theme,
    required this.showArchived,
    required this.onToggleArchived,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'بحث باسم العميل...',
                      hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                      prefixIcon: Icon(Icons.search, size: 20, color: theme.colorScheme.onSurfaceVariant),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => searchCtrl.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 42,
                child: IconButton(
                  onPressed: onToggleArchived,
                  style: IconButton.styleFrom(
                    backgroundColor: showArchived
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerLowest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: Icon(
                    showArchived ? Icons.history : Icons.archive_outlined,
                    color: showArchived
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  tooltip: showArchived ? 'السجل الحالي' : 'الأرشيف',
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 42,
                child: Badge(
                  isLabelVisible: filterCount > 0,
                  label: Text('$filterCount'),
                  child: IconButton(
                    onPressed: onOpenFilter,
                    style: IconButton.styleFrom(
                      backgroundColor: filterCount > 0
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerLowest,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: Icon(
                      Icons.tune,
                      color: filterCount > 0
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Text(
                  '${showArchived ? 'الأرشيف' : 'السجل'}: $totalCount فاتورة',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (resultCount != totalCount)
                  Text(
                    ' • عرض $resultCount',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                  ),
                const Spacer(),
                if (filterCount > 0 || searchQuery.isNotEmpty)
                  TextButton.icon(
                    onPressed: onClearAll,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.close, size: 14),
                    label: const Text('مسح الكل', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  final Map<String, dynamic> sale;
  final ThemeData theme;
  final VoidCallback onTap;
  final VoidCallback onPrint;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;

  const _SaleCard({
    required this.sale,
    required this.theme,
    required this.onTap,
    required this.onPrint,
    this.onArchive,
    this.onUnarchive,
  });

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.parse(sale['created_at'] as String);
    final hasCustomer = sale['customer_name'] != null && (sale['customer_name'] as String).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _badgeGradient(),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '#${sale['id']}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white, height: 1.3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2, size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(
                        '${sale['items_count']}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 28, height: 28,
                    child: IconButton(
                      onPressed: onPrint,
                      icon: Icon(Icons.print_outlined, size: 15, color: theme.colorScheme.onSurfaceVariant),
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (onArchive != null) SizedBox(width: 5),
                  if (onArchive != null)
                    SizedBox(
                      width: 28, height: 28,
                      child: IconButton(
                        onPressed: onArchive,
                        icon: Icon(Icons.archive_outlined, size: 15, color: Colors.orange.shade400),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.orange.shade50,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  if (onUnarchive != null) SizedBox(width: 5),
                  if (onUnarchive != null)
                    SizedBox(
                      width: 28, height: 28,
                      child: IconButton(
                        onPressed: onUnarchive,
                        icon: Icon(Icons.unarchive_outlined, size: 15, color: Colors.blue.shade400),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.blue.shade50,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  SizedBox(width: 5,),
                  SizedBox(
                    width: 28, height: 28,
                    child: IconButton(
                      onPressed: onTap,
                      icon: Icon(Icons.chevron_left, size: 17, color: theme.colorScheme.onSurfaceVariant),
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${sale['total']} $kCurrencySymbol',
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: theme.colorScheme.onSurface,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  children: [
                                    Icon(Icons.calendar_today, size: 12, color: theme.colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(_dateFmt.format(dt), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Container(width: 3, height: 3, decoration: BoxDecoration(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4), shape: BoxShape.circle)),
                                    ),
                                    Icon(Icons.access_time, size: 12, color: theme.colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(_timeFmt.format(dt), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hasCustomer)
                          Flexible(
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                        Icon(Icons.person, size: 15, color: theme.colorScheme.onPrimaryContainer),
                                        const SizedBox(width: 5),
                                        Text(
                                          sale['customer_name'] as String,
                                          style: theme.textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: theme.colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ),
                            ),
                          ),
                        ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatePickTile extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  final VoidCallback onClear;

  const _DatePickTile({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
          locale: const Locale('en'),
        );
        if (picked != null) onPick(picked);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value != null ? _dateFmt.format(value!) : label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: value != null ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 16, color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
