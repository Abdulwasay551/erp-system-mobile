import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import 'staff_form_screen.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  List<dynamic> _users = [];
  bool _loading = true;
  String? _error;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.request('/api/auth/users/') as List<dynamic>;
      if (mounted) setState(() => _users = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final currentUserId = context.read<AuthService>().user?.id;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => StaffFormScreen(existing: existing, isSelf: existing != null && existing['id'] == currentUserId),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.person_add_alt),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!))])
                : _users.isEmpty
                    ? const Center(child: Text('No staff accounts yet.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _users.length,
                        itemBuilder: (context, i) {
                          final u = _users[i] as Map<String, dynamic>;
                          final active = u['is_active'] == true;
                          final scheme = Theme.of(context).colorScheme;
                          return Card(
                            child: ListTile(
                              title: Text('${u['first_name']} ${u['last_name']}'.trim().isEmpty ? u['email'] : '${u['first_name']} ${u['last_name']}'),
                              subtitle: Text('${u['email']} · ${u['role_name'] ?? ''}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: active ? scheme.primary : scheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      active ? 'Active' : 'Inactive',
                                      style: TextStyle(fontSize: 11, color: active ? scheme.onPrimary : scheme.onSurfaceVariant),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: () => _openForm(u),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
