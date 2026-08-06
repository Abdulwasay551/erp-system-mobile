import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/pdf_helper.dart';

class _CartLine {
  final String key;
  final int productId;
  final int? trackingId;
  final String name;
  final String identifier;
  final double unitPrice;
  double quantity;
  final double maxQty;

  _CartLine({
    required this.key,
    required this.productId,
    required this.trackingId,
    required this.name,
    required this.identifier,
    required this.unitPrice,
    required this.quantity,
    required this.maxQty,
  });
}

const _paymentMethods = [
  ('cash', 'Cash'),
  ('bank_transfer', 'Bank Transfer'),
  ('cheque', 'Cheque'),
  ('credit_card', 'Credit Card'),
  ('online', 'Online Payment'),
];

class POSScreen extends StatefulWidget {
  const POSScreen({super.key});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  final _searchController = TextEditingController();
  final _customerSearchController = TextEditingController();
  List<dynamic> _results = [];
  List<dynamic> _customerResults = [];
  Map<String, dynamic>? _selectedCustomer;
  final List<_CartLine> _cart = [];
  bool _searching = false;
  bool _checkingOut = false;
  String _paymentMethod = 'cash';
  Map<String, dynamic>? _lastInvoice;
  bool _openingPdf = false;

  Future<void> _searchCustomers(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _customerResults = []);
      return;
    }
    try {
      final data = await _api.request('/api/crm/customers/?search=${Uri.encodeComponent(q)}');
      if (mounted) setState(() => _customerResults = data as List<dynamic>);
    } catch (_) {}
  }

  ApiClient get _api => context.read<AuthService>().api;

  double get _cartTotal => _cart.fold(0, (sum, l) => sum + l.unitPrice * l.quantity);

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final data = await _api.request('/api/sales/pos/search/?q=${Uri.encodeComponent(q)}');
      setState(() => _results = data as List<dynamic>);
      if (_results.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No matching products found.')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _addToCart(Map<String, dynamic> item) {
    final trackingId = item['tracking_id'] as int?;
    final key = trackingId != null ? 't-$trackingId' : 'p-${item['product_id']}';
    if (_cart.any((l) => l.key == key)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Already in cart.')));
      return;
    }
    final variant = item['variant'] as String?;
    setState(() {
      _cart.add(_CartLine(
        key: key,
        productId: item['product_id'] as int,
        trackingId: trackingId,
        name: variant != null ? '${item['name']} ($variant)' : item['name'] as String,
        identifier: item['identifier']?.toString() ?? '',
        unitPrice: double.parse(item['unit_price'].toString()),
        quantity: 1,
        maxQty: trackingId != null ? 1 : double.parse(item['available_qty'].toString()),
      ));
      _results = [];
      _searchController.clear();
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cart is empty.')));
      return;
    }
    setState(() => _checkingOut = true);
    try {
      final payload = {
        if (_selectedCustomer != null) 'customer_id': _selectedCustomer!['id'],
        'items': _cart
            .map((l) => {
                  'product_id': l.productId,
                  if (l.trackingId != null) 'tracking_id': l.trackingId,
                  if (l.trackingId == null) 'quantity': l.quantity,
                  'unit_price': l.unitPrice,
                })
            .toList(),
        'payment': {'method': _paymentMethod, 'amount': _cartTotal},
      };
      final result = await _api.request('/api/sales/pos/checkout/', method: 'POST', body: payload);
      setState(() {
        _lastInvoice = result as Map<String, dynamic>;
        _cart.clear();
        _selectedCustomer = null;
        _customerSearchController.clear();
        _customerResults = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Invoice ${result['invoice_number']} created.')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<void> _openInvoicePdf() async {
    final invoiceId = _lastInvoice?['invoice_id'];
    if (invoiceId == null) return;
    setState(() => _openingPdf = true);
    try {
      await downloadAndOpenPdf(_api, '/api/sales/invoices/$invoiceId/pdf/', 'invoice-$invoiceId.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _openingPdf = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customerSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Scan IMEI/barcode or type a name',
                  border: OutlineInputBorder(),
                ),
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
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: _results.map((r) {
                final item = r as Map<String, dynamic>;
                return ListTile(
                  title: Text(item['name'] as String),
                  subtitle: Text('${item['identifier']} · Rs. ${item['unit_price']} · Qty ${item['available_qty']}'),
                  trailing: FilledButton(onPressed: () => _addToCart(item), child: const Text('Add')),
                );
              }).toList(),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('Cart', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_cart.isEmpty)
          const Text('No items yet - search above to add.', style: TextStyle(color: Colors.grey))
        else
          Card(
            child: Column(
              children: _cart.map((l) {
                return ListTile(
                  title: Text(l.name),
                  subtitle: Text('Rs. ${l.unitPrice.toStringAsFixed(2)} × ${l.quantity.toStringAsFixed(0)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Rs. ${(l.unitPrice * l.quantity).toStringAsFixed(2)}'),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _cart.remove(l)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 20),
        Text('Customer (optional)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_selectedCustomer != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(_selectedCustomer!['name'] as String),
              trailing: TextButton(
                onPressed: () => setState(() => _selectedCustomer = null),
                child: const Text('Change'),
              ),
            ),
          )
        else ...[
          TextField(
            controller: _customerSearchController,
            decoration: const InputDecoration(labelText: 'Search customer (defaults to walk-in)', border: OutlineInputBorder()),
            onChanged: _searchCustomers,
          ),
          ..._customerResults.map((c) {
            final customer = c as Map<String, dynamic>;
            return ListTile(
              dense: true,
              title: Text(customer['name'] as String),
              subtitle: Text(customer['phone']?.toString() ?? ''),
              onTap: () => setState(() {
                _selectedCustomer = customer;
                _customerResults = [];
                _customerSearchController.clear();
              }),
            );
          }),
        ],
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Rs. ${_cartTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  decoration: const InputDecoration(labelText: 'Payment method', border: OutlineInputBorder()),
                  items: _paymentMethods
                      .map((m) => DropdownMenuItem(value: m.$1, child: Text(m.$2)))
                      .toList(),
                  onChanged: (v) => setState(() => _paymentMethod = v ?? 'cash'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _checkingOut ? null : _checkout,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _checkingOut
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Complete Sale'),
                ),
              ],
            ),
          ),
        ),
        if (_lastInvoice != null) ...[
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Last Invoice', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text('Invoice: ${_lastInvoice!['invoice_number']}'),
                  Text('Total: Rs. ${_lastInvoice!['total']}'),
                  Text('Outstanding: Rs. ${_lastInvoice!['outstanding_amount']}'),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _openingPdf ? null : _openInvoicePdf,
                    icon: _openingPdf
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.picture_as_pdf),
                    label: Text(_openingPdf ? 'Opening...' : 'Open PDF'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
