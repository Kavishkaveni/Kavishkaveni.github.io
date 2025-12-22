import 'package:flutter/material.dart';

import 'package:qcitrack/qc_track/core/api_service.dart';
import 'category_list_page.dart';
import 'product_form_page.dart';

class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  // ================= THEME =================
  static const Color themeRed = Color(0xFFB33A3A);
  static const Color pageBg = Color(0xFFF6F6F6);

  // ================= STATE =================
  bool loading = true;

  List<dynamic> products = [];
  List<dynamic> filteredProducts = [];
  List<String> categories = [];

  String searchText = '';
  String selectedCategory = 'All Categories';
  String selectedStatus = 'All Status';
  String selectedType = 'All Types';

  final List<String> statusList = [
    'All Status',
    'Available',
    'Discontinued',
    'Out of Stock',
    'Low Stock',
  ];

  final List<String> typeList = [
    'All Types',
    'Ingredient',
    'Sellable',
    'Asset',
  ];

  @override
  void initState() {
    super.initState();
    loadAll();
  }

  // ================= LOAD DATA =================
  Future<void> loadAll() async {
    setState(() => loading = true);

    try {
      final prod = await ApiService.getProducts();
      final cat = await ApiService.getProductCategories();

      categories = [
        'All Categories',
        ...cat.map<String>((e) => e['name'].toString()).toList(),
      ];

      products = prod;
      applyFilters();
    } catch (e) {
      debugPrint(e.toString());
    }

    setState(() => loading = false);
  }

  // ================= FILTER =================
  void applyFilters() {
    filteredProducts = products.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final id = (p['id'] ?? '').toString();

      final category = (p['category'] ?? '').toString();
      final status = (p['product_status'] ?? '').toString();
      final type = (p['product_type'] ?? '').toString();

      final searchOk = searchText.isEmpty ||
          name.contains(searchText.toLowerCase()) ||
          id.contains(searchText);

      final categoryOk =
          selectedCategory == 'All Categories' || category == selectedCategory;

      final statusOk =
          selectedStatus == 'All Status' || status == selectedStatus;

      final typeOk = selectedType == 'All Types' || type == selectedType;

      return searchOk && categoryOk && statusOk && typeOk;
    }).toList();

    setState(() {});
  }

  // ================= DELETE =================
  Future<void> deleteProduct(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure you want to delete this product?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: themeRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ApiService.deleteProduct(id);
      loadAll();
    }
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Theme(
      // REMOVE PURPLE COMPLETELY
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: themeRed,
          primary: themeRed,
        ),
      ),
      child: Scaffold(
        backgroundColor: pageBg,

        // ================= APPBAR =================
        appBar: AppBar(
          backgroundColor: themeRed,
          title: const Text(
            'Product Management',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.category),
              tooltip: 'Category List',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CategoryListPage(),
                  ),
                );
              },
            ),
          ],
        ),

        // ================= BODY =================
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    // SEARCH
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search by ID or Name',
                        prefixIcon: Icon(Icons.search, color: Colors.black),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black),
                        ),
                      ),
                      onChanged: (v) {
                        searchText = v;
                        applyFilters();
                      },
                    ),

                    const SizedBox(height: 12),

                    // CATEGORY
                    dropdown(
                      value: selectedCategory,
                      items: categories,
                      onChanged: (v) {
                        selectedCategory = v!;
                        applyFilters();
                      },
                    ),

                    // STATUS
                    dropdown(
                      value: selectedStatus,
                      items: statusList,
                      onChanged: (v) {
                        selectedStatus = v!;
                        applyFilters();
                      },
                    ),

                    // TYPE
                    dropdown(
                      value: selectedType,
                      items: typeList,
                      onChanged: (v) {
                        selectedType = v!;
                        applyFilters();
                      },
                    ),

                    const SizedBox(height: 12),

                    // LIST
                    Expanded(
                      child: filteredProducts.isEmpty
                          ? const Center(child: Text('No products found'))
                          : ListView.builder(
                              itemCount: filteredProducts.length,
                              itemBuilder: (_, i) {
                                final p = filteredProducts[i];
                                return productCard(p);
                              },
                            ),
                    ),
                  ],
                ),
              ),

        // ================= ADD BUTTON =================
        floatingActionButton: FloatingActionButton(
          backgroundColor: themeRed,
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProductFormPage(),
              ),
            ).then((_) => loadAll());
          },
        ),
      ),
    );
  }

  // ================= DROPDOWN =================
  Widget dropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      items: items
          .map(
            (e) => DropdownMenuItem(value: e, child: Text(e)),
          )
          .toList(),
      onChanged: onChanged,
      decoration: const InputDecoration(
        enabledBorder:
            UnderlineInputBorder(borderSide: BorderSide(color: Colors.black)),
        focusedBorder:
            UnderlineInputBorder(borderSide: BorderSide(color: Colors.black)),
      ),
    );
  }

  // ================= PRODUCT CARD =================
  Widget productCard(dynamic p) {
    final status = (p['product_status'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(
          p['name'] ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(status),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.visibility, color: themeRed),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductFormPage(
                      productId: p['id'],
                      viewOnly: true,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.edit, color: themeRed),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductFormPage(
                      productId: p['id'],
                    ),
                  ),
                ).then((_) => loadAll());
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => deleteProduct(p['id'].toString()),
            ),
          ],
        ),
      ),
    );
  }
}
