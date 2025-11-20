import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/qctrade_api.dart';

class ReservationsMainPage extends StatefulWidget {
  const ReservationsMainPage({super.key});

  @override
  State<ReservationsMainPage> createState() => _ReservationsMainPageState();
}

class _ReservationsMainPageState extends State<ReservationsMainPage> {
  bool loading = true;

  int todayReservations = 0;
  int confirmed = 0;
  int pending = 0;
  int availableTables = 0;

  List allTables = [];
  List visibleTables = [];

  String searchTerm = "";

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    setState(() => loading = true);

    try {
      allTables = await QcTradeApi.getTables(); 
      visibleTables = allTables;

      final stats = await QcTradeApi.get("${QcTradeApi.baseUrl}/reservations/stats/overview");

      todayReservations = stats["reservations_today"] ?? 0;
      confirmed = stats["confirmed_reservations"] ?? 0;
      pending = stats["pending_reservations"] ?? 0;
      availableTables = stats["available_tables"] ?? 0;

    } catch (e) {
      print("LOAD ERROR: $e");
    }

    setState(() => loading = false);
  }

  void applySearch() {
    setState(() {
      visibleTables = allTables.where((t) {
        return t["table_number"]
                .toString()
                .toLowerCase()
                .contains(searchTerm.toLowerCase()) ||
            t["section"]
                .toString()
                .toLowerCase()
                .contains(searchTerm.toLowerCase());
      }).toList();
    });
  }

  Color statusColor(String status) {
    switch (status) {
      case "available":
        return Colors.green.shade100;
      case "occupied":
        return Colors.red.shade100;
      case "reserved":
        return Colors.yellow.shade100;
      default:
        return Colors.grey.shade200;
    }
  }

  Color statusText(String status) {
    switch (status) {
      case "available":
        return Colors.green;
      case "occupied":
        return Colors.red;
      case "reserved":
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff3f4f6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text(
          "Table Management & Reservations",
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.black87),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _statsSection(),
                _searchBar(),
                Expanded(child: _grid()),
              ],
            ),
    );
  }

  Widget _statsSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _stat("Today's Reservations", todayReservations, Colors.blue.shade100),
          _stat("Confirmed", confirmed, Colors.green.shade100),
          _stat("Pending", pending, Colors.yellow.shade100),
          _stat("Available Tables", availableTables, Colors.purple.shade100),
        ],
      ),
    );
  }

  Widget _stat(String title, int value, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.poppins(fontSize: 13)),
            const SizedBox(height: 5),
            Text(
              value.toString(),
              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        onChanged: (v) {
          searchTerm = v;
          applySearch();
        },
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          hintText: "Search tables...",
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _grid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: visibleTables.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,       // EXACTLY 4 PER ROW LIKE YOU WANT
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.35,  // PERFECT SIZE
      ),
      itemBuilder: (_, i) => _tableCard(visibleTables[i]),
    );
  }

  Widget _tableCard(Map t) {
    String status = t["status"]?.toLowerCase() ?? "unknown";

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Table ${t["table_number"]}",
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w600)),

          const SizedBox(height: 3),

          Text(
            t["section"]?.toString().isEmpty ?? true
                ? "No Section"
                : t["section"],
            style: GoogleFonts.poppins(
                fontSize: 11, color: Colors.grey.shade600),
          ),

          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: statusColor(status),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: statusText(status),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              const Icon(Icons.event_seat,
                  size: 14, color: Colors.black54),
              const SizedBox(width: 5),
              Text("${t["seating_capacity"]} Seats",
                  style: GoogleFonts.poppins(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
