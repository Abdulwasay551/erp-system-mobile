import 'offline_db.dart';

/// Local-mirror search, used as the offline fallback for POS/vendor-invoice search.
/// Each method returns the same shape the equivalent live endpoint returns, so the
/// calling screen doesn't need to branch on where the data came from.
class OfflineSearch {
  /// Mirrors GET /api/sales/pos/search/?q= - tracked units first (one row per unit),
  /// then untracked products with pooled quantity.
  static Future<List<Map<String, dynamic>>> posSearch(String q) async {
    final db = await OfflineDb.instance;
    final like = '%$q%';
    final results = <Map<String, dynamic>>[];

    final trackedRows = await db.query(
      'cached_tracking_units',
      where: 'identifier LIKE ? OR product_name LIKE ? OR brand LIKE ?',
      whereArgs: [like, like, like],
      limit: 20,
    );
    for (final row in trackedRows) {
      results.add({
        'product_id': row['product_id'],
        'tracking_id': row['id'],
        'name': row['product_name'],
        'brand': row['brand'],
        'variant': row['variant'],
        'identifier': row['identifier'],
        'tracking_method': row['tracking_method'],
        'unit_price': row['unit_price'],
        'avg_purchase_price': row['avg_purchase_price'],
        'available_qty': 1,
      });
    }

    final productRows = await db.query(
      'cached_products',
      where: '(name LIKE ? OR sku LIKE ? OR barcode LIKE ?) AND tracking_method = ?',
      whereArgs: [like, like, like, 'none'],
      limit: 20,
    );
    for (final row in productRows) {
      final available = double.tryParse(row['available_qty']?.toString() ?? '') ?? 0;
      if (available <= 0) continue;
      results.add({
        'product_id': row['id'],
        'tracking_id': null,
        'name': row['name'],
        'brand': row['brand'],
        'variant': null,
        'identifier': row['barcode'] ?? row['sku'],
        'tracking_method': 'none',
        'unit_price': row['selling_price'],
        'avg_purchase_price': row['avg_purchase_price'],
        'available_qty': row['available_qty'],
      });
    }
    return results.take(20).toList();
  }

  /// Mirrors GET /api/crm/customers/?search= results list ({id, name, phone}).
  static Future<List<Map<String, dynamic>>> searchCustomers(String q) async {
    final db = await OfflineDb.instance;
    return db.query('cached_customers', where: 'name LIKE ?', whereArgs: ['%$q%'], limit: 20);
  }

  /// Mirrors GET /api/purchase/suppliers/?search= results list ({id, name, city}).
  static Future<List<Map<String, dynamic>>> searchSuppliers(String q) async {
    final db = await OfflineDb.instance;
    return db.query('cached_suppliers', where: 'name LIKE ?', whereArgs: ['%$q%'], limit: 20);
  }

  /// Mirrors GET /api/products/products/?search= (only the fields receiving_screen/
  /// invoice-edit/bill-edit actually read: id, name, sku, tracking_method, plus
  /// cost_price/selling_price for defaulting a new line's price).
  static Future<List<Map<String, dynamic>>> searchProducts(String q) async {
    final db = await OfflineDb.instance;
    final like = '%$q%';
    return db.query(
      'cached_products',
      where: 'name LIKE ? OR sku LIKE ? OR barcode LIKE ?',
      whereArgs: [like, like, like],
      limit: 20,
    );
  }
}
