import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../ReservationsPages/new_reservation_page.dart';
import '../services/qctrade_api.dart';
import 'reservation_details_page.dart';

class ReservationsMainPage extends StatefulWidget {
  const ReservationsMainPage({super.key});

  @override
  State<ReservationsMainPage> createState() => _ReservationsMainPageState();
}

class _ReservationsMainPageState extends State<ReservationsMainPage> {
  int availableTables = 0;
  int confirmed = 0;
  int pending = 0;
  int todayReservations = 0;

  bool loading = true;
  List reservations = [];

  @override
  void initState() {
    super.initState();
    loadStats();
  }

  Future<void> loadStats() async {
    try {
      final stats = await ReservationApi.getStats();
      final tables = await ReservationApi.getAvailableTables();

      setState(() {
        availableTables = tables.length;
        confirmed = stats["confirmed"] ?? 0;
        pending = stats["pending"] ?? 0;
        todayReservations = stats["today"] ?? 0;
        loading = false;
      });
    } catch (e) {
      print("STATS LOAD ERROR: $e");
      setState(() => loading = false);
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
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NewReservationPage()),
                );
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
          )
        ],
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : _mainContent(),
    );
  }

  Widget _mainContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              _box("Today's Reservations", todayReservations, Colors.blue.shade100),
              _box("Confirmed", confirmed, Colors.green.shade100),
              _box("Pending", pending, Colors.yellow.shade100),
              _box("Available Tables", availableTables, Colors.purple.shade100),
            ],
          ),
          const SizedBox(height: 16),

          // Search + Filters
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: "Search reservations...",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.white,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month, size: 18),
                    const SizedBox(width: 8),
                    Text("dd-mm-yyyy"),
                  ],
                ),
              ),

              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white),
                child: Row(
                  children: const [
                    Text("All Status"),
                    Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),

              const SizedBox(width: 12),
              IconButton(
                onPressed: loadStats,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),

          const SizedBox(height: 40),

          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today,
                      size: 60, color: Colors.grey),
                  const SizedBox(height: 10),
                  Text(
                    "No reservations found",
                    style: GoogleFonts.poppins(
                        color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(String title, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    GoogleFonts.poppins(fontSize: 13, color: Colors.black87)),
            const SizedBox(height: 6),
            Text(
              value.toString(),
              style: GoogleFonts.poppins(
                  fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
