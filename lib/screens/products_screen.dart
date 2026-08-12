import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/connectivity_service.dart';
import '../widgets/gradient_fab.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/offline_banner.dart';
import 'product_form_screen.dart';

const _sortOptions = [
  ('name', 'Name'),
  ('-created_at', 'Newest'),
  ('sku', 'SKU'),
];

/// Product catalog screen: search, add/edit/delete - the mobile counterpart to the web
/// app's Products page, reachable from the overflow menu.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchController = TextEditingController();
  List<dynamic> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String _ordering = _sortOptions.first.$1;
  DateTime? _cachedAt;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    };
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    final online = context.read<ConnectivityService>().isOnline;
    try {
      final cached = await _api.requestCached('/api/products/products/?$qs', isOnline: online);
      if (cached == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load products.')));
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
      MaterialPageRoute(builder: (context) => ProductFormScreen(existing: existing)),
    );
    if (saved == true) _load(q: _searchController.text);
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final confirmed = await confirmDelete(context, itemLabel: item['name'] as String?);
    if (!confirmed) return;
    try {
      await _api.request('/api/products/products/${item['id']}/', method: 'DELETE');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product deleted.')));
      _load(q: _searchController.text);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthService>().isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      floatingActionButton: GradientFab(
        onPressed: () => _openForm(),
        tooltip: 'Add product',
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
                labelText: 'Search by name, SKU...',
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
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Sort by',
                  onSelected: (v) {
                    setState(() => _ordering = v);
                    _load(q: _searchController.text);
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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('No products yet.'))
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
                            return ListTile(
                              title: Text(item['name'] as String? ?? ''),
                              subtitle: Text([
                                if ((item['sku'] as String?)?.isNotEmpty == true) item['sku'],
                                if ((item['category_name'] as String?)?.isNotEmpty == true) item['category_name'],
                              ].join(' · ')),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Rs. ${item['selling_price']}'),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: () => _openForm(item),
                                  ),
                                  if (isAdmin) DeleteIconButton(onPressed: () => _deleteItem(item)),
                                ],
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
