import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../theme/app_semantic_colors.dart';
import '../widgets/skeleton.dart';
import 'expenses_screen.dart';
import 'staff_screen.dart';

const _periods = [
  (7, 'Last 7 days'),
  (30, 'Last 30 days'),
  (90, 'Last 90 days'),
];

class AccountingScreen extends StatefulWidget {
  const AccountingScreen({super.key});

  @override
  State<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends State<AccountingScreen> {
  int _days = 30;
  Map<String, dynamic>? _report;
  bool _loading = true;
  String? _error;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.request('/api/analytics/profit-report/?days=$_days');
      if (mounted) setState(() => _report = data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _statCard(String label, String value, IconData icon, {Color? color}) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Rs. $value',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCardSkeleton() {
    return const Expanded(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(width: 60, height: 11),
              SizedBox(height: 8),
              Skeleton(width: 70, height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chart(List<dynamic> days) {
    if (days.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;
    final revenueGradient = LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [
      scheme.primary,
      scheme.secondary,
    ]);
    final groups = <BarChartGroupData>[];
    double maxY = 1;
    for (var i = 0; i < days.length; i++) {
      final d = days[i] as Map<String, dynamic>;
      final revenue = double.tryParse(d['revenue'].toString()) ?? 0;
      final cost = (double.tryParse(d['cogs'].toString()) ?? 0) + (double.tryParse(d['expenses'].toString()) ?? 0);
      maxY = [maxY, revenue, cost].reduce((a, b) => a > b ? a : b);
      groups.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: revenue, gradient: revenueGradient, width: 6, borderRadius: BorderRadius.circular(2)),
        BarChartRodData(toY: cost, color: semantic.danger, width: 6, borderRadius: BorderRadius.circular(2)),
      ]));
    }
    final labelEvery = (days.length / 6).ceil().clamp(1, days.length);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Row(
                children: [
                  Text('Revenue vs. Costs', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  _legendDot(scheme.primary, 'Revenue'),
                  const SizedBox(width: 10),
                  _legendDot(semantic.danger, 'Costs'),
                ],
              ),
            ),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: maxY * 1.15,
                  barGroups: groups,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: (maxY * 1.15) / 4,
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `days` always runs from `today - (period-1)` through `today` inclusive
  /// regardless of which period chip is selected, so the last element is always
  /// today's row - no separate "today" endpoint needed.
  Widget _todayCard(List<dynamic> days) {
    if (days.isEmpty) return const SizedBox.shrink();
    final today = days.last as Map<String, dynamic>;
    final scheme = Theme.of(context).colorScheme;
    final revenue = double.tryParse(today['revenue'].toString()) ?? 0;
    final cogs = double.tryParse(today['cogs'].toString()) ?? 0;
    final expenses = double.tryParse(today['expenses'].toString()) ?? 0;
    final netProfit = revenue - cogs - expenses;
    return Container(
      decoration: BoxDecoration(
        gradient: AppGradients.primary(scheme),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: scheme.primary.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.today_outlined, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Today', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text(
                    'Rs. ${revenue.toStringAsFixed(2)} revenue',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Net Profit', style: TextStyle(color: Colors.white70, fontSize: 11)),
                Text(
                  'Rs. ${netProfit.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final totals = _report?['totals'] as Map<String, dynamic>?;
    final days = _report?['days'] as List<dynamic>? ?? [];
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: const TabBar(tabs: [Tab(text: 'Profit & Loss'), Tab(text: 'Expenses'), Tab(text: 'Staff')]),
          ),
          Expanded(
            child: TabBarView(
              children: [
            RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!))])
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          children: _periods
                              .map((p) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(p.$2),
                                      selected: _days == p.$1,
                                      onSelected: (_) {
                                        setState(() => _days = p.$1);
                                        _load();
                                      },
                                    ),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                        if (!_loading && days.isNotEmpty) ...[
                          _todayCard(days),
                          const SizedBox(height: 16),
                        ],
                        if (_loading) ...[
                          Row(children: [_statCardSkeleton(), const SizedBox(width: 8), _statCardSkeleton()]),
                          const SizedBox(height: 8),
                          Row(children: [_statCardSkeleton(), const SizedBox(width: 8), _statCardSkeleton()]),
                          const SizedBox(height: 8),
                          Row(children: [_statCardSkeleton()]),
                          const SizedBox(height: 16),
                          const Skeleton(height: 220, borderRadius: BorderRadius.all(Radius.circular(12))),
                        ] else if (totals != null) ...[
                          Row(children: [
                            _statCard('Revenue', totals['revenue'].toString(), Icons.trending_up),
                            const SizedBox(width: 8),
                            _statCard('COGS', totals['cogs'].toString(), Icons.inventory_2_outlined),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            _statCard(
                              'Gross Profit',
                              totals['gross_profit'].toString(),
                              Icons.savings_outlined,
                              color: context.semanticColors.success,
                            ),
                            const SizedBox(width: 8),
                            _statCard(
                              'Expenses',
                              totals['expenses'].toString(),
                              Icons.receipt_long_outlined,
                              color: context.semanticColors.danger,
                            ),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            _statCard(
                              'Net Profit',
                              totals['net_profit'].toString(),
                              Icons.account_balance_wallet_outlined,
                              color: (double.tryParse(totals['net_profit'].toString()) ?? 0) >= 0
                                  ? context.semanticColors.success
                                  : context.semanticColors.danger,
                            ),
                          ]),
                          const SizedBox(height: 16),
                          _chart(days),
                        ],
                      ],
                    ),
            ),
                const ExpensesScreen(),
                const StaffScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
