import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';

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

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<dynamic> _expenses = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final month = DateTime.now().toIso8601String().substring(0, 7);
    try {
      final expenses = await _api.request('/api/accounting/expenses/');
      final summary = await _api.request('/api/accounting/expenses/summary/?month=$month');
      if (mounted) {
        setState(() {
          _expenses = expenses as List<dynamic>;
          _summary = summary as Map<String, dynamic>;
        });
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
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
                            const Text('This Month'),
                            Text('Rs. ${_summary!['grand_total']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (_expenses.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('No expenses recorded yet.')),
                    )
                  else
                    ..._expenses.map((e) {
                      final expense = e as Map<String, dynamic>;
                      return Card(
                        child: ListTile(
                          title: Text(expense['category_display'] as String),
                          subtitle: Text('${expense['expense_date']}${expense['description'] != null && (expense['description'] as String).isNotEmpty ? ' · ${expense['description']}' : ''}'),
                          trailing: Text('Rs. ${expense['amount']}'),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
