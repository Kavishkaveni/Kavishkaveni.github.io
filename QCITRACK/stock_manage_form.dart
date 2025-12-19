import 'package:flutter/material.dart';
import 'package:qcitrack/qc_track/core/api_service.dart';

class StockFormPage extends StatefulWidget {
  final String? stockId;
  final bool viewOnly;

  const StockFormPage({
    super.key,
    this.stockId,
    this.viewOnly = false,
  });

  @override
  State<StockFormPage> createState() => _StockFormPageState();
}

class _StockFormPageState extends State<StockFormPage> {
  bool loading = true;

  // MODULE COLOR (GREEN)
  static const Color stockColor = Color(0xFF0FA4AF);

  // DATA
  List<dynamic> products = [];
  List<dynamic> branches = [];

  // CONTROLLERS
  final qtyCtrl = TextEditingController();
  final uomCtrl = TextEditingController();
  final minCtrl = TextEditingController();
  final locationCtrl = TextEditingController();
  final batchCtrl = TextEditingController();
  final rackCtrl = TextEditingController();
  final rowCtrl = TextEditingController();
  final shelfCtrl = TextEditingController();
  final costCtrl = TextEditingController();
  final sellCtrl = TextEditingController();
  final promoCtrl = TextEditingController();
  final priceNotesCtrl = TextEditingController();

  String? selectedProductId;
  String? selectedProductName;
  String? selectedBranchId;

  bool overridePrice = false;

  DateTime? promoStart;
  DateTime? promoEnd;
  DateTime? expiryDate;

  @override
  void initState() {
    super.initState();
    loadInitial();
  }

  Future<void> loadInitial() async {
    products = await ApiService.getProductsForDropdown();
    branches = await ApiService.getBranches();

    if (widget.stockId != null) {
      final data = await ApiService.getStockById(widget.stockId!);
      bindData(data);
    }

    setState(() => loading = false);
  }

  void bindData(Map<String, dynamic> s) {
    selectedProductId = s['product_id']?.toString();
    selectedProductName = s['product_name'];
    selectedBranchId = s['branch_id']?.toString();

    qtyCtrl.text = '${s['quantity'] ?? ''}';
    uomCtrl.text = s['unit_of_measure'] ?? '';
    minCtrl.text = '${s['min_threshold'] ?? ''}';
    locationCtrl.text = s['stock_location'] ?? '';
    batchCtrl.text = s['batch_number'] ?? '';
    rackCtrl.text = s['rack_number'] ?? '';
    rowCtrl.text = s['row_number'] ?? '';
    shelfCtrl.text = s['shelf_number'] ?? '';
    costCtrl.text = '${s['cost_price'] ?? ''}';
    sellCtrl.text = '${s['selling_price'] ?? ''}';

    overridePrice = s['price_override'] == true;

    if (s['promo_start'] != null) promoStart = DateTime.parse(s['promo_start']);
    if (s['promo_end'] != null) promoEnd = DateTime.parse(s['promo_end']);
    if (s['expiry_date'] != null) expiryDate = DateTime.parse(s['expiry_date']);
  }

  Future<void> pickDate(Function(DateTime) onPick) async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: DateTime.now(),
    );
    if (d != null) onPick(d);
  }

  Future<void> saveStock() async {
  final payload = {
    // REQUIRED
    'product_id': selectedProductId,
    'branch_id': selectedBranchId,

    // INT fields
    'quantity': qtyCtrl.text.isEmpty
        ? null
        : int.parse(qtyCtrl.text),

    'min_threshold': minCtrl.text.isEmpty
        ? null
        : int.parse(minCtrl.text),

    // STRING / NULL
    'unit_of_measure': uomCtrl.text.isEmpty ? null : uomCtrl.text,
    'stock_location': locationCtrl.text.isEmpty ? null : locationCtrl.text,
    'batch_number': batchCtrl.text.isEmpty ? null : batchCtrl.text,
    'rack_number': rackCtrl.text.isEmpty ? null : rackCtrl.text,
    'row_number': rowCtrl.text.isEmpty ? null : rowCtrl.text,
    'shelf_number': shelfCtrl.text.isEmpty ? null : shelfCtrl.text,

    // PRICING
    'stock_cost_price': costCtrl.text.isEmpty
        ? null
        : double.parse(costCtrl.text),

    'stock_selling_price': sellCtrl.text.isEmpty
        ? null
        : double.parse(sellCtrl.text),

    'price_override_enabled': overridePrice,

    'promotional_price': promoCtrl.text.isEmpty
        ? null
        : double.parse(promoCtrl.text),

    'promotion_start_date':
        promoStart == null ? null : promoStart!.toIso8601String(),

    'promotion_end_date':
        promoEnd == null ? null : promoEnd!.toIso8601String(),

    'price_notes':
        priceNotesCtrl.text.isEmpty ? null : priceNotesCtrl.text,

    'expiry_date':
        expiryDate == null ? null : expiryDate!.toIso8601String(),
  };

  if (widget.stockId == null) {
    await ApiService.createStock(payload);
  } else {
    await ApiService.updateStock(widget.stockId!, payload);
  }

  Navigator.pop(context, true);
}

  Widget textField(String label, TextEditingController c, {bool enabled = true}) {
    return TextField(
      controller: c,
      enabled: enabled,
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget outlinedButton(String text, VoidCallback onTap) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: stockColor,
        side: const BorderSide(color: stockColor),
        padding: const EdgeInsets.all(14),
      ),
      onPressed: onTap,
      child: Text(text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.viewOnly
        ? 'View Stock'
        : widget.stockId == null
            ? 'Add New Stock'
            : 'Edit Stock';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: stockColor,
        title: Text(title),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // PRODUCT
                  DropdownButtonFormField<String>(
                    value: selectedProductId,
                    decoration: const InputDecoration(labelText: 'Product'),
                    items: products
                        .map<DropdownMenuItem<String>>(
                          (p) => DropdownMenuItem<String>(
                            value: p['id'].toString(),
                            child: Text(p['name']),
                          ),
                        )
                        .toList(),
                    onChanged: widget.viewOnly
                        ? null
                        : (v) {
                            final p = products.firstWhere(
                                (e) => e['id'].toString() == v);
                            setState(() {
                              selectedProductId = v;
                              selectedProductName = p['name'];
                            });
                          },
                  ),

                  if (selectedProductName != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Selected Product: $selectedProductName',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // BRANCH
                  DropdownButtonFormField<String>(
                    value: selectedBranchId,
                    decoration: const InputDecoration(labelText: 'Branch'),
                    items: branches
                        .map<DropdownMenuItem<String>>(
                          (b) => DropdownMenuItem<String>(
                            value: b['id'].toString(),
                            child: Text(b['name']),
                          ),
                        )
                        .toList(),
                    onChanged:
                        widget.viewOnly ? null : (v) => selectedBranchId = v,
                  ),

                  const SizedBox(height: 12),

                  textField('Quantity', qtyCtrl, enabled: !widget.viewOnly),
                  textField('Unit of Measure', uomCtrl,
                      enabled: !widget.viewOnly),
                  textField('Min Threshold', minCtrl,
                      enabled: !widget.viewOnly),
                  textField('Location', locationCtrl,
                      enabled: !widget.viewOnly),

                  Row(
                    children: [
                      Expanded(
                          child: textField('Batch Number', batchCtrl,
                              enabled: !widget.viewOnly)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: textField('Rack Number', rackCtrl,
                              enabled: !widget.viewOnly)),
                    ],
                  ),

                  Row(
                    children: [
                      Expanded(
                          child: textField('Row Number', rowCtrl,
                              enabled: !widget.viewOnly)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: textField('Shelf Number', shelfCtrl,
                              enabled: !widget.viewOnly)),
                    ],
                  ),

                  const Divider(height: 30),

                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Pricing Information',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),

                  textField('Cost Price', costCtrl,
                      enabled: !widget.viewOnly),
                  textField('Selling Price', sellCtrl,
                      enabled: !widget.viewOnly),

                  CheckboxListTile(
                    value: overridePrice,
                    onChanged: widget.viewOnly
                        ? null
                        : (v) => setState(() => overridePrice = v!),
                    title: const Text(
                        'Enable custom pricing (override product default price)'),
                  ),

                  const Divider(height: 30),

                  ListTile(
                    title: Text(expiryDate == null
                        ? 'Expiry Date'
                        : expiryDate!.toLocal().toString().split(' ')[0]),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: widget.viewOnly
                        ? null
                        : () => pickDate(
                            (d) => setState(() => expiryDate = d)),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: outlinedButton(
                          widget.viewOnly ? 'Close' : 'Cancel',
                          () => Navigator.pop(context),
                        ),
                      ),
                      if (!widget.viewOnly) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: outlinedButton(
                            widget.stockId == null
                                ? 'Add Stock'
                                : 'Update Stock',
                            saveStock,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
