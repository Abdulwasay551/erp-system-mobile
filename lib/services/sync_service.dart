import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'api_client.dart';
import 'offline_db.dart';

/// Drains the offline write queue sequentially (oldest first - see the plan for why not
/// parallel) whenever there's a reasonable chance of being online: called on app start,
/// on ConnectivityService regaining a connection, and available for a manual "Sync Now"
/// button. Safe to call repeatedly/concurrently - re-entrant calls are no-ops while a
/// drain is already running.
class SyncService {
  final ApiClient api;
  SyncService(this.api);

  static bool _draining = false;

  /// True after a drain attempt hit a 401 even post-refresh - the refresh token itself
  /// has likely expired (offline >7 days) and the user needs to log in again before any
  /// more queued items can sync. Cleared automatically the next time a drain succeeds.
  static bool authRequired = false;

  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      // Cheap reachability + auth check before burning through the whole queue -
      // avoids marking every item 'failed' one by one if the token itself is dead.
      try {
        await api.request('/api/auth/me/');
        authRequired = false;
      } on ApiException catch (e) {
        authRequired = e.statusCode == 401;
        return;
      } catch (_) {
        return; // not actually reachable right now, try again next trigger
      }

      final db = await OfflineDb.instance;
      while (true) {
        final rows = await db.query(
          'sync_queue',
          where: "status = 'pending'",
          orderBy: 'created_at ASC',
          limit: 1,
        );
        if (rows.isEmpty) break;
        final row = rows.first;
        final id = row['id'] as int;

        await db.update('sync_queue', {'status': 'syncing'}, where: 'id = ?', whereArgs: [id]);
        try {
          final payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
          await api.request(row['path'] as String, method: row['method'] as String, body: payload);
          await db.update(
            'sync_queue',
            {'status': 'synced', 'synced_at': DateTime.now().millisecondsSinceEpoch, 'error_message': null},
            where: 'id = ?',
            whereArgs: [id],
          );
        } on ApiException catch (e) {
          // A real server rejection (e.g. the tracked unit this queued sale wanted was
          // sold by another device before this one synced) - stays visible in Sync
          // Status for the user to retry/discard, doesn't block the rest of the queue.
          await db.update(
            'sync_queue',
            {
              'status': 'failed',
              'error_message': e.message,
              'retry_count': (row['retry_count'] as int) + 1,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        } catch (_) {
          // Connection dropped mid-drain - put it back and stop for now rather than
          // marking a possibly-transient network blip as a hard failure.
          await db.update('sync_queue', {'status': 'pending'}, where: 'id = ?', whereArgs: [id]);
          break;
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// Manual cleanup only (Sync Status screen's "Sweep Cache" button) - deliberately not
  /// run automatically on every drain so the user can see and control when local storage
  /// gets cleared, rather than it happening silently in the background. Safe by
  /// construction either way: this only ever deletes [sync_queue] rows already marked
  /// 'synced' (the server already confirmed them, so the local record is redundant) and
  /// rows in the separate read-only [cached_responses] table (Dashboard/Invoices/etc.
  /// display cache) - it never touches pending/syncing/failed queue rows, so a write
  /// that hasn't synced yet can't be lost by running this. Returns counts for the
  /// confirmation snackbar.
  static Future<({int queueRows, int cacheRows})> sweepCache() async {
    final db = await OfflineDb.instance;
    final queueCutoff = DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch;
    final queueRows =
        await db.delete('sync_queue', where: "status = 'synced' AND synced_at < ?", whereArgs: [queueCutoff]);
    final cacheCutoff = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final cacheRows = await db.delete('cached_responses', where: 'cached_at < ?', whereArgs: [cacheCutoff]);
    return (queueRows: queueRows, cacheRows: cacheRows);
  }

  static Future<int> pendingCount() async {
    final db = await OfflineDb.instance;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) as c FROM sync_queue WHERE status IN ('pending', 'syncing', 'failed')",
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Queue rows still needing attention (pending/syncing/failed), oldest first - powers
  /// the "Active" section of the Sync Status screen.
  static Future<List<Map<String, dynamic>>> activeItems() async {
    final db = await OfflineDb.instance;
    return db.query('sync_queue', where: "status IN ('pending', 'syncing', 'failed')", orderBy: 'created_at ASC');
  }

  /// A capped, most-recent-first window into successfully synced items - full cleanup of
  /// old synced rows happens via the manual [sweepCache] button, not automatically.
  static Future<List<Map<String, dynamic>>> recentlySynced({int limit = 20}) async {
    final db = await OfflineDb.instance;
    return db.query('sync_queue', where: "status = 'synced'", orderBy: 'synced_at DESC', limit: limit);
  }

  /// Resets a failed item back to pending so the next [drain] picks it up again.
  static Future<void> retry(int id) async {
    final db = await OfflineDb.instance;
    await db.update('sync_queue', {'status': 'pending', 'error_message': null}, where: 'id = ?', whereArgs: [id]);
  }

  /// Drops a failed item permanently - the user has decided the write it represents
  /// (e.g. a sale for a tracked unit someone else already sold) shouldn't be retried.
  static Future<void> discard(int id) async {
    final db = await OfflineDb.instance;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }
}
