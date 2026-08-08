import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../widgets/confirm_delete_dialog.dart';
import 'staff_form_screen.dart';

const _sortOptions = [
  ('email', 'Email'),
  ('first_name', 'First name'),
  ('-date_joined', 'Newest'),
];

const _activeFilterOptions = [(null, 'All'), ('true', 'Active'), ('false', 'Inactive')];

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  List<dynamic> _users = [];
  List<Role> _roles = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _isActive;
  int? _roleId;
  String _ordering = 'email';
  String? _error;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _load();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    try {
      final data = await _api.request('/api/auth/roles/') as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      if (mounted) {
        setState(() => _roles = results.map((r) => Role(r['id'] as int, r['name'] as String)).toList());
      }
    } catch (_) {}
  }

  Future<void> _load({bool reset = true}) async {
    setState(() {
      if (reset) {
        _page = 1;
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    final params = {
      'page': '$_page',
      'ordering': _ordering,
      if (_isActive != null) 'is_active': _isActive!,
      if (_roleId != null) 'role': '$_roleId',
    };
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    try {
      final data = await _api.request('/api/auth/users/?$qs') as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      if (mounted) {
        setState(() {
          _users = reset ? results : [..._users, ...results];
          _hasMore = data['next'] != null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = _loadingMore = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    _page++;
    await _load(reset: false);
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

  Future<void> _deleteUser(Map<String, dynamic> u) async {
    final label = '${u['first_name']} ${u['last_name']}'.trim();
    final confirmed = await confirmDelete(context, itemLabel: label.isEmpty ? u['email'] as String? : label);
    if (!confirmed) return;
    try {
      await _api.request('/api/auth/users/${u['id']}/', method: 'DELETE');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staff account deleted.')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthService>().isAdmin;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.person_add_alt),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (value, label) in _activeFilterOptions) ...[
                          ChoiceChip(
                            label: Text(label),
                            selected: _isActive == value,
                            onSelected: (_) {
                              setState(() => _isActive = value);
                              _load();
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (_roles.isNotEmpty) ...[
                          ChoiceChip(
                            label: const Text('All roles'),
                            selected: _roleId == null,
                            onSelected: (_) {
                              setState(() => _roleId = null);
                              _load();
                            },
                          ),
                          const SizedBox(width: 8),
                          for (final role in _roles) ...[
                            ChoiceChip(
                              label: Text(role.name),
                              selected: _roleId == role.id,
                              onSelected: (_) {
                                setState(() => _roleId = role.id);
                                _load();
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Sort by',
                  onSelected: (v) {
                    setState(() => _ordering = v);
                    _load();
                  },
                  itemBuilder: (context) => [
                    for (final (value, label) in _sortOptions)
                      CheckedPopupMenuItem(value: value, checked: _ordering == value, child: Text(label)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!))])
                      : _users.isEmpty
                          ? const Center(child: Text('No staff accounts yet.'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _users.length + (_hasMore ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (i == _users.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: _loadingMore
                                          ? const CircularProgressIndicator()
                                          : TextButton(onPressed: _loadMore, child: const Text('Load more')),
                                    ),
                                  );
                                }
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
                                        if (isAdmin) DeleteIconButton(onPressed: () => _deleteUser(u)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}
