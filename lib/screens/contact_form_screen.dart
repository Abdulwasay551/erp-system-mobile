import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';

enum ContactKind { customer, supplier }

const _supplierTypes = [
  ('distributor', 'Distributor'),
  ('wholesaler', 'Wholesaler'),
  ('manufacturer', 'Manufacturer'),
  ('retailer', 'Retailer'),
  ('other', 'Other'),
];

/// Full-page add/edit form for a customer or supplier - replaces the old small popup
/// dialog (which only collected name/phone/one extra field) with a proper screen
/// exposing every field the backend actually accepts, matching the web app's forms.
class ContactFormScreen extends StatefulWidget {
  final ContactKind kind;
  final Map<String, dynamic>? existing;
  const ContactFormScreen({super.key, required this.kind, this.existing});

  @override
  State<ContactFormScreen> createState() => _ContactFormScreenState();
}

class _ContactFormScreenState extends State<ContactFormScreen> {
  late final _name = TextEditingController(text: widget.existing?['name'] ?? '');
  late final _phone = TextEditingController(text: widget.existing?['phone'] ?? '');
  late final _email = TextEditingController(text: widget.existing?['email'] ?? '');
  late final _cnic = TextEditingController(text: widget.existing?['cnic'] ?? '');
  late final _city = TextEditingController(text: widget.existing?['city'] ?? '');
  late final _contactPerson = TextEditingController(text: widget.existing?['contact_person'] ?? '');
  late final _address = TextEditingController(text: widget.existing?['address'] ?? '');
  late String _supplierType = widget.existing?['supplier_type'] ?? 'distributor';
  bool _saving = false;

  bool get _isEdit => widget.existing != null;
  bool get _isCustomer => widget.kind == ContactKind.customer;
  String get _endpoint => _isCustomer ? '/api/crm/customers/' : '/api/purchase/suppliers/';

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _cnic.dispose();
    _city.dispose();
    _contactPerson.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_isCustomer ? "Customer" : "Vendor"} name is required.')),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final body = _isCustomer
          ? {
              'name': _name.text.trim(),
              'phone': _phone.text.trim(),
              'email': _email.text.trim(),
              'cnic': _cnic.text.trim(),
              'address': _address.text.trim(),
            }
          : {
              'name': _name.text.trim(),
              'phone': _phone.text.trim(),
              'email': _email.text.trim(),
              'city': _city.text.trim(),
              'contact_person': _contactPerson.text.trim(),
              'address': _address.text.trim(),
              'supplier_type': _supplierType,
            };
      if (_isEdit) {
        await _api.request('$_endpoint${widget.existing!['id']}/', method: 'PATCH', body: body);
      } else {
        await _api.request(_endpoint, method: 'POST', body: body);
      }
      messenger.showSnackBar(SnackBar(
        content: Text('${_isCustomer ? "Customer" : "Vendor"} ${_isEdit ? "updated" : "added"}.'),
      ));
      navigator.pop(true);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = '${_isEdit ? "Edit" : "Add"} ${_isCustomer ? "Customer" : "Vendor"}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email (optional)'),
          ),
          const SizedBox(height: 12),
          if (_isCustomer)
            TextField(controller: _cnic, decoration: const InputDecoration(labelText: 'CNIC (optional)'))
          else ...[
            TextField(controller: _city, decoration: const InputDecoration(labelText: 'City (optional)')),
            const SizedBox(height: 12),
            TextField(controller: _contactPerson, decoration: const InputDecoration(labelText: 'Contact Person (optional)')),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Address (optional)'),
          ),
          if (!_isCustomer) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _supplierType,
              decoration: const InputDecoration(labelText: 'Vendor Type'),
              items: _supplierTypes.map((t) => DropdownMenuItem(value: t.$1, child: Text(t.$2))).toList(),
              onChanged: (v) => setState(() => _supplierType = v ?? 'distributor'),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(_saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
    );
  }
}
