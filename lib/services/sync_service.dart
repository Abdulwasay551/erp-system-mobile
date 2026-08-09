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

      await _purgeOldSynced(db);
    } finally {
      _draining = false;
    }
  }

  Future<void> _purgeOldSynced(Database db) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch;
    await db.delete('sync_queue', where: "status = 'synced' AND synced_at < ?", whereArgs: [cutoff]);
  }

  static Future<int> pendingCount() async {
    final db = await OfflineDb.instance;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) as c FROM sync_queue WHERE status IN ('pending', 'syncing', 'failed')",
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }
}
