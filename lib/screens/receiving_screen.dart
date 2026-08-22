import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/pdf_helper.dart';
import '../widgets/gradient_fab.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/discount_editor.dart';
import '../services/connectivity_service.dart';
import '../services/offline_search.dart';
import 'bill_edit_screen.dart';
import 'barcode_scanner_screen.dart';

/// Bottom-nav "Receiving" tab - houses both the pending-receipt worklist and a
/// browsable history of every vendor bill ever recorded, mirroring how the web app
/// nests "Pending Receipts" + "All Vendor Bills" under one Inventory/Receiving area.
/// No Scaffold/AppBar of its own - HomeScreen already provides one.
class ReceivingScreen extends StatelessWidget {
  const ReceivingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: const TabBar(tabs: [Tab(text: 'Pending'), Tab(text: 'All Invoices')]),
          ),
          const Expanded(child: TabBarView(children: [_PendingReceiptsTab(), _AllBillsTab()])),
        ],
      ),
    );
  }
}

class _PendingReceiptsTab extends StatefulWidget {
  const _PendingReceiptsTab();

  @override
  State<_PendingReceiptsTab> createState() => _PendingReceiptsTabState();
}

class _PendingReceiptsTabState extends State<_PendingReceiptsTab> {
  List<dynamic> _pending = [];
  bool _loading = true;
  String? _error;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.request('/api/purchase/bills/pending-receipt/');
      if (mounted) setState(() => _pending = data as List<dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
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
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
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
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!))])
                  : _pending.isEmpty
                      ? ListView(
                          children: const [
                            Padding(
                              padding: EdgeInsets.only(top: 80),
                              child: Center(child: Text('No pending vendor invoices.')),
                            ),
                          ],
                        )
                      : ListView.builder(
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
                              if (isAdmin)
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: 'Edit',
                                  onPressed: () async {
                                    final changed = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(builder: (context) => BillEditScreen(bill: bill)),
                                    );
                                    if (changed == true) _load();
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

class _AllBillsTab extends StatefulWidget {
  const _AllBillsTab();

  @override
  State<_AllBillsTab> createState() => _AllBillsTabState();
}

class _AllBillsTabState extends State<_AllBillsTab> {
  List<dynamic> _bills = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = true}) async {
    setState(() {
      if (reset) {
        _page = 1;
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });
    try {
      final data = await _api.request('/api/purchase/bills/?page=$_page&ordering=-bill_date') as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      if (mounted) {
        setState(() {
          _bills = reset ? results : [..._bills, ...results];
          _hasMore = data['next'] != null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = _loadingMore = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    _page++;
    await _load(reset: false);
  }

  Future<void> _openBill(Map<String, dynamic> bill) async {
    if (bill['goods_received'] == true) {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => _ReceivedBillDetailSheet(bill: bill, api: _api, onChanged: _load),
      );
      return;
    }
    final received = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => _ReceiveBillScreen(bill: bill)),
    );
    if (received == true) _load();
  }

  Future<void> _editBill(Map<String, dynamic> bill) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => BillEditScreen(bill: bill)),
    );
    if (changed == true) _load();
  }

  Future<void> _deleteBill(Map<String, dynamic> bill) async {
    final confirmed = await confirmDelete(context, itemLabel: bill['bill_number'] as String?);
    if (!confirmed) return;
    try {
      await _api.request('/api/purchase/bills/${bill['id']}/', method: 'DELETE');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vendor invoice deleted.')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthService>().isAdmin;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!))])
                  : _bills.isEmpty
                      ? ListView(
                          children: const [
                            Padding(
                              padding: EdgeInsets.only(top: 80),
                              child: Center(child: Text('No vendor bills recorded yet.')),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _bills.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == _bills.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: _loadingMore
                                      ? const CircularProgressIndicator()
                                      : TextButton(onPressed: _loadMore, child: const Text('Load more')),
                                ),
                              );
                            }
                            final bill = _bills[i] as Map<String, dynamic>;
                            final received = bill['goods_received'] == true;
                            return Card(
                              child: ListTile(
                                title: Text('${bill['bill_number']} · ${bill['supplier_name']}'),
                                subtitle: Text('${bill['bill_date']} · Rs. ${bill['total_amount']}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Chip(
                                      label: Text(received ? 'Received' : 'Pending'),
                                      backgroundColor: received
                                          ? Colors.green.withValues(alpha: 0.15)
                                          : Colors.orange.withValues(alpha: 0.15),
                                      labelStyle:
                                          TextStyle(color: received ? Colors.green.shade800 : Colors.orange.shade800),
                                      side: BorderSide.none,
                                    ),
                                    if (isAdmin)
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 20),
                                        tooltip: 'Edit',
                                        onPressed: () => _editBill(bill),
                                      ),
                                    if (isAdmin) DeleteIconButton(onPressed: () => _deleteBill(bill)),
                                  ],
                                ),
                                onTap: () => _openBill(bill),
                              ),
                            );
                          },
                        ),
            ),
    );
  }
}

class _ReceivedBillDetailSheet extends StatefulWidget {
  final Map<String, dynamic> bill;
  final ApiClient api;
  final VoidCallback onChanged;
  const _ReceivedBillDetailSheet({required this.bill, required this.api, required this.onChanged});

  @override
  State<_ReceivedBillDetailSheet> createState() => _ReceivedBillDetailSheetState();
}

class _ReceivedBillDetailSheetState extends State<_ReceivedBillDetailSheet> {
  bool _downloadingPdf = false;

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(bill['bill_number'] as String, style: Theme.of(context).textTheme.titleLarge),
          Text(bill['supplier_name'] as String, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Date'),
              Text(bill['bill_date'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total'),
              Text('Rs. ${bill['total_amount']}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _downloadingPdf
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _downloadingPdf = true);
                    try {
                      await downloadAndOpenPdf(
                        widget.api,
                        '/api/purchase/bills/${bill['id']}/pdf/',
                        '${bill['bill_number']}-receiving.pdf',
                      );
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text('$e')));
                    } finally {
                      if (mounted) setState(() => _downloadingPdf = false);
                    }
                  },
            icon: const Icon(Icons.print_outlined),
            label: Text(_downloadingPdf ? 'Preparing...' : 'Print'),
          ),
          if (context.read<AuthService>().isAdmin) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final changed = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(builder: (context) => BillEditScreen(bill: bill)),
                      );
                      if (changed == true) {
                        widget.onChanged();
                        navigator.pop();
                      }
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      final confirmed = await confirmDelete(context, itemLabel: bill['bill_number'] as String?);
                      if (!confirmed) return;
                      try {
                        await widget.api.request('/api/purchase/bills/${bill['id']}/', method: 'DELETE');
                        messenger.showSnackBar(const SnackBar(content: Text('Vendor invoice deleted.')));
                        widget.onChanged();
                        navigator.pop();
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ],
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
  final _headerDiscountController = TextEditingController();
  String _headerDiscountType = 'fixed';
  bool _creating = false;

  ApiClient get _api => context.read<AuthService>().api;

  Future<void> _searchSuppliers(String q) async {
    if (q.trim().isEmpty) return;
    if (!context.read<ConnectivityService>().isOnline) {
      final data = await OfflineSearch.searchSuppliers(q);
      if (mounted) setState(() => _supplierResults = data);
      return;
    }
    try {
      final data = await _api.request('/api/purchase/suppliers/?search=${Uri.encodeComponent(q)}') as Map<String, dynamic>;
      setState(() => _supplierResults = data['results'] as List<dynamic>);
    } catch (_) {
      final data = await OfflineSearch.searchSuppliers(q);
      if (mounted) setState(() => _supplierResults = data);
    }
  }

  Future<void> _searchProducts(String q) async {
    if (q.trim().isEmpty) return;
    if (!context.read<ConnectivityService>().isOnline) {
      final data = await OfflineSearch.searchProducts(q);
      if (mounted) setState(() => _productResults = data);
      return;
    }
    try {
      final data = await _api.request('/api/products/products/?search=${Uri.encodeComponent(q)}');
      setState(() => _productResults = data is List ? data : (data['results'] as List<dynamic>));
    } catch (_) {
      final data = await OfflineSearch.searchProducts(q);
      if (mounted) setState(() => _productResults = data);
    }
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
        'discounts': <DiscountEntry>[],
        'received_now': false,
        'scanned_codes': <String>[],
        'received_qty': TextEditingController(),
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
    for (final l in _lines) {
      if (l['received_now'] != true) continue;
      final trackingMethod = l['tracking_method'] as String;
      if (trackingMethod == 'none') continue;
      final expected = int.tryParse((l['expected_quantity'] as TextEditingController).text) ?? 0;
      final codes = l['scanned_codes'] as List<String>;
      if (codes.length != expected) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${l['name']}: marked received now, but ${codes.length} code(s) entered - needs exactly $expected.'),
        ));
        return;
      }
    }
    setState(() => _creating = true);
    final online = context.read<ConnectivityService>().isOnline;
    try {
      final result = await _api.enqueueOrSend(
        isOnline: online,
        queueType: 'create_vendor_invoice',
        path: '/api/purchase/vendor-invoice/',
        body: {
          'supplier_id': _selectedSupplier!['id'],
          'items': _lines
              .map((l) => {
                    'product_id': l['product_id'],
                    'unit_price': (l['unit_price'] as TextEditingController).text,
                    'expected_quantity': (l['expected_quantity'] as TextEditingController).text,
                    'discounts': (l['discounts'] as List<DiscountEntry>)
                        .where((d) => (double.tryParse(d.value) ?? 0) > 0)
                        .map((d) => d.toJson())
                        .toList(),
                    if (l['received_now'] == true) 'received': true,
                    if (l['received_now'] == true && l['tracking_method'] != 'none') 'codes': l['scanned_codes'],
                    if (l['received_now'] == true && l['tracking_method'] == 'none')
                      'received_quantity': (l['received_qty'] as TextEditingController).text,
                  })
              .toList(),
          if (_headerDiscountController.text.isNotEmpty) 'discount_amount': _headerDiscountController.text,
          'discount_type': _headerDiscountType,
        },
        summary: 'Vendor invoice - ${_selectedSupplier!['name']} - ${_lines.length} item${_lines.length == 1 ? '' : 's'}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.queued
              ? 'Vendor invoice saved offline - will sync automatically.'
              : 'Vendor invoice recorded - now pending receipt.'),
        ));
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
          ..._lines.map((l) {
            final discounts = l['discounts'] as List<DiscountEntry>;
            final activeCount = discounts.where((d) => (double.tryParse(d.value) ?? 0) > 0).length;
            return Card(
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
                          icon: Badge(
                            isLabelVisible: activeCount > 0,
                            label: Text('$activeCount'),
                            child: const Icon(Icons.percent),
                          ),
                          tooltip: 'Discounts',
                          onPressed: () async {
                            final result = await showDiscountEditorDialog(
                              context,
                              title: l['name'] as String,
                              initial: discounts,
                            );
                            if (result != null) setState(() => l['discounts'] = result);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() => _lines.remove(l)),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Already have these in hand - receive now'),
                      value: l['received_now'] as bool,
                      onChanged: (v) => setState(() => l['received_now'] = v ?? false),
                    ),
                    if (l['received_now'] == true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: (l['tracking_method'] as String) == 'none'
                            ? TextField(
                                controller: l['received_qty'] as TextEditingController,
                                decoration: const InputDecoration(labelText: 'Quantity received'),
                                keyboardType: TextInputType.number,
                              )
                            : _TrackingCodeCaptureField(
                                trackingType: l['tracking_method'] as String,
                                expectedCount: int.tryParse(
                                        (l['expected_quantity'] as TextEditingController).text) ??
                                    0,
                                codes: l['scanned_codes'] as List<String>,
                                onChanged: (codes) => setState(() => l['scanned_codes'] = codes),
                              ),
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _headerDiscountController,
                  decoration: const InputDecoration(labelText: 'Whole-bill discount', hintText: '0.00', border: OutlineInputBorder()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'fixed', label: Text('Rs.')),
                  ButtonSegment(value: 'percent', label: Text('%')),
                ],
                selected: {_headerDiscountType},
                onSelectionChanged: (s) => setState(() => _headerDiscountType = s.first),
              ),
            ],
          ),
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

bool _isValidImei(String code) => code.length == 15 && RegExp(r'^\d+$').hasMatch(code);

/// Per-line IMEI/serial/barcode capture: manual entry + camera scan + validation,
/// reused wherever a fixed number of tracking codes needs to be collected for one line
/// (currently: creation-time "receive now" on a new vendor invoice). Deliberately
/// self-contained/stateless-from-the-outside (codes live in the parent's line map,
/// passed in and reported back via onChanged) so it can be dropped into any screen with
/// its own per-line state shape without this widget needing to know about it.
class _TrackingCodeCaptureField extends StatefulWidget {
  final String trackingType;
  final int expectedCount;
  final List<String> codes;
  final ValueChanged<List<String>> onChanged;

  const _TrackingCodeCaptureField({
    required this.trackingType,
    required this.expectedCount,
    required this.codes,
    required this.onChanged,
  });

  @override
  State<_TrackingCodeCaptureField> createState() => _TrackingCodeCaptureFieldState();
}

class _TrackingCodeCaptureFieldState extends State<_TrackingCodeCaptureField> {
  final _manualController = TextEditingController();

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _showInvalidImeiDialog(String code) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Invalid IMEI'),
        content: Text(
          '"$code" is not a valid IMEI.\n\nAn IMEI must be exactly 15 digits (numbers only). '
          'This code was rejected - press OK, then scan or type again.',
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _addCode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;
    if (widget.codes.length >= widget.expectedCount) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Already entered the expected quantity for this line.')));
      return;
    }
    if (widget.trackingType == 'imei' && !_isValidImei(code)) {
      await _showInvalidImeiDialog(code);
      return;
    }
    if (widget.codes.contains(code)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('That code was already entered for this line.')));
      return;
    }
    widget.onChanged([...widget.codes, code]);
    _manualController.clear();
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
    );
    if (code == null) return;
    await _addCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final fullyCaptured = widget.codes.length >= widget.expectedCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.codes.length} of ${widget.expectedCount} entered',
          style: TextStyle(
            color: fullyCaptured ? Colors.green.shade700 : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: fullyCaptured ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        if (widget.codes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.codes
                .map((code) => Chip(
                      label: Text(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      onDeleted: () => widget.onChanged([...widget.codes]..remove(code)),
                    ))
                .toList(),
          ),
        ],
        if (!fullyCaptured) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualController,
                  decoration: InputDecoration(
                    labelText: widget.trackingType == 'imei' ? 'Enter 15-digit IMEI' : 'Enter ${widget.trackingType}',
                  ),
                  keyboardType: widget.trackingType == 'imei' ? TextInputType.number : TextInputType.text,
                  onSubmitted: (v) => _addCode(v),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Add',
                onPressed: () => _addCode(_manualController.text),
              ),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Scan with camera',
                onPressed: _scan,
              ),
            ],
          ),
        ],
      ],
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
  final Map<int, List<String>> _scannedCodes = {};
  final Map<int, TextEditingController> _manualControllers = {};
  final Map<int, TextEditingController> _qtyControllers = {};
  final Map<int, int> _remainingByItem = {};
  Map<String, dynamic>? _billDetail;
  int? _warehouseId;
  bool _loadingDetail = true;
  bool _submitting = false;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _loadDetail();
    _loadWarehouse();
  }

  @override
  void dispose() {
    for (final c in _manualControllers.values) {
      c.dispose();
    }
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Fetched fresh rather than trusting widget.bill (which may be a stale list-page
  // snapshot) - another device could be receiving the same bill concurrently, so the
  // remaining-to-receive count per line must come from the server at the moment this
  // screen opens.
  Future<void> _loadDetail() async {
    setState(() => _loadingDetail = true);
    try {
      final data = await _api.request('/api/purchase/bills/${widget.bill['id']}/') as Map<String, dynamic>;
      final items = (data['items'] as List).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _billDetail = data;
          for (final it in items) {
            final id = it['id'] as int;
            final qty = double.tryParse(it['quantity'].toString()) ?? 0;
            final received = double.tryParse(it['received_quantity'].toString()) ?? 0;
            _remainingByItem[id] = (qty - received).round();
            _scannedCodes.putIfAbsent(id, () => []);
            _manualControllers.putIfAbsent(id, () => TextEditingController());
            _qtyControllers.putIfAbsent(id, () => TextEditingController());
          }
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Future<void> _loadWarehouse() async {
    try {
      final data = await _api.request('/api/inventory/warehouses/') as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      if (results.isNotEmpty && mounted) setState(() => _warehouseId = results.first['id'] as int);
    } catch (_) {}
  }

  Future<void> _showInvalidImeiDialog(String code) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Invalid IMEI'),
        content: Text(
          '"$code" is not a valid IMEI.\n\nAn IMEI must be exactly 15 digits (numbers only). '
          'This code was rejected - press OK, then scan again.',
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _addCode(int itemId, String trackingType, String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;
    final remaining = _remainingByItem[itemId] ?? 0;
    final scanned = _scannedCodes[itemId] ?? [];

    if (scanned.length >= remaining) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Already scanned the expected quantity for this item.')));
      return;
    }
    if (trackingType == 'imei' && !_isValidImei(code)) {
      await _showInvalidImeiDialog(code);
      return;
    }
    if (scanned.contains(code)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('That code was already scanned for this item.')));
      return;
    }
    setState(() => _scannedCodes[itemId] = [...scanned, code]);
    _manualControllers[itemId]?.clear();
  }

  Future<void> _scanForItem(int itemId, String trackingType) async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
    );
    if (code == null) return;
    await _addCode(itemId, trackingType, code);
  }

  bool get _canSubmit {
    final items = (_billDetail?['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final it in items) {
      final id = it['id'] as int;
      if (it['tracking_type'] == 'none') continue;
      final remaining = _remainingByItem[id] ?? 0;
      if (remaining > 0 && (_scannedCodes[id]?.length ?? 0) != remaining) return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (_warehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No warehouse found.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final items = (_billDetail?['items'] as List).cast<Map<String, dynamic>>();
      final payload = items.map((item) {
        final id = item['id'] as int;
        if (item['tracking_type'] == 'none') {
          return {'bill_item_id': id, 'quantity': _qtyControllers[id]!.text.isEmpty ? '0' : _qtyControllers[id]!.text};
        }
        return {'bill_item_id': id, 'codes': _scannedCodes[id] ?? []};
      }).toList();

      await _api.request('/api/purchase/bills/${widget.bill['id']}/receive-items/',
          method: 'POST', body: {'warehouse_id': _warehouseId, 'items': payload});
      await _api.request('/api/purchase/bills/${widget.bill['id']}/confirm-received/', method: 'POST', body: {});

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${widget.bill['bill_number']} marked received.')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingDetail || _billDetail == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.bill['bill_number'] as String)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final items = (_billDetail!['items'] as List).cast<Map<String, dynamic>>();
    final alreadyReceived = _billDetail!['goods_received'] == true;
    return Scaffold(
      appBar: AppBar(title: Text(widget.bill['bill_number'] as String)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Chip(
            avatar: Icon(
              alreadyReceived ? Icons.check_circle : Icons.pending_outlined,
              size: 18,
              color: alreadyReceived ? Colors.green.shade800 : Colors.orange.shade800,
            ),
            label: Text(alreadyReceived ? 'Already fully received' : 'Pending receipt'),
            backgroundColor:
                alreadyReceived ? Colors.green.withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
            side: BorderSide.none,
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final id = item['id'] as int;
            final trackingType = item['tracking_type'] as String;
            final remaining = _remainingByItem[id] ?? 0;
            final scanned = _scannedCodes[id] ?? [];
            final fullyScanned = trackingType != 'none' && scanned.length >= remaining;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item['product_name']} (expected ${item['quantity']})',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (trackingType == 'none') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _qtyControllers[id],
                        decoration: const InputDecoration(labelText: 'Quantity received'),
                        keyboardType: TextInputType.number,
                      ),
                    ] else ...[
                      const SizedBox(height: 4),
                      Text(
                        remaining == 0
                            ? 'Nothing left to receive for this line.'
                            : '${scanned.length} of $remaining scanned',
                        style: TextStyle(
                          color: fullyScanned ? Colors.green.shade700 : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: fullyScanned ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (scanned.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: scanned
                              .map((code) => Chip(
                                    label: Text(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                                    onDeleted: () => setState(() => _scannedCodes[id] = [...scanned]..remove(code)),
                                  ))
                              .toList(),
                        ),
                      ],
                      if (!fullyScanned && remaining > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _manualControllers[id],
                                decoration: InputDecoration(
                                  labelText: trackingType == 'imei' ? 'Enter 15-digit IMEI' : 'Enter $trackingType',
                                ),
                                keyboardType:
                                    trackingType == 'imei' ? TextInputType.number : TextInputType.text,
                                onSubmitted: (v) => _addCode(id, trackingType, v),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              tooltip: 'Add',
                              onPressed: () => _addCode(id, trackingType, _manualControllers[id]!.text),
                            ),
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner),
                              tooltip: 'Scan with camera',
                              onPressed: () => _scanForItem(id, trackingType),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          if (!_canSubmit)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Scan the exact expected quantity for every tracked item before this bill can be marked received.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
          FilledButton(
            onPressed: (_submitting || !_canSubmit) ? null : _submit,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _submitting ? const CircularProgressIndicator() : const Text('Receive & Mark Complete'),
          ),
        ],
      ),
    );
  }
}
