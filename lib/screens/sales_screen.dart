import 'package:flutter/material.dart';
import 'pos_screen.dart';
import 'invoices_screen.dart';

/// Bottom-nav "Sales" tab - houses both making a sale (POS) and browsing past
/// invoices, mirroring how the web app nests POS + Invoices under one Sales module.
/// No Scaffold/AppBar of its own - HomeScreen already provides one, and nesting a
/// second AppBar+title here would just stack two "Sales" bars on top of each other.
class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: const TabBar(tabs: [Tab(text: 'POS / Sell'), Tab(text: 'Invoices')]),
          ),
          const Expanded(child: TabBarView(children: [POSScreen(), InvoicesScreen()])),
        ],
      ),
    );
  }
}
