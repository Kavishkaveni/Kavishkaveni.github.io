import 'package:flutter/material.dart';

import 'package:qcitrack/qc_track/core/api_service.dart';
import 'purchase_order_form_page.dart';
import 'purchase_order_print_page.dart';

class PurchaseOrderListPage extends StatefulWidget {
  const PurchaseOrderListPage({super.key});

  @override
  State<PurchaseOrderListPage> createState() => _PurchaseOrderListPageState();
}

class _PurchaseOrderListPageState extends State<PurchaseOrderListPage> {
  bool loading = true;

  List<dynamic> purchaseOrders = [];
  List<dynamic> branches = [];

  String searchQuery = "";
  String statusFilter = "";
  String branchFilter = "";

  final List<String> statuses = [
    "Pending",
    "Completed",
    "Cancelled",
    "Partially Delivered",
  ];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    setState(() => loading = true);
    purchaseOrders = await ApiService.getPurchaseOrders();
    branches = await ApiService.getBranches();
    setState(() => loading = false);
  }

  List<dynamic> get filteredPOs {
    return purchaseOrders.where((po) {
      final matchesSearch = searchQuery.isEmpty ||
          po["id"]
              .toString()
              .toLowerCase()
              .contains(searchQuery.toLowerCase());

      final matchesStatus =
          statusFilter.isEmpty || po["status"] == statusFilter;

      final matchesBranch =
          branchFilter.isEmpty || po["branch_id"] == branchFilter;

      return matchesSearch && matchesStatus && matchesBranch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        title: const Text("Purchase Order Management"),
        backgroundColor: const Color(0xFF0D47A1),
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF0D47A1),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PurchaseOrderFormPage(),
            ),
          ).then((_) => loadData());
        },
        child: const Icon(Icons.add),
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [

                // FILTER CARD
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [

                          // SEARCH
                          TextField(
                            decoration: InputDecoration(
                              hintText: "Search by PO ID",
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onChanged: (v) {
                              setState(() => searchQuery = v);
                            },
                          ),

                          const SizedBox(height: 12),

                          DropdownButtonFormField<String>(
                            value:
                                statusFilter.isEmpty ? null : statusFilter,
                            hint: const Text("All Statuses"),
                            items: statuses
                                .map(
                                  (s) => DropdownMenuItem<String>(
                                    value: s,
                                    child: Text(s),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              setState(() => statusFilter = v ?? "");
                            },
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),

                          const SizedBox(height: 12),

                          DropdownButtonFormField<String>(
                            value:
                                branchFilter.isEmpty ? null : branchFilter,
                            hint: const Text("All Branches"),
                            items: branches
                                .map<DropdownMenuItem<String>>(
                                  (b) => DropdownMenuItem<String>(
                                    value: b["id"].toString(),
                                    child: Text(b["name"].toString()),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              setState(() => branchFilter = v ?? "");
                            },
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // LIST
                Expanded(
                  child: filteredPOs.isEmpty
                      ? const Center(child: Text("No Purchase Orders"))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredPOs.length,
                          itemBuilder: (_, index) {
                            final po = filteredPOs[index];

                            return Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [

                                    Text(
                                      po["id"],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      "${po["supplier_name"]} • ${po["branch_name"]}",
                                      style: const TextStyle(
                                        color: Colors.black54,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text("Status: ${po["status"]}"),

                                    const SizedBox(height: 8),

                                    Row(
                                      children: [

                                        // VIEW
                                        IconButton(
                                          icon: const Icon(
                                            Icons.visibility,
                                            color: Color(0xFF0D47A1),
                                          ),
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    PurchaseOrderFormPage(
                                                  poId: po["id"],
                                                  viewOnly: true,
                                                ),
                                              ),
                                            );
                                          },
                                        ),

                                        // EDIT
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Color(0xFF0D47A1),
                                          ),
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    PurchaseOrderFormPage(
                                                  poId: po["id"],
                                                ),
                                              ),
                                            ).then((_) => loadData());
                                          },
                                        ),

                                        // PRINT
                                        IconButton(
                                          icon: const Icon(
                                            Icons.print,
                                            color: Color(0xFF0D47A1),
                                          ),
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    PurchaseOrderPrintPage(
                                                  purchaseOrder: po,
                                                ),
                                              ),
                                            );
                                          },
                                        ),

                                        // DELETE (WITH POPUP)
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text(
                                                    "Delete Purchase Order"),
                                                content: const Text(
                                                    "Are you sure you want to delete this purchase order?"),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(ctx),
                                                    child:
                                                        const Text("Cancel"),
                                                  ),
                                                  ElevatedButton(
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          Colors.red,
                                                    ),
                                                    onPressed: () async {
                                                      Navigator.pop(ctx);
                                                      await ApiService
                                                          .deletePurchaseOrder(
                                                              po["id"]);
                                                      loadData();
                                                    },
                                                    child:
                                                        const Text("Delete"),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ],
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
    );
  }
}
