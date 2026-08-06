import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../widgets/logo_loader.dart';

const _ink = Color(0xFF171717);

class DashboardScreen extends StatefulWidget {
  /// Switches the parent HomeScreen's bottom-nav tab - lets a stat card jump
  /// straight to the screen it summarizes (e.g. "Pending Vendor Receipts" -> Receiving).
  final void Function(int tabIndex)? onNavigate;
  const DashboardScreen({super.key, this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthService>().api;
    try {
      final data = await api.request('/api/analytics/dashboard/');
      if (mounted) setState(() => _stats = data as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load dashboard.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final stats = _stats;
    if (stats == null) {
      return const LogoLoader(label: 'Loading dashboard...');
    }

    // (label, value, bottom-nav tab index to jump to on tap)
    final cards = [
      ("Today's Sales", "Rs. ${stats['todays_sales_total']}", 1),
      ("Sales Count Today", "${stats['todays_sales_count']}", 1),
      ("Customer Outstanding", "Rs. ${stats['customer_outstanding_total']}", 3),
      ("Supplier Outstanding", "Rs. ${stats['supplier_outstanding_total']}", 3),
      ("Low Stock Items", "${stats['low_stock_count']}", 2),
      ("Available Tracked Units", "${stats['available_tracked_units']}", 2),
      ("Pending Vendor Receipts", "${stats['pending_vendor_receipts']}", 2),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
        ),
        itemCount: cards.length,
        itemBuilder: (context, i) {
          final (label, value, tabIndex) = cards[i];
          return _AnimatedStatCard(
            index: i,
            label: label,
            value: value,
            onTap: widget.onNavigate == null ? null : () => widget.onNavigate!(tabIndex),
          );
        },
      ),
    );
  }
}

class _AnimatedStatCard extends StatefulWidget {
  final int index;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _AnimatedStatCard({required this.index, required this.label, required this.value, this.onTap});

  @override
  State<_AnimatedStatCard> createState() => _AnimatedStatCardState();
}

class _AnimatedStatCardState extends State<_AnimatedStatCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(_fade);
    Future.delayed(Duration(milliseconds: widget.index * 60), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Card(
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(widget.label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      ),
                      if (widget.onTap != null)
                        Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(widget.value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _ink)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
