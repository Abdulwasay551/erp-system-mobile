import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../screens/contact_form_screen.dart' show ContactKind;

/// Record Payment and Debit/Credit Adjustment dialogs for a customer/supplier -
/// extracted out of contacts_screen.dart so both the list's row-tap flow and
/// ContactDetailScreen call the exact same code instead of two copies. Returns true if
/// something was actually recorded (caller should refresh), false/null otherwise.
Future<bool> recordContactPayment(
  BuildContext context, {
  required ApiClient api,
  required bool online,
  required ContactKind kind,
  required Map<String, dynamic> item,
  required double outstanding,
}) async {
  final hasOutstanding = outstanding > 0;
  final amountController = TextEditingController(text: hasOutstanding ? outstanding.toStringAsFixed(2) : '');
  var paymentType = hasOutstanding ? 'full' : 'partial';
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
  if (confirmed != true) return false;
  if (!context.mounted) return false;
  try {
    final endpoint = kind == ContactKind.customer ? '/api/sales/payments/' : '/api/purchase/purchase-payments/';
    final body = kind == ContactKind.customer
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
    final result = await api.enqueueOrSend(
      isOnline: online,
      queueType: 'record_payment',
      path: endpoint,
      body: body,
      summary: 'Payment - Rs. ${amountController.text} - ${item['name']}',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.queued ? 'Payment saved offline - will sync automatically.' : 'Payment recorded.'),
      ));
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

Future<bool> recordContactAdjustment(
  BuildContext context, {
  required ApiClient api,
  required bool online,
  required ContactKind kind,
  required Map<String, dynamic> item,
}) async {
  final amountController = TextEditingController();
  final referenceController = TextEditingController();
  final descriptionController = TextEditingController();
  var entryType = 'debit';
  var method = 'cash';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Ledger Adjustment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'debit', label: Text('Debit')),
                  ButtonSegment(value: 'credit', label: Text('Credit')),
                ],
                selected: {entryType},
                onSelectionChanged: (selection) => setDialogState(() => entryType = selection.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Payment Method'),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                  DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                  DropdownMenuItem(value: 'credit_card', child: Text('Credit Card')),
                  DropdownMenuItem(value: 'online', child: Text('Online Payment')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setDialogState(() => method = v ?? 'cash'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: referenceController,
                decoration: const InputDecoration(labelText: 'Reference (optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description / Reason'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (confirmed != true) return false;
  if (!context.mounted) return false;
  if (amountController.text.trim().isEmpty || (double.tryParse(amountController.text) ?? 0) <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
    return false;
  }
  if (descriptionController.text.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A description/reason is required.')));
    return false;
  }
  try {
    final endpoint =
        kind == ContactKind.customer ? '/api/crm/customer-ledger-adjustments/' : '/api/purchase/supplier-ledger-adjustments/';
    final body = {
      kind == ContactKind.customer ? 'customer' : 'supplier': item['id'],
      'entry_type': entryType,
      'amount': amountController.text,
      'payment_method': method,
      if (referenceController.text.trim().isNotEmpty) 'reference': referenceController.text.trim(),
      'description': descriptionController.text.trim(),
      'transaction_date': DateTime.now().toIso8601String().substring(0, 10),
    };
    final result = await api.enqueueOrSend(
      isOnline: online,
      queueType: 'ledger_adjustment',
      path: endpoint,
      body: body,
      summary: '${entryType == 'debit' ? 'Debit' : 'Credit'} - Rs. ${amountController.text} - ${item['name']}',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.queued ? 'Adjustment saved offline - will sync automatically.' : 'Adjustment recorded.'),
      ));
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}
