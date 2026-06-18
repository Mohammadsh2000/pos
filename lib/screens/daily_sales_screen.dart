import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pos_provider.dart';
import '../constants.dart';

final DateFormat _dateFmt = DateFormat('dd/MM/yyyy', 'en');
final DateFormat _dayNameFmt = DateFormat('EEEE', 'ar');
final DateFormat _dayMonthFmt = DateFormat('dd/MM/yyyy', 'en');

enum _QuickFilter { none, lastWeek, lastMonth, custom }

class DailySalesScreen extends StatefulWidget {
  const DailySalesScreen({super.key});

  @override
  State<DailySalesScreen> createState() => _DailySalesScreenState();
}

class _DailySalesScreenState extends State<DailySalesScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  _QuickFilter _quickFilter = _QuickFilter.none;
  bool _showStats = true;

  void _applyQuickFilter(_QuickFilter f) {
    final now = DateTime.now();
    switch (f) {
      case _QuickFilter.lastWeek:
        setState(() {
          _quickFilter = f;
          _startDate = now.subtract(const Duration(days: 7));
          _endDate = null;
        });
      case _QuickFilter.lastMonth:
        setState(() {
          _quickFilter = f;
          _startDate = DateTime(now.year, now.month - 1, now.day);
          if (now.month == 1) _startDate = DateTime(now.year - 1, 12, now.day);
          _endDate = null;
        });
      case _QuickFilter.custom:
        _showFilterSheet();
      case _QuickFilter.none:
        setState(() {
          _quickFilter = f;
          _startDate = null;
          _endDate = null;
        });
    }
  }

  bool get _isFiltered => _startDate != null || _endDate != null;

  String _filterLabel() {
    if (_quickFilter == _QuickFilter.lastWeek) return 'آخر أسبوع';
    if (_quickFilter == _QuickFilter.lastMonth) return 'آخر شهر';
    if (_startDate != null && _endDate != null) {
      return '${_dateFmt.format(_startDate!)} - ${_dateFmt.format(_endDate!)}';
    }
    if (_startDate != null) return 'من ${_dateFmt.format(_startDate!)}';
    if (_endDate != null) return 'إلى ${_dateFmt.format(_endDate!)}';
    return '';
  }

  void _showFilterSheet() {
    DateTime? tempStart = _startDate;
    DateTime? tempEnd = _endDate;

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
                Text('نطاق مخصص', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
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
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setSheetState(() {
                            tempStart = null;
                            tempEnd = null;
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
                            _quickFilter = _QuickFilter.custom;
                          });
                          Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('تطبيق'),
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

  List<Map<String, dynamic>> _filterData(List<Map<String, dynamic>> data) {
    var result = data.toList();

    if (_startDate != null) {
      final start = _startDate!;
      result = result.where((r) {
        final day = r['day'] as String?;
        if (day == null) return false;
        final dt = DateTime.tryParse(day);
        if (dt == null) return false;
        return dt.isAfter(start.subtract(const Duration(days: 1)));
      }).toList();
    }

    if (_endDate != null) {
      final end = _endDate!;
      result = result.where((r) {
        final day = r['day'] as String?;
        if (day == null) return false;
        final dt = DateTime.tryParse(day);
        if (dt == null) return false;
        return dt.isBefore(end.add(const Duration(days: 1)));
      }).toList();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('المبيعات اليومية'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.surfaceTint,
        actions: [
          IconButton(
            onPressed: () => setState(() => _showStats = !_showStats),
            icon: Icon(
              _showStats
                  ? Icons.remove_red_eye_outlined
                  : Icons.visibility_off_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: _showStats ? 'إخفاء الإحصائيات' : 'إظهار الإحصائيات',
          ),
          if (_isFiltered)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: IconButton(
                  onPressed: () => _applyQuickFilter(_QuickFilter.none),
                  icon: Icon(Icons.close, size: 20, color: theme.colorScheme.onSurfaceVariant),
                  tooltip: 'إلغاء التصفية',
                ),
              ),
            ),
        ],
      ),
      body: Consumer<POSProvider>(
        builder: (context, p, _) {
          final allData = p.dailySales;
          final data = _filterData(allData);
          final hasData = data.isNotEmpty;
          final hasAnyData = allData.isNotEmpty;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _FilterBar(
                quickFilter: _quickFilter,
                isFiltered: _isFiltered,
                filterLabel: _filterLabel(),
                onApply: _applyQuickFilter,
                theme: theme,
              ),
              if (!hasAnyData)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 64),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.bar_chart, size: 72, color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text('لا توجد مبيعات', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                  ),
                ),
              if (hasAnyData && !hasData)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.search_off, size: 56, color: theme.colorScheme.outline.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text('لا توجد نتائج للتصفية', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.outline)),
                        const SizedBox(height: 4),
                        Text('حاول تغيير نطاق التاريخ', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                  ),
                ),
              if (hasData) ...[
                const SizedBox(height: 8),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: ClipRect(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _showStats ? 1.0 : 0.0,
                      child: _showStats
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: _buildSummaryCards(data, theme),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
                _buildSectionHeader('تفاصيل الأيام', '${data.length} يوم', theme),
                const SizedBox(height: 12),
                ...data.asMap().entries.map((e) => _buildDayCard(e.value, e.key, theme)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle, ThemeData theme) {
    return Row(
      children: [
        Container(
          width: 4, height: 20,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface)),
        const Spacer(),
        Text(subtitle, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildSummaryCards(List<Map<String, dynamic>> data, ThemeData theme) {
    final totalSales = data.fold<double>(0, (s, r) => s + (r['total'] as num).toDouble());
    final totalProfit = data.fold<double>(0, (s, r) => s + (r['profit'] as num).toDouble());
    final totalCount = data.fold<int>(0, (s, r) => s + (r['count'] as int));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.surfaceContainerLow, theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      child: Row(
        children: [
          _MiniStat(
            icon: Icons.account_balance_wallet_rounded,
            value: '${totalSales.toStringAsFixed(1)} $kCurrencySymbol',
            label: 'إجمالي المبيعات',
            color: theme.colorScheme.primary,
            theme: theme,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(width: 1, height: 52, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          _MiniStat(
            icon: Icons.savings_rounded,
            value: '${totalProfit.toStringAsFixed(1)} $kCurrencySymbol',
            label: 'صافي الربح',
            color: Colors.green.shade600,
            theme: theme,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(width: 1, height: 52, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          _MiniStat(
            icon: Icons.receipt_rounded,
            value: '$totalCount',
            label: 'عدد الفواتير',
            color: const Color(0xFF7C3AED),
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(Map<String, dynamic> row, int index, ThemeData theme) {
    final day = row['day'] as String? ?? '';
    final total = (row['total'] as num).toDouble();
    final profit = (row['profit'] as num).toDouble();
    final count = row['count'] as int;
    final date = DateTime.tryParse(day);
    final fullDate = date != null ? _dayMonthFmt.format(date) : day;
    final dayName = date != null ? _dayNameFmt.format(date) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: Center(
                  child: Text('${date?.day ?? ''}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(dayName,
                    style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 1),
                  Text(fullDate,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF7C3AED), const Color(0xFF4F46E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF7C3AED).withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 1)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt, size: 12, color: Colors.white.withValues(alpha: 0.9)),
                    const SizedBox(width: 4),
                    Text('$count',
                      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$total $kCurrencySymbol',
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900, color: Colors.orange.shade900)),
                    const SizedBox(height: 1),
                    Text('ربح ${profit.toStringAsFixed(2)} $kCurrencySymbol',
                      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: Colors.green.shade700)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final _QuickFilter quickFilter;
  final bool isFiltered;
  final String filterLabel;
  final ValueChanged<_QuickFilter> onApply;
  final ThemeData theme;

  const _FilterBar({
    required this.quickFilter,
    required this.isFiltered,
    required this.filterLabel,
    required this.onApply,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChipBtn(
                label: 'الكل',
                icon: Icons.grid_view_rounded,
                selected: !isFiltered,
                onTap: () => onApply(_QuickFilter.none),
                theme: theme,
              ),

              const SizedBox(width: 8),
              _FilterChipBtn(
                label: 'آخر أسبوع',
                icon: Icons.date_range_rounded,
                selected: quickFilter == _QuickFilter.lastWeek,
                onTap: () => onApply(_QuickFilter.lastWeek),
                theme: theme,
              ),
              const SizedBox(width: 8),
              _FilterChipBtn(
                label: 'آخر شهر',
                icon: Icons.calendar_month_rounded,
                selected: quickFilter == _QuickFilter.lastMonth,
                onTap: () => onApply(_QuickFilter.lastMonth),
                theme: theme,
              ),
              const SizedBox(width: 8),
              _FilterChipBtn(
                label: 'نطاق',
                icon: Icons.tune_rounded,
                selected: quickFilter == _QuickFilter.custom,
                onTap: () => onApply(_QuickFilter.custom),
                theme: theme,
              ),
            ],
          ),
        ),
        if (isFiltered && quickFilter != _QuickFilter.lastWeek && quickFilter != _QuickFilter.lastMonth) ...[
          const SizedBox(height: 6),
          Text('التصفية: $filterLabel',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

class _FilterChipBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _FilterChipBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    if (selected) {
      bg = theme.colorScheme.primary;
      fg = Colors.white;
      border = theme.colorScheme.primary;
    } else {
      bg = theme.colorScheme.surfaceContainerLowest;
      fg = theme.colorScheme.onSurfaceVariant;
      border = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
          boxShadow: selected
              ? [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
            Text(label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final ThemeData theme;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 6),
          Text(value,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface, height: 1.1),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(label,
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant, height: 1.1),
            textAlign: TextAlign.center,
          ),
        ],
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
