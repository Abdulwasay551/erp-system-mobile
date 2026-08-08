import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../widgets/discount_editor.dart';

class _EditableBillItem {
  final int? id;
  final int productId;
  final String productName;
  final double receivedQuantity;
  final TextEditingController unitPriceController;
  final TextEditingController quantityController;
  List<DiscountEntry> discounts;

  _EditableBillItem({
    this.id,
    required this.productId,
    required this.productName,
    required this.receivedQuantity,
    required String unitPrice,
    required String quantity,
    List<DiscountEntry>? discounts,
  })  : unitPriceController = TextEditingController(text: unitPrice),
        quantityController = TextEditingController(text: quantity),
        discounts = discounts ?? [];
}

/// Owner/Manager-only correction of a vendor bill's line items. Lines with
/// received_quantity > 0 (already scanned/counted in) lock product/quantity - there's
/// no reversible record of physical receiving the way there is for invoice sales, so
/// price/discount stay editable but the line itself can't be resized or removed.
class BillEditScreen extends StatefulWidget {
  final Map<String, dynamic> bill;
  const BillEditScreen({super.key, required this.bill});

  @override
  State<BillEditScreen> createState() => _BillEditScreenState();
}

class _BillEditScreenState extends State<BillEditScreen> {
  final List<_EditableBillItem> _items = [];
  final _headerDiscountController = TextEditingController();
  final _productSearchController = TextEditingController();
  List<dynamic> _productResults = [];
  bool _saving = false;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    final items = (widget.bill['items'] as List).cast<Map<String, dynamic>>();
    _items.addAll(items.map((it) => _EditableBillItem(
          id: it['id'] as int,
          productId: it['product'] as int,
          productName: it['product_name'] as String,
          receivedQuantity: double.tryParse(it['received_quantity']?.toString() ?? '') ?? 0,
          unitPrice: it['unit_price'].toString(),
          quantity: it['quantity'].toString(),
          discounts: ((it['discounts'] as List?) ?? [])
              .map((d) => DiscountEntry(type: d['type'] as String, value: d['value'].toString()))
              .toList(),
        )));
    _headerDiscountController.text = widget.bill['discount_amount']?.toString() ?? '';
  }

  @override
  void dispose() {
    _headerDiscountController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  Future<void> _searchProducts(String q) async {
    if (q.trim().isEmpty) return;
    try {
      final data = await _api.request('/api/products/products/?search=${Uri.encodeComponent(q)}');
      setState(() => _productResults = data is List ? data : (data['results'] as List<dynamic>));
    } catch (_) {}
  }

  void _addProduct(Map<String, dynamic> product) {
    setState(() {
      _items.add(_EditableBillItem(
        productId: product['id'] as int,
        productName: product['name'] as String,
        receivedQuantity: 0,
        unitPrice: product['cost_price']?.toString() ?? '0',
        quantity: '1',
      ));
      _productResults = [];
      _productSearchController.clear();
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A bill needs at least one line item.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.request('/api/purchase/bills/${widget.bill['id']}/edit/', method: 'POST', body: {
        if (_headerDiscountController.text.isNotEmpty) 'discount_amount': _headerDiscountController.text,
        'items': _items
            .map((it) => {
                  if (it.id != null) 'id': it.id,
                  'product_id': it.productId,
                  'unit_price': it.unitPriceController.text,
                  'quantity': it.quantityController.text,
                  'discounts': it.discounts
                      .where((d) => (double.tryParse(d.value) ?? 0) > 0)
                      .map((d) => d.toJson())
                      .toList(),
                })
            .toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bill updated.')));
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit ${widget.bill['bill_number']}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ..._items.map((it) {
            final activeCount = it.discounts.where((d) => (double.tryParse(d.value) ?? 0) > 0).length;
            final locked = it.receivedQuantity > 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(it.productName, style: const TextStyle(fontWeight: FontWeight.w600))),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: locked ? null : () => setState(() => _items.remove(it)),
                        ),
                      ],
                    ),
                    if (locked)
                      Text('${it.receivedQuantity.toStringAsFixed(0)} already received',
                          style: const TextStyle(fontSize: 12)),
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
                        Expanded(
                          child: TextField(
                            controller: it.quantityController,
                            enabled: !locked,
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
            decoration: const InputDecoration(labelText: 'Add a product by name...', border: OutlineInputBorder()),
            onChanged: _searchProducts,
          ),
          ..._productResults.map((p) {
            final product = p as Map<String, dynamic>;
            return ListTile(
              title: Text(product['name'] as String),
              trailing: FilledButton(onPressed: () => _addProduct(product), child: const Text('Add')),
            );
          }),
          const SizedBox(height: 12),
          TextField(
            controller: _headerDiscountController,
            decoration: const InputDecoration(labelText: 'Whole-bill discount', hintText: '0.00', border: OutlineInputBorder()),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
