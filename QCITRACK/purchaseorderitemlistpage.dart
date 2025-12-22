import 'package:flutter/material.dart';

import 'package:qcitrack/qc_track/core/api_service.dart';
import 'purchase_order_item_form_page.dart';

class PurchaseOrderItemListPage extends StatefulWidget {
  const PurchaseOrderItemListPage({super.key});

  @override
  State<PurchaseOrderItemListPage> createState() =>
      _PurchaseOrderItemListPageState();
}

class _PurchaseOrderItemListPageState extends State<PurchaseOrderItemListPage> {
  bool loading = true;

  List<dynamic> items = [];
  List<dynamic> purchaseOrders = [];

  String searchQuery = "";
  String statusFilter = "";
  String poFilter = "";

  final List<String> statuses = [
    "Delivered",
    "Pending",
    "Backordered",
    "Partially Delivered",
  ];

  // ---------- SAFE LIST EXTRACTOR ----------
  List<dynamic> _extractList(dynamic res, {String key = "items"}) {
    if (res is Map) {
      final v = res[key];
      if (v is List) return v;
      return [];
    }
    if (res is List) return res;
    return [];
  }

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    setState(() => loading = true);
    try {
      final resItems = await ApiService.getPurchaseOrderItems();
      items = _extractList(resItems, key: "items");

      final resPOs = await ApiService.getPurchaseOrders();
      purchaseOrders = _extractList(resPOs, key: "items");
    } catch (e) {
      items = [];
      purchaseOrders = [];
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<dynamic> get filteredItems {
    return items.where((it) {
      final poNumber = (it["purchase_order_number"] ??
              it["purchase_order_id"] ??
              it["order_id"] ??
              "")
          .toString()
          .toLowerCase();

      final matchesSearch =
          searchQuery.isEmpty || poNumber.contains(searchQuery.toLowerCase());

      final matchesStatus =
          statusFilter.isEmpty || it["status"] == statusFilter;

      final itPoId =
          (it["purchase_order_id"] ?? it["order_id"] ?? "").toString();

      final matchesPO = poFilter.isEmpty || itPoId == poFilter;

      return matchesSearch && matchesStatus && matchesPO;
    }).toList();
  }

  InputDecoration _inputDecoration({required String hint, Widget? prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54),
      prefixIcon: prefixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFBDBDBD)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF9E9E9E), width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
    );
  }

  Widget _buildFilters() {
    return Card(
      color: const Color(0xFFF2F2F2),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              decoration: _inputDecoration(
                hint: "Search by PO number",
                prefixIcon: const Icon(Icons.search),
              ),
              style: const TextStyle(fontWeight: FontWeight.w800),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: statusFilter.isEmpty ? null : statusFilter,
              hint: const Text(
                "All Statuses",
                style:
                    TextStyle(fontWeight: FontWeight.w800, color: Colors.black),
              ),
              items: statuses
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          s,
                          style:
                              const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => statusFilter = v ?? ""),
              decoration: _inputDecoration(hint: "All Statuses"),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: poFilter.isEmpty ? null : poFilter,
              hint: const Text(
                "All Purchase Orders",
                style:
                    TextStyle(fontWeight: FontWeight.w800, color: Colors.black),
              ),
              items: purchaseOrders.map<DropdownMenuItem<String>>((po) {
                final id = po["id"].toString();
                return DropdownMenuItem(
                  value: id,
                  child: Text(
                    id,
                    style:
                        const TextStyle(fontWeight: FontWeight.w800),
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => poFilter = v ?? ""),
              decoration: _inputDecoration(hint: "All Purchase Orders"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String itemId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(
        "Delete Item",
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: const Text(
        "Are you sure you want to delete this purchase order item?",
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(
            "Cancel",
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            "Delete",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.red,
            ),
          ),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    try {
      await ApiService.deletePurchaseOrderItem(itemId);
      loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to delete item")),
      );
    }
  }
}

  Widget _buildItemCard(dynamic it) {
    final poNo = it["purchase_order_number"] ??
        it["purchase_order_id"] ??
        it["order_id"];

    final status = it["status"] ?? "";

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // LEFT INFO
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "PO $poNo",
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Status: $status",
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

            // RIGHT ACTIONS
            Row(
              children: [
                IconButton(
                  icon:
                      const Icon(Icons.visibility, color: Colors.blueGrey),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PurchaseOrderItemFormPage(
                          itemId: it["id"].toString(),
                          viewOnly: true,
                        ),
                      ),
                    ).then((_) => loadData());
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blueGrey),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PurchaseOrderItemFormPage(
                          itemId: it["id"].toString(),
                          viewOnly: false,
                        ),
                      ),
                    ).then((_) => loadData());
                  },
                ),
                IconButton(
  icon: const Icon(Icons.delete, color: Colors.red),
  onPressed: () {
    _confirmDelete(it["id"].toString());
  },
),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: const Text(
          "Purchase Order Items",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: const Color(0xFF9E9E9E),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildFilters(),
                ),
                Expanded(
                  child: filteredItems.isEmpty
                      ? const Center(
                          child: Text(
                            "No purchase order items found",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Colors.black87,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredItems.length,
                          itemBuilder: (_, i) =>
                              _buildItemCard(filteredItems[i]),
                        ),
                ),
              ],
            ),
    );
  }
}
