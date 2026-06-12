import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/pos_provider.dart';
import '../utils/notifications.dart';

class PayDebtSheet extends StatefulWidget {
  const PayDebtSheet({super.key});

  @override
  State<PayDebtSheet> createState() => _PayDebtSheetState();
}

class _PayDebtSheetState extends State<PayDebtSheet> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  int? _selectedCustomerId;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _selectCustomer(String name, int id) {
    setState(() {
      _nameCtrl.text = name;
      _selectedCustomerId = id;
    });
    FocusScope.of(context).requestFocus(FocusNode());
    Future.delayed(const Duration(milliseconds: 100), () {
      FocusScope.of(context).requestFocus(FocusNode());
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      showTopNotification(context, 'اختر العميل أولاً من القائمة');
      return;
    }
    setState(() => _isSubmitting = true);
    final amount = double.parse(_amountCtrl.text.trim());
    final p = context.read<POSProvider>();
    final err = await p.recordDebtPayment(_selectedCustomerId!, amount);
    if (!mounted) return;
    if (err != null) {
      showTopNotification(context, err);
      setState(() => _isSubmitting = false);
    } else {
      Navigator.pop(context);
      showTopNotification(context, 'تم تسجيل الدفعة بنجاح');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 16),
      child: Form(
        key: _formKey,
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
            const SizedBox(height: 20),
            Text(
              'تسديد دين',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _CustomerSearchField(
              controller: _nameCtrl,
              onSelected: _selectCustomer,
              selectedId: _selectedCustomerId,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'المبلغ',
                hintText: 'أدخل المبلغ المسدد',
                prefixIcon: const Icon(Icons.monetization_on_outlined),
                suffixText: kCurrencySymbol,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLowest,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'أدخل المبلغ';
                final amt = double.tryParse(v.trim());
                if (amt == null || amt <= 0) return 'مبلغ غير صالح';
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_isSubmitting ? 'جارٍ التسجيل...' : 'تأكيد التسديد'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerSearchField extends StatefulWidget {
  final TextEditingController controller;
  final void Function(String name, int id) onSelected;
  final int? selectedId;

  const _CustomerSearchField({
    required this.controller,
    required this.onSelected,
    this.selectedId,
  });

  @override
  State<_CustomerSearchField> createState() => _CustomerSearchFieldState();
}

class _CustomerSearchFieldState extends State<_CustomerSearchField> {
  List<Map<String, dynamic>> _suggestions = [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    final p = context.read<POSProvider>();
    p.searchCustomers(text).then((_) {
      if (!mounted) return;
      final debtCustomers = p.debtCustomers;
      setState(() {
        _suggestions = p.customerSuggestions.map((c) {
          final debt = debtCustomers.cast<Map<String, dynamic>?>().firstWhere(
            (d) => d != null && d['id'] == c.id,
            orElse: () => null,
          );
          return {
            'id': c.id,
            'name': c.name,
            'remaining': debt != null
                ? (debt['total_debt'] as num).toDouble() - (debt['total_paid'] as num).toDouble()
                : 0.0,
          };
        }).toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: widget.controller,
          decoration: InputDecoration(
            labelText: 'اختر العميل',
            hintText: 'ابحث عن اسم العميل',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: widget.selectedId != null
                ? Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20)
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerLowest,
          ),
          validator: (_) => widget.selectedId == null ? 'اختر عميلاً من القائمة' : null,
        ),
        if (_suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              itemBuilder: (context, i) {
                final item = _suggestions[i];
                final remaining = (item['remaining'] as num).toDouble();
                return ListTile(
                  dense: true,
                  title: Text(item['name'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'المتبقي: ${remaining.toStringAsFixed(2)} $kCurrencySymbol',
                    style: TextStyle(
                      fontSize: 12,
                      color: remaining > 0 ? theme.colorScheme.error : theme.colorScheme.primary,
                    ),
                  ),
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      (item['name'] as String)[0].toUpperCase(),
                      style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ),
                  trailing: remaining > 0
                      ? Text(
                          '${remaining.toStringAsFixed(2)} $kCurrencySymbol',
                          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.error),
                        )
                      : const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  onTap: () {
                    widget.onSelected(item['name'] as String, item['id'] as int);
                    setState(() => _suggestions = []);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
