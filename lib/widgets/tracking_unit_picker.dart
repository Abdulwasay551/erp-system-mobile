import 'package:flutter/material.dart';
import '../services/api_client.dart';

const _imeiLength = 15;

/// Lets a user pick one or more specific IMEI/serial units already in stock for a
/// tracked product - used both by POS (instead of silently attaching whichever unit a
/// name/scan search happened to match first) and by the invoice edit screen's "add by
/// name" flow. Only status="available" units are offered, matching the backend's own
/// availability check on submit - selection is always an explicit, deliberate step,
/// never automatic. Returns the selected units (each `{'id', 'identifier'}`) or null if
/// cancelled.
///
/// Also validates IMEI format client-side (exactly 15 digits) before searching, and -
/// if a typed/scanned code matches no *available* unit for this product - runs a
/// second, unscoped lookup so the error explains why (wrong product, already sold/
/// returned, or genuinely not found) instead of just showing an empty list.
Future<List<Map<String, dynamic>>?> showTrackingUnitPicker(
  BuildContext context, {
  required ApiClient api,
  required int productId,
  required String productName,
  required String trackingMethod,
  String? initialQuery,
}) {
  return showModalBottomSheet<List<Map<String, dynamic>>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _TrackingUnitPickerSheet(
      api: api,
      productId: productId,
      productName: productName,
      trackingMethod: trackingMethod,
      initialQuery: initialQuery,
    ),
  );
}

class _TrackingUnitPickerSheet extends StatefulWidget {
  final ApiClient api;
  final int productId;
  final String productName;
  final String trackingMethod;
  final String? initialQuery;
  const _TrackingUnitPickerSheet({
    required this.api,
    required this.productId,
    required this.productName,
    required this.trackingMethod,
    this.initialQuery,
  });

  @override
  State<_TrackingUnitPickerSheet> createState() => _TrackingUnitPickerSheetState();
}

class _TrackingUnitPickerSheetState extends State<_TrackingUnitPickerSheet> {
  late final _searchController = TextEditingController(text: widget.initialQuery ?? '');
  List<Map<String, dynamic>> _units = [];
  bool _loading = true;
  final Map<int, String> _selected = {};
  String? _formatError;
  String? _conflict;

  @override
  void initState() {
    super.initState();
    _load(widget.initialQuery ?? '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _checkFormat(String q) {
    final trimmed = q.trim();
    final isAllDigits = trimmed.isNotEmpty && RegExp(r'^\d+$').hasMatch(trimmed);
    if (widget.trackingMethod == 'imei' && isAllDigits && trimmed.length != _imeiLength) {
      setState(() => _formatError = 'An IMEI must be exactly $_imeiLength digits (got ${trimmed.length}).');
      return false;
    }
    setState(() => _formatError = null);
    return true;
  }

  Future<void> _load(String q) async {
    setState(() {
      _conflict = null;
      _units = [];
    });
    if (!_checkFormat(q)) return;
    setState(() => _loading = true);
    try {
      final qs = StringBuffer('product=${widget.productId}&status=available');
      if (q.trim().isNotEmpty) qs.write('&search=${Uri.encodeComponent(q.trim())}');
      final data = await widget.api.request('/api/products/tracking/?$qs');
      final results = (data is List ? data : (data['results'] as List<dynamic>)).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _units = results);
      if (results.isEmpty && q.trim().isNotEmpty) await _explainConflict(q.trim());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A specific code was typed/scanned but matched no available unit for this product -
  /// look it up without the product/status filter to explain why, instead of leaving the
  /// user with just an empty list.
  Future<void> _explainConflict(String code) async {
    try {
      final data = await widget.api.request('/api/products/tracking/?search=${Uri.encodeComponent(code)}');
      final matches = (data is List ? data : (data['results'] as List<dynamic>)).cast<Map<String, dynamic>>();
      Map<String, dynamic>? exact;
      for (final m in matches) {
        final ti = m['tracking_identifier'] as Map<String, dynamic>?;
        if (ti != null && ti['value'] == code) {
          exact = m;
          break;
        }
      }
      exact ??= matches.isNotEmpty ? matches.first : null;
      if (!mounted) return;
      if (exact == null) {
        setState(() => _conflict = '"$code" was not found in tracking records at all.');
      } else if (exact['product'] != widget.productId) {
        setState(() => _conflict = '"$code" belongs to a different product (${exact!['product_name']}), not ${widget.productName}.');
      } else {
        setState(() => _conflict = '"$code" is already ${exact!['status']} - it can\'t be sold again.');
      }
    } catch (_) {
      // Best-effort explanation only - the empty list above is still a correct result.
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
            autofocus: true,
            decoration: InputDecoration(
              labelText: widget.trackingMethod == 'imei' ? 'Scan or type a 15-digit IMEI...' : 'Search serial/code...',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: _load,
          ),
          if (_formatError != null) ...[
            const SizedBox(height: 6),
            Text(_formatError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ],
          if (_conflict != null && _formatError == null) ...[
            const SizedBox(height: 6),
            Text(_conflict!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ],
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: _loading
                ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                : _units.isEmpty
                    ? (_conflict == null && _formatError == null
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No available units in stock for this product.'),
                          )
                        : const SizedBox.shrink())
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
