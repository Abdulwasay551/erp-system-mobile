import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../widgets/skeleton.dart';
import 'expenses_screen.dart';
import 'staff_screen.dart';

const _ink = Color(0xFF171717);

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

  Widget _statCard(String label, String value, {Color? color}) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
    final groups = <BarChartGroupData>[];
    double maxY = 1;
    for (var i = 0; i < days.length; i++) {
      final d = days[i] as Map<String, dynamic>;
      final revenue = double.tryParse(d['revenue'].toString()) ?? 0;
      final cost = (double.tryParse(d['cogs'].toString()) ?? 0) + (double.tryParse(d['expenses'].toString()) ?? 0);
      maxY = [maxY, revenue, cost].reduce((a, b) => a > b ? a : b);
      groups.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: revenue, color: _ink, width: 6, borderRadius: BorderRadius.circular(2)),
        BarChartRodData(toY: cost, color: Colors.red.shade300, width: 6, borderRadius: BorderRadius.circular(2)),
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
                  _legendDot(_ink, 'Revenue'),
                  const SizedBox(width: 10),
                  _legendDot(Colors.red.shade300, 'Costs'),
                ],
              ),
            ),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: maxY * 1.15,
                  barGroups: groups,
                  gridData: const FlGridData(show: false),
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
                            child: Text(date.substring(5), style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
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

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
                            _statCard('Revenue', totals['revenue'].toString()),
                            const SizedBox(width: 8),
                            _statCard('COGS', totals['cogs'].toString()),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            _statCard('Gross Profit', totals['gross_profit'].toString(), color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            _statCard('Expenses', totals['expenses'].toString(), color: Colors.red.shade700),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            _statCard(
                              'Net Profit',
                              totals['net_profit'].toString(),
                              color: (double.tryParse(totals['net_profit'].toString()) ?? 0) >= 0
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
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
