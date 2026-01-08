import 'package:flutter/material.dart';

import 'package:qcitrack/qc_track/core/api_service.dart';

class EODFormPage extends StatefulWidget {
  final String branchId;
  final String? eodId;
  final bool viewOnly;

  const EODFormPage({
    super.key,
    required this.branchId,
    this.eodId,
    this.viewOnly = false,
  });

  @override
  State<EODFormPage> createState() => _EODFormPageState();
}

class _EODFormPageState extends State<EODFormPage> {
  static const Color eodColor = Color(0xFF8B3A2E);

  bool loading = true;
  bool isEdit = false;

  List<dynamic> products = [];
  String? selectedProductId;
  String? stockId; 

  final quantityCtrl = TextEditingController();
  final expectedQtyCtrl = TextEditingController();
  final batchCtrl = TextEditingController();
  final locationCtrl = TextEditingController();
  final rackCtrl = TextEditingController();
  final rowCtrl = TextEditingController();
  final shelfCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final countedByCtrl = TextEditingController();

  String status = "unknown";
  DateTime? lastCountedDate;

  @override
  void initState() {
    super.initState();
    isEdit = widget.eodId != null;
    _loadInitialData();
  }

  // ================= LOAD INITIAL =================
  Future<void> _loadInitialData() async {
    try {
      products = await ApiService.getProductsForDropdown();

      if (isEdit || widget.viewOnly) {
        final data = await ApiService.getEODInventoryById(widget.eodId!);

        selectedProductId = data['product_id']?.toString();
        stockId = data['stock_id']?.toString();

        quantityCtrl.text = data['quantity_in_hand']?.toString() ?? '';
        expectedQtyCtrl.text = data['expected_quantity']?.toString() ?? '';
        batchCtrl.text = data['batch_number'] ?? '';
        locationCtrl.text = data['stock_location'] ?? '';
        rackCtrl.text = data['rack_number'] ?? '';
        rowCtrl.text = data['row_number'] ?? '';
        shelfCtrl.text = data['shelf_number'] ?? '';
        notesCtrl.text = data['notes'] ?? '';
        countedByCtrl.text = data['counted_by'] ?? '';

        lastCountedDate = data['last_counted_date'] != null
            ? DateTime.parse(data['last_counted_date'])
            : null;

        _calculateStatus();
      }
    } finally {
      setState(() => loading = false);
    }
  }

  // ================= AUTO LOAD STOCK =================
  Future<void> _loadStockDetails(String productId) async {
    final stocks = await ApiService.getStocks(
      branchId: widget.branchId,
      productId: productId,
    );

    if (stocks.isEmpty) return;

    final stock = stocks.first;

    setState(() {
      stockId = stock['id']?.toString(); // MOST IMPORTANT

      batchCtrl.text = stock['batch_number'] ?? '';
      locationCtrl.text = stock['stock_location'] ?? '';
      rackCtrl.text = stock['rack_number'] ?? '';
      rowCtrl.text = stock['row_number'] ?? '';
      shelfCtrl.text = stock['shelf_number'] ?? '';
      expectedQtyCtrl.text = stock['quantity']?.toString() ?? '';
      countedByCtrl.text = stock['updated_by'] ?? '';
      lastCountedDate = stock['updated_at'] != null
          ? DateTime.parse(stock['updated_at'])
          : null;

      _calculateStatus();
    });
  }

  // ================= STATUS =================
  void _calculateStatus() {
    final actual = int.tryParse(quantityCtrl.text);
    final expected = int.tryParse(expectedQtyCtrl.text);

    if (actual == null || expected == null) {
      status = "unknown";
    } else if (actual == expected) {
      status = "matched";
    } else if (actual < expected) {
      status = "shortage";
    } else {
      status = "overage";
    }
  }

  // ================= SAVE =================
  Future<void> _save() async {
    if (quantityCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Quantity In Hand is required")),
      );
      return;
    }

    if (!isEdit && stockId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Stock not found for this product")),
      );
      return;
    }

    final payload = {
      "stock_id": stockId, // REQUIRED
      "branch_id": widget.branchId,
      "product_id": selectedProductId,
      "quantity_in_hand": int.parse(quantityCtrl.text),
      "expected_quantity":
          expectedQtyCtrl.text.isNotEmpty ? int.parse(expectedQtyCtrl.text) : null,
      "batch_number": batchCtrl.text,
      "stock_location": locationCtrl.text,
      "rack_number": rackCtrl.text,
      "row_number": rowCtrl.text,
      "shelf_number": shelfCtrl.text,
      "notes": notesCtrl.text,
      "counted_by": countedByCtrl.text,
      "last_counted_date":
          lastCountedDate?.toIso8601String().split('T')[0],
    };

    if (isEdit) {
      await ApiService.updateEODInventory(widget.eodId!, payload);
    } else {
      await ApiService.createEODInventory(payload);
    }

    Navigator.pop(context, true);
  }

  // ================= INPUT =================
  Widget _field(String label, TextEditingController ctrl,
      {bool readOnly = false}) {
    return TextField(
      controller: ctrl,
      readOnly: readOnly || widget.viewOnly,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => _calculateStatus(),
    );
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: eodColor,
        title: Text(isEdit ? "Edit Inventory Count" : "Add Inventory Count"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: selectedProductId,
                decoration: const InputDecoration(labelText: "Product"),
                items: products.map<DropdownMenuItem<String>>((p) {
                  return DropdownMenuItem(
                    value: p['id'].toString(),
                    child: Text(p['name'].toString()),
                  );
                }).toList(),
                onChanged: widget.viewOnly
                    ? null
                    : (v) async {
                        setState(() => selectedProductId = v);
                        await _loadStockDetails(v!);
                      },
              ),

              _field("Quantity In Hand", quantityCtrl),
              _field("Expected Quantity", expectedQtyCtrl, readOnly: true),
              _field("Batch Number", batchCtrl),
              _field("Location", locationCtrl),
              _field("Rack Number", rackCtrl),
              _field("Row Number", rowCtrl),
              _field("Shelf Number", shelfCtrl),
              _field("Notes", notesCtrl),
              _field("Counted By", countedByCtrl),

              const SizedBox(height: 12),

              Row(
                children: [
                  const Text("Status: ",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(status.toUpperCase()),
                ],
              ),

              const SizedBox(height: 24),

              if (!widget.viewOnly)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: eodColor,
                    side: const BorderSide(color: eodColor),
                  ),
                  onPressed: _save,
                  child: Text(isEdit ? "Update Inventory" : "Add Inventory"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
