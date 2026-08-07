import 'package:flutter/material.dart';

/// One shared rounded status/label badge - replaces three independent ad hoc pill
/// implementations that used to live in invoices_screen.dart (status text),
/// search_screen.dart (result-type badge), and staff_screen.dart (active/inactive).
class TagPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color? background;
  const TagPill({super.key, required this.label, required this.color, this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
