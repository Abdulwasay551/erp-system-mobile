import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';

const _typeLabel = {
  'invoice': 'Invoice',
  'bill': 'Vendor Bill',
  'credit_note': 'Credit Note',
  'payment': 'Payment',
  'purchase_payment': 'Vendor Payment',
  'product': 'Product',
  'customer': 'Customer',
  'supplier': 'Supplier',
};

/// Full-page search hitting the same /api/core/search/ endpoint the web app's header
/// search bar uses - looks up any invoice/bill/product/customer/supplier by number or
/// name from one place.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<dynamic> _results = [];
  bool _loading = false;
  Timer? _debounce;

  ApiClient get _api => context.read<AuthService>().api;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final data = await _api.request('/api/core/search/?q=${Uri.encodeComponent(q)}');
      if (mounted) setState(() => _results = (data['results'] as List<dynamic>?) ?? []);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Search invoices, products, customers...',
            border: InputBorder.none,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? Center(
                  child: Text(
                    _controller.text.trim().length < 2 ? 'Type at least 2 characters to search.' : 'No matches.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final r = _results[i] as Map<String, dynamic>;
                    return ListTile(
                      title: Text(r['label']?.toString() ?? ''),
                      subtitle: r['subtitle'] != null && r['subtitle'].toString().isNotEmpty
                          ? Text(r['subtitle'].toString())
                          : null,
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          _typeLabel[r['type']] ?? r['type'].toString(),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
