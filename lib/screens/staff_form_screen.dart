import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';

class Role {
  final int id;
  final String name;
  Role(this.id, this.name);
}

/// Full-page add/edit form for a staff account - mirrors the web app's Settings page
/// (same /api/auth/users/ + /api/auth/roles/ endpoints), so roles created there
/// (Owner/Manager/Cashier/Salesman/Warehouse) show up here too.
class StaffFormScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final bool isSelf;
  const StaffFormScreen({super.key, this.existing, this.isSelf = false});

  @override
  State<StaffFormScreen> createState() => _StaffFormScreenState();
}

class _StaffFormScreenState extends State<StaffFormScreen> {
  late final _firstName = TextEditingController(text: widget.existing?['first_name'] ?? '');
  late final _lastName = TextEditingController(text: widget.existing?['last_name'] ?? '');
  late final _email = TextEditingController(text: widget.existing?['email'] ?? '');
  final _password = TextEditingController();
  List<Role> _roles = [];
  int? _roleId;
  late bool _active = widget.existing?['is_active'] ?? true;
  bool _saving = false;
  bool _loadingRoles = true;

  bool get _isEdit => widget.existing != null;
  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _roleId = widget.existing?['role'];
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    try {
      final data = await _api.request('/api/auth/roles/') as List<dynamic>;
      if (mounted) {
        setState(() {
          _roles = data.map((r) => Role(r['id'] as int, r['name'] as String)).toList();
          _roleId ??= _roles.isNotEmpty ? _roles.first.id : null;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingRoles = false);
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (!_isEdit && (_email.text.trim().isEmpty || _password.text.isEmpty || _roleId == null)) {
      messenger.showSnackBar(const SnackBar(content: Text('Email, role, and password are required.')));
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        final body = <String, dynamic>{
          'first_name': _firstName.text.trim(),
          'last_name': _lastName.text.trim(),
          'role': _roleId,
          'is_active': _active,
        };
        if (_password.text.isNotEmpty) body['password'] = _password.text;
        await _api.request('/api/auth/users/${widget.existing!['id']}/', method: 'PATCH', body: body);
        messenger.showSnackBar(const SnackBar(content: Text('Staff account updated.')));
      } else {
        await _api.request('/api/auth/users/', method: 'POST', body: {
          'email': _email.text.trim(),
          'first_name': _firstName.text.trim(),
          'last_name': _lastName.text.trim(),
          'role': _roleId,
          'password': _password.text,
        });
        messenger.showSnackBar(const SnackBar(content: Text('Staff account created.')));
      }
      navigator.pop(true);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Staff' : 'Add Staff')),
      body: _loadingRoles
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(controller: _firstName, decoration: const InputDecoration(labelText: 'First name')),
                const SizedBox(height: 12),
                TextField(controller: _lastName, decoration: const InputDecoration(labelText: 'Last name')),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  enabled: !_isEdit,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: 'Email', helperText: _isEdit ? 'Email can\'t be changed' : null),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _roleId,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: _roles.map((r) => DropdownMenuItem(value: r.id, child: Text(r.name))).toList(),
                  onChanged: (v) => setState(() => _roleId = v),
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Active', style: TextStyle(fontWeight: FontWeight.w500)),
                              Text('Inactive staff can\'t log in.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        Switch(
                          value: _active,
                          onChanged: widget.isSelf ? null : (v) => setState(() => _active = v),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isSelf)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('You can\'t deactivate your own account.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _isEdit ? 'Reset password (optional)' : 'Password',
                    hintText: _isEdit ? 'Leave blank to keep current password' : null,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(_saving ? 'Saving...' : (_isEdit ? 'Save Changes' : 'Create Account')),
                ),
              ],
            ),
    );
  }
}
