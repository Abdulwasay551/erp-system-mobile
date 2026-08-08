import 'package:flutter/material.dart';
import '../theme/app_semantic_colors.dart';

/// Shared confirmation dialog for the soft-delete action offered on list rows
/// (Invoices, Bills, Customers, Suppliers, Expenses, Staff) - keeps the wording and
/// look consistent instead of five copy-pasted AlertDialogs. Returns true if the user
/// confirmed.
Future<bool> confirmDelete(BuildContext context, {String? itemLabel}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete?'),
      content: Text(
        itemLabel != null
            ? 'Delete "$itemLabel"? This moves it to the Recycle Bin, it can be restored later.'
            : 'This moves it to the Recycle Bin, it can be restored later.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: context.semanticColors.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// A small trash IconButton in the app's danger color - shown on list rows only when
/// the current user is Owner/Manager (checked by the caller before rendering).
class DeleteIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String? tooltip;
  const DeleteIconButton({super.key, required this.onPressed, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.delete_outline, size: 20, color: context.semanticColors.danger),
      tooltip: tooltip ?? 'Delete',
      onPressed: onPressed,
    );
  }
}
