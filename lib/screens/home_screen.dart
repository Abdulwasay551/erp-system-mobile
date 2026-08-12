import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../theme/app_semantic_colors.dart';
import 'dashboard_screen.dart';
import 'sales_screen.dart';
import 'receiving_screen.dart';
import 'contacts_screen.dart';
import 'expenses_screen.dart';
import 'accounting_screen.dart';
import 'search_screen.dart';
import 'recycle_bin_screen.dart';
import 'item_lookup_screen.dart';
import 'products_screen.dart';
import 'staff_screen.dart';
import 'sync_status_screen.dart';
import '../services/connectivity_service.dart';
import '../services/reference_sync_service.dart';
import '../services/sync_service.dart';

const _adminRoles = {'Owner', 'Manager'};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  int _pendingSyncCount = 0;
  Timer? _pendingCountTimer;

  static const _baseTitles = ['Dashboard', 'Sales', 'Receiving', 'Contacts', 'Expenses'];

  void _goToTab(int i) => setState(() => _index = i);

  @override
  void initState() {
    super.initState();
    _maybeSyncReferenceData();
    final api = context.read<AuthService>().api;
    _refreshPendingCount();
    SyncService(api).drain().then((_) => _refreshPendingCount());
    context.read<ConnectivityService>().onRegained =
        () => SyncService(api).drain().then((_) => _refreshPendingCount());
    // Cheap local-only COUNT query - catches the queue count changing on its own
    // (e.g. a Tier 2 write queued from another tab) without needing every write site to
    // remember to notify HomeScreen.
    _pendingCountTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshPendingCount());
  }

  @override
  void dispose() {
    _pendingCountTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshPendingCount() async {
    final count = await SyncService.pendingCount();
    if (mounted) setState(() => _pendingSyncCount = count);
  }

  Future<void> _maybeSyncReferenceData() async {
    if (!mounted) return;
    final online = context.read<ConnectivityService>().isOnline;
    if (!online) return;
    final api = context.read<AuthService>().api;
    if (!await ReferenceSyncService.isStale()) return;
    try {
      await ReferenceSyncService.syncNow(api);
    } catch (_) {
      // Best-effort - POS/vendor-invoice search just falls back to whatever was cached
      // last time this succeeded (or stays empty offline if it's never succeeded yet).
    }
  }

  Future<void> _showAppearanceDialog(BuildContext context) async {
    final themeService = context.read<ThemeService>();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Appearance'),
          content: RadioGroup<ThemeMode>(
            groupValue: themeService.themeMode,
            onChanged: (v) {
              themeService.setThemeMode(v!);
              setDialogState(() {});
            },
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<ThemeMode>(title: Text('System'), value: ThemeMode.system),
                RadioListTile<ThemeMode>(title: Text('Light'), value: ThemeMode.light),
                RadioListTile<ThemeMode>(title: Text('Dark'), value: ThemeMode.dark),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isAdmin = _adminRoles.contains(auth.user?.roleName) || auth.user?.isSuperuser == true;
    final titles = isAdmin ? [..._baseTitles, 'Analytics'] : _baseTitles;
    final screens = [
      DashboardScreen(onNavigate: _goToTab),
      const SalesScreen(),
      const ReceivingScreen(),
      const ContactsScreen(),
      const ExpensesScreen(),
      if (isAdmin) const AccountingScreen(),
    ];
    if (_index >= titles.length) _index = 0;
    final online = context.watch<ConnectivityService>().isOnline;
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          if (!online || _pendingSyncCount > 0)
            IconButton(
              icon: Badge(
                label: _pendingSyncCount > 0 ? Text('$_pendingSyncCount') : null,
                isLabelVisible: _pendingSyncCount > 0,
                backgroundColor: context.semanticColors.warning,
                child: Icon(
                  online ? Icons.sync_problem_outlined : Icons.cloud_off_outlined,
                  color: context.semanticColors.warning,
                ),
              ),
              tooltip: online ? 'Sync pending' : 'Offline',
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (context) => const SyncStatusScreen()));
                _refreshPendingCount();
              },
            ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchScreen())),
          ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.badge_outlined),
              tooltip: 'Staff Management',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const StaffScreen())),
            ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout') {
                context.read<AuthService>().logout();
              } else if (value == 'appearance') {
                _showAppearanceDialog(context);
              } else if (value == 'recycle_bin') {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const RecycleBinScreen()));
              } else if (value == 'item_lookup') {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const ItemLookupScreen()));
              } else if (value == 'products') {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const ProductsScreen()));
              } else if (value == 'sync_status') {
                await Navigator.push(context, MaterialPageRoute(builder: (context) => const SyncStatusScreen()));
                _refreshPendingCount();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  '${auth.user?.fullName ?? ''}\n${auth.user?.roleName ?? ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'appearance',
                child: ListTile(
                  leading: Icon(Icons.palette_outlined),
                  title: Text('Appearance'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'item_lookup',
                child: ListTile(
                  leading: Icon(Icons.qr_code_scanner_outlined),
                  title: Text('Item Lookup'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'products',
                child: ListTile(
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('Products'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'sync_status',
                child: ListTile(
                  leading: const Icon(Icons.sync_outlined),
                  title: const Text('Sync Status'),
                  trailing: _pendingSyncCount > 0
                      ? Badge(label: Text('$_pendingSyncCount'), backgroundColor: context.semanticColors.warning)
                      : null,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (context.read<AuthService>().isAdmin)
                const PopupMenuItem(
                  value: 'recycle_bin',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Recycle Bin'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              child: Text(auth.user?.initials ?? '?', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          const NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'Sales'),
          const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Receiving'),
          const NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Contacts'),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Expenses'),
          if (isAdmin)
            const NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Analytics'),
        ],
      ),
    );
  }
}
