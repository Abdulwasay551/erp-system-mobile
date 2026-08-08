import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../theme/app_semantic_colors.dart';

const _statusTone = {
  'available': 'success',
  'sold': 'neutral',
  'returned': 'warning',
  'damaged': 'danger',
  'expired': 'danger',
  'quarantined': 'warning',
};

/// Search any IMEI/serial/barcode/batch number and see its full purchase (which bill)
/// and sale (which invoice) history - hits the same tracking/lookup/ endpoint the web
/// frontend's Item Lookup page uses.
class ItemLookupScreen extends StatefulWidget {
  const ItemLookupScreen({super.key});

  @override
  State<ItemLookupScreen> createState() => _ItemLookupScreenState();
}

class _ItemLookupScreenState extends State<ItemLookupScreen> {
  final _controller = TextEditingController();
  List<dynamic> _results = [];
  bool _searching = false;
  bool _searched = false;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _searched = true;
    });
    try {
      final data = await _api.request('/api/products/tracking/lookup/?q=${Uri.encodeComponent(q)}') as Map<String, dynamic>;
      if (mounted) setState(() => _results = (data['results'] as List<dynamic>?) ?? []);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Color _toneColor(BuildContext context, String status) {
    final colors = context.semanticColors;
    switch (_statusTone[status]) {
      case 'success':
        return colors.success;
      case 'warning':
        return colors.warning;
      case 'danger':
        return colors.danger;
      default:
        return colors.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Item Lookup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(labelText: 'Scan or type an IMEI/serial/barcode', border: OutlineInputBorder()),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _searching ? null : _search,
                child: _searching
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_searched && !_searching && _results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No matching item found.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ..._results.map((r) {
            final item = r as Map<String, dynamic>;
            final purchase = item['purchase'] as Map<String, dynamic>?;
            final sale = item['sale'] as Map<String, dynamic>?;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${item['product_name']} (${item['product_sku']})', style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(item['identifier']?.toString() ?? '', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _toneColor(context, item['status'] as String).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            item['status_display'] as String,
                            style: TextStyle(color: _toneColor(context, item['status'] as String), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Purchase', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              if (purchase != null) ...[
                                Text('Bill: ${purchase['bill_number'] ?? '-'}', style: const TextStyle(fontSize: 13)),
                                Text('Supplier: ${purchase['supplier_name'] ?? '-'}', style: const TextStyle(fontSize: 13)),
                                Text('Price: ${purchase['purchase_price'] != null ? 'Rs. ${purchase['purchase_price']}' : '-'}', style: const TextStyle(fontSize: 13)),
                                Text('Date: ${purchase['purchase_date'] ?? '-'}', style: const TextStyle(fontSize: 13)),
                              ] else
                                const Text('No purchase record.', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Sale', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              if (sale != null) ...[
                                Text('Invoice: ${sale['invoice_number'] ?? '-'}', style: const TextStyle(fontSize: 13)),
                                Text('Customer: ${sale['customer_name'] ?? '-'}', style: const TextStyle(fontSize: 13)),
                                Text('Price: ${sale['sold_price'] != null ? 'Rs. ${sale['sold_price']}' : '-'}', style: const TextStyle(fontSize: 13)),
                                Text('Date: ${sale['sold_date'] ?? '-'}', style: const TextStyle(fontSize: 13)),
                              ] else
                                const Text('Currently in stock.', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
