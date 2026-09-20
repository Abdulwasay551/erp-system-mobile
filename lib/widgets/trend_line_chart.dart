import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A generic sparkline-style line chart for "value over time" data, styled identically
/// to dashboard_screen.dart's _SalesTrendChart (same grid/tooltip/gradient-fill look)
/// but parameterized on arbitrary (label, value) points instead of assuming a specific
/// revenue/day shape - shared by the new Product/Customer/Supplier detail screens
/// rather than re-implementing this chart three more times.
class TrendLineChart extends StatelessWidget {
  final String title;
  final List<MapEntry<String, double>> points; // short x-axis label -> y value
  final String Function(double value)? tooltipFormatter;
  final String emptyMessage;

  const TrendLineChart({
    super.key,
    required this.title,
    required this.points,
    this.tooltipFormatter,
    this.emptyMessage = 'No data yet.',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (points.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 24),
              Center(child: Text(emptyMessage, style: TextStyle(color: scheme.onSurfaceVariant))),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
    }

    final spots = <FlSpot>[];
    double maxY = 1;
    for (var i = 0; i < points.length; i++) {
      final v = points[i].value;
      spots.add(FlSpot(i.toDouble(), v));
      if (v > maxY) maxY = v;
    }
    final labelEvery = (points.length / 4).ceil().clamp(1, points.length);
    final formatter = tooltipFormatter ?? (v) => v.toStringAsFixed(0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
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
                          if (i % labelEvery != 0 || i >= points.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(points[i].key, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) =>
                          spots.map((s) => LineTooltipItem(formatter(s.y), TextStyle(color: scheme.onInverseSurface, fontSize: 11))).toList(),
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
