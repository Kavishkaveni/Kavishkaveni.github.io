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
  TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> tables = [];
  bool isLoading = true;

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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff7f5f0),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        titleSpacing: 12,
        title: Text(
          "Table Selection",
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.brown.shade700,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _filtersRow(),
            const SizedBox(height: 18),
            Expanded(child: _tableGrid())
          ],
        ),
      ),
    );
  }

  // FILTER LINE (Optimized for Mobile)
Widget _filtersRow() {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.05),
          blurRadius: 6,
        )
      ],
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // smaller
    child: Row(
      children: [
        SizedBox(
          width: 180, // was 240 → now mobile-friendly
          height: 42, // fixed search box height
          child: TextField(
            controller: searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: "Search...",
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Filter chips
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ["All", "Available", "Occupied", "Reserved", "Cleaning"]
                  .map((f) => _chip(f))
                  .toList(),
            ),
          ),
        ),
      ],
    ),
  );
}

  // FILTER CHIP (Option 2 style)
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
            // colored dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),

            // text
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

  // TABLE GRID
  Widget _tableGrid() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = tables.where((t) {
      final matchStatus =
          selectedFilter == "All" || selectedFilter == t["status"];
      final matchSearch = searchController.text.isEmpty ||
          t["number"].toString().contains(searchController.text);
      return matchStatus && matchSearch;
    }).toList();

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

  // TABLE CARD — improved
  Widget _tableCard(Map<String, dynamic> table) {
    final status = table["status"];
    final color = statusColor(status);

    return GestureDetector(
      onTap: status == "Available"
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DineInOrderCartPage(
                    tableNumber: table["number"],
                    cartItems: {},
                    total: 0,
                  ),
                ),
              );
            }
          : null,
      child: AnimatedContainer(
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

        // Smaller card size
        child: Column(
          children: [
            // status badge
            Align(
              alignment: Alignment.topRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
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

            // Bigger circle
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Text(
                "${table["number"]}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
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
    );
  }

  // API CALL
  Future<void> loadTables() async {
    try {
      final data = await QcTradeApi.getTables();

      setState(() {
        tables = data.map<Map<String, dynamic>>((t) {
          return {
            "number": int.tryParse(t["table_number"].toString()) ?? 0,
            "status": (t["status"] ?? "").toString().capitalizeFirstLetter(),
            "section": t["section"] ?? "",
          };
        }).toList();

        isLoading = false;
      });
    } catch (e) {
      print("Error loading tables: $e");
      setState(() => isLoading = false);
    }
  }
}

// EXTENSION FOR CAPITALIZING STATUS
extension StringExtension on String {
  String capitalizeFirstLetter() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}
