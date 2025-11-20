import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/qctrade_api.dart';
import 'new_reservation_page.dart';

class ReservationsMainPage extends StatefulWidget {
  const ReservationsMainPage({super.key});

  @override
  State<ReservationsMainPage> createState() => _ReservationsMainPageState();
}

class _ReservationsMainPageState extends State<ReservationsMainPage> {
  bool loading = true;

  // Stats
  int todayReservations = 0;
  int confirmed = 0;
  int pending = 0;
  int availableTables = 0;

  // Tabs
  String activeTab = "reservations"; // reservations / tables

  // Lists
  List allReservations = [];
  List allTablesCombined = [];
  List visibleTables = [];

  // Filters
  String searchTerm = "";

  @override
  void initState() {
    super.initState();
    loadAll();
  }

  Future<void> loadAll() async {
    setState(() => loading = true);

    try {
      // Stats
      final stats = await ReservationApi.getStats();

      // Available tables
      final today = DateTime.now();
      final String date =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      final String time = "10:00";

      final available = await ReservationApi.getAvailableTables(date, time);

      // All reservations (occupied tables)
      final reservations = await ReservationApi.getAllReservations();

      // Build ALL tables merged list
      List occupied = reservations.map((r) {
        return {
          "table_number": r["table_number"],
          "section": r["section"] ?? "No Section",
          "capacity": r["seating_capacity"] ?? 0,
          "status": "occupied",
          "created_at": r["created_at"] ?? "",
          "updated_at": r["updated_at"] ?? "",
        };
      }).toList();

      List availableMapped = available.map((t) {
        return {
          "table_number": t["table_number"],
          "section": t["section"] ?? "No Section",
          "capacity": t["seating_capacity"] ?? 0,
          "status": "available",
          "created_at": t["created_at"] ?? "",
          "updated_at": t["updated_at"] ?? "",
        };
      }).toList();

      // Combine (React reference → 8 tables total)
      final combined = [...occupied, ...availableMapped];

      setState(() {
        todayReservations = stats["today"] ?? 0;
        confirmed = stats["confirmed"] ?? 0;
        pending = stats["pending"] ?? 0;
        availableTables = availableMapped.length;

        allReservations = reservations;
        allTablesCombined = combined;
        visibleTables = combined;

        loading = false;
      });
    } catch (e) {
      print("LOAD ERROR: $e");
      setState(() => loading = false);
    }
  }

  // Search tables
  void applyTableSearch() {
    setState(() {
      visibleTables = allTablesCombined.where((t) {
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

  // -------------------- UI -------------------------
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
              color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NewReservationPage()));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text("New Reservation",
                  style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ),
        ],
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _topTabs(),
                const SizedBox(height: 10),
                _statsRow(),
                const SizedBox(height: 15),
                if (activeTab == "tables") _tableSearchBar(),
                Expanded(
                    child: activeTab == "tables"
                        ? _tablesGrid()
                        : _reservationPlaceholder()),
              ],
            ),
    );
  }

  // ---------------- TABS -------------------------
  Widget _topTabs() {
    return Row(
      children: [
        _tabButton("Reservations", "reservations"),
        _tabButton("All Tables", "tables"),
      ],
    );
  }

  Widget _tabButton(String label, String key) {
    bool active = (activeTab == key);
    return GestureDetector(
      onTap: () => setState(() {
        activeTab = key;
        visibleTables = allTablesCombined;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 22),
        margin: const EdgeInsets.only(left: 12, top: 12),
        decoration: BoxDecoration(
          color: active ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? Colors.blue : Colors.grey.shade300, width: 1.2),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: active ? Colors.blue : Colors.black87)),
      ),
    );
  }

  // ---------------- STATS -------------------------
  Widget _statsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _statBox("Today's Reservations", todayReservations,
              Colors.blue.shade100),
          _statBox("Confirmed", confirmed, Colors.green.shade100),
          _statBox("Pending", pending, Colors.yellow.shade100),
          GestureDetector(
              onTap: () {
                activeTab = "tables";
                visibleTables = allTablesCombined
                    .where((t) => t["status"] == "available")
                    .toList();
                setState(() {});
              },
              child: _statBox(
                  "Available Tables", availableTables, Colors.purple.shade100)),
        ],
      ),
    );
  }

  Widget _statBox(String title, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.black87)),
            const SizedBox(height: 6),
            Text(value.toString(),
                style: GoogleFonts.poppins(
                    fontSize: 22, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  // ---------------- TABLE SEARCH -------------------------
  Widget _tableSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        onChanged: (v) {
          searchTerm = v;
          applyTableSearch();
        },
        decoration: InputDecoration(
          hintText: "Search tables...",
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  // ---------------- TABLE GRID -------------------------
  Widget _tablesGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: visibleTables.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemBuilder: (_, i) {
        final t = visibleTables[i];
        return _tableCard(t);
      },
    );
  }

  Widget _tableCard(Map t) {
    bool available = t["status"] == "available";

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Table ${t["table_number"]}",
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(t["section"],
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 10),

          // Status badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: available ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              available ? "available" : "occupied",
              style: TextStyle(
                color: available ? Colors.green : Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(Icons.event_seat, size: 16),
              const SizedBox(width: 6),
              Text("${t["capacity"]} Seats",
                  style: GoogleFonts.poppins(fontSize: 13))
            ],
          ),

          const SizedBox(height: 6),

          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16),
              const SizedBox(width: 6),
              Text(t["section"], style: GoogleFonts.poppins(fontSize: 13))
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- NO RESERVATIONS PLACEHOLDER -------------------------
  Widget _reservationPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.calendar_today, size: 60, color: Colors.grey),
          const SizedBox(height: 10),
          Text("This section only for reservation list\n(Not in your scope)",
              textAlign: TextAlign.center,
              style:
                  GoogleFonts.poppins(color: Colors.grey, fontSize: 15)),
        ],
      ),
    );
  }
}
