import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'dashboard_screen.dart';
import 'pos_screen.dart';
import 'receiving_screen.dart';
import 'contacts_screen.dart';
import 'expenses_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _titles = ['Dashboard', 'POS / Sell', 'Receiving', 'Contacts', 'Expenses'];
  static const _screens = [
    DashboardScreen(),
    POSScreen(),
    ReceivingScreen(),
    ContactsScreen(),
    ExpensesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
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
              child: Text(auth.user?.initials ?? '?', style: const TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'POS'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Receiving'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Contacts'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Expenses'),
        ],
      ),
    );
  }
}
