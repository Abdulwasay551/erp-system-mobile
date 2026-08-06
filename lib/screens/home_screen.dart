import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'dashboard_screen.dart';
import 'pos_screen.dart';
import 'receiving_screen.dart';
import 'contacts_screen.dart';
import 'expenses_screen.dart';
import 'accounting_screen.dart';

const _adminRoles = {'Owner', 'Manager'};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _baseTitles = ['Dashboard', 'POS / Sell', 'Receiving', 'Contacts', 'Expenses'];

  void _goToTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isAdmin = _adminRoles.contains(auth.user?.roleName) || auth.user?.isSuperuser == true;
    final titles = isAdmin ? [..._baseTitles, 'Accounting'] : _baseTitles;
    final screens = [
      DashboardScreen(onNavigate: _goToTab),
      const POSScreen(),
      const ReceivingScreen(),
      const ContactsScreen(),
      const ExpensesScreen(),
      if (isAdmin) const AccountingScreen(),
    ];
    if (_index >= titles.length) _index = 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                context.read<AuthService>().logout();
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
              const PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
            child: CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF171717),
              foregroundColor: Colors.white,
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
          const NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'POS'),
          const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Receiving'),
          const NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Contacts'),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Expenses'),
          if (isAdmin)
            const NavigationDestination(icon: Icon(Icons.account_balance_outlined), selectedIcon: Icon(Icons.account_balance), label: 'Accounting'),
        ],
      ),
    );
  }
}
