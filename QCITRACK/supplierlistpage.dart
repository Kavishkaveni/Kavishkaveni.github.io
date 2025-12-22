import 'package:flutter/material.dart';
import 'package:qcitrack/qc_track/core/api_service.dart';

import 'supplier_form_page.dart';
import 'supplier_print_page.dart';

class SupplierListPage extends StatefulWidget {
  const SupplierListPage({super.key});

  @override
  State<SupplierListPage> createState() => _SupplierListPageState();
}

class _SupplierListPageState extends State<SupplierListPage> {
  List<dynamic> _allSuppliers = [];
  List<dynamic> _filteredSuppliers = [];
  bool loading = true;
  String searchQuery = "";

  final Color themePurple = const Color(0xFF6A5AE0);

  @override
  void initState() {
    super.initState();
    loadSuppliers();
  }

  // ================= LOAD =================
  Future<void> loadSuppliers() async {
    setState(() => loading = true);
    try {
      final data = await ApiService.getSuppliers();
      _allSuppliers = data;
      _applySearch();
    } catch (e) {
      debugPrint("LOAD SUPPLIERS ERROR: $e");
    }
    setState(() => loading = false);
  }

  // ================= SEARCH =================
  void _applySearch() {
    if (searchQuery.isEmpty) {
      _filteredSuppliers = List.from(_allSuppliers);
    } else {
      final q = searchQuery.toLowerCase();
      _filteredSuppliers = _allSuppliers.where((s) {
        return (s["id"] ?? "").toString().toLowerCase().contains(q) ||
            (s["supplier_name"] ?? "").toString().toLowerCase().contains(q) ||
            (s["contact_info"] ?? "").toString().toLowerCase().contains(q);
      }).toList();
    }
    setState(() {});
  }

  // ================= DELETE =================
  void _deleteSupplier(String id) async {
    final confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Supplier"),
        content: const Text("Are you sure you want to delete this supplier?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ApiService.deleteSupplier(id);
      loadSuppliers();
    }
  }

  // ================= PRINT =================
  void _openPrint(String id) async {
    final data = await ApiService.getSupplierById(id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierPrintPage(supplier: data),
      ),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // ✅ FIXED

      appBar: AppBar(
        title: const Text("Supplier Management"),
        backgroundColor: themePurple,
        elevation: 0,
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: themePurple,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SupplierFormPage()),
          ).then((_) => loadSuppliers());
        },
        child: const Icon(Icons.add),
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [

                  // ================= SEARCH BAR =================
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: "Search by Supplier ID, Name, or Contact Info",
                        prefixIcon: Icon(Icons.search, color: themePurple),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() => searchQuery = "");
                                  _applySearch();
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      onChanged: (v) {
                        searchQuery = v;
                        _applySearch();
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ================= LIST =================
                  Expanded(
                    child: _filteredSuppliers.isEmpty
                        ? const Center(
                            child: Text(
                              "No suppliers found",
                              style: TextStyle(fontSize: 16),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredSuppliers.length,
                            itemBuilder: (_, index) {
                              final s = _filteredSuppliers[index];

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.08),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    )
                                  ],
                                ),
                                child: ListTile(
                                  title: Text(
                                    s["supplier_name"] ?? "Unknown Supplier",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: Text(
                                    "Status: ${s["status"]}",
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.visibility, color: themePurple),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => SupplierFormPage(
                                                supplierId: s["id"],
                                                viewOnly: true,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.edit, color: themePurple),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  SupplierFormPage(supplierId: s["id"]),
                                            ),
                                          ).then((_) => loadSuppliers());
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () => _deleteSupplier(s["id"]),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.print, color: themePurple),
                                        onPressed: () => _openPrint(s["id"]),
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
