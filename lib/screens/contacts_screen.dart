import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/pdf_helper.dart';
import '../theme/app_semantic_colors.dart';
import '../widgets/gradient_fab.dart';
import 'contact_form_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Customers'), Tab(text: 'Suppliers')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _ContactList(kind: ContactKind.customer),
              _ContactList(kind: ContactKind.supplier),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactList extends StatefulWidget {
  final ContactKind kind;
  const _ContactList({required this.kind});

  @override
  State<_ContactList> createState() => _ContactListState();
}

class _ContactListState extends State<_ContactList> {
  final _searchController = TextEditingController();
  List<dynamic> _items = [];
  bool _loading = true;

  String get _endpoint => widget.kind == ContactKind.customer ? '/api/crm/customers/' : '/api/purchase/suppliers/';
  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([String? q]) async {
    setState(() => _loading = true);
    try {
      final qs = q != null && q.isNotEmpty ? '?search=${Uri.encodeComponent(q)}' : '';
      final data = await _api.request('$_endpoint$qs');
      if (mounted) setState(() => _items = data as List<dynamic>);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => ContactFormScreen(kind: widget.kind, existing: existing)),
    );
    if (saved == true) _load(_searchController.text);
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    final id = item['id'];
    final name = item['name'] as String;
    final outstanding = double.tryParse(item['outstanding_balance']?.toString() ?? '0') ?? 0;
    List<dynamic> ledger = [];
    try {
      ledger = await _api.request('$_endpoint$id/ledger/') as List<dynamic>;
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleLarge),
              Text(
                'Outstanding: Rs. ${outstanding.toStringAsFixed(2)}',
                style: TextStyle(
                  color: outstanding > 0
                      ? context.semanticColors.warning
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Record Payment'),
                    onPressed: () async {
                      Navigator.pop(context);
                      await _recordPayment(item, outstanding);
                    },
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Ledger PDF'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await downloadAndOpenPdf(_api, '$_endpoint$id/ledger/pdf/', '$name-ledger.pdf');
                      } catch (e) {
                        if (mounted) messenger.showSnackBar(SnackBar(content: Text('$e')));
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Ledger', style: Theme.of(context).textTheme.titleSmall),
              Expanded(
                child: ledger.isEmpty
                    ? const Center(child: Text('No transactions yet.'))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: ledger.length,
                        itemBuilder: (context, i) {
                          final e = ledger[i] as Map<String, dynamic>;
                          final debit = double.tryParse(e['debit_amount']?.toString() ?? '0') ?? 0;
                          final credit = double.tryParse(e['credit_amount']?.toString() ?? '0') ?? 0;
                          return ListTile(
                            dense: true,
                            title: Text(e['description']?.toString() ?? ''),
                            subtitle: Text(e['transaction_date']?.toString() ?? ''),
                            trailing: Text(
                              debit > 0 ? '+Rs. $debit' : '-Rs. $credit',
                              style: TextStyle(
                                color: debit > 0 ? context.semanticColors.danger : context.semanticColors.success,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _recordPayment(Map<String, dynamic> item, double outstanding) async {
    final hasOutstanding = outstanding > 0;
    final amountController = TextEditingController(text: hasOutstanding ? outstanding.toStringAsFixed(2) : '');
    var paymentType = hasOutstanding ? 'full' : 'partial'; // 'full' or 'partial'
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'full', label: Text('Full Amount')),
                  ButtonSegment(value: 'partial', label: Text('Partial Amount')),
                ],
                selected: {paymentType},
                onSelectionChanged: (selection) => setDialogState(() {
                  paymentType = selection.first;
                  amountController.text = paymentType == 'full' ? outstanding.toStringAsFixed(2) : '';
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                enabled: paymentType == 'partial',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  hintText: paymentType == 'partial' ? 'Amount received' : null,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Record')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final endpoint = widget.kind == ContactKind.customer ? '/api/sales/payments/' : '/api/purchase/purchase-payments/';
      final body = widget.kind == ContactKind.customer
          ? {
              'customer': item['id'],
              'amount': amountController.text,
              'method': 'cash',
              'payment_date': DateTime.now().toIso8601String().substring(0, 10),
            }
          : {
              'supplier': item['id'],
              'amount': amountController.text,
              'payment_method': 'cash',
              'payment_date': DateTime.now().toIso8601String().substring(0, 10),
            };
      await _api.request(endpoint, method: 'POST', body: body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment recorded.')));
      }
      _load(_searchController.text);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: GradientFab(
        onPressed: () => _openForm(),
        tooltip: 'Add contact',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search by name, phone...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => _load(_searchController.text)),
              ),
              onSubmitted: _load,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('Nothing here yet.'))
                    : RefreshIndicator(
                        onRefresh: () => _load(_searchController.text),
                        child: ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, i) {
                            final item = _items[i] as Map<String, dynamic>;
                            final outstanding = double.tryParse(item['outstanding_balance']?.toString() ?? '0') ?? 0;
                            return ListTile(
                              title: Text(item['name'] as String? ?? ''),
                              subtitle: Text(item['phone']?.toString() ?? ''),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (outstanding > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text(
                                        'Rs. ${outstanding.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          color: context.semanticColors.warning,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: () => _openForm(item),
                                  ),
                                ],
                              ),
                              onTap: () => _openDetail(item),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
