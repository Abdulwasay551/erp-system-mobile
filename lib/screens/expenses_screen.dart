import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../widgets/confirm_delete_dialog.dart';

const _categories = [
  ('rent', 'Rent'),
  ('salary', 'Salary'),
  ('utilities', 'Utilities'),
  ('petrol', 'Petrol/Fuel'),
  ('maintenance', 'Maintenance'),
  ('supplies', 'Office Supplies'),
  ('marketing', 'Marketing'),
  ('other', 'Other'),
];

const _categoryFilterOptions = [(null, 'All categories'), ..._categories];

const _sortOptions = [
  ('-expense_date', 'Date (newest)'),
  ('expense_date', 'Date (oldest)'),
  ('-amount', 'Amount (high-low)'),
  ('amount', 'Amount (low-high)'),
];

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<dynamic> _expenses = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _category;
  String _ordering = '-expense_date';

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
    });
    final month = DateTime.now().toIso8601String().substring(0, 7);
    final params = {
      'page': '$_page',
      'ordering': _ordering,
      if (_category != null) 'category': _category!,
    };
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    try {
      final expenses = await _api.request('/api/accounting/expenses/?$qs') as Map<String, dynamic>;
      final summary = await _api.request('/api/accounting/expenses/summary/?month=$month');
      final results = expenses['results'] as List<dynamic>;
      if (mounted) {
        setState(() {
          _expenses = reset ? results : [..._expenses, ...results];
          _hasMore = expenses['next'] != null;
          _summary = summary as Map<String, dynamic>;
        });
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = _loadingMore = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    _page++;
    await _load(reset: false);
  }

  Future<void> _deleteExpense(Map<String, dynamic> expense) async {
    final confirmed = await confirmDelete(context, itemLabel: expense['category_display'] as String?);
    if (!confirmed) return;
    try {
      await _api.request('/api/accounting/expenses/${expense['id']}/', method: 'DELETE');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense deleted.')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openAddDialog() async {
    String category = 'rent';
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Expense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories.map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2))).toList(),
                onChanged: (v) => setDialogState(() => category = v ?? 'rent'),
              ),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: category == 'other' ? 'Description (required for Other)' : 'Description (optional)',
                ),
              ),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    if (amountController.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an amount.')));
      return;
    }
    try {
      await _api.request('/api/accounting/expenses/', method: 'POST', body: {
        'category': category,
        'description': descriptionController.text,
        'amount': amountController.text,
        'payment_method': 'cash',
        'expense_date': DateTime.now().toIso8601String().substring(0, 10),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense recorded.')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthService>().isAdmin;
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _openAddDialog, child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_summary != null)
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'This Month',
                              style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
                            ),
                            Text(
                              'Rs. ${_summary!['grand_total']}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final (value, label) in _categoryFilterOptions) ...[
                                ChoiceChip(
                                  label: Text(label),
                                  selected: _category == value,
                                  onSelected: (_) {
                                    setState(() => _category = value);
                                    _load();
                                  },
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.sort),
                        tooltip: 'Sort by',
                        onSelected: (v) {
                          setState(() => _ordering = v);
                          _load();
                        },
                        itemBuilder: (context) => [
                          for (final (value, label) in _sortOptions)
                            CheckedPopupMenuItem(value: value, checked: _ordering == value, child: Text(label)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_expenses.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('No expenses recorded yet.')),
                    )
                  else ...[
                    ..._expenses.map((e) {
                      final expense = e as Map<String, dynamic>;
                      return Card(
                        child: ListTile(
                          title: Text(expense['category_display'] as String),
                          subtitle: Text('${expense['expense_date']}${expense['description'] != null && (expense['description'] as String).isNotEmpty ? ' · ${expense['description']}' : ''}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Rs. ${expense['amount']}'),
                              if (isAdmin) DeleteIconButton(onPressed: () => _deleteExpense(expense)),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (_hasMore)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: _loadingMore
                              ? const CircularProgressIndicator()
                              : TextButton(onPressed: _loadMore, child: const Text('Load more')),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
