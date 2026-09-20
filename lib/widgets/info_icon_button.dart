import 'package:flutter/material.dart';

/// A small "i" info icon that explains a potentially-confusing term or figure - e.g.
/// what "Credit" means on a customer vs. supplier ledger, or what "Outstanding" is
/// computed from. Tap to show the explanation (works the same on touch as it would on
/// a desktop click; Flutter's own long-press Tooltip is reserved for a different
/// purpose here since this needs to work reliably on mobile too). Place right next to
/// the label/value it explains, not as a replacement for it.
class InfoIconButton extends StatelessWidget {
  final String message;
  const InfoIconButton({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(Icons.info_outline, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
