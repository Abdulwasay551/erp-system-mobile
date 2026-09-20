import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/pdf_helper.dart';
import '../services/connectivity_service.dart';
import '../theme/app_semantic_colors.dart';
import '../widgets/tag_pill.dart';
import '../widgets/offline_banner.dart';
import '../widgets/info_icon_button.dart';
import 'invoice_edit_screen.dart';

const _statusOptions = [
  (null, 'All'),
  ('draft', 'Draft'),
  ('sent', 'Sent'),
  ('partially_paid', 'Partially Paid'),
  ('paid', 'Paid'),
  ('overdue', 'Overdue'),
  ('cancelled', 'Cancelled'),
];

const _sortOptions = [
  ('-invoice_date', 'Date (newest)'),
  ('invoice_date', 'Date (oldest)'),
  ('-total', 'Total (high-low)'),
  ('total', 'Total (low-high)'),
  ('invoice_number', 'Invoice #'),
];

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<dynamic> _invoices = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _status;
  String _ordering = '-invoice_date';
  DateTime? _cachedAt;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  ApiClient get _api => context.read<AuthService>().api;

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _dateFrom : _dateTo) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => isFrom ? _dateFrom = picked : _dateTo = picked);
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = true}) async {
    setState(() {
      if (reset) {
        _page = 1;
        _loading = true;
      } else {
        _loadingMore = true;
      }
    });
    final params = {
      'page': '$_page',
      'ordering': _ordering,
      if (_status != null) 'status': _status!,
      if (_dateFrom != null) 'date_from': _fmt(_dateFrom!),
      if (_dateTo != null) 'date_to': _fmt(_dateTo!),
    };
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    final online = context.read<ConnectivityService>().isOnline;
    try {
      final cached = await _api.requestCached('/api/sales/invoices/?$qs', isOnline: online);
      if (cached == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load invoices.')));
      } else {
        final data = cached.data as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>;
        if (mounted) {
          setState(() {
            _invoices = reset ? results : [..._invoices, ...results];
            _hasMore = data['next'] != null;
            _cachedAt = cached.fromCache ? cached.cachedAt : null;
          });
        }
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = _loadingMore = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    _page++;
    await _load(reset: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_cachedAt != null) OfflineDataBanner(cachedAt: _cachedAt!),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (value, label) in _statusOptions) ...[
                          _FilterChip(
                            label: label,
                            selected: _status == value,
                            onTap: () {
                              setState(() => _status = value);
                              _load();
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Sort by',
                  onSelected: (v) {
                    setState(() => _ordering = v);
                    _load();
                  },
                  itemBuilder: (context) => [
                    for (final (value, label) in _sortOptions)
                      CheckedPopupMenuItem(
                        value: value,
                        checked: _ordering == value,
                        child: Text(label),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isFrom: true),
                    child: Text(_dateFrom == null ? 'From' : _fmt(_dateFrom!), style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isFrom: false),
                    child: Text(_dateTo == null ? 'To' : _fmt(_dateTo!), style: const TextStyle(fontSize: 12)),
                  ),
                ),
                if (_dateFrom != null || _dateTo != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear dates',
                    onPressed: () {
                      setState(() {
                        _dateFrom = null;
                        _dateTo = null;
                      });
                      _load();
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _invoices.isEmpty
                    ? const Center(child: Text('No invoices match this filter.'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _invoices.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == _invoices.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: _loadingMore
                                      ? const CircularProgressIndicator()
                                      : TextButton(onPressed: _loadMore, child: const Text('Load more')),
                                ),
                              );
                            }
                            final inv = _invoices[i] as Map<String, dynamic>;
                            final outstanding = double.tryParse(inv['outstanding_amount'].toString()) ?? 0;
                            final status = inv['status'] as String;
                            final (statusColor, _) = context.semanticColors.statusColor(status);
                            return Card(
                              child: ListTile(
                                title: Text(inv['invoice_number'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('${inv['customer_name']} · ${inv['invoice_date']}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('Rs. ${inv['total']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        TagPill(label: status, color: statusColor),
                                      ],
                                    ),
                                  ],
                                ),
                                onTap: () => _openDetail(inv, outstanding),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> inv, double outstanding) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _InvoiceDetailSheet(invoice: inv, outstanding: outstanding, api: _api, onChanged: _load),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
  }
}

class _InvoiceDetailSheet extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final double outstanding;
  final ApiClient api;
  final VoidCallback onChanged;
  const _InvoiceDetailSheet({required this.invoice, required this.outstanding, required this.api, required this.onChanged});

  @override
  State<_InvoiceDetailSheet> createState() => _InvoiceDetailSheetState();
}

class _InvoiceDetailSheetState extends State<_InvoiceDetailSheet> {
  bool _downloadingPdf = false;
  bool _paying = false;
  final _amountController = TextEditingController();
  String _method = 'cash';
  List<Map<String, dynamic>>? _items;
  bool _loadingItems = true;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.outstanding > 0 ? widget.outstanding.toStringAsFixed(2) : '';
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final data = await widget.api.request('/api/sales/invoices/${widget.invoice['id']}/') as Map<String, dynamic>;
      final items = (data['items'] as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _items = items);
    } on ApiException {
      // Header fields already loaded from the list response - a failed item fetch just
      // means the line-item breakdown stays hidden, not a hard error for the sheet.
    } finally {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _openPdf(String size) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _downloadingPdf = true);
    try {
      await downloadAndOpenPdf(
        widget.api,
        '/api/sales/invoices/${widget.invoice['id']}/pdf/?size=$size',
        '${widget.invoice['invoice_number']}-$size.pdf',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _downloadingPdf = false);
    }
  }

  Future<void> _recordPayment() async {
    if (_amountController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a payment amount.')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _paying = true);
    final online = context.read<ConnectivityService>().isOnline;
    try {
      final result = await widget.api.enqueueOrSend(
        isOnline: online,
        queueType: 'record_payment',
        path: '/api/sales/payments/',
        body: {
          'customer': widget.invoice['customer'],
          'invoice': widget.invoice['id'],
          'amount': _amountController.text,
          'method': _method,
          'payment_date': DateTime.now().toIso8601String().substring(0, 10),
        },
        summary: 'Payment - Rs. ${_amountController.text} - ${widget.invoice['invoice_number']}',
      );
      messenger.showSnackBar(SnackBar(
        content: Text(result.queued ? 'Payment saved offline - will sync automatically.' : 'Payment recorded.'),
      ));
      widget.onChanged();
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(inv['invoice_number'] as String, style: Theme.of(context).textTheme.titleLarge),
          Text(inv['customer_name'] as String, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          _row('Date', inv['invoice_date'].toString()),
          _row('Total', 'Rs. ${inv['total']}'),
          _row('Paid', 'Rs. ${inv['paid_amount']}'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('Outstanding'),
                    SizedBox(width: 4),
                    InfoIconButton(message: 'Total minus Paid for this invoice - what the customer still owes on it specifically.'),
                  ],
                ),
                Text('Rs. ${inv['outstanding_amount']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 4),
          Text('Items', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_loadingItems)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_items == null || _items!.isEmpty)
            const Text('No line items.')
          else
            Column(
              children: [
                for (final item in _items!) _InvoiceItemRow(item: item),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _downloadingPdf ? null : () => _openPdf('mini'),
                  icon: const Icon(Icons.receipt_long, size: 18),
                  label: const Text('Mini PDF'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _downloadingPdf ? null : () => _openPdf('a4'),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('A4 PDF'),
                ),
              ),
            ],
          ),
          if (context.read<AuthService>().isAdmin) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => InvoiceEditScreen(
                      invoiceId: inv['id'] as int,
                      invoiceNumber: inv['invoice_number'] as String,
                    ),
                  ),
                );
                if (changed == true) {
                  widget.onChanged();
                  navigator.pop();
                }
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit Line Items'),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text('Record Payment', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _method,
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                  DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                  DropdownMenuItem(value: 'online', child: Text('Online')),
                ],
                onChanged: (v) => setState(() => _method = v ?? 'cash'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _paying ? null : _recordPayment,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: Text(_paying ? 'Recording...' : 'Record Payment'),
          ),
        ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
        ],
      ),
    );
  }
}

/// One read-only invoice line - mirrors the web invoice detail page's rendering: product
/// name plus qty x price = total, with the specific IMEI/serial (if this line is a
/// tracked unit) shown as a small sub-line underneath.
class _InvoiceItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  const _InvoiceItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trackingIdentifier = item['tracking_identifier'] as String?;
    final trackingStatus = item['tracking_status'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(item['product_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(
                '${item['quantity']} x Rs. ${item['unit_price']} = Rs. ${item['line_total']}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
          if (trackingIdentifier != null) ...[
            const SizedBox(height: 6),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 6),
            Text(
              trackingStatus != null && trackingStatus != 'available'
                  ? '($trackingStatus) $trackingIdentifier'
                  : trackingIdentifier,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontFamily: 'monospace'),
            ),
          ],
        ],
      ),
    );
  }
}
