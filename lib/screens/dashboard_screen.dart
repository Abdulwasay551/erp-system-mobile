import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthService>().api;
    try {
      final data = await api.request('/api/analytics/dashboard/');
      if (mounted) setState(() => _stats = data as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load dashboard.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final stats = _stats;
    if (stats == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final cards = [
      ("Today's Sales", "Rs. ${stats['todays_sales_total']}"),
      ("Sales Count Today", "${stats['todays_sales_count']}"),
      ("Customer Outstanding", "Rs. ${stats['customer_outstanding_total']}"),
      ("Supplier Outstanding", "Rs. ${stats['supplier_outstanding_total']}"),
      ("Low Stock Items", "${stats['low_stock_count']}"),
      ("Available Tracked Units", "${stats['available_tracked_units']}"),
      ("Pending Vendor Receipts", "${stats['pending_vendor_receipts']}"),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
        ),
        itemCount: cards.length,
        itemBuilder: (context, i) {
          final (label, value) = cards[i];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
