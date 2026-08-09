import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'offline_db.dart';

/// Pulls the full products / available tracking units / customers / suppliers lists
/// down into the local mirror tables, so POS and vendor-invoice search still work with
/// no internet. Each table is cleared and fully repopulated in one transaction (not an
/// incremental upsert) - a product/unit sold or deleted server-side actually disappears
/// locally instead of lingering as a stale match. Triggered on login, on app resume if
/// stale, and via manual pull-to-refresh; safe to call whenever the app is online.
class ReferenceSyncService {
  static const _lastSyncKey = 'reference_data_last_synced_at';
  static const staleAfter = Duration(hours: 6);

  static Future<DateTime?> lastSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_lastSyncKey);
    return iso == null ? null : DateTime.tryParse(iso);
  }

  static Future<bool> isStale() async {
    final last = await lastSyncedAt();
    if (last == null) return true;
    return DateTime.now().difference(last) > staleAfter;
  }

  /// Fetches every page of a paginated (or plain-list) endpoint.
  static Future<List<Map<String, dynamic>>> _fetchAll(ApiClient api, String path) async {
    final items = <Map<String, dynamic>>[];
    String? next = path;
    while (next != null) {
      final data = await api.request(next);
      if (data is List) {
        items.addAll(data.cast<Map<String, dynamic>>());
        break;
      }
      final map = data as Map<String, dynamic>;
      items.addAll((map['results'] as List).cast<Map<String, dynamic>>());
      final nextUrl = map['next'] as String?;
      if (nextUrl == null) {
        next = null;
      } else {
        // request() prepends the base URL itself - DRF's `next` is a full absolute URL,
        // so only the path+query survives here.
        final nextUri = Uri.parse(nextUrl);
        next = nextUri.query.isEmpty ? nextUri.path : '${nextUri.path}?${nextUri.query}';
      }
    }
    return items;
  }

  static Future<void> syncNow(ApiClient api) async {
    final products = await _fetchAll(api, '/api/products/products/');
    final trackingUnits = await _fetchAll(api, '/api/products/tracking/?status=available');
    final customers = await _fetchAll(api, '/api/crm/customers/');
    final suppliers = await _fetchAll(api, '/api/purchase/suppliers/');
    // Product has no stock field of its own - available quantity is only ever known by
    // summing StockItem rows per product (same as pos_search does live), so fetch all
    // stock items once and aggregate here rather than one lookup per product.
    final stockItems = await _fetchAll(api, '/api/inventory/stockitems/');
    final availableByProduct = <int, double>{};
    for (final s in stockItems) {
      final productId = s['product'];
      if (productId == null) continue;
      final qty = double.tryParse(s['available_quantity']?.toString() ?? '') ?? 0;
      availableByProduct[productId as int] = (availableByProduct[productId] ?? 0) + qty;
    }

    final db = await OfflineDb.instance;
    await db.transaction((txn) async {
      await txn.delete('cached_products');
      for (final p in products) {
        await txn.insert('cached_products', {
          'id': p['id'],
          'name': p['name'],
          'sku': p['sku'],
          'brand': p['brand'],
          'barcode': p['barcode'],
          'tracking_method': p['tracking_method'] ?? 'none',
          'selling_price': p['selling_price']?.toString(),
          'cost_price': p['cost_price']?.toString(),
          'avg_purchase_price': p['cost_price']?.toString(),
          'available_qty': (availableByProduct[p['id']] ?? 0).toString(),
        });
      }

      await txn.delete('cached_tracking_units');
      // ProductTrackingSerializer's `product` field is a raw FK id, not nested - resolve
      // brand/tracking_method/default price by joining against the products list already
      // fetched above rather than adding a second round trip per unit.
      final productsById = {for (final p in products) p['id'] as int: p};
      for (final t in trackingUnits) {
        final productId = t['product'] as int?;
        final product = productId == null ? null : productsById[productId];
        await txn.insert('cached_tracking_units', {
          'id': t['id'],
          'product_id': productId,
          'product_name': t['product_name'] ?? product?['name'] ?? '',
          'brand': product?['brand'],
          'variant': t['variant_name'],
          'identifier': t['imei_number'] ?? t['serial_number'] ?? t['barcode'] ?? t['batch_number'] ?? '',
          'tracking_method': product?['tracking_method'] ?? 'imei',
          'unit_price': (t['selling_price'] ?? product?['selling_price'])?.toString(),
          'avg_purchase_price': t['purchase_price']?.toString(),
        });
      }

      await txn.delete('cached_customers');
      for (final c in customers) {
        await txn.insert('cached_customers', {'id': c['id'], 'name': c['name'], 'phone': c['phone']});
      }

      await txn.delete('cached_suppliers');
      for (final s in suppliers) {
        await txn.insert('cached_suppliers', {'id': s['id'], 'name': s['name'], 'city': s['city']});
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }
}
