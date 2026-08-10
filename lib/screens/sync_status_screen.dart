import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../theme/app_semantic_colors.dart';
import '../widgets/tag_pill.dart';

const _statusLabels = {
  'pending': 'Pending',
  'syncing': 'Syncing',
  'failed': 'Failed',
  'synced': 'Synced',
};

/// Local write-queue viewer (offline POS sales, customer/supplier/expense/payment/
/// vendor-invoice writes queued while offline) - mirrors recycle_bin_screen.dart's
/// structure. Everything here is read from the on-device sqlite queue, not the
/// backend, so it works offline too.
class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  List<Map<String, dynamic>> _active = [];
  List<Map<String, dynamic>> _synced = [];
  bool _loading = true;
  bool _syncing = false;
  bool _sweeping = false;
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final active = await SyncService.activeItems();
    final synced = await SyncService.recentlySynced();
    if (mounted) {
      setState(() {
        _active = active;
        _synced = synced;
        _loading = false;
      });
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final api = context.read<AuthService>().api;
    await SyncService(api).drain();
    if (mounted) {
      setState(() => _syncing = false);
      final stillPending = _active.any((r) => r['status'] != 'failed');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SyncService.authRequired
            ? 'Please log in again to resume syncing.'
            : stillPending
                ? 'Sync attempted - still offline or some items pending.'
                : 'Sync complete.'),
      ));
    }
    _load();
  }

  Future<void> _retry(Map<String, dynamic> row) async {
    setState(() => _busyKey = 'retry-${row['id']}');
    final api = context.read<AuthService>().api;
    await SyncService.retry(row['id'] as int);
    await SyncService(api).drain();
    if (mounted) setState(() => _busyKey = null);
    _load();
  }

  Future<void> _sweepCache() async {
    setState(() => _sweeping = true);
    final result = await SyncService.sweepCache();
    if (mounted) {
      setState(() => _sweeping = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.queueRows == 0 && result.cacheRows == 0
            ? 'Nothing to clear right now.'
            : 'Cleared ${result.queueRows} synced record(s) and ${result.cacheRows} stale cache entr${result.cacheRows == 1 ? 'y' : 'ies'}.'),
      ));
    }
    _load();
  }

  Future<void> _discard(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this item?'),
        content: Text(
          '"${row['summary']}" will be permanently removed from the sync queue and never sent to the server. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.semanticColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyKey = 'discard-${row['id']}');
    await SyncService.discard(row['id'] as int);
    if (mounted) setState(() => _busyKey = null);
    _load();
  }

  String _formatTime(int? millis) {
    if (millis == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final online = context.watch<ConnectivityService>().isOnline;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Status'),
        actions: [
          IconButton(
            icon: _sweeping
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cleaning_services_outlined),
            tooltip: 'Sweep old synced records & stale cache',
            onPressed: _sweeping ? null : _sweepCache,
          ),
          IconButton(
            icon: _syncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            tooltip: 'Sync Now',
            onPressed: _syncing || !online ? null : _syncNow,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (!online)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: context.semanticColors.warningContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        Icon(Icons.cloud_off_outlined, size: 16, color: context.semanticColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Offline - queued items will sync automatically once back online.',
                            style: TextStyle(color: context.semanticColors.warning, fontSize: 12.5),
                          ),
                        ),
                      ]),
                    )
                  else if (SyncService.authRequired)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: context.semanticColors.dangerContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        Icon(Icons.lock_outline, size: 16, color: context.semanticColors.danger),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Session expired - log in again to resume syncing queued items.',
                            style: TextStyle(color: context.semanticColors.danger, fontSize: 12.5),
                          ),
                        ),
                      ]),
                    ),
                  if (_active.isEmpty && _synced.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: Text('Nothing queued - everything is synced.')),
                    ),
                  if (_active.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Text('Active (${_active.length})', style: Theme.of(context).textTheme.titleSmall),
                    ),
                    ..._active.map((row) => _QueueTile(
                          row: row,
                          formatTime: _formatTime,
                          busy: _busyKey == 'retry-${row['id']}' || _busyKey == 'discard-${row['id']}',
                          onRetry: row['status'] == 'failed' ? () => _retry(row) : null,
                          onDiscard: row['status'] == 'failed' ? () => _discard(row) : null,
                        )),
                    const SizedBox(height: 16),
                  ],
                  if (_synced.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Text('Recently Synced', style: Theme.of(context).textTheme.titleSmall),
                    ),
                    ..._synced.map((row) => _QueueTile(row: row, formatTime: _formatTime)),
                  ],
                ],
              ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final String Function(int?) formatTime;
  final bool busy;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;
  const _QueueTile({
    required this.row,
    required this.formatTime,
    this.busy = false,
    this.onRetry,
    this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final status = row['status'] as String;
    final (color, container) = switch (status) {
      'synced' => (context.semanticColors.success, context.semanticColors.successContainer),
      'failed' => (context.semanticColors.danger, context.semanticColors.dangerContainer),
      _ => (context.semanticColors.warning, context.semanticColors.warningContainer),
    };
    final subtitleParts = <String>[
      status == 'synced'
          ? 'Synced ${formatTime(row['synced_at'] as int?)}'
          : 'Queued ${formatTime(row['created_at'] as int?)}',
    ];
    if (status == 'failed' && row['error_message'] != null) {
      subtitleParts.add(row['error_message'].toString());
    }
    return Card(
      color: status == 'failed' ? container.withValues(alpha: 0.35) : null,
      child: ListTile(
        title: Text(row['summary']?.toString() ?? ''),
        subtitle: Text(subtitleParts.join(' - ')),
        leading: TagPill(label: _statusLabels[status] ?? status, color: color),
        isThreeLine: status == 'failed' && row['error_message'] != null,
        trailing: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : (onRetry != null || onDiscard != null)
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onRetry != null)
                        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Retry', onPressed: onRetry),
                      if (onDiscard != null)
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: context.semanticColors.danger),
                          tooltip: 'Discard',
                          onPressed: onDiscard,
                        ),
                    ],
                  )
                : null,
      ),
    );
  }
}
