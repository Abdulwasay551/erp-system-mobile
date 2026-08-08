import 'package:flutter/material.dart';

/// Mirrors the web frontend's DiscountEditor/DiscountEntry shape exactly, so the JSON
/// sent to the backend (`[{"type": "fixed"|"percent"|"per_unit", "value": "10.00"}]`)
/// is identical on both platforms.
class DiscountEntry {
  String type; // 'fixed' | 'percent' | 'per_unit'
  String value;
  DiscountEntry({this.type = 'fixed', this.value = ''});

  Map<String, dynamic> toJson() => {'type': type, 'value': value};

  DiscountEntry copy() => DiscountEntry(type: type, value: value);
}

const Map<String, String> discountTypeLabels = {
  'fixed': 'Fixed amount',
  'percent': 'Percent',
  'per_unit': 'Per unit',
};

/// Mirrors core/pricing.py's compute_line_discount exactly: sum every fixed/per_unit
/// discount first (capped at the base amount), then apply every percent discount to
/// what's left.
double computeDiscountTotal(double baseAmount, double quantity, List<DiscountEntry> discounts) {
  double flatOff = 0;
  final percents = <double>[];
  for (final d in discounts) {
    final val = double.tryParse(d.value) ?? 0;
    if (d.type == 'fixed') {
      flatOff += val;
    } else if (d.type == 'per_unit') {
      flatOff += val * quantity;
    } else if (d.type == 'percent') {
      percents.add(val);
    }
  }
  flatOff = flatOff.clamp(0, baseAmount);
  double remaining = baseAmount - flatOff;
  double percentOff = 0;
  for (final p in percents) {
    final off = remaining * (p / 100);
    percentOff += off;
    remaining -= off;
  }
  return (flatOff + percentOff).clamp(0, baseAmount);
}

/// Opens a dialog letting the user add/edit/remove multiple stacked discounts on one
/// line. Returns the edited list, or null if cancelled.
Future<List<DiscountEntry>?> showDiscountEditorDialog(
  BuildContext context, {
  required String title,
  required List<DiscountEntry> initial,
}) {
  final entries = initial.map((e) => e.copy()).toList();
  return showDialog<List<DiscountEntry>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Discounts - $title'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No discounts added.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ...entries.asMap().entries.map((e) {
                final i = e.key;
                final entry = e.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          initialValue: entry.type,
                          isDense: true,
                          isExpanded: true,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                          items: discountTypeLabels.entries
                              .map((t) => DropdownMenuItem(value: t.key, child: Text(t.value, overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) => setState(() => entry.type = v ?? 'fixed'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          initialValue: entry.value,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            isDense: true,
                            hintText: entry.type == 'percent' ? '%' : 'Rs.',
                          ),
                          onChanged: (v) => entry.value = v,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => entries.removeAt(i)),
                      ),
                    ],
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => entries.add(DiscountEntry())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add discount'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, entries), child: const Text('Done')),
        ],
      ),
    ),
  );
}
