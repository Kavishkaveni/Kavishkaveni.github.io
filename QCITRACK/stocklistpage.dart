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

  List<dynamic> allStocks = [];
  List<dynamic> filteredStocks = [];
  List<dynamic> branches = [];

  // ✅ NEW: Locations list from API
  List<dynamic> locations = [];

  String searchText = '';
  String selectedBranchId = '';
  String selectedStatus = '';

  // ✅ NEW: Selected location filter
  String selectedLocation = '';

  // pagination
  int currentPage = 1;
  final int pageSize = 5;

  static const Color stockColor = Color(0xFF0FA4AF);

  @override
  void initState() {
    super.initState();
    loadInitial();
  }

  Future<void> loadInitial() async {
    setState(() => loading = true);

    // existing
    branches = await ApiService.getBranches();

    // ✅ NEW: set default branch if only one branch exists
    if (branches.length == 1 && selectedBranchId.isEmpty) {
      selectedBranchId = branches.first['id'].toString();
    }

    // ✅ NEW: load locations from API (must return list)
    // Expected formats supported:
    // 1) ["Loc1","Loc2"]
    // 2) [{"name":"Loc1"}, {"name":"Loc2"}]
    // 3) [{"stock_location":"Loc1"}, ...]
    try {
      locations = await ApiService.getStockLocations();
    } catch (_) {
      locations = [];
    }

    await loadStocks();

    setState(() => loading = false);
  }

  Future<void> loadStocks() async {
    allStocks = await ApiService.getStocks(
      search: searchText,
      branchId: selectedBranchId,
      status: '',
    );

    applyFilters();
  }

  void applyFilters() {
    List<dynamic> temp = [...allStocks];

    // ✅ NEW: LOCATION FILTER (All Locations = selectedLocation is empty)
    if (selectedLocation.isNotEmpty) {
      temp = temp.where((s) {
        final loc = (s['stock_location'] ?? '').toString();
        return loc == selectedLocation;
      }).toList();
    }

    // STATUS FILTER
    if (selectedStatus.isNotEmpty) {
      if (selectedStatus == 'EXPIRING') {
        final now = DateTime.now();
        final limit = now.add(const Duration(days: 30));

        temp = temp.where((s) {
          if (s['expiry_date'] == null) return false;
          final exp = DateTime.tryParse(s['expiry_date'].toString());
          if (exp == null) return false;
          return exp.isBefore(limit);
        }).toList();
      } else {
        temp = temp.where((s) => s['status'] == selectedStatus).toList();
      }
    }

    filteredStocks = temp;
    currentPage = 1;
    setState(() {});
  }

  List<dynamic> get paginatedStocks {
    final start = (currentPage - 1) * pageSize;
    final end = start + pageSize;
    return filteredStocks.sublist(
      start,
      end > filteredStocks.length ? filteredStocks.length : end,
    );
  }

  int get totalPages =>
      (filteredStocks.length / pageSize).ceil().clamp(1, 999);

  void applyStatus(String status) {
    selectedStatus = status;
    applyFilters();
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
      await loadStocks();
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

  // ✅ NEW: Convert API "locations" list to dropdown strings safely
  List<String> get locationOptions {
    final List<String> opts = [];
    for (final item in locations) {
      if (item == null) continue;

      if (item is String) {
        if (item.trim().isNotEmpty) opts.add(item.trim());
      } else if (item is Map) {
        final v1 = (item['name'] ?? '').toString().trim();
        final v2 = (item['stock_location'] ?? '').toString().trim();
        final v = v1.isNotEmpty ? v1 : v2;
        if (v.isNotEmpty) opts.add(v);
      } else {
        final v = item.toString().trim();
        if (v.isNotEmpty) opts.add(v);
      }
    }

    // remove duplicates
    return opts.toSet().toList();
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

                  // BRANCH (default branch already auto-selected if only one)
                  DropdownButtonFormField<String>(
                    value: selectedBranchId.isEmpty ? null : selectedBranchId,
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

                  const SizedBox(height: 10),

                  // ✅ NEW: LOCATION DROPDOWN (All Locations + API locations)
                  DropdownButtonFormField<String>(
                    value: selectedLocation.isEmpty ? '' : selectedLocation,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('All Locations'),
                      ),
                      ...locationOptions.map(
                        (loc) => DropdownMenuItem<String>(
                          value: loc,
                          child: Text(loc),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      selectedLocation = v ?? '';
                      applyFilters();
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

                  Expanded(
                    child: paginatedStocks.isEmpty
                        ? const Center(child: Text('No stocks found'))
                        : ListView.builder(
                            itemCount: paginatedStocks.length,
                            itemBuilder: (_, i) {
                              final s = paginatedStocks[i];
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
                                                stockId: s['id'].toString(),
                                                viewOnly: true,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon:
                                            Icon(Icons.edit, color: stockColor),
                                        onPressed: () async {
                                          final refreshed =
                                              await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => StockFormPage(
                                                stockId: s['id'].toString(),
                                              ),
                                            ),
                                          );
                                          if (refreshed == true) loadStocks();
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete,
                                            color: Colors.red),
                                        onPressed: () =>
                                            confirmDelete(s['id'].toString()),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.print,
                                            color: stockColor),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => StockPrintPage(
                                                stockId: s['id'].toString(),
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

                  // PAGINATION
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: currentPage > 1
                            ? () => setState(() => currentPage--)
                            : null,
                      ),
                      Text('Page $currentPage of $totalPages'),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: currentPage < totalPages
                            ? () => setState(() => currentPage++)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
