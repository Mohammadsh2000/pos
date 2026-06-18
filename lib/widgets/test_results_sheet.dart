import 'package:flutter/material.dart';
import '../services/test_module.dart';
import '../utils/notifications.dart';

class TestResultsSheet extends StatefulWidget {
  final TestModule module;
  const TestResultsSheet({super.key, required this.module});

  @override
  State<TestResultsSheet> createState() => _TestResultsSheetState();
}

class _TestResultsSheetState extends State<TestResultsSheet> {
  late TestModule _module;
  List<TestScenario> _results = [];
  bool _isLoaded = false;
  bool _isCleaning = false;

  @override
  void initState() {
    super.initState();
    _module = widget.module;
    _runTests();
  }

  Future<void> _runTests() async {
    try {
      final r = await _module.runAllTests();
      if (!mounted) return;
      setState(() {
        _results = r;
        _isLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = [
          TestScenario(
            name: 'فشل تشغيل الاختبارات',
            passed: false,
            expected: 'بدون أخطاء',
            actual: 'خطأ: $e',
          ),
        ];
        _isLoaded = true;
      });
    }
  }

  Future<void> _cleanup() async {
    setState(() => _isCleaning = true);
    try {
      await _module.cleanupTestData();
    } catch (e) {
      if (!mounted) return;
      showTopNotification(context, 'فشل الحذف: $e');
      setState(() => _isCleaning = false);
      return;
    }
    if (!mounted) return;
    setState(() => _isCleaning = false);
    if (mounted) {
      showSuccessNotification(context, 'تم حذف بيانات الاختبار');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('نتائج اختبار النظام'),
          actions: [
            if (_isLoaded)
              TextButton.icon(
                onPressed: _isCleaning ? null : _cleanup,
                icon: _isCleaning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline, size: 20),
                label: Text(_isCleaning ? 'جاري الحذف...' : 'حذف بيانات الاختبار'),
              ),
          ],
        ),
        body: _isLoaded ? _buildResults(theme) : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildResults(ThemeData theme) {
    final passed = _results.where((r) => r.passed).length;
    final total = _results.length;
    final allPassed = passed == total;

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: allPassed
                  ? [const Color(0xFF059669), const Color(0xFF10B981)]
                  : [const Color(0xFFDC2626), const Color(0xFFEF4444)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(
                allPassed ? Icons.check_circle : Icons.cancel,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 8),
              Text(
                allPassed ? 'جميع الاختبارات ناجحة' : 'بعض الاختبارات فشلت',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '$passed من $total نجح',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _results.length,
            itemBuilder: (_, i) {
              final r = _results[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            r.passed ? Icons.check_circle : Icons.error,
                            color: r.passed
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      _row('المتوقع', r.expected, const Color(0xFF2563EB)),
                      const SizedBox(height: 4),
                      _row('الفعلي', r.actual,
                          r.passed ? const Color(0xFF059669) : const Color(0xFFDC2626)),
                      if (r.details != null) ...[
                        const SizedBox(height: 4),
                        _row('تفاصيل', r.details!, Colors.orange.shade800),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
