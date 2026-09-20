import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/pdf_helper.dart';
import '../theme/app_semantic_colors.dart';
import '../widgets/gradient_button.dart';
import '../widgets/discount_editor.dart';
import '../services/connectivity_service.dart';
import '../services/offline_search.dart';
import '../widgets/tracking_unit_picker.dart';
import '../widgets/info_icon_button.dart';
import 'barcode_scanner_screen.dart';

class _CartLine {
  final String key;
  final int productId;
  final int? trackingId;
  final String name;
  final String identifier;
  double unitPrice;
  final double avgPurchasePrice;
  double quantity;
  final double maxQty;
  List<DiscountEntry> discounts;

  _CartLine({
    required this.key,
    required this.productId,
    required this.trackingId,
    required this.name,
    required this.identifier,
    required this.unitPrice,
    required this.avgPurchasePrice,
    required this.quantity,
    required this.maxQty,
    List<DiscountEntry>? discounts,
  }) : discounts = discounts ?? [];
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
  final _discountController = TextEditingController();
  String _discountType = 'fixed';

  Future<void> _searchCustomers(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _customerResults = []);
      return;
    }
    if (!context.read<ConnectivityService>().isOnline) {
      final data = await OfflineSearch.searchCustomers(q);
      if (mounted) setState(() => _customerResults = data);
      return;
    }
    try {
      final data = await _api.request('/api/crm/customers/?search=${Uri.encodeComponent(q)}') as Map<String, dynamic>;
      if (mounted) setState(() => _customerResults = data['results'] as List<dynamic>);
    } catch (_) {
      final data = await OfflineSearch.searchCustomers(q);
      if (mounted) setState(() => _customerResults = data);
    }
  }

  ApiClient get _api => context.read<AuthService>().api;

  double get _cartSubtotal => _cart.fold(0, (sum, l) => sum + l.unitPrice * l.quantity);
  double get _lineDiscountsTotal => _cart.fold(
        0,
        (sum, l) => sum + computeDiscountTotal(l.unitPrice * l.quantity, l.quantity, l.discounts),
      );
  double get _discountAmount {
    final netSubtotal = (_cartSubtotal - _lineDiscountsTotal).clamp(0, double.infinity).toDouble();
    final raw = double.tryParse(_discountController.text) ?? 0;
    final resolved = _discountType == 'percent' ? netSubtotal * (raw / 100) : raw;
    return resolved.clamp(0, netSubtotal).toDouble();
  }

  double get _cartTotal => _cartSubtotal - _lineDiscountsTotal - _discountAmount;

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    final online = context.read<ConnectivityService>().isOnline;
    try {
      if (online) {
        final data = await _api.request('/api/sales/pos/search/?q=${Uri.encodeComponent(q)}');
        setState(() => _results = data as List<dynamic>);
      } else {
        final data = await OfflineSearch.posSearch(q);
        setState(() => _results = data);
      }
      if (_results.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(online ? 'No matching products found.' : 'No matching products found in offline data.'),
        ));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      // Live request failed for a non-ApiException reason (e.g. WiFi with no real
      // internet, even though ConnectivityService thought we were online) - fall back
      // to the local mirror instead of surfacing a raw exception.
      final data = await OfflineSearch.posSearch(q);
      if (mounted) setState(() => _results = data);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
    );
    if (code == null || code.isEmpty) return;
    _searchController.text = code;
    await _search();
  }

  /// Untracked only - tracked products always go through the picker (see
  /// _selectTrackedUnits below) so a specific unit is always a deliberate, explicit
  /// choice, never whichever row a name/scan search happened to match first.
  void _addToCart(Map<String, dynamic> item) {
    final key = 'p-${item['product_id']}';
    if (_cart.any((l) => l.key == key)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Already in cart.')));
      return;
    }
    final variant = item['variant'] as String?;
    setState(() {
      _cart.add(_CartLine(
        key: key,
        productId: item['product_id'] as int,
        trackingId: null,
        name: variant != null ? '${item['name']} ($variant)' : item['name'] as String,
        identifier: item['identifier']?.toString() ?? '',
        unitPrice: double.parse(item['unit_price'].toString()),
        avgPurchasePrice: double.tryParse(item['avg_purchase_price']?.toString() ?? '') ?? 0,
        quantity: 1,
        maxQty: double.parse(item['available_qty'].toString()),
      ));
      _results = [];
      _searchController.clear();
    });
  }

  Future<void> _selectTrackedUnits(Map<String, dynamic> item) async {
    final units = await showTrackingUnitPicker(
      context,
      api: _api,
      productId: item['product_id'] as int,
      productName: item['name'] as String,
      trackingMethod: item['tracking_method'] as String? ?? 'imei',
      initialQuery: _searchController.text,
    );
    if (units == null || units.isEmpty || !mounted) return;
    final variant = item['variant'] as String?;
    setState(() {
      final existingKeys = _cart.map((l) => l.key).toSet();
      var skipped = 0;
      for (final unit in units) {
        final key = 't-${unit['id']}';
        if (existingKeys.contains(key)) {
          skipped++;
          continue;
        }
        _cart.add(_CartLine(
          key: key,
          productId: item['product_id'] as int,
          trackingId: unit['id'] as int,
          name: variant != null ? '${item['name']} ($variant)' : item['name'] as String,
          identifier: unit['identifier'] as String? ?? '',
          unitPrice: double.parse(item['unit_price'].toString()),
          avgPurchasePrice: double.tryParse(item['avg_purchase_price']?.toString() ?? '') ?? 0,
          quantity: 1,
          maxQty: 1,
        ));
      }
      if (skipped > 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Some selected units were already in the cart.')));
      }
      _results = [];
      _searchController.clear();
    });
  }

  /// Tracked results collapse to one row per product ("N available - Select units")
  /// instead of one row per unit - picking a specific unit is always an explicit step
  /// through the picker, never a single tap on whichever row a search happened to match.
  List<Map<String, dynamic>> get _untrackedResults =>
      _results.cast<Map<String, dynamic>>().where((r) => r['tracking_method'] == 'none').toList();

  List<MapEntry<int, List<Map<String, dynamic>>>> get _trackedGroups {
    final groups = <int, List<Map<String, dynamic>>>{};
    for (final r in _results.cast<Map<String, dynamic>>()) {
      if (r['tracking_method'] == 'none') continue;
      groups.putIfAbsent(r['product_id'] as int, () => []).add(r);
    }
    return groups.entries.toList();
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
                  'discounts': l.discounts
                      .where((d) => (double.tryParse(d.value) ?? 0) > 0)
                      .map((d) => d.toJson())
                      .toList(),
                })
            .toList(),
        if (_discountController.text.isNotEmpty) 'discount_amount': _discountController.text,
        'discount_type': _discountType,
        'payment': {'method': _paymentMethod, 'amount': _cartTotal},
      };
      final itemCount = _cart.length;
      final summary = 'Sale - Rs. ${_cartTotal.toStringAsFixed(2)} - $itemCount item${itemCount == 1 ? '' : 's'}';
      final online = context.read<ConnectivityService>().isOnline;
      final enqueueResult = await _api.enqueueOrSend(
        isOnline: online,
        queueType: 'pos_checkout',
        path: '/api/sales/pos/checkout/',
        body: payload,
        summary: summary,
      );

      setState(() {
        _lastInvoice = enqueueResult.queued ? null : enqueueResult.result as Map<String, dynamic>;
        _cart.clear();
        _selectedCustomer = null;
        _customerSearchController.clear();
        _customerResults = [];
        _discountController.clear();
        _discountType = 'fixed';
      });
      if (mounted) {
        final message = enqueueResult.queued
            ? 'Sale saved offline - will sync automatically once back online.'
            : 'Invoice ${enqueueResult.result['invoice_number']} created.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<void> _openInvoicePdf(String size) async {
    final invoiceId = _lastInvoice?['invoice_id'];
    if (invoiceId == null) return;
    setState(() => _openingPdf = true);
    try {
      await downloadAndOpenPdf(
        _api,
        '/api/sales/invoices/$invoiceId/pdf/?size=$size',
        'invoice-$invoiceId-$size.pdf',
      );
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
    _discountController.dispose();
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
            OutlinedButton(
              onPressed: _scanBarcode,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14)),
              child: const Icon(Icons.qr_code_scanner),
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
              children: [
                for (final group in _trackedGroups)
                  ListTile(
                    title: Row(children: [
                      Expanded(child: Text(group.value.first['name'] as String)),
                      Chip(
                        label: Text(group.value.first['tracking_method'] as String, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ]),
                    subtitle: Text('${group.value.length} available · Rs. ${group.value.first['unit_price']}'),
                    trailing: FilledButton(
                      onPressed: () => _selectTrackedUnits(group.value.first),
                      child: const Text('Select units'),
                    ),
                  ),
                for (final item in _untrackedResults)
                  ListTile(
                    title: Text(item['name'] as String),
                    subtitle: Text('${item['identifier']} · Rs. ${item['unit_price']} · Qty ${item['available_qty']}'),
                    trailing: FilledButton(onPressed: () => _addToCart(item), child: const Text('Add')),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('Cart', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_cart.isEmpty)
          Text('No items yet - search above to add.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
        else
          Card(
            child: Column(
              children: _cart.map((l) {
                final belowCost = l.avgPurchasePrice > 0 && l.unitPrice < l.avgPurchasePrice;
                final lineDiscount = computeDiscountTotal(l.unitPrice * l.quantity, l.quantity, l.discounts);
                final activeDiscounts = l.discounts.where((d) => (double.tryParse(d.value) ?? 0) > 0).length;
                return ListTile(
                  title: Text(l.name),
                  subtitle: Row(
                    children: [
                      if (belowCost)
                        Tooltip(
                          message: 'Below average purchase price of Rs. ${l.avgPurchasePrice.toStringAsFixed(2)} - reduces margin.',
                          child: Icon(Icons.warning_amber_rounded, size: 16, color: context.semanticColors.warning),
                        ),
                      if (belowCost) const SizedBox(width: 4),
                      SizedBox(
                        width: 90,
                        child: TextFormField(
                          initialValue: l.unitPrice.toStringAsFixed(2),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                          onChanged: (v) => setState(() => l.unitPrice = double.tryParse(v) ?? l.unitPrice),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('× ${l.quantity.toStringAsFixed(0)}'),
                      IconButton(
                        icon: Badge(
                          isLabelVisible: activeDiscounts > 0,
                          label: Text('$activeDiscounts'),
                          child: const Icon(Icons.percent, size: 18),
                        ),
                        tooltip: 'Discounts',
                        onPressed: () async {
                          final result = await showDiscountEditorDialog(context, title: l.name, initial: l.discounts);
                          if (result != null) setState(() => l.discounts = result);
                        },
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Rs. ${(l.unitPrice * l.quantity - lineDiscount).toStringAsFixed(2)}'),
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
                    Text('Subtotal', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    Text('Rs. ${_cartSubtotal.toStringAsFixed(2)}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
                if (_lineDiscountsTotal > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Line discounts', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      Text('- Rs. ${_lineDiscountsTotal.toStringAsFixed(2)}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _discountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'Cart-wide discount', hintText: '0.00', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'fixed', label: Text('Rs.')),
                        ButtonSegment(value: 'percent', label: Text('%')),
                      ],
                      selected: {_discountType},
                      onSelectionChanged: (s) => setState(() => _discountType = s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
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
                GradientButton(
                  onPressed: _checkingOut ? null : _checkout,
                  child: _checkingOut
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                        )
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Outstanding: Rs. ${_lastInvoice!['outstanding_amount']}'),
                      const SizedBox(width: 4),
                      const InfoIconButton(message: 'Total minus Paid for this invoice - what the customer still owes on it specifically.'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  PopupMenuButton<String>(
                    enabled: !_openingPdf,
                    onSelected: _openInvoicePdf,
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'mini', child: Text('Mini receipt (billing machine)')),
                      PopupMenuItem(value: 'a4', child: Text('A4 invoice (printer)')),
                    ],
                    child: IgnorePointer(
                      child: TextButton.icon(
                        onPressed: () {},
                        icon: _openingPdf
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.picture_as_pdf),
                        label: Text(_openingPdf ? 'Opening...' : 'Open PDF'),
                      ),
                    ),
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
