import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../theme/app_semantic_colors.dart';
import '../widgets/logo_loader.dart';

class DashboardScreen extends StatefulWidget {
  /// Switches the parent HomeScreen's bottom-nav tab - lets a stat card jump
  /// straight to the screen it summarizes (e.g. "Pending Vendor Receipts" -> Receiving).
  final void Function(int tabIndex)? onNavigate;
  const DashboardScreen({super.key, this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _StatCardSpec {
  final String label;
  final String value;
  final int tabIndex;
  final IconData icon;
  final bool isHero;
  final bool isAlert;
  const _StatCardSpec({
    required this.label,
    required this.value,
    required this.tabIndex,
    required this.icon,
    this.isHero = false,
    this.isAlert = false,
  });
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  List<dynamic>? _trendDays;
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
    try {
      final report = await api.request('/api/analytics/profit-report/?days=14') as Map<String, dynamic>;
      if (mounted) setState(() => _trendDays = report['days'] as List<dynamic>?);
    } catch (_) {
      // Chart is a nice-to-have on the dashboard - a failure here shouldn't block the
      // stat cards above, which already have their own error handling.
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

    final customerOutstanding = double.tryParse(stats['customer_outstanding_total'].toString()) ?? 0;
    final supplierOutstanding = double.tryParse(stats['supplier_outstanding_total'].toString()) ?? 0;
    final lowStock = double.tryParse(stats['low_stock_count'].toString()) ?? 0;
    final pendingReceipts = double.tryParse(stats['pending_vendor_receipts'].toString()) ?? 0;

    final cards = [
      _StatCardSpec(
        label: "Today's Sales",
        value: "Rs. ${stats['todays_sales_total']}",
        tabIndex: 1,
        icon: Icons.trending_up,
        isHero: true,
      ),
      _StatCardSpec(
        label: "Sales Count Today",
        value: "${stats['todays_sales_count']}",
        tabIndex: 1,
        icon: Icons.receipt_long_outlined,
      ),
      _StatCardSpec(
        label: "Customer Outstanding",
        value: "Rs. ${stats['customer_outstanding_total']}",
        tabIndex: 3,
        icon: Icons.account_balance_wallet_outlined,
        isAlert: customerOutstanding > 0,
      ),
      _StatCardSpec(
        label: "Supplier Outstanding",
        value: "Rs. ${stats['supplier_outstanding_total']}",
        tabIndex: 3,
        icon: Icons.local_shipping_outlined,
        isAlert: supplierOutstanding > 0,
      ),
      _StatCardSpec(
        label: "Low Stock Items",
        value: "${stats['low_stock_count']}",
        tabIndex: 2,
        icon: Icons.inventory_2_outlined,
        isAlert: lowStock > 0,
      ),
      _StatCardSpec(
        label: "Available Tracked Units",
        value: "${stats['available_tracked_units']}",
        tabIndex: 2,
        icon: Icons.qr_code_2,
      ),
      _StatCardSpec(
        label: "Pending Vendor Receipts",
        value: "${stats['pending_vendor_receipts']}",
        tabIndex: 2,
        icon: Icons.pending_actions_outlined,
        isAlert: pendingReceipts > 0,
      ),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          if (_trendDays != null && _trendDays!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _SalesTrendChart(days: _trendDays!),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final spec = cards[i];
                  return _AnimatedStatCard(
                    index: i,
                    spec: spec,
                    onTap: widget.onNavigate == null ? null : () => widget.onNavigate!(spec.tabIndex),
                  );
                },
                childCount: cards.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedStatCard extends StatefulWidget {
  final int index;
  final _StatCardSpec spec;
  final VoidCallback? onTap;
  const _AnimatedStatCard({required this.index, required this.spec, this.onTap});

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
    final spec = widget.spec;
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;

    final (badgeBg, badgeFg) = spec.isAlert
        ? (semantic.warningContainer, semantic.warning)
        : (scheme.primaryContainer, scheme.onPrimaryContainer);

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: spec.isHero ? _heroCard(context, spec, scheme) : _flatCard(context, spec, badgeBg, badgeFg, scheme),
      ),
    );
  }

  Widget _flatCard(BuildContext context, _StatCardSpec spec, Color badgeBg, Color badgeFg, ColorScheme scheme) {
    return Card(
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(8)),
                    child: Icon(spec.icon, size: 16, color: badgeFg),
                  ),
                  if (widget.onTap != null)
                    Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                spec.label,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.15),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                spec.value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroCard(BuildContext context, _StatCardSpec spec, ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppGradients.primary(scheme),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: scheme.primary.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(spec.icon, size: 16, color: Colors.white),
                    ),
                    if (widget.onTap != null)
                      const Icon(Icons.chevron_right, size: 16, color: Colors.white70),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  spec.label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.15),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  spec.value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// At-a-glance revenue trend for the last `days` entries (from /api/analytics/
/// profit-report/) - the full Revenue-vs-Costs bar chart lives on the Analytics tab;
/// this is a lighter single-line sparkline-style summary for the dashboard.
class _SalesTrendChart extends StatelessWidget {
  final List<dynamic> days;
  const _SalesTrendChart({required this.days});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spots = <FlSpot>[];
    double maxY = 1;
    for (var i = 0; i < days.length; i++) {
      final d = days[i] as Map<String, dynamic>;
      final revenue = double.tryParse(d['revenue'].toString()) ?? 0;
      spots.add(FlSpot(i.toDouble(), revenue));
      if (revenue > maxY) maxY = revenue;
    }
    final labelEvery = (days.length / 4).ceil().clamp(1, days.length);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Text('Revenue - Last ${days.length} Days', style: Theme.of(context).textTheme.titleSmall),
            ),
            SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY * 1.15,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: (maxY * 1.15) / 3,
                    getDrawingHorizontalLine: (value) => FlLine(color: scheme.outline.withValues(alpha: 0.15), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i % labelEvery != 0 || i >= days.length) return const SizedBox.shrink();
                          final date = (days[i] as Map<String, dynamic>)['date'].toString();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(date.substring(5), style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map((s) => LineTooltipItem('Rs. ${s.y.toStringAsFixed(0)}', TextStyle(color: scheme.onInverseSurface, fontSize: 11)))
                          .toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: scheme.primary,
                      barWidth: 2.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [scheme.primary.withValues(alpha: 0.25), scheme.primary.withValues(alpha: 0.0)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
