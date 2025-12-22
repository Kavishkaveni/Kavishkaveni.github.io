import 'package:flutter/material.dart';
import 'package:qcitrack/qc_track/core/api_service.dart';

import 'inventory_audit_form_page.dart';

class InventoryAuditListPage extends StatefulWidget {
  const InventoryAuditListPage({super.key});

  @override
  State<InventoryAuditListPage> createState() =>
      _InventoryAuditListPageState();
}

class _InventoryAuditListPageState extends State<InventoryAuditListPage> {
  static const Color auditGreen = Color(0xFF7CB342);

  List<dynamic> audits = [];
  List<dynamic> filteredAudits = [];
  List<dynamic> products = [];
  List<dynamic> branches = [];

  String searchText = '';
  String selectedProductId = '';
  String selectedBranchId = '';
  String selectedStatus = '';

  bool loading = true;

  final List<Map<String, String>> statusOptions = const [
    {'value': '', 'label': 'All Status'},
    {'value': 'regular_audit', 'label': 'Regular Audit'},
    {'value': 'purchase_verification', 'label': 'Purchase Verification'},
    {'value': 'sales_reconciliation', 'label': 'Sales Reconciliation'},
    {'value': 'return_processing', 'label': 'Return Processing'},
    {'value': 'discrepancy_investigation', 'label': 'Discrepancy Investigation'},
    {'value': 'pending_approval', 'label': 'Pending Approval'},
    {'value': 'approved', 'label': 'Approved'},
    {'value': 'rejected', 'label': 'Rejected'},
  ];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    setState(() => loading = true);

    final auditData = await ApiService.getInventoryAudits();
    final productData = await ApiService.getProducts();
    final branchData = await ApiService.getBranches();

    setState(() {
      audits = auditData;
      filteredAudits = auditData;
      products = productData;
      branches = branchData;
      loading = false;
    });
  }

  void applyFilters() {
    setState(() {
      filteredAudits = audits.where((a) {
        final idStr = (a['id'] ?? '').toString();
        final productName =
            (a['product_name'] ?? '').toString().toLowerCase();
        final auditor =
            (a['audited_by'] ?? '').toString().toLowerCase();

        final matchesSearch = searchText.isEmpty ||
            idStr.contains(searchText) ||
            productName.contains(searchText.toLowerCase()) ||
            auditor.contains(searchText.toLowerCase());

        final matchesProduct = selectedProductId.isEmpty ||
            a['product_id'].toString() == selectedProductId;

        final matchesBranch = selectedBranchId.isEmpty ||
            a['branch_id'].toString() == selectedBranchId;

        final matchesStatus =
            selectedStatus.isEmpty || a['status'] == selectedStatus;

        return matchesSearch &&
            matchesProduct &&
            matchesBranch &&
            matchesStatus;
      }).toList();
    });
  }

  Future<void> confirmDelete(String id) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Inventory Audit'),
        content: const Text('Do you want to delete this inventory audit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: auditGreen,
              side: const BorderSide(color: auditGreen),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true) {
      await ApiService.deleteInventoryAudit(id);
      await loadData();
    }
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: auditGreen, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),

      appBar: AppBar(
        backgroundColor: auditGreen,
        elevation: 0,
        title: const Text(
          'Inventory Audit',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: auditGreen,
        foregroundColor: Colors.white,
        onPressed: () async {
  final created = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const InventoryAuditFormPage(
        mode: InventoryAuditMode.create,
      ),
    ),
  );

  if (created == true) {
    loadData();
  }
},
        child: const Icon(Icons.add),
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Search
                  TextField(
                    decoration: _fieldDecoration(
                      'Search by ID, Product or Auditor',
                    ),
                    onChanged: (v) {
                      searchText = v.trim();
                      applyFilters();
                    },
                  ),

                  const SizedBox(height: 12),

                  // All Products (NO ICON)
                  DropdownButtonFormField<String>(
                    value: selectedProductId,
                    decoration: _fieldDecoration('All Products'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All Products'),
                      ),
                      ...products.map(
                        (p) => DropdownMenuItem(
                          value: p['id'].toString(),
                          child: Text(p['name'].toString()),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      selectedProductId = v ?? '';
                      applyFilters();
                    },
                  ),

                  const SizedBox(height: 12),

                  // All Branches (NO ICON)
                  DropdownButtonFormField<String>(
                    value: selectedBranchId,
                    decoration: _fieldDecoration('All Branches'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All Branches'),
                      ),
                      ...branches.map(
                        (b) => DropdownMenuItem(
                          value: b['id'].toString(),
                          child: Text(b['name'].toString()),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      selectedBranchId = v ?? '';
                      applyFilters();
                    },
                  ),

                  const SizedBox(height: 12),

                  // All Status (NO ICON)
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    decoration: _fieldDecoration('All Status'),
                    items: statusOptions
                        .map(
                          (s) => DropdownMenuItem(
                            value: s['value'],
                            child: Text(s['label']!),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      selectedStatus = v ?? '';
                      applyFilters();
                    },
                  ),

                  const SizedBox(height: 16),

                  Expanded(
                    child: filteredAudits.isEmpty
                        ? const Center(
                            child: Text('No inventory audits found'),
                          )
                        : ListView.builder(
                            itemCount: filteredAudits.length,
                            itemBuilder: (_, i) {
                              final a = filteredAudits[i];
                              final auditId = a['id'].toString();

                              return Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  title: Text(
                                    a['product_name'] ?? 'Unknown Product',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Audit #$auditId • Audited by ${a['audited_by']}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.visibility,
                                          color: auditGreen,
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  InventoryAuditFormPage(
                                                mode:
                                                    InventoryAuditMode.view,
                                                auditId: auditId,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit,
                                          color: auditGreen,
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  InventoryAuditFormPage(
                                                mode:
                                                    InventoryAuditMode.edit,
                                                auditId: auditId,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        onPressed: () =>
                                            confirmDelete(auditId),
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
