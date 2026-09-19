import 'package:flutter/material.dart';
import '../services/api_client.dart';

/// Lets the user pick one or more specific IMEI/serial units already in stock for a
/// tracked product - used when adding a product to a sale by name search rather than by
/// scanning a specific unit (POS's scan-to-search flow already returns per-unit
/// results). Only status="available" units are offered, matching the backend's own
/// availability check on submit. Returns the selected units (each `{'id', 'identifier'}`)
/// or null if cancelled.
Future<List<Map<String, dynamic>>?> showTrackingUnitPicker(
  BuildContext context, {
  required ApiClient api,
  required int productId,
  required String productName,
}) {
  return showModalBottomSheet<List<Map<String, dynamic>>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _TrackingUnitPickerSheet(api: api, productId: productId, productName: productName),
  );
}

class _TrackingUnitPickerSheet extends StatefulWidget {
  final ApiClient api;
  final int productId;
  final String productName;
  const _TrackingUnitPickerSheet({required this.api, required this.productId, required this.productName});

  @override
  State<_TrackingUnitPickerSheet> createState() => _TrackingUnitPickerSheetState();
}

class _TrackingUnitPickerSheetState extends State<_TrackingUnitPickerSheet> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _units = [];
  bool _loading = true;
  final Map<int, String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    setState(() => _loading = true);
    try {
      final qs = StringBuffer('product=${widget.productId}&status=available');
      if (q.trim().isNotEmpty) qs.write('&search=${Uri.encodeComponent(q.trim())}');
      final data = await widget.api.request('/api/products/tracking/?$qs');
      final results = data is List ? data : (data['results'] as List<dynamic>);
      if (mounted) setState(() => _units = results.cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _identifierOf(Map<String, dynamic> unit) {
    final ti = unit['tracking_identifier'] as Map<String, dynamic>?;
    return ti?['value']?.toString() ?? '#${unit['id']}';
  }

  void _toggle(Map<String, dynamic> unit) {
    final id = unit['id'] as int;
    setState(() {
      if (_selected.containsKey(id)) {
        _selected.remove(id);
      } else {
        _selected[id] = _identifierOf(unit);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select units — ${widget.productName}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(labelText: 'Search IMEI/serial...', border: OutlineInputBorder()),
            onSubmitted: _load,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: _loading
                ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                : _units.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No available units in stock for this product.'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final unit in _units)
                            CheckboxListTile(
                              value: _selected.containsKey(unit['id'] as int),
                              onChanged: (_) => _toggle(unit),
                              title: Text(_identifierOf(unit), style: const TextStyle(fontFamily: 'monospace')),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                        ],
                      ),
          ),
          const SizedBox(height: 8),
          Text('${_selected.length} unit${_selected.length == 1 ? '' : 's'} selected.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                            context,
                            _selected.entries.map((e) => {'id': e.key, 'identifier': e.value}).toList(),
                          ),
                  child: Text('Add ${_selected.isEmpty ? '' : _selected.length} unit${_selected.length == 1 ? '' : 's'}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
