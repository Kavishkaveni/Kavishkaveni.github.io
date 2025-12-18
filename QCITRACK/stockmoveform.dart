import 'package:flutter/material.dart';

import '../core/api_service.dart';

class StockMoveFormPage extends StatefulWidget {
  final bool isTransfer;
  final bool viewOnly;
  final String? stockMovementId;

  const StockMoveFormPage({
    super.key,
    this.isTransfer = false,
    this.viewOnly = false,
    this.stockMovementId,
  });

  @override
  State<StockMoveFormPage> createState() => _StockMoveFormPageState();
}

class _StockMoveFormPageState extends State<StockMoveFormPage> {
  static const Color moduleColor = Color(0xFF1F7EA8);
  final _formKey = GlobalKey<FormState>();

  // ================= DATA (dropdown sources) =================
  List<dynamic> stocks = [];
  List<dynamic> branches = [];
  bool loading = true;

  // ================= FORM / VIEW VALUES =================
  String movementType = 'IN'; // IN | OUT
  String? status;

  String? stockId;
  String? productName;
  String? supplierName;

  String? reason;
  String? promotionType;
  String? batchNumber;

  String? sourceLocation;       // can auto-fill
  String? destinationLocation;  // choose / type

  int quantity = 0;
  int discountedQuantity = 0;

  DateTime? movementDate;
  DateTime? expiryDate;

  // ====== VIEW EXTRA (FROM BACKEND) ======
  String? createdBy;
  String? updatedBy;
  DateTime? createdAt;
  DateTime? updatedAt;

  // ================= DROPDOWN OPTIONS =================
  static const List<String> statusOptions = [
    "Received",
    "Dispatched",
    "In Transit",
    "Pending",
    "Cancelled",
  ];

  static const List<String> reasonOptions = [
    "Return In",
    "Return Out",
    "Sales",
    "Purchase",
    "Branch Transfer",
    "Other",
  ];

  // ================= INIT =================
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // load dropdown data
      stocks = await ApiService.getStocks();
      branches = await ApiService.getBranches();

      // set defaults for ADD NEW
      if (!widget.viewOnly) {
        status = "Received";
        movementDate = DateTime.now();
      }

      // load data for VIEW
      if (widget.viewOnly && widget.stockMovementId != null) {
        await _loadViewData();
      }
    } catch (e) {
      debugPrint("INIT ERROR: $e");
    }

    setState(() => loading = false);
  }

  // ================= LOAD VIEW DATA (16 fields) =================
  Future<void> _loadViewData() async {
    final m = await ApiService.getStockMovementById(widget.stockMovementId!);

    setState(() {
      stockId = m['stock_id']?.toString();
      productName = m['product_name']?.toString();
      supplierName = m['supplier_name']?.toString();

      movementType = (m['movement_type'] ?? 'IN').toString();

      final incomingStatus = m['status']?.toString();
      status = statusOptions.contains(incomingStatus) ? incomingStatus : null;

      reason = m['reason']?.toString();
      promotionType = m['promotion_type']?.toString();
      batchNumber = m['batch_number']?.toString();

      sourceLocation = m['source_location']?.toString();
      destinationLocation = m['destination_location']?.toString();

      quantity = (m['quantity'] ?? 0) is int
          ? (m['quantity'] ?? 0)
          : int.tryParse(m['quantity'].toString()) ?? 0;

      discountedQuantity = (m['discounted_quantity'] ?? 0) is int
          ? (m['discounted_quantity'] ?? 0)
          : int.tryParse(m['discounted_quantity'].toString()) ?? 0;

      movementDate = DateTime.tryParse(m['movement_date']?.toString() ?? '');
      expiryDate = DateTime.tryParse(m['expiry_date']?.toString() ?? '');

      // ✅ Missing fields you asked — now loaded from backend
      createdBy = m['created_by']?.toString();
      updatedBy = m['updated_by']?.toString();
      createdAt = DateTime.tryParse(m['created_at']?.toString() ?? '');
      updatedAt = DateTime.tryParse(m['updated_at']?.toString() ?? '');
    });
  }

  // ================= SAVE (ADD NEW) =================
  Future<void> saveMovement() async {
    if (!_formKey.currentState!.validate()) return;

    final payload = {
      "movement_type": movementType,
      "status": status,
      "stock_id": stockId,
      "quantity": quantity,
      "discounted_quantity": discountedQuantity,
      "reason": reason,
      "promotion_type": promotionType,
      "batch_number": batchNumber,
      "movement_date": movementDate?.toIso8601String(),
      "expiry_date": expiryDate?.toIso8601String(),
      "source_location": sourceLocation,
      "destination_location": destinationLocation,
    };

    await ApiService.createStockMovement(payload);
    Navigator.pop(context);
  }

  // ================= UI ROOT =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: moduleColor,
        title: Text(
          widget.viewOnly
              ? "Stock Movement Details"
              : widget.isTransfer
                  ? "Branch Transfer"
                  : "Add New Stock Movement",
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : widget.viewOnly
              ? _buildViewUI() // ✅ VIEW (16 fields)
              : _buildAddFormUI(), // ✅ ADD NEW (16 fields)
    );
  }

  // ============================================================
  // ======================= VIEW UI (16 fields) =================
  // ============================================================
  Widget _buildViewUI() {
    TextStyle labelStyle = const TextStyle(
      color: Colors.grey,
      fontSize: 13,
    );

    TextStyle valueStyle = const TextStyle(
      color: Colors.black,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    );

    Widget field(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: labelStyle),
            const SizedBox(height: 3),
            Text(value, style: valueStyle),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---------- HEADER (NO OVERLAP) ----------
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    "Movement ID: ${widget.stockMovementId ?? '-'}",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      backgroundColor: Colors.green.shade50,
                      label: Text(
                        movementType == 'IN' ? "STOCK IN" : "STOCK OUT",
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Chip(
                      backgroundColor: Colors.blue.shade50,
                      label: Text(
                        status ?? "N/A",
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ---------- DETAILS (ALL 16 FIELDS) ----------
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1–3
                field("Stock ID", _na(stockId)),
                field("Product", _na(productName)),
                field("Reason", _na(reason)),

                // 4–6
                field("Quantity", quantity.toString()),
                field("Discounted Quantity", discountedQuantity.toString()),
                field("Promotion Type", _na(promotionType)),

                // 7–9
                field("Batch Number", _na(batchNumber)),
                field("Movement Date", _fmtDateTime(movementDate)),
                field("Expiry Date", _fmtDateTime(expiryDate)),

                // 10–12
                field("Source Location", _na(sourceLocation)),
                field("Destination Location", _na(destinationLocation)),
                field("Supplier", _na(supplierName)),

                // 13–16 ✅ (the missing ones you shouted about)
                field("Created By", _na(createdBy)),
                field("Updated By", _na(updatedBy)),
                field("Created At", _fmtDateTime(createdAt)),
                field("Updated At", _fmtDateTime(updatedAt)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // ---------- BACK BUTTON ----------
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: moduleColor),
            foregroundColor: moduleColor,
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text("Back to List"),
        ),
      ],
    );
  }

  // ============================================================
  // ================== ADD NEW UI (16 fields) ===================
  // ============================================================
  // ============================================================
// ================== ADD NEW UI (16 fields) ===================
// ============================================================
Widget _buildAddFormUI() {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Form(
      key: _formKey,
      child: ListView(
        children: [

          // ---------- 1) MOVEMENT TYPE ----------
          const Text(
            "Movement Type *",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Radio<String>(
                value: 'IN',
                groupValue: movementType,
                onChanged: (v) => setState(() => movementType = v!),
              ),
              const Text("Stock IN"),
              const SizedBox(width: 16),
              Radio<String>(
                value: 'OUT',
                groupValue: movementType,
                onChanged: (v) => setState(() => movementType = v!),
              ),
              const Text("Stock OUT"),
            ],
          ),

          const SizedBox(height: 16),

          // ---------- 2) STATUS ----------
          DropdownButtonFormField<String>(
            value: status,
            decoration: const InputDecoration(
              labelText: "Status *",
              border: OutlineInputBorder(),
            ),
            items: statusOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => status = v),
            validator: (v) =>
                (v == null || v.isEmpty) ? "Select status" : null,
          ),

          const SizedBox(height: 16),

          // ---------- 3) STOCK ID ----------
          DropdownButtonFormField<String>(
            value: stockId,
            decoration: const InputDecoration(
              labelText: "Stock ID *",
              border: OutlineInputBorder(),
            ),
            items: stocks
                .map<DropdownMenuItem<String>>(
                  (s) => DropdownMenuItem(
                    value: s['id'].toString(),
                    child: Text(
                      "${s['id']} - ${s['product_name'] ?? ''}",
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
  if (v == null) return;

  onChanged: (v) async {
  if (v == null) return;

  setState(() {
    stockId = v;
  });

  try {
    final details =
        await ApiService.getStockDetailsForMovement(v);

    setState(() {
      productName = details['product_name']?.toString();
      supplierName = details['supplier_name']?.toString();
      sourceLocation = details['source_location']?.toString();
    });

    debugPrint("AUTO PRODUCT: $productName");
    debugPrint("AUTO SUPPLIER: $supplierName");
    debugPrint("AUTO LOCATION: $sourceLocation");

  } catch (e) {
    debugPrint("AUTO-FILL ERROR: $e");
  }
},

  // DEBUG (VERY IMPORTANT)
  debugPrint("AUTO PRODUCT: $productName");
  debugPrint("AUTO LOCATION: $sourceLocation");
},
            validator: (v) =>
                (v == null || v.isEmpty) ? "Select stock" : null,
          ),

          const SizedBox(height: 16),

          // ---------- 4) PRODUCT (AUTO) ----------
          _readOnlyBox("Product *", productName),

          const SizedBox(height: 16),

          // ---------- 5) SUPPLIER (AUTO) ----------
          _readOnlyBox("Supplier", supplierName),

          const SizedBox(height: 16),

          // ---------- 6) REASON ----------
          DropdownButtonFormField<String>(
            value: reason,
            decoration: const InputDecoration(
              labelText: "Reason for Movement *",
              border: OutlineInputBorder(),
            ),
            items: reasonOptions
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) => setState(() => reason = v),
            validator: (v) =>
                (v == null || v.isEmpty) ? "Select reason" : null,
          ),

          const SizedBox(height: 16),

          // ---------- 7) MOVEMENT DATE ----------
          _datePickerField(
            label: "Movement Date *",
            value: movementDate,
            onPick: (d) => setState(() => movementDate = d),
            required: true,
          ),

          const SizedBox(height: 16),

          // ---------- 8) QUANTITY ----------
          _numberField(
            label: "Quantity *",
            initial: quantity,
            onChanged: (v) => quantity = v,
            required: true,
          ),

          const SizedBox(height: 16),

          // ---------- 9) DISCOUNTED QUANTITY ----------
          _numberField(
            label: "Discounted Quantity",
            initial: discountedQuantity,
            onChanged: (v) => discountedQuantity = v,
          ),

          const SizedBox(height: 16),

          // ---------- 10) PROMOTION TYPE ----------
          _textField(
            label: "Promotion Type",
            initial: promotionType,
            onChanged: (v) => promotionType = v,
          ),

          const SizedBox(height: 16),

          // ---------- 11) SOURCE LOCATION (TEXT / AUTO) ----------
          _textField(
            label: "Source Location",
            initial: sourceLocation,
            onChanged: (v) => sourceLocation = v,
          ),

          const SizedBox(height: 16),

          // ---------- 12) DESTINATION LOCATION (BRANCH DROPDOWN) ----------
          DropdownButtonFormField<String>(
            value: destinationLocation,
            decoration: const InputDecoration(
              labelText: "Destination Location",
              border: OutlineInputBorder(),
            ),
            items: branches
                .map<DropdownMenuItem<String>>(
                  (b) => DropdownMenuItem(
                    value: b['id'].toString(),
                    child: Text(b['id'].toString()),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => destinationLocation = v),
          ),

          const SizedBox(height: 16),

          // ---------- 13) BATCH NUMBER ----------
          _textField(
            label: "Batch Number",
            initial: batchNumber,
            onChanged: (v) => batchNumber = v,
          ),

          const SizedBox(height: 16),

          // ---------- 14) EXPIRY DATE ----------
          _datePickerField(
            label: "Expiry Date",
            value: expiryDate,
            onPick: (d) => setState(() => expiryDate = d),
            required: false,
          ),

          const SizedBox(height: 24),

          // ---------- SAVE ----------
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: moduleColor),
              foregroundColor: moduleColor,
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: saveMovement,
            child: const Text("Save Movement"),
          ),
        ],
      ),
    ),
  );
}

  // ================= HELPERS =================

  String _na(String? v) => (v == null || v.trim().isEmpty) ? "N/A" : v;

  String _fmtDateTime(DateTime? d) {
    if (d == null) return "N/A";
    final yy = d.year.toString();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return "$yy-$mm-$dd $hh:$mi";
  }

  Widget _readOnlyBox(String label, String? value) {
  return InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    child: Text(_na(value)),
  );
}

  Widget _textField({
    required String label,
    String? initial,
    required Function(String) onChanged,
  }) {
    return TextFormField(
      initialValue: initial,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _numberField({
    required String label,
    required int initial,
    required Function(int) onChanged,
    bool required = false,
  }) {
    return TextFormField(
      initialValue: initial.toString(),
      keyboardType: TextInputType.number,
      onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
      validator: (v) {
        if (!required) return null;
        final n = int.tryParse(v ?? '');
        if (n == null || n <= 0) return "Enter valid $label";
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _datePickerField({
    required String label,
    required DateTime? value,
    required Function(DateTime) onPick,
    required bool required,
  }) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(
          value == null
              ? "Select date"
              : "${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}",
        ),
      ),
    );
  }
}
