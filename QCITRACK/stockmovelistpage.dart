import 'package:flutter/material.dart';
import 'package:qcitrack/qc_track/core/api_service.dart';

import 'stock_branch_page.dart';
import 'stock_move_form_page.dart';
import 'stock_move_print_page.dart';

class StockMoveListPage extends StatefulWidget {
  const StockMoveListPage({super.key});

  @override
  State<StockMoveListPage> createState() => _StockMoveListPageState();
}

class _StockMoveListPageState extends State<StockMoveListPage> {
  // MODULE COLOR (same as dashboard)
  static const Color stockMovementColor = Color(0xFF1F7EA8);

  bool loading = true;

  List<dynamic> movements = [];
  List<dynamic> filteredMovements = [];

  String searchText = '';
  String movementType = '';

  @override
  void initState() {
    super.initState();
    fetchStockMovements();
  }

  // ---------------- FETCH ----------------
  Future<void> fetchStockMovements() async {
    setState(() => loading = true);

    try {
      final data = await ApiService.getStockMovements();
      movements = data;
      applyFilters();
    } catch (e) {
      debugPrint("ERROR FETCHING STOCK MOVEMENTS: $e");
    }

    setState(() => loading = false);
  }

  // ---------------- FILTER ----------------
  void applyFilters() {
    filteredMovements = movements.where((m) {
      final idMatch = searchText.isEmpty
          ? true
          : m['id']
              .toString()
              .toLowerCase()
              .contains(searchText.toLowerCase());

      final typeMatch =
          movementType.isEmpty ? true : m['movement_type'] == movementType;

      return idMatch && typeMatch;
    }).toList();

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),

      appBar: AppBar(
        backgroundColor: stockMovementColor,
        title: const Text("Stock Movement"),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ---------------- SEARCH ----------------
            TextField(
              decoration: const InputDecoration(
                hintText: "Search by Movement ID",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                searchText = value;
                applyFilters();
              },
            ),

            const SizedBox(height: 12),

            // ---------------- DROPDOWN ----------------
            DropdownButtonFormField<String>(
              value: movementType.isEmpty ? null : movementType,
              hint: const Text("All Movement Types"),
              items: const [
                DropdownMenuItem(value: "", child: Text("All Movement Types")),
                DropdownMenuItem(value: "IN", child: Text("Stock IN")),
                DropdownMenuItem(value: "OUT", child: Text("Stock OUT")),
              ],
              onChanged: (value) {
                movementType = value ?? '';
                applyFilters();
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            // ---------------- LIST ----------------
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredMovements.isEmpty
                      ? const Center(child: Text("No stock movements found"))
                      : ListView.builder(
                          itemCount: filteredMovements.length,
                          itemBuilder: (context, index) {
                            final m = filteredMovements[index];

                            return Card(
                              child: ListTile(
                                title: Text(
                                  m['id'].toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  "Status: ${m['status'] ?? 'N/A'}",
                                ),

                                // ✅ ACTION ICONS (MODULE COLOR)
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // VIEW
                                    IconButton(
                                      icon:
                                          const Icon(Icons.visibility),
                                      color: stockMovementColor,
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                StockMoveFormPage(
                                                  stockMovementId:
                                                      m['id'].toString(),
                                                  viewOnly: true,
                                                ),
                                          ),
                                        );
                                      },
                                    ),

                                    // PRINT
                                    IconButton(
                                      icon: const Icon(Icons.print),
                                      color: stockMovementColor,
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                StockMovePrintPage(
                                                  movementId:
                                                      m['id'].toString(),
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

      // ---------------- BOTTOM RIGHT BUTTONS ----------------
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // BRANCH TRANSFER (MODULE COLOR)
          // BRANCH TRANSFER (MODULE COLOR)
FloatingActionButton(
  heroTag: "branchTransfer",
  backgroundColor: stockMovementColor,
  child: const Icon(Icons.compare_arrows),
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BranchTransferPage(),
      ),
    );
  },
),

          const SizedBox(height: 12),

          // ADD NEW
          FloatingActionButton(
            heroTag: "addMovement",
            backgroundColor: stockMovementColor,
            child: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const StockMoveFormPage(isTransfer: false),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
