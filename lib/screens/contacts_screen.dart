import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/connectivity_service.dart';
import '../theme/app_semantic_colors.dart';
import '../widgets/gradient_fab.dart';
import '../widgets/offline_banner.dart';
import 'contact_form_screen.dart';
import 'contact_detail_screen.dart';

const _customerSortOptions = [
  ('name', 'Name'),
  ('-created_at', 'Newest'),
  ('customer_code', 'Code'),
];

const _supplierSortOptions = [
  ('partner__name', 'Name'),
  ('-created_at', 'Newest'),
  ('-overall_rating', 'Rating'),
];

const _supplierTypeOptions = [
  (null, 'All types'),
  ('distributor', 'Distributor'),
  ('wholesaler', 'Wholesaler'),
  ('manufacturer', 'Manufacturer'),
  ('retailer', 'Retailer'),
  ('other', 'Other'),
];

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Customers'), Tab(text: 'Suppliers')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _ContactList(kind: ContactKind.customer),
              _ContactList(kind: ContactKind.supplier),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactList extends StatefulWidget {
  final ContactKind kind;
  const _ContactList({required this.kind});

  @override
  State<_ContactList> createState() => _ContactListState();
}

class _ContactListState extends State<_ContactList> {
  final _searchController = TextEditingController();
  List<dynamic> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _supplierType;
  late String _ordering = widget.kind == ContactKind.customer ? _customerSortOptions.first.$1 : _supplierSortOptions.first.$1;
  DateTime? _cachedAt;

  String get _endpoint => widget.kind == ContactKind.customer ? '/api/crm/customers/' : '/api/purchase/suppliers/';
  bool get _isCustomer => widget.kind == ContactKind.customer;
  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? q, bool reset = true}) async {
    setState(() {
      if (reset) {
        _page = 1;
        _loading = true;
      } else {
        _loadingMore = true;
      }
    });
    final search = q ?? _searchController.text;
    final params = {
      'page': '$_page',
      'ordering': _ordering,
      if (search.isNotEmpty) 'search': search,
      if (!_isCustomer && _supplierType != null) 'supplier_type': _supplierType!,
    };
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    final online = context.read<ConnectivityService>().isOnline;
    try {
      final cached = await _api.requestCached('$_endpoint?$qs', isOnline: online);
      if (cached == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed to load ${_isCustomer ? "customers" : "suppliers"}.')));
        }
      } else {
        final data = cached.data as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>;
        if (mounted) {
          setState(() {
            _items = reset ? results : [..._items, ...results];
            _hasMore = data['next'] != null;
            _cachedAt = cached.fromCache ? cached.cachedAt : null;
          });
        }
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = _loadingMore = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    _page++;
    await _load(q: _searchController.text, reset: false);
  }

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => ContactFormScreen(kind: widget.kind, existing: existing)),
    );
    if (saved == true) _load(q: _searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    final sortOptions = _isCustomer ? _customerSortOptions : _supplierSortOptions;
    return Scaffold(
      floatingActionButton: GradientFab(
        onPressed: () => _openForm(),
        tooltip: 'Add contact',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (_cachedAt != null) OfflineDataBanner(cachedAt: _cachedAt!),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search by name, phone...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => _load(q: _searchController.text)),
              ),
              onSubmitted: (v) => _load(q: v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                if (!_isCustomer)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final (value, label) in _supplierTypeOptions) ...[
                            ChoiceChip(
                              label: Text(label),
                              selected: _supplierType == value,
                              onSelected: (_) {
                                setState(() => _supplierType = value);
                                _load(q: _searchController.text);
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Sort by',
                  onSelected: (v) {
                    setState(() => _ordering = v);
                    _load(q: _searchController.text);
                  },
                  itemBuilder: (context) => [
                    for (final (value, label) in sortOptions)
                      CheckedPopupMenuItem(value: value, checked: _ordering == value, child: Text(label)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('Nothing here yet.'))
                    : RefreshIndicator(
                        onRefresh: () => _load(q: _searchController.text),
                        child: ListView.builder(
                          itemCount: _items.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == _items.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: _loadingMore
                                      ? const CircularProgressIndicator()
                                      : TextButton(onPressed: _loadMore, child: const Text('Load more')),
                                ),
                              );
                            }
                            final item = _items[i] as Map<String, dynamic>;
                            final outstanding = double.tryParse(item['outstanding_balance']?.toString() ?? '0') ?? 0;
                            return ListTile(
                              title: Text(item['name'] as String? ?? ''),
                              subtitle: Text(item['phone']?.toString() ?? ''),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (outstanding > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text(
                                        'Rs. ${outstanding.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          color: context.semanticColors.warning,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: () => _openForm(item),
                                  ),
                                ],
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => ContactDetailScreen(kind: widget.kind, contact: item)),
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
