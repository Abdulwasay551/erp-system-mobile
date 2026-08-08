import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/pdf_helper.dart';
import '../widgets/gradient_fab.dart';
import '../widgets/confirm_delete_dialog.dart';

class ReceivingScreen extends StatefulWidget {
  const ReceivingScreen({super.key});

  @override
  State<ReceivingScreen> createState() => _ReceivingScreenState();
}

class _ReceivingScreenState extends State<ReceivingScreen> {
  List<dynamic> _pending = [];
  bool _loading = true;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.request('/api/purchase/bills/pending-receipt/');
      if (mounted) setState(() => _pending = data as List<dynamic>);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNewInvoice() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const _NewVendorInvoiceScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _openReceive(Map<String, dynamic> bill) async {
    final received = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => _ReceiveBillScreen(bill: bill)),
    );
    if (received == true) _load();
  }

  Future<void> _deleteBill(Map<String, dynamic> bill) async {
    final confirmed = await confirmDelete(context, itemLabel: bill['bill_number'] as String?);
    if (!confirmed) return;
    try {
      await _api.request('/api/purchase/bills/${bill['id']}/', method: 'DELETE');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vendor invoice deleted.')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthService>().isAdmin;
    return Scaffold(
      floatingActionButton: GradientFab(
        onPressed: _openNewInvoice,
        label: 'New Invoice',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pending.isEmpty
              ? const Center(child: Text('No pending vendor invoices.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _pending.length,
                    itemBuilder: (context, i) {
                      final bill = _pending[i] as Map<String, dynamic>;
                      return Card(
                        child: ListTile(
                          title: Text('${bill['bill_number']} · ${bill['supplier_name']}'),
                          subtitle: Text('Rs. ${bill['total_amount']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.print_outlined),
                                tooltip: 'Print',
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  try {
                                    await downloadAndOpenPdf(
                                      _api,
                                      '/api/purchase/bills/${bill['id']}/pdf/',
                                      '${bill['bill_number']}-receiving.pdf',
                                    );
                                  } catch (e) {
                                    if (mounted) messenger.showSnackBar(SnackBar(content: Text('$e')));
                                  }
                                },
                              ),
                              if (isAdmin) DeleteIconButton(onPressed: () => _deleteBill(bill)),
                              const SizedBox(width: 4),
                              FilledButton(onPressed: () => _openReceive(bill), child: const Text('Receive')),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _NewVendorInvoiceScreen extends StatefulWidget {
  const _NewVendorInvoiceScreen();

  @override
  State<_NewVendorInvoiceScreen> createState() => _NewVendorInvoiceScreenState();
}

class _NewVendorInvoiceScreenState extends State<_NewVendorInvoiceScreen> {
  final _supplierSearchController = TextEditingController();
  final _productSearchController = TextEditingController();
  List<dynamic> _supplierResults = [];
  List<dynamic> _productResults = [];
  Map<String, dynamic>? _selectedSupplier;
  final List<Map<String, dynamic>> _lines = [];
  bool _creating = false;

  ApiClient get _api => context.read<AuthService>().api;

  Future<void> _searchSuppliers(String q) async {
    if (q.trim().isEmpty) return;
    try {
      final data = await _api.request('/api/purchase/suppliers/?search=${Uri.encodeComponent(q)}') as Map<String, dynamic>;
      setState(() => _supplierResults = data['results'] as List<dynamic>);
    } catch (_) {}
  }

  Future<void> _searchProducts(String q) async {
    if (q.trim().isEmpty) return;
    try {
      final data = await _api.request('/api/products/products/?search=${Uri.encodeComponent(q)}');
      setState(() => _productResults = data is List ? data : (data['results'] as List<dynamic>));
    } catch (_) {}
  }

  void _addLine(Map<String, dynamic> product) {
    if (_lines.any((l) => l['product_id'] == product['id'])) return;
    setState(() {
      _lines.add({
        'product_id': product['id'],
        'name': product['name'],
        'tracking_method': product['tracking_method'],
        'unit_price': TextEditingController(),
        'expected_quantity': TextEditingController(text: product['tracking_method'] != 'none' ? '1' : ''),
      });
      _productResults = [];
      _productSearchController.clear();
    });
  }

  Future<void> _createInvoice() async {
    if (_selectedSupplier == null || _lines.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a supplier and add at least one product.')));
      return;
    }
    setState(() => _creating = true);
    try {
      await _api.request('/api/purchase/vendor-invoice/', method: 'POST', body: {
        'supplier_id': _selectedSupplier!['id'],
        'items': _lines
            .map((l) => {
                  'product_id': l['product_id'],
                  'unit_price': (l['unit_price'] as TextEditingController).text,
                  'expected_quantity': (l['expected_quantity'] as TextEditingController).text,
                })
            .toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Vendor invoice recorded - now pending receipt.')));
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Vendor Invoice')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_selectedSupplier == null) ...[
            TextField(
              controller: _supplierSearchController,
              decoration: const InputDecoration(labelText: 'Search vendor by name', border: OutlineInputBorder()),
              onChanged: _searchSuppliers,
            ),
            ..._supplierResults.map((s) {
              final supplier = s as Map<String, dynamic>;
              return ListTile(
                title: Text(supplier['name'] as String),
                subtitle: Text(supplier['city']?.toString() ?? ''),
                onTap: () => setState(() {
                  _selectedSupplier = supplier;
                  _supplierResults = [];
                }),
              );
            }),
          ] else
            Card(
              child: ListTile(
                title: Text(_selectedSupplier!['name'] as String),
                trailing: TextButton(
                  onPressed: () => setState(() => _selectedSupplier = null),
                  child: const Text('Change'),
                ),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _productSearchController,
            decoration: const InputDecoration(labelText: 'Search product to add', border: OutlineInputBorder()),
            onChanged: _searchProducts,
          ),
          ..._productResults.map((p) {
            final product = p as Map<String, dynamic>;
            return ListTile(
              title: Text(product['name'] as String),
              subtitle: Text(product['sku']?.toString() ?? ''),
              trailing: FilledButton(onPressed: () => _addLine(product), child: const Text('Add')),
            );
          }),
          const SizedBox(height: 16),
          ..._lines.map((l) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: l['unit_price'] as TextEditingController,
                              decoration: const InputDecoration(labelText: 'Unit price'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: l['expected_quantity'] as TextEditingController,
                              decoration: const InputDecoration(labelText: 'Expected qty'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() => _lines.remove(l)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _creating ? null : _createInvoice,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _creating ? const CircularProgressIndicator() : const Text('Record Vendor Invoice'),
          ),
        ],
      ),
    );
  }
}

class _ReceiveBillScreen extends StatefulWidget {
  final Map<String, dynamic> bill;
  const _ReceiveBillScreen({required this.bill});

  @override
  State<_ReceiveBillScreen> createState() => _ReceiveBillScreenState();
}

class _ReceiveBillScreenState extends State<_ReceiveBillScreen> {
  late final Map<int, TextEditingController> _codeControllers;
  late final Map<int, TextEditingController> _qtyControllers;
  int? _warehouseId;
  bool _submitting = false;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    final items = (widget.bill['items'] as List).cast<Map<String, dynamic>>();
    _codeControllers = {for (final it in items) it['id'] as int: TextEditingController()};
    _qtyControllers = {for (final it in items) it['id'] as int: TextEditingController()};
    _loadWarehouse();
  }

  Future<void> _loadWarehouse() async {
    try {
      final data = await _api.request('/api/inventory/warehouses/') as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      if (results.isNotEmpty && mounted) setState(() => _warehouseId = results.first['id'] as int);
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (_warehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No warehouse found.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final items = (widget.bill['items'] as List).cast<Map<String, dynamic>>();
      final payload = items.map((item) {
        final id = item['id'] as int;
        if (item['tracking_type'] == 'none') {
          return {'bill_item_id': id, 'quantity': _qtyControllers[id]!.text.isEmpty ? '0' : _qtyControllers[id]!.text};
        }
        final codes = _codeControllers[id]!
            .text
            .split('\n')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList();
        return {'bill_item_id': id, 'codes': codes};
      }).toList();

      await _api.request('/api/purchase/bills/${widget.bill['id']}/receive-items/',
          method: 'POST', body: {'warehouse_id': _warehouseId, 'items': payload});
      await _api.request('/api/purchase/bills/${widget.bill['id']}/confirm-received/', method: 'POST', body: {});

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${widget.bill['bill_number']} marked received.')));
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (widget.bill['items'] as List).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.bill['bill_number'] as String)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...items.map((item) {
            final id = item['id'] as int;
            final trackingType = item['tracking_type'] as String;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item['product_name']} (expected ${item['quantity']})',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (trackingType == 'none')
                      TextField(
                        controller: _qtyControllers[id],
                        decoration: const InputDecoration(labelText: 'Quantity received'),
                        keyboardType: TextInputType.number,
                      )
                    else
                      TextField(
                        controller: _codeControllers[id],
                        maxLines: 3,
                        decoration: InputDecoration(labelText: 'Scan/paste $trackingType codes, one per line'),
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _submitting ? const CircularProgressIndicator() : const Text('Receive & Mark Complete'),
          ),
        ],
      ),
    );
  }
}
