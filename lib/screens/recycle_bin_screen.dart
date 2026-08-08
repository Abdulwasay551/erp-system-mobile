import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../theme/app_semantic_colors.dart';
import '../widgets/tag_pill.dart';

const _modelLabels = {
  'sales.invoice': 'Invoice',
  'sales.payment': 'Payment',
  'purchase.bill': 'Vendor Bill',
  'purchase.purchasepayment': 'Vendor Payment',
  'purchase.supplier': 'Supplier',
  'crm.customer': 'Customer',
  'products.product': 'Product',
  'products.producttracking': 'Product Unit',
  'accounting.expense': 'Expense',
  'user_auth.user': 'Staff',
};

/// Cross-model recycle bin (Owner/Manager only) - lists every soft-deleted row across
/// Invoices/Payments/Bills/PurchasePayments/Suppliers/Customers/Products/ProductTracking/
/// Expenses/Users for this company, with per-item restore/purge and a whole-bin empty
/// action. Modeled structurally on staff_screen.dart (simple list, Scaffold, ListTiles).
class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;
  String? _busyKey;
  bool _emptying = false;

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
      final data = await _api.request('/api/core/recycle-bin/') as Map<String, dynamic>;
      if (mounted) setState(() => _items = data['results'] as List<dynamic>);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _key(Map<String, dynamic> item) => '${item['model']}:${item['id']}';

  Future<void> _restore(Map<String, dynamic> item) async {
    setState(() => _busyKey = _key(item));
    try {
      await _api.request('/api/core/recycle-bin/restore/',
          method: 'POST', body: {'model': item['model'], 'id': item['id']});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item['repr']} restored.')));
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _purge(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete?'),
        content: Text(
          '"${item['repr']}" will be permanently deleted and cannot be recovered afterwards, unlike a regular delete. This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.semanticColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Permanently Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyKey = _key(item));
    try {
      await _api.request('/api/core/recycle-bin/purge/',
          method: 'POST', body: {'model': item['model'], 'id': item['id']});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item['repr']} permanently deleted.')));
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _emptyBin() async {
    final typed = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Empty Recycle Bin', style: TextStyle(color: context.semanticColors.danger)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently deletes everything currently in the recycle bin (${_items.length} item${_items.length == 1 ? '' : 's'}). '
                'None of it can be restored afterwards. This is the one truly irreversible action in this app.',
              ),
              const SizedBox(height: 16),
              Text('Type DELETE to confirm:', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: typed,
                autofocus: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'DELETE'),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.semanticColors.danger),
              onPressed: typed.text.trim() == 'DELETE' ? () => Navigator.pop(context, true) : null,
              child: const Text('Empty Recycle Bin'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => _emptying = true);
    try {
      final result = await _api.request('/api/core/recycle-bin/empty/', method: 'POST', body: {}) as Map<String, dynamic>;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Permanently deleted ${result['purged_count']} item(s).')));
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _emptying = false);
    }
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return raw.toString();
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recycle Bin')),
      floatingActionButton: _items.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _emptying ? null : _emptyBin,
              backgroundColor: context.semanticColors.danger,
              foregroundColor: Colors.white,
              icon: _emptying
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.delete_forever_outlined),
              label: const Text('Empty Recycle Bin'),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!))])
                : _items.isEmpty
                    ? ListView(
                        children: const [
                          Padding(
                            padding: EdgeInsets.only(top: 80),
                            child: Center(child: Text('Recycle bin is empty.')),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final item = _items[i] as Map<String, dynamic>;
                          final model = item['model'] as String;
                          final busy = _busyKey == _key(item);
                          return Card(
                            child: ListTile(
                              title: Text(item['repr']?.toString() ?? ''),
                              subtitle: Text(
                                'Deleted ${_formatDate(item['deleted_at'])}'
                                '${item['deleted_by'] != null ? ' by ${item['deleted_by']}' : ''}',
                              ),
                              leading: TagPill(
                                label: _modelLabels[model] ?? model,
                                color: context.semanticColors.neutral,
                              ),
                              trailing: busy
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.restore_outlined),
                                          tooltip: 'Restore',
                                          onPressed: () => _restore(item),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete_forever_outlined, color: context.semanticColors.danger),
                                          tooltip: 'Permanently delete',
                                          onPressed: () => _purge(item),
                                        ),
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
