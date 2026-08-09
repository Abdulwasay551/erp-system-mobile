import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite store backing offline support: a generic GET-response cache
/// (`cached_responses`), a generic write queue (`sync_queue`), and four reference-data
/// mirror tables that need indexed lookup (not just a cached blob) so POS/vendor-invoice
/// search still works with no internet. Plain hand-written SQL, matching this codebase's
/// existing no-codegen style (see the plan for why sqflite over drift/hive).
class OfflineDb {
  OfflineDb._();
  static Database? _db;

  static Future<Database> get instance async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'mobile_corner_offline.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cached_responses (
            cache_key TEXT PRIMARY KEY,
            json_body TEXT NOT NULL,
            cached_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_request_id TEXT NOT NULL UNIQUE,
            queue_type TEXT NOT NULL,
            method TEXT NOT NULL,
            path TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            summary TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            created_at INTEGER NOT NULL,
            synced_at INTEGER,
            error_message TEXT,
            retry_count INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_products (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            sku TEXT,
            brand TEXT,
            barcode TEXT,
            tracking_method TEXT NOT NULL,
            selling_price TEXT,
            cost_price TEXT,
            avg_purchase_price TEXT,
            available_qty TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_tracking_units (
            id INTEGER PRIMARY KEY,
            product_id INTEGER NOT NULL,
            product_name TEXT NOT NULL,
            brand TEXT,
            variant TEXT,
            identifier TEXT NOT NULL,
            tracking_method TEXT NOT NULL,
            unit_price TEXT,
            avg_purchase_price TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_customers (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_suppliers (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            city TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_products_name ON cached_products(name)');
        await db.execute('CREATE INDEX idx_products_barcode ON cached_products(barcode)');
        await db.execute('CREATE INDEX idx_tracking_identifier ON cached_tracking_units(identifier)');
        await db.execute('CREATE INDEX idx_tracking_product_name ON cached_tracking_units(product_name)');
        await db.execute('CREATE INDEX idx_customers_name ON cached_customers(name)');
        await db.execute('CREATE INDEX idx_suppliers_name ON cached_suppliers(name)');
      },
    );
  }

  /// Wipes every table - called on logout so one company's cached/queued data never
  /// leaks into a different account signing in on the same device.
  static Future<void> clearAll() async {
    final db = await instance;
    final batch = db.batch();
    for (final table in [
      'cached_responses',
      'sync_queue',
      'cached_products',
      'cached_tracking_units',
      'cached_customers',
      'cached_suppliers',
    ]) {
      batch.delete(table);
    }
    await batch.commit(noResult: true);
  }
}
