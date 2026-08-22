import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';

const Map<String, String> _fieldByMethod = {
  'imei': 'imei_number',
  'serial': 'serial_number',
  'barcode': 'barcode',
  'batch': 'batch_number',
};

/// A tracking unit's code (IMEI/serial/barcode/batch), editable in place only while the
/// unit is still "available" - the backend (products.api_views.ProductTrackingViewSet.
/// perform_update) enforces the same rule, this just avoids offering an edit control
/// that would only fail once already sold. Mirrors the web frontend's
/// tracking-code-editor.tsx exactly, including which detail views it's meant for: only
/// Bill/Invoice Edit screens, not read-only Detail views.
class TrackingCodeEditor extends StatefulWidget {
  final int id;
  final String? code;
  final String status;
  final String trackingMethod;
  final ValueChanged<String>? onSaved;

  const TrackingCodeEditor({
    super.key,
    required this.id,
    required this.code,
    required this.status,
    required this.trackingMethod,
    this.onSaved,
  });

  @override
  State<TrackingCodeEditor> createState() => _TrackingCodeEditorState();
}

class _TrackingCodeEditorState extends State<TrackingCodeEditor> {
  bool _editing = false;
  bool _saving = false;
  late final TextEditingController _controller = TextEditingController(text: widget.code ?? '');

  ApiClient get _api => context.read<AuthService>().api;
  bool get _editable => widget.status == 'available';
  String get _field => _fieldByMethod[widget.trackingMethod] ?? 'imei_number';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Code can't be empty.")));
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.request('/api/products/tracking/${widget.id}/', method: 'PATCH', body: {_field: trimmed});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tracking code updated.')));
        setState(() => _editing = false);
        widget.onSaved?.call(trimmed);
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 140,
            height: 32,
            child: TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_saving,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
              onSubmitted: (_) => _save(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check, size: 16),
            visualDensity: VisualDensity.compact,
            onPressed: _saving ? null : _save,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            onPressed: _saving
                ? null
                : () => setState(() {
                      _controller.text = widget.code ?? '';
                      _editing = false;
                    }),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.code ?? '—',
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
        if (_editable)
          IconButton(
            icon: const Icon(Icons.edit, size: 14),
            visualDensity: VisualDensity.compact,
            tooltip: 'Correct this code',
            onPressed: () => setState(() => _editing = true),
          ),
      ],
    );
  }
}
