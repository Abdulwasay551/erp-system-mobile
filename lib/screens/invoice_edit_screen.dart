import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../widgets/discount_editor.dart';
import '../widgets/tracking_code_editor.dart';

class _EditableItem {
  int? id;
  final int productId;
  final String productName;
  final String productTrackingMethod;
  String? trackingIdentifier;
  final int? trackingUnitId;
  final String? trackingStatus;
  final TextEditingController unitPriceController;
  final TextEditingController quantityController;
  List<DiscountEntry> discounts;

  _EditableItem({
    this.id,
    required this.productId,
    required this.productName,
    this.productTrackingMethod = 'none',
    this.trackingIdentifier,
    this.trackingUnitId,
    this.trackingStatus,
    required String unitPrice,
    required String quantity,
    List<DiscountEntry>? discounts,
  })  : unitPriceController = TextEditingController(text: unitPrice),
        quantityController = TextEditingController(text: quantity),
        discounts = discounts ?? [];
}

/// Owner/Manager-only correction of a posted invoice's line items - fetches the
/// invoice's current items, lets price/discount/quantity be edited (quantity locked
/// for tracked/IMEI lines, always 1), lines removed, or new untracked products added,
/// then submits the whole set to InvoiceViewSet.edit().
class InvoiceEditScreen extends StatefulWidget {
  final int invoiceId;
  final String invoiceNumber;
  const InvoiceEditScreen({super.key, required this.invoiceId, required this.invoiceNumber});

  @override
  State<InvoiceEditScreen> createState() => _InvoiceEditScreenState();
}

class _InvoiceEditScreenState extends State<InvoiceEditScreen> {
  final List<_EditableItem> _items = [];
  final _productSearchController = TextEditingController();
  List<dynamic> _productResults = [];
  bool _loading = true;
  bool _saving = false;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _productSearchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.request('/api/sales/invoices/${widget.invoiceId}/') as Map<String, dynamic>;
      final items = (data['items'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _items
          ..clear()
          ..addAll(items.map((it) => _EditableItem(
                id: it['id'] as int,
                productId: it['product'] as int,
                productName: it['product_name'] as String,
                productTrackingMethod: it['product_tracking_method'] as String? ?? 'none',
                trackingIdentifier: it['tracking_identifier'] as String?,
                trackingUnitId: it['tracking_unit'] as int?,
                trackingStatus: it['tracking_status'] as String?,
                unitPrice: it['unit_price'].toString(),
                quantity: it['quantity'].toString(),
                discounts: ((it['discounts'] as List?) ?? [])
                    .map((d) => DiscountEntry(type: d['type'] as String, value: d['value'].toString()))
                    .toList(),
              )));
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchProducts(String q) async {
    if (q.trim().isEmpty) return;
    try {
      final data = await _api.request('/api/products/products/?search=${Uri.encodeComponent(q)}');
      setState(() => _productResults = data is List ? data : (data['results'] as List<dynamic>));
    } catch (_) {}
  }

  void _addProduct(Map<String, dynamic> product) {
    if (product['tracking_method'] != 'none') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tracked items (IMEI/serial) can't be added here - use POS for new phones.")),
      );
      return;
    }
    setState(() {
      _items.add(_EditableItem(
        productId: product['id'] as int,
        productName: product['name'] as String,
        unitPrice: product['selling_price']?.toString() ?? '0',
        quantity: '1',
      ));
      _productResults = [];
      _productSearchController.clear();
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('An invoice needs at least one line item.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.request('/api/sales/invoices/${widget.invoiceId}/edit/', method: 'POST', body: {
        'items': _items
            .map((it) => {
                  'product_id': it.productId,
                  if (it.trackingUnitId != null) 'tracking_id': it.trackingUnitId,
                  if (it.trackingUnitId == null) 'quantity': it.quantityController.text,
                  'unit_price': it.unitPriceController.text,
                  'discounts': it.discounts
                      .where((d) => (double.tryParse(d.value) ?? 0) > 0)
                      .map((d) => d.toJson())
                      .toList(),
                })
            .toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice updated.')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit ${widget.invoiceNumber}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ..._items.map((it) {
                  final activeCount = it.discounts.where((d) => (double.tryParse(d.value) ?? 0) > 0).length;
                  final locked = it.trackingUnitId != null;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(it.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => setState(() => _items.remove(it)),
                              ),
                            ],
                          ),
                          if (it.trackingUnitId != null)
                            TrackingCodeEditor(
                              id: it.trackingUnitId!,
                              code: it.trackingIdentifier,
                              status: it.trackingStatus ?? 'sold',
                              trackingMethod: it.productTrackingMethod,
                              onSaved: (newCode) => setState(() => it.trackingIdentifier = newCode),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: it.unitPriceController,
                                  decoration: const InputDecoration(labelText: 'Price'),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (locked)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('x1'),
                                )
                              else
                                Expanded(
                                  child: TextField(
                                    controller: it.quantityController,
                                    decoration: const InputDecoration(labelText: 'Qty'),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: Badge(
                                  isLabelVisible: activeCount > 0,
                                  label: Text('$activeCount'),
                                  child: const Icon(Icons.percent),
                                ),
                                tooltip: 'Discounts',
                                onPressed: () async {
                                  final result = await showDiscountEditorDialog(context, title: it.productName, initial: it.discounts);
                                  if (result != null) setState(() => it.discounts = result);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                TextField(
                  controller: _productSearchController,
                  decoration: const InputDecoration(labelText: 'Add an untracked product by name...', border: OutlineInputBorder()),
                  onChanged: _searchProducts,
                ),
                ..._productResults.map((p) {
                  final product = p as Map<String, dynamic>;
                  return ListTile(
                    title: Text(product['name'] as String),
                    trailing: FilledButton(onPressed: () => _addProduct(product), child: const Text('Add')),
                  );
                }),
                const SizedBox(height: 4),
                Text(
                  'To add a new phone/IMEI-tracked item, use POS for a new sale instead.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: _saving ? const CircularProgressIndicator() : const Text('Save Changes'),
                ),
              ],
            ),
    );
  }
}
