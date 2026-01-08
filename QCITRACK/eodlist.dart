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

  // SELECTION MODE
  bool selectionMode = false;
  String? pendingAction; // edit / print / delete
  Set<String> selectedIds = {};

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
      selectedBranchId = branches.first['id'];
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

  // ---------------- SELECTION HANDLERS ----------------
  void _startSelection(String action) {
    setState(() {
      selectionMode = true;
      pendingAction = action;
      selectedIds.clear();
    });
  }

  void _cancelSelection() {
    setState(() {
      selectionMode = false;
      pendingAction = null;
      selectedIds.clear();
    });
  }

  Future<void> _confirmSelection() async {
    if (selectedIds.isEmpty) return;

    final id = selectedIds.first;

    if (pendingAction == 'edit') {
      final refreshed = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EODFormPage(
            branchId: selectedBranchId,
            eodId: id,
            viewOnly: false,
          ),
        ),
      );
      if (refreshed == true) _loadEODs();
    }

    if (pendingAction == 'print') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EODPrintPage(eodId: id),
        ),
      );
    }

    if (pendingAction == 'delete') {
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

    _cancelSelection();
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
        leading: selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _cancelSelection,
              )
            : null,
        actions: [
          if (selectionMode)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _confirmSelection,
            )
          else
            PopupMenuButton<String>(
              onSelected: _startSelection,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'print', child: Text('Print')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
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
      onChanged: (v) {
        searchText = v.trim();
        _loadEODs();
      },
    );
  }

  // ---------------- BRANCH ----------------
  Widget _buildBranchFilter() {
    if (branches.isEmpty) return const SizedBox();

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
        final id = e['id'].toString();

        return Card(
          elevation: 6,
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: InkWell(
            onTap: selectionMode
                ? () {
                    setState(() {
                      selectedIds.contains(id)
                          ? selectedIds.remove(id)
                          : selectedIds.add(id);
                    });
                  }
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EODFormPage(
                          branchId: selectedBranchId,
                          eodId: id,
                          viewOnly: true,
                        ),
                      ),
                    );
                  },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  if (selectionMode)
                    Checkbox(
                      value: selectedIds.contains(id),
                      onChanged: (_) {
                        setState(() {
                          selectedIds.contains(id)
                              ? selectedIds.remove(id)
                              : selectedIds.add(id);
                        });
                      },
                    ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      id,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      e['location'] ?? '',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      e['status'] ?? '',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: eodColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
