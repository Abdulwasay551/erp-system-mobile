import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/pdf_helper.dart';
import '../services/connectivity_service.dart';
import '../theme/app_semantic_colors.dart';
import '../widgets/trend_line_chart.dart';
import '../widgets/contact_actions.dart';
import '../widgets/info_icon_button.dart';
import 'contact_form_screen.dart' show ContactKind;

/// Full customer/supplier dashboard - the mobile counterpart to the web's
/// contacts/{customers,suppliers}/detail pages. Replaces the old row-tap bottom sheet
/// (which only showed one unpaged combined ledger): four tabs, real pagination, and a
/// spend-over-time chart, parameterized on ContactKind since the backend endpoints are
/// identical in shape between customers and suppliers.
class ContactDetailScreen extends StatefulWidget {
  final ContactKind kind;
  final Map<String, dynamic> contact;
  const ContactDetailScreen({super.key, required this.kind, required this.contact});

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> {
  Map<String, dynamic>? _detail;

  ApiClient get _api => context.read<AuthService>().api;
  bool get _isCustomer => widget.kind == ContactKind.customer;
  String get _base => _isCustomer ? '/api/crm/customers/${widget.contact['id']}' : '/api/purchase/suppliers/${widget.contact['id']}';

  @override
  void initState() {
    super.initState();
    _loadHeader();
  }

  Future<void> _loadHeader() async {
    try {
      final data = await _api.request('$_base/') as Map<String, dynamic>;
      if (mounted) setState(() => _detail = data);
    } catch (_) {
      // Keep the list-row snapshot on failure - the tabs below will surface their own errors.
    }
  }

  Future<void> _pay() async {
    final contact = _detail ?? widget.contact;
    final outstanding = double.tryParse(contact['outstanding_balance']?.toString() ?? '0') ?? 0;
    final online = context.read<ConnectivityService>().isOnline;
    final done = await recordContactPayment(context, api: _api, online: online, kind: widget.kind, item: widget.contact, outstanding: outstanding);
    if (done) _loadHeader();
  }

  Future<void> _adjust() async {
    final online = context.read<ConnectivityService>().isOnline;
    final done = await recordContactAdjustment(context, api: _api, online: online, kind: widget.kind, item: widget.contact);
    if (done) _loadHeader();
  }

  @override
  Widget build(BuildContext context) {
    final contact = _detail ?? widget.contact;
    final name = contact['name'] as String? ?? '';
    final outstanding = double.tryParse(contact['outstanding_balance']?.toString() ?? '0') ?? 0;
    final isAdmin = context.watch<AuthService>().isAdmin;
    final contactId = widget.contact['id'] as int;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(name),
          bottom: TabBar(
            isScrollable: true,
            tabs: [Tab(text: _isCustomer ? 'Invoices' : 'Bills'), const Tab(text: 'Payments'), const Tab(text: 'Ledger'), const Tab(text: 'Analytics')],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact['phone']?.toString() ?? '', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Outstanding: Rs. ${outstanding.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: outstanding > 0 ? context.semanticColors.warning : null,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InfoIconButton(
                        message: _isCustomer
                            ? 'Total amount this customer currently owes you: invoices billed, minus payments received and credit notes issued.'
                            : 'Total amount you currently owe this supplier: bills received, minus payments you made and returns/debit notes issued.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(icon: const Icon(Icons.payments_outlined), label: const Text('Pay'), onPressed: _pay),
                      if (isAdmin)
                        OutlinedButton.icon(icon: const Icon(Icons.swap_horiz), label: const Text('Adjust'), onPressed: _adjust),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _TxTab(kind: widget.kind, contactId: contactId),
                  _LedgerFilteredTab(kind: widget.kind, contactId: contactId, referenceType: 'payment'),
                  _LedgerFilteredTab(kind: widget.kind, contactId: contactId, showPdf: true, name: name),
                  _AnalyticsTab(kind: widget.kind, contactId: contactId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TxTab extends StatefulWidget {
  final ContactKind kind;
  final int contactId;
  const _TxTab({required this.kind, required this.contactId});

  @override
  State<_TxTab> createState() => _TxTabState();
}

class _TxTabState extends State<_TxTab> {
  final _searchController = TextEditingController();
  List<dynamic> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;

  ApiClient get _api => context.read<AuthService>().api;
  bool get _isCustomer => widget.kind == ContactKind.customer;
  String get _path => _isCustomer ? '/api/crm/customers/${widget.contactId}/invoices/' : '/api/purchase/suppliers/${widget.contactId}/bills/';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      'page_size': '25',
      if (_searchController.text.isNotEmpty) 'search': _searchController.text,
    };
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    try {
      final data = await _api.request('$_path?$qs') as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      if (mounted) {
        setState(() {
          _items = reset ? results : [..._items, ...results];
          _hasMore = _page < (data['total_pages'] as int? ?? 1);
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search ${_isCustomer ? "invoice" : "bill"} number...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => _load()),
            ),
            onSubmitted: (_) => _load(),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(child: Text('No results.'))
                  : ListView.builder(
                      itemCount: _items.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _items.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: _loadingMore
                                  ? const CircularProgressIndicator()
                                  : TextButton(onPressed: _loadMore, child: const Text('Load more')),
                            ),
                          );
                        }
                        final item = _items[i] as Map<String, dynamic>;
                        final number = _isCustomer ? item['invoice_number'] : item['bill_number'];
                        final date = _isCustomer ? item['invoice_date'] : item['bill_date'];
                        final total = _isCustomer ? item['total'] : item['total_amount'];
                        return ListTile(
                          title: Text(number?.toString() ?? ''),
                          subtitle: Text(date?.toString() ?? ''),
                          trailing: Text('Rs. $total'),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _LedgerFilteredTab extends StatefulWidget {
  final ContactKind kind;
  final int contactId;
  final String? referenceType;
  final bool showPdf;
  final String name;
  const _LedgerFilteredTab({required this.kind, required this.contactId, this.referenceType, this.showPdf = false, this.name = ''});

  @override
  State<_LedgerFilteredTab> createState() => _LedgerFilteredTabState();
}

class _LedgerFilteredTabState extends State<_LedgerFilteredTab> {
  List<dynamic> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final Map<int, Map<String, dynamic>?> _details = {};
  int? _loadingDetailId;

  ApiClient get _api => context.read<AuthService>().api;
  bool get _isCustomer => widget.kind == ContactKind.customer;
  String get _endpoint => _isCustomer ? '/api/crm/customers/${widget.contactId}' : '/api/purchase/suppliers/${widget.contactId}';
  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
      'page_size': '20',
      if (widget.referenceType != null) 'reference_type': widget.referenceType!,
      if (_dateFrom != null) 'date_from': _fmt(_dateFrom!),
      if (_dateTo != null) 'date_to': _fmt(_dateTo!),
    };
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    try {
      final data = await _api.request('$_endpoint/ledger/?$qs') as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      if (mounted) {
        setState(() {
          _items = reset ? results : [..._items, ...results];
          _hasMore = _page < (data['total_pages'] as int? ?? 1);
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _loading = _loadingMore = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    _page++;
    await _load(reset: false);
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _dateFrom : _dateTo) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => isFrom ? _dateFrom = picked : _dateTo = picked);
  }

  Future<void> _loadDetail(int entryId) async {
    if (_details.containsKey(entryId)) return;
    setState(() => _loadingDetailId = entryId);
    try {
      final data = await _api.request('$_endpoint/ledger/$entryId/detail/') as Map<String, dynamic>;
      if (mounted) setState(() => _details[entryId] = data['detail'] as Map<String, dynamic>?);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
        setState(() => _details[entryId] = null);
      }
    } finally {
      if (mounted) setState(() => _loadingDetailId = null);
    }
  }

  Future<void> _downloadPdf(bool extended) async {
    final messenger = ScaffoldMessenger.of(context);
    final params = {
      if (_dateFrom != null) 'date_from': _fmt(_dateFrom!),
      if (_dateTo != null) 'date_to': _fmt(_dateTo!),
      if (extended) 'extended': 'true',
    };
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    try {
      await downloadAndOpenPdf(_api, '$_endpoint/ledger/pdf/?$qs', '${widget.name}-ledger${extended ? '-extended' : ''}.pdf');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _buildDetail(Map<String, dynamic>? detail) {
    if (detail == null) return const Padding(padding: EdgeInsets.all(12), child: Text('No further detail available.'));
    if (detail['kind'] == 'payment') {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Wrap(
          spacing: 16,
          children: [
            Text('Method: ${detail['method']}'),
            if ((detail['reference'] as String?)?.isNotEmpty == true) Text('Ref: ${detail['reference']}'),
            Text('Payment #: ${detail['number']}'),
          ],
        ),
      );
    }
    final items = (detail['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          final trackingUnits = (item['tracking_units'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
          final codes = detail['kind'] == 'invoice'
              ? (item['tracking_identifier'] as String?)
              : (trackingUnits.map((u) => u['code']).where((c) => c != null).join(', '));
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${item['quantity']}x ${item['product_name']}${codes != null && codes.isNotEmpty ? ' [$codes]' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text('Rs. ${item['line_total']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expandableTypes = _isCustomer ? const {'invoice', 'payment'} : const {'bill', 'payment'};
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
              const SizedBox(width: 6),
              IconButton(icon: const Icon(Icons.filter_alt_outlined), tooltip: 'Apply filter', onPressed: () => _load()),
              if (widget.showPdf)
                PopupMenuButton<bool>(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: 'Download PDF',
                  onSelected: _downloadPdf,
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: false, child: Text('Standard PDF')),
                    PopupMenuItem(value: true, child: Text('Extended PDF (line items & tracking)')),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(child: Text('No transactions yet.'))
                  : ListView.builder(
                      itemCount: _items.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _items.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: _loadingMore
                                  ? const CircularProgressIndicator()
                                  : TextButton(onPressed: _loadMore, child: const Text('Load more')),
                            ),
                          );
                        }
                        final e = _items[i] as Map<String, dynamic>;
                        final entryId = e['id'] as int;
                        final debit = double.tryParse(e['debit_amount']?.toString() ?? '0') ?? 0;
                        final credit = double.tryParse(e['credit_amount']?.toString() ?? '0') ?? 0;
                        final refType = e['reference_type'] as String? ?? '';
                        final trailing = Text(
                          debit > 0 ? '+Rs. ${debit.toStringAsFixed(0)}' : '-Rs. ${credit.toStringAsFixed(0)}',
                          style: TextStyle(color: debit > 0 ? context.semanticColors.danger : context.semanticColors.success),
                        );
                        if (!expandableTypes.contains(refType)) {
                          return ListTile(
                            dense: true,
                            title: Text(e['description']?.toString() ?? ''),
                            subtitle: Text(e['transaction_date']?.toString() ?? ''),
                            trailing: trailing,
                          );
                        }
                        return ExpansionTile(
                          dense: true,
                          title: Text(e['description']?.toString() ?? ''),
                          subtitle: Text(e['transaction_date']?.toString() ?? ''),
                          trailing: trailing,
                          onExpansionChanged: (open) {
                            if (open) _loadDetail(entryId);
                          },
                          children: [
                            if (_loadingDetailId == entryId)
                              const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                            else
                              _buildDetail(_details[entryId]),
                          ],
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _AnalyticsTab extends StatefulWidget {
  final ContactKind kind;
  final int contactId;
  const _AnalyticsTab({required this.kind, required this.contactId});

  @override
  State<_AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<_AnalyticsTab> {
  List<dynamic>? _days;
  bool _loading = true;

  ApiClient get _api => context.read<AuthService>().api;
  bool get _isCustomer => widget.kind == ContactKind.customer;
  String get _path => _isCustomer ? '/api/crm/customers/${widget.contactId}/analytics/' : '/api/purchase/suppliers/${widget.contactId}/analytics/';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.request('$_path?days=90') as Map<String, dynamic>;
      if (mounted) setState(() => _days = data['days'] as List<dynamic>);
    } catch (_) {
      // Chart just stays empty on failure - no separate error UI needed for a
      // secondary/nice-to-have analytics tab.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final days = _days ?? [];
    final countKey = _isCustomer ? 'invoice_count' : 'bill_count';
    double totalSpend = 0;
    int totalCount = 0;
    for (final d in days) {
      final m = d as Map<String, dynamic>;
      totalSpend += double.tryParse(m['spend']?.toString() ?? '0') ?? 0;
      totalCount += (m[countKey] as int? ?? 0);
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.4,
          children: [
            _statCard(context, 'Total Spend (90d)', 'Rs. ${totalSpend.toStringAsFixed(0)}'),
            _statCard(context, '${_isCustomer ? "Invoices" : "Bills"} (90d)', '$totalCount'),
            _statCard(context, 'Avg per ${_isCustomer ? "Invoice" : "Bill"}', 'Rs. ${(totalCount > 0 ? totalSpend / totalCount : 0).toStringAsFixed(0)}'),
          ],
        ),
        const SizedBox(height: 12),
        TrendLineChart(
          title: 'Spend Over Time',
          points: days.map((d) {
            final m = d as Map<String, dynamic>;
            final date = m['date'] as String;
            return MapEntry(date.length >= 10 ? date.substring(5, 10) : date, double.tryParse(m['spend']?.toString() ?? '0') ?? 0);
          }).toList(),
          tooltipFormatter: (v) => 'Rs. ${v.toStringAsFixed(0)}',
        ),
      ],
    );
  }

  Widget _statCard(BuildContext context, String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
