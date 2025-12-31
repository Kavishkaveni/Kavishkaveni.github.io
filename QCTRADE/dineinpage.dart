import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../OrdersPages/dine_in_order_cart_page.dart';
import '../services/qctrade_api.dart';

class DineInPage extends StatefulWidget {
  const DineInPage({super.key});

  @override
  State<DineInPage> createState() => _DineInPageState();
}

class _DineInPageState extends State<DineInPage> {
  String selectedFilter = "All";
  final TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> tables = [];
  bool isLoading = true;

  // ===== selection mode =====
  bool selectionMode = false;
  String currentAction = ""; // view | edit | delete | mark_available
  final Set<String> selectedTableIds = {};

  // ===== add/edit dialog controllers =====
  final TextEditingController _tableNumberCtrl = TextEditingController();
  String _seatCap = "2";
  String _status = "Available";
  String _section = "Window";

  Color statusColor(String status) {
    switch (status) {
      case "Available":
        return Colors.green;
      case "Occupied":
        return Colors.red;
      case "Reserved":
        return Colors.orange;
      case "Cleaning":
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  void initState() {
    super.initState();
    loadTables();
  }

  @override
  void dispose() {
    searchController.dispose();
    _tableNumberCtrl.dispose();
    super.dispose();
  }

  // ================= HELPERS =================

  Map<String, dynamic>? _findTableById(String id) {
    try {
      return tables.firstWhere((t) => (t["id"]?.toString() ?? "") == id);
    } catch (_) {
      return null;
    }
  }

  bool _isCleaningTable(String id) {
    final t = _findTableById(id);
    return (t?["status"]?.toString() ?? "") == "Cleaning";
  }

  bool _isConfirmEnabled() {
    if (!selectionMode) return false;
    if (selectedTableIds.isEmpty) return false;

    if (currentAction == "view" || currentAction == "edit") {
      return selectedTableIds.length == 1;
    }

    if (currentAction == "mark_available") {
      // only cleaning tables selectable/confirmable
      return selectedTableIds.isNotEmpty &&
          selectedTableIds.every((id) => _isCleaningTable(id));
    }

    // delete: allow 1+
    if (currentAction == "delete") return selectedTableIds.isNotEmpty;

    return false;
  }

  void _enterSelectionMode(String action) {
    setState(() {
      selectionMode = true;
      currentAction = action;
      selectedTableIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      selectionMode = false;
      currentAction = "";
      selectedTableIds.clear();
    });
  }

  // ================= APP BAR ACTION =================

  Future<void> _onConfirm() async {
    if (!_isConfirmEnabled()) return;

    if (currentAction == "view") {
      final id = selectedTableIds.first;
      final t = _findTableById(id);
      if (t == null) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("View Table"),
          content: Text(
            "Table: ${t["number"]}\n"
            "Seating: ${t["seating_capacity"] ?? "-"}\n"
            "Status: ${t["status"]}\n"
            "Section: ${t["section"] ?? "-"}",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        ),
      );

      _exitSelectionMode();
      return;
    }

    if (currentAction == "edit") {
      final id = selectedTableIds.first;
      final t = _findTableById(id);
      if (t == null) return;

      _tableNumberCtrl.text = (t["number"] ?? "").toString();

// ---- SAFE seating capacity ----
final seat = (t["seating_capacity"] ?? "2").toString();
_seatCap = ["2", "4", "6", "8", "10", "12"].contains(seat)
    ? seat
    : "2";

// ---- SAFE status ----
final status = (t["status"] ?? "Available").toString();
_status = ["Available", "Occupied", "Reserved", "Cleaning"].contains(status)
    ? status
    : "Available";

// ---- SAFE section ----
final section = (t["section"] ?? "Window").toString();
_section = ["Window", "Center", "Bar", "Outdoor", "Private"].contains(section)
    ? section
    : "Window";

      final saved = await _showTableDialog(mode: "edit", tableId: id);
      if (saved == true) {
        await loadTables();
      }
      _exitSelectionMode();
      return;
    }

    if (currentAction == "delete") {
      final ok = await _showDeleteConfirm(selectedTableIds.length);
      if (ok != true) return;

      // delete selected tables
      for (final id in selectedTableIds) {
        await QcTradeApi.delete("${QcTradeApi.baseUrl}/tables/$id");
      }

      _exitSelectionMode();
      await loadTables();
      return;
    }

    if (currentAction == "mark_available") {
      // mark available only for cleaning tables
      for (final id in selectedTableIds) {
        await QcTradeApi.post(
          "${QcTradeApi.baseUrl}/tables/$id/mark-available",
          {},
        );
      }

      _exitSelectionMode();
      await loadTables();
      return;
    }
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff7f5f0),
      appBar: AppBar(
        leading: selectionMode
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: _exitSelectionMode,
              )
            : const BackButton(color: Colors.black),
        elevation: 0,
        backgroundColor: Colors.white,
        titleSpacing: 12,
        title: Text(
          selectionMode
              ? "Select Tables (${selectedTableIds.length})"
              : "Table Selection",
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.brown.shade700,
          ),
        ),
        actions: selectionMode
            ? [
                IconButton(
                  icon: Icon(
                    Icons.check,
                    color: _isConfirmEnabled() ? Colors.green : Colors.grey,
                  ),
                  onPressed: _isConfirmEnabled() ? _onConfirm : null,
                ),
                const SizedBox(width: 6),
              ]
            : [
                // + Add Table (near action button)
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.black),
                  onPressed: () async {
                    // reset defaults for create
                    _tableNumberCtrl.clear();
                    _seatCap = "2";
                    _status = "Available";
                    _section = "Window";

                    final saved = await _showTableDialog(mode: "create");
                    if (saved == true) {
                      await loadTables();
                    }
                  },
                ),

                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.black),
                  onSelected: (action) {
                    // enter selection mode
                    _enterSelectionMode(action);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'view', child: Text('View')),
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                    PopupMenuItem(
                      value: 'mark_available',
                      child: Text('Mark as Available'),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
              ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _filtersRow(),
            const SizedBox(height: 18),
            Expanded(child: _tableGrid()),
          ],
        ),
      ),
    );
  }

  // ================= FILTER BAR =================
  Widget _filtersRow() {
  return Column(
    children: [
      // SEARCH BAR 
      TextField(
        controller: searchController,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 18),
          hintText: "Search table number...",
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),

      const SizedBox(height: 8),

      // STATUS BUTTONS — ONE LINE, SMALL
      Row(
        children: [
          _statusBtnExpanded("All"),
          _statusBtnExpanded("Available"),
          _statusBtnExpanded("Occupied"),
          _statusBtnExpanded("Reserved"),
          _statusBtnExpanded("Cleaning"),
        ],
      ),
    ],
  );
}

Widget _statusBtnExpanded(String label) {
  final bool active = selectedFilter == label;
  final Color color = statusColor(label);

  return Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: () => setState(() => selectedFilter = label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34, 
          decoration: BoxDecoration(
            color: active ? color : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color, width: 1),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis, 
            style: GoogleFonts.poppins(
              fontSize: 11, 
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : color,
            ),
          ),
        ),
      ),
    ),
  );
}

  // ================= FILTER CHIP =================
  Widget _chip(String label) {
    bool active = label == selectedFilter;
    final color = statusColor(label);

    return GestureDetector(
      onTap: () => setState(() => selectedFilter = label),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: active ? color : color.withOpacity(.40),
            width: 1.3,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: active ? color : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= TABLE GRID =================
  Widget _tableGrid() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = tables.where((t) {
      final matchStatus =
          selectedFilter == "All" || selectedFilter == t["status"];
      final matchSearch = searchController.text.isEmpty ||
          (t["number"] ?? "").toString().contains(searchController.text);
      return matchStatus && matchSearch;
    }).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text("No tables found"));
    }

    // IMPORTANT: keep your original responsive columns (no overlap)
    return LayoutBuilder(builder: (context, constraints) {
      int columns = (constraints.maxWidth ~/ 150).clamp(1, 5);

      return GridView.builder(
        itemCount: filtered.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.82,
        ),
        itemBuilder: (_, i) => _tableCard(filtered[i]),
      );
    });
  }

  // ================= TABLE CARD =================
  Widget _tableCard(Map<String, dynamic> table) {
    final status = (table["status"] ?? "").toString();
    final color = statusColor(status);

    final String id = (table["id"] ?? "").toString();
    final bool checked = selectedTableIds.contains(id);

    // For mark_available: ONLY cleaning tables can be selected
    final bool disableCheckbox =
        selectionMode && currentAction == "mark_available" && status != "Cleaning";

    return GestureDetector(
      onTap: (!selectionMode &&
        (status == "Available" || status == "Occupied"))
    ? () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DineInOrderCartPage(
              tableId: int.parse(table["id"].toString()),
              tableNumber: table["number"].toString(),
              cartItems: const {},
            ),
          ),
        );
      }
    : (selectionMode
        ? () {
            if (disableCheckbox) return;
            setState(() {
              if (checked) {
                selectedTableIds.remove(id);
              } else {
                selectedTableIds.add(id);
              }
            });
          }
        : null),
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: color.withOpacity(.50),
                width: status == "Available" ? 2.0 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.04),
                  blurRadius: 5,
                  offset: const Offset(1, 2),
                )
              ],
            ),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
  "${table["number"]}",
  textAlign: TextAlign.center,
  style: const TextStyle(
    color: Colors.white,
    fontSize: 22,
    fontWeight: FontWeight.bold,
    height: 1.1,
  ),
),
                ),
                const Spacer(),
                Text(
                  "Table ${table["number"]}",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.brown.shade700,
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),

          // Checkbox only in selection mode
          if (selectionMode)
            Positioned(
              top: 6,
              left: 6,
              child: IgnorePointer(
                ignoring: false,
                child: Checkbox(
                  value: checked,
                  onChanged: disableCheckbox
                      ? null
                      : (_) {
                          setState(() {
                            if (checked) {
                              selectedTableIds.remove(id);
                            } else {
                              selectedTableIds.add(id);
                            }
                          });
                        },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ================= API CALL =================
  Future<void> loadTables() async {
    setState(() => isLoading = true);

    try {
      final data = await QcTradeApi.getTables();

      setState(() {
        tables = data.map<Map<String, dynamic>>((t) {
          final rawStatus = (t["status"] ?? "").toString().toLowerCase();

          return {
            "id": t["id"],
            "number": t["table_number"]?.toString() ?? "",
            "status": rawStatus.capitalizeFirstLetter(),
            "section": t["section"] ?? "",
            // optional if backend returns
            "seating_capacity": t["seating_capacity"] ?? t["capacity"] ?? "",
          };
        }).toList();

        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  // ================= DIALOGS =================

  Future<bool?> _showDeleteConfirm(int count) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete"),
        content: Text("Do you want to delete $count table(s)?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showTableDialog({required String mode, String? tableId}) {
    final bool isEdit = mode == "edit";

    final seatingOptions = ["2", "4", "6", "8", "10", "12"];
    final statusOptions = ["Available", "Occupied", "Reserved", "Cleaning"];
    final sectionOptions = ["Window", "Center", "Bar", "Outdoor", "Private"];

    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEdit ? "Edit Table" : "Add New Table"),
        content: SingleChildScrollView(
  child: Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom,
    ),
    child: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _tableNumberCtrl,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: "Table Number *",
              hintText: "Enter table number",
            ),
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _seatCap,
            items: seatingOptions
                .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text("$e people"),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _seatCap = v ?? "2"),
            decoration: const InputDecoration(
              labelText: "Seating Capacity *",
            ),
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _status,
            items: statusOptions
                .map((e) =>
                    DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _status = v ?? "Available"),
            decoration: const InputDecoration(
              labelText: "Status *",
            ),
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _section,
            items: sectionOptions
                .map((e) =>
                    DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _section = v ?? "Window"),
            decoration: const InputDecoration(
              labelText: "Section",
            ),
          ),
        ],
      ),
    ),
  ),
),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final number = _tableNumberCtrl.text.trim();
              if (number.isEmpty) return;

              final body = {
                "table_number": number,
                "seating_capacity": int.tryParse(_seatCap) ?? 2,
                "status": _status.toLowerCase(), // backend often expects lowercase
                "section": _section,
              };

              if (isEdit) {
                await QcTradeApi.put(
                  "${QcTradeApi.baseUrl}/tables/$tableId",
                  body,
                );
              } else {
                await QcTradeApi.post(
                  "${QcTradeApi.baseUrl}/tables",
                  body,
                );
              }

              if (!mounted) return;
              Navigator.pop(context, true);
            },
            child: Text(isEdit ? "Save" : "Create Table"),
          ),
        ],
      ),
    );
  }
}

// ================= STRING EXTENSION =================
extension StringExtension on String {
  String capitalizeFirstLetter() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}
