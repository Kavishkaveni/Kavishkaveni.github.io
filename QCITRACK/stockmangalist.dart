import 'package:flutter/material.dart';
import 'package:qcitrack/qc_track/core/api_service.dart';

import 'stock_form_page.dart';
import 'stock_print_page.dart';

class StockListPage extends StatefulWidget {
  const StockListPage({super.key});

  @override
  State<StockListPage> createState() => _StockListPageState();
}

class _StockListPageState extends State<StockListPage> {
  bool loading = true;

  List<dynamic> stocks = [];
  List<dynamic> branches = [];

  String searchText = '';
  String selectedBranchId = '';
  String selectedStatus = '';

  static const Color stockColor = Color(0xFF0FA4AF);

  @override
  void initState() {
    super.initState();
    loadInitial();
  }

  Future<void> loadInitial() async {
    setState(() => loading = true);
    branches = await ApiService.getBranches();
    await loadStocks();
    setState(() => loading = false);
  }

  Future<void> loadStocks() async {
    stocks = await ApiService.getStocks(
      search: searchText,
      branchId: selectedBranchId,
      status: selectedStatus,
    );
    setState(() {});
  }

  void applyStatus(String status) {
    selectedStatus = status;
    loadStocks();
  }

  void confirmDelete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Stock'),
        content: const Text('Are you sure you want to delete this stock?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await ApiService.deleteStock(id);
      loadStocks();
    }
  }

  Widget statusCard(String label, String status) {
    return Expanded(
      child: InkWell(
        onTap: () => applyStatus(status),
        child: Container(
          height: 70,
          decoration: BoxDecoration(
            color: stockColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: stockColor,
        title: const Text(
          'Stock Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      // ➕ ADD NEW STOCK
      floatingActionButton: FloatingActionButton(
        backgroundColor: stockColor,
        child: const Icon(Icons.add),
        onPressed: () async {
          final refreshed = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StockFormPage()),
          );

          if (refreshed == true) loadStocks();
        },
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // SEARCH
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search by Product / Stock ID',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      searchText = v;
                      loadStocks();
                    },
                  ),

                  const SizedBox(height: 10),

                  // BRANCH
                  DropdownButtonFormField<String>(
                    value:
                        selectedBranchId.isEmpty ? null : selectedBranchId,
                    hint: const Text('Select Branch'),
                    items: branches
                        .map(
                          (b) => DropdownMenuItem<String>(
                            value: b['id'].toString(),
                            child: Text(b['name']),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      selectedBranchId = v ?? '';
                      loadStocks();
                    },
                  ),

                  const SizedBox(height: 12),

                  // STATUS CARDS
                  Row(
                    children: [
                      statusCard('Total', ''),
                      const SizedBox(width: 8),
                      statusCard('Low', 'LOW'),
                      const SizedBox(width: 8),
                      statusCard('Alert', 'ALERT'),
                      const SizedBox(width: 8),
                      statusCard('Expiring', 'EXPIRING'),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // STATUS FILTER
                  DropdownButtonFormField<String>(
                    value: selectedStatus.isEmpty ? null : selectedStatus,
                    hint: const Text('Status'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All')),
                      DropdownMenuItem(value: 'GOOD', child: Text('Good')),
                      DropdownMenuItem(value: 'LOW', child: Text('Low')),
                      DropdownMenuItem(value: 'ALERT', child: Text('Alert')),
                      DropdownMenuItem(
                          value: 'EXPIRING', child: Text('Expiring')),
                    ],
                    onChanged: (v) {
                      selectedStatus = v ?? '';
                      loadStocks();
                    },
                  ),

                  const SizedBox(height: 12),

                  // LIST
                  Expanded(
                    child: stocks.isEmpty
                        ? const Center(child: Text('No stocks found'))
                        : ListView.builder(
                            itemCount: stocks.length,
                            itemBuilder: (_, i) {
                              final s = stocks[i];
                              return Card(
                                child: ListTile(
                                  title: Text(
                                    s['product_name'] ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    'Qty: ${s['quantity']} | Status: ${s['status']}',
                                  ),

                                  // ✅ ICON ACTIONS (NO 3 DOTS)
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.visibility,
                                            color: stockColor),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => StockFormPage(
                                                stockId:
                                                    s['id'].toString(),
                                                viewOnly: true,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.edit,
                                            color: stockColor),
                                        onPressed: () async {
                                          final refreshed =
                                              await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => StockFormPage(
                                                stockId:
                                                    s['id'].toString(),
                                              ),
                                            ),
                                          );

                                          if (refreshed == true) {
                                            loadStocks();
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete,
                                            color: Colors.red),
                                        onPressed: () => confirmDelete(
                                            s['id'].toString()),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.print,
                                            color: stockColor),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  StockPrintPage(
                                                stockId:
                                                    s['id'].toString(),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
