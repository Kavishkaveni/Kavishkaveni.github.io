import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../OrdersPages/dine_in_order_cart_page.dart';

class DineInPage extends StatefulWidget {
  const DineInPage({super.key});

  @override
  State<DineInPage> createState() => _DineInPageState();
}

class _DineInPageState extends State<DineInPage> {
  String selectedFilter = "All";
  TextEditingController searchController = TextEditingController();

  final List<Map<String, dynamic>> tables = [
    {"number": 100, "section": "Window", "status": "Occupied"},
    {"number": 300, "section": "Window", "status": "Cleaning"},
    {"number": 200, "section": "Window", "status": "Occupied"},
    {"number": 150, "section": "Window", "status": "Available"},
    {"number": 180, "section": "Window", "status": "Reserved"},
  ];

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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff7f5f0), // modern restaurant cream bg
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
        padding: const EdgeInsets.all(18),
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

  // FILTER + SEARCH
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
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              controller: searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: "Search table...",
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 12),
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

  // modern chip
  Widget _chip(String label) {
    bool active = label == selectedFilter;
    return GestureDetector(
      onTap: () => setState(() => selectedFilter = label),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        decoration: BoxDecoration(
          color: active ? statusColor(label).withOpacity(.15) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: active ? statusColor(label) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: active ? statusColor(label) : Colors.black87,
          ),
        ),
      ),
    );
  }

  // TABLE GRID
  Widget _tableGrid() {
    final filtered = tables.where((t) {
      final matchStatus = selectedFilter == "All" || selectedFilter == t["status"];
      final matchSearch = searchController.text.isEmpty ||
          t["number"].toString().contains(searchController.text);
      return matchStatus && matchSearch;
    }).toList();

    return LayoutBuilder(builder: (context, constraints) {
      int columns = (constraints.maxWidth ~/ 170).clamp(1, 5);

      return GridView.builder(
        itemCount: filtered.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.05,
        ),
        itemBuilder: (_, i) => _tableCard(filtered[i]),
      );
    });
  }

  // TABLE CARD MODERN
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: status == "Available"
                ? Colors.green.withOpacity(.40)
                : Colors.grey.shade300,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.045),
              blurRadius: 6,
              offset: const Offset(1, 2),
            )
          ],
        ),
        child: Column(
          children: [
            // status badge
            Align(
              alignment: Alignment.topRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: color),
                ),
              ),
            ),
            const Spacer(),
            // table circle
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Text(
                "${table["number"]}",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const Spacer(),
            Text(
              "Table ${table["number"]}",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
                color: Colors.brown.shade700,
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
