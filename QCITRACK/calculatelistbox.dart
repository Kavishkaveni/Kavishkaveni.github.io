import 'package:flutter/material.dart';
import '../ims_api.dart';
import '../calculate_ingrediants/calculate_form_page.dart';

class CalculateListPage extends StatefulWidget {
  const CalculateListPage({super.key});

  @override
  State<CalculateListPage> createState() => _CalculateListPageState();
}

class _CalculateListPageState extends State<CalculateListPage> {
  bool loading = true;

  // ================= STATE =================
  String? selectedBranchId;
  bool includeWastage = false;

  List<dynamic> branches = [];
  List<dynamic> products = [];

  List<Map<String, dynamic>> selectedProducts = [
    {
      "recipe_id": null,
      "quantity": 1,
    }
  ];

  // ================= INIT =================
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ================= LOAD DATA =================
  Future<void> _loadData() async {
    try {
      branches = await ImsApiService.getBranches();
      products = await ImsApiService.getRecipesForCalculator();

      if (branches.isNotEmpty) {
        selectedBranchId = branches.first['id'];
      }
    } finally {
      setState(() => loading = false);
    }
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF3FF),

      // ================= APP BAR =================
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),
        title: const Text(
          'Ingredient Calculator',
          style: TextStyle(color: Colors.white),
        ),
        leading: const BackButton(color: Colors.white),
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _branchDropdown(),
                  const SizedBox(height: 20),

                  const Text(
                    'Products to Calculate',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  ..._productRows(),

                  const SizedBox(height: 12),
                  _addAnotherProduct(),

                  const SizedBox(height: 24),
                  _wastageAndCalculate(),
                ],
              ),
            ),
    );
  }

  // ================= BRANCH DROPDOWN =================
  Widget _branchDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedBranchId,
      decoration: const InputDecoration(
        labelText: 'Select Branch',
        border: OutlineInputBorder(),
      ),
      items: branches
          .map<DropdownMenuItem<String>>(
            (b) => DropdownMenuItem(
              value: b['id'],
              child: Text(b['name']),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => selectedBranchId = v),
    );
  }

  // ================= PRODUCT ROWS =================
  List<Widget> _productRows() {
  return List.generate(selectedProducts.length, (index) {
    final row = selectedProducts[index];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            // ===== PRODUCT / RECIPE DROPDOWN =====
            Expanded(
              flex: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: row['recipe_id'],
                    hint: const Text('Select Product'),
                    isExpanded: true,
                    items: products.map<DropdownMenuItem<String>>(
  (p) => DropdownMenuItem(
    value: p['id'],
    child: Text(
      '${p['product_name']} (${p['name']})', 
      overflow: TextOverflow.ellipsis,
    ),
  ),
).toList(),
                    onChanged: (v) =>
                        setState(() => row['recipe_id'] = v),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // ===== QUANTITY BOX =====
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () {
                      if (row['quantity'] > 1) {
                        setState(() => row['quantity']--);
                      }
                    },
                  ),
                  Text(
                    row['quantity'].toString(),
                    style: const TextStyle(fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () =>
                        setState(() => row['quantity']++),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 6),

            // ===== DELETE =====
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.red.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                  if (selectedProducts.length > 1) {
                    setState(() => selectedProducts.removeAt(index));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  });
}

  // ================= ADD ANOTHER PRODUCT =================
  Widget _addAnotherProduct() {
    return TextButton.icon(
      onPressed: () {
        setState(() {
          selectedProducts.add({
            "recipe_id": null,
            "quantity": 1,
          });
        });
      },
      icon: const Icon(Icons.add),
      label: const Text('Add Another Product'),
    );
  }

  // ================= WASTAGE + CALCULATE =================
  Widget _wastageAndCalculate() {
    return Row(
      children: [
        Checkbox(
          value: includeWastage,
          onChanged: (v) => setState(() => includeWastage = v!),
        ),
        const Text('Include wastage buffer'),
        const Spacer(),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1976D2),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          onPressed: _calculate,
          child: const Text(
            'Calculate All',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  // ================= CALCULATE ACTION =================
void _calculate() {
  debugPrint('CALCULATE CLICKED');
  debugPrint('includeWastage = $includeWastage');
  debugPrint('selectedBranchId = $selectedBranchId');
  debugPrint('selectedProducts = $selectedProducts');

  // check list empty
  if (selectedProducts.isEmpty) {
    debugPrint('selectedProducts is EMPTY');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No products added')),
    );
    return;
  }

  // VALID ROWS (must have recipe_id and quantity)
  final validRows = selectedProducts.where((r) {
    final rid = r['recipe_id'];
    final qty = r['quantity'];
    debugPrint('ROW -> recipe_id=$rid qty=$qty');
    return rid != null && qty != null && qty > 0;
  }).toList();

  debugPrint('validRows length = ${validRows.length}');
  debugPrint('validRows = $validRows');

  if (validRows.isEmpty) {
    debugPrint('No valid rows (recipe not selected)');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please select at least one recipe')),
    );
    return;
  }

  // NAVIGATION TEST 
  debugPrint('NAVIGATING to CalculateFormPage...');
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CalculateFormPage(
        items: validRows,
        includeWastage: includeWastage,
      ),
    ),
  );
}
}
