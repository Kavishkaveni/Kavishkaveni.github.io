import 'package:flutter/material.dart';

import 'package:qcitrack/qc_track/core/api_service.dart';
import 'eod_form_page.dart';
import 'eod_print_page.dart';

class EODListPage extends StatefulWidget {
  const EODListPage({super.key});

  @override
  State<EODListPage> createState() => _EODListPageState();
}

class _EODListPageState extends State<EODListPage> {
  static const Color eodColor = Color(0xFF9C4A2F);

  bool loading = true;

  // DATA
  List<dynamic> branches = [];
  List<dynamic> eodList = [];
  List<String> locations = [];

  // FILTERS
  String selectedBranchId = '';
  String selectedLocation = '';
  String selectedStatus = '';
  String searchText = '';

  final TextEditingController searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  // ---------------- INITIAL LOAD ----------------
  Future<void> _loadInitial() async {
    setState(() => loading = true);

    branches = await ApiService.getBranches();

    if (branches.isNotEmpty) {
      selectedBranchId = branches.first['id']; // AUTO SELECT FIRST BRANCH
      await _loadLocations();
      await _loadEODs();
    }

    setState(() => loading = false);
  }

  // ---------------- LOAD LOCATIONS ----------------
  Future<void> _loadLocations() async {
    locations = await ApiService.getEODLocationsByBranch(selectedBranchId);
  }

  // ---------------- LOAD EODS ----------------
  Future<void> _loadEODs() async {
    if (selectedBranchId.isEmpty) return;

    setState(() => loading = true);

    eodList = await ApiService.getEODInventories(
      branchId: selectedBranchId,
      location: selectedLocation.isEmpty ? null : selectedLocation,
      status: selectedStatus.isEmpty ? null : selectedStatus,
    );

    // INVENTORY ID SEARCH FILTER
    if (searchText.isNotEmpty) {
      eodList = eodList.where((e) {
        return e['id']
            .toString()
            .toLowerCase()
            .contains(searchText.toLowerCase());
      }).toList();
    }

    setState(() => loading = false);
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: eodColor,
        title: const Text(
          'EOD Reconciliation',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: eodColor,
        child: const Icon(Icons.add),
        onPressed: () async {
          final refreshed = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EODFormPage(branchId: selectedBranchId),
            ),
          );
          if (refreshed == true) _loadEODs();
        },
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildSearch(),
                  const SizedBox(height: 8),
                  _buildBranchFilter(),
                  _buildLocationFilter(),
                  _buildStatusFilter(),
                  const SizedBox(height: 12),
                  Expanded(child: _buildList()),
                ],
              ),
            ),
    );
  }

  // ---------------- SEARCH ----------------
  Widget _buildSearch() {
    return TextField(
      controller: searchCtrl,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: 'Search by Inventory ID',
      ),
      onChanged: (v) => setState(() => searchText = v.trim()),
    );
  }

  // ---------------- BRANCH ----------------
  Widget _buildBranchFilter() {
  if (branches.isEmpty) {
    return const SizedBox();
  }

  return DropdownButtonFormField<String>(
    value: branches.any((b) => b['id'] == selectedBranchId)
        ? selectedBranchId
        : null,
    decoration: const InputDecoration(labelText: 'Select Branch'),
    items: branches.map<DropdownMenuItem<String>>((b) {
      return DropdownMenuItem<String>(
        value: b['id'].toString(),
        child: Text(b['name'].toString()),
      );
    }).toList(),
    onChanged: (v) async {
      if (v == null) return;

      setState(() {
        selectedBranchId = v;
        selectedLocation = '';
      });

      await _loadLocations();
      await _loadEODs();
    },
  );
}

  // ---------------- LOCATION ----------------
  Widget _buildLocationFilter() {
    return DropdownButtonFormField<String>(
      value: selectedLocation.isEmpty ? null : selectedLocation,
      decoration: const InputDecoration(labelText: 'All Locations'),
      items: [
        const DropdownMenuItem(value: '', child: Text('All Locations')),
        ...locations.map(
          (l) => DropdownMenuItem(value: l, child: Text(l)),
        ),
      ],
      onChanged: (v) {
        selectedLocation = v ?? '';
        _loadEODs();
      },
    );
  }

  // ---------------- STATUS ----------------
  Widget _buildStatusFilter() {
    const statuses = ['', 'shortage', 'overage', 'unknown'];

    return DropdownButtonFormField<String>(
      value: selectedStatus,
      decoration: const InputDecoration(labelText: 'All Status'),
      items: statuses
          .map(
            (s) => DropdownMenuItem(
              value: s,
              child: Text(s.isEmpty ? 'All Status' : s),
            ),
          )
          .toList(),
      onChanged: (v) {
        selectedStatus = v ?? '';
        _loadEODs();
      },
    );
  }

  // ---------------- LIST ----------------
  Widget _buildList() {
  if (eodList.isEmpty) {
    return const Center(child: Text('No EOD records found'));
  }

  return ListView.builder(
    itemCount: eodList.length,
    itemBuilder: (_, i) {
      final e = eodList[i];

      return Card(
        child: ListTile(
          title: Text(e['product_name'] ?? '—'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (e['location'] != null &&
                  e['location'].toString().isNotEmpty)
                Text('Location: ${e['location']}'),
              Text('Status: ${e['status']}'),
            ],
          ),
          trailing: Wrap(
            spacing: 6,
            children: [
              //  VIEW
              IconButton(
                icon: Icon(Icons.visibility, color: eodColor),
                onPressed: () => _openForm(e['id'], true),
              ),

              //  EDIT
              IconButton(
                icon: Icon(Icons.edit, color: eodColor),
                onPressed: () => _openForm(e['id'], false),
              ),

              // PRINT
              IconButton(
                icon: Icon(Icons.print, color: eodColor),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EODPrintPage(eodId: e['id']),
                    ),
                  );
                },
              ),

              // DELETE (RED)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _confirmDelete(e['id']),
              ),
            ],
          ),
        ),
      );
    },
  );
}

  // ---------------- HELPERS ----------------
  Future<void> _openForm(String id, bool viewOnly) async {
    final refreshed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EODFormPage(
          branchId: selectedBranchId,
          eodId: id,
          viewOnly: viewOnly,
        ),
      ),
    );
    if (refreshed == true) _loadEODs();
  }

  Future<void> _confirmDelete(String id) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Delete EOD Record'),
      content: const Text(
        'Are you sure you want to delete this EOD inventory record?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    final ok = await ApiService.deleteEODInventory(id);
    if (ok) _loadEODs();
  }
}
}
