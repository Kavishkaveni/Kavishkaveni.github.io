import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../kds_staff/order_detail_page.dart';
import '../services/kds_api.dart';

class KdsOrderListPage extends StatefulWidget {
  const KdsOrderListPage({super.key});

  @override
  State<KdsOrderListPage> createState() => _KdsOrderListPageState();
}

class _KdsOrderListPageState extends State<KdsOrderListPage> {
  // ================= STATE =================
  bool loading = true;
  String? kitchenName;
  int? kitchenId;
  List<Map<String, dynamic>> orders = [];

  int currentPage = 0;
  final int pageSize = 10;

  Timer? refreshTimer;

  // ================= INIT =================
  @override
  void initState() {
    super.initState();
    loadOrders();

    // AUTO REFRESH EVERY 5 SECONDS
    refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => loadOrders(),
    );
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  // ================= API PART =================
  Future<void> loadOrders() async {
    try {
      if (!mounted) return;

      // Do not show loader every refresh
      if (orders.isEmpty) {
        setState(() => loading = true);
      }

      final kitchens = await KdsApi.getKitchens();
      final selectedKitchen = kitchens.first;

      kitchenId = selectedKitchen['id'];
      kitchenName = selectedKitchen['name'];

      final orderList = await KdsApi.getActiveOrders(
        kitchenId: kitchenId!,
        excludeCompleted: true,
      );

      if (!mounted) return;

      setState(() {
        orders = orderList;
        loading = false;
      });
    } catch (e) {
      debugPrint('KDS ORDER LIST ERROR: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  // ================= UI PART =================
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isTablet = width >= 900;

    final paginatedOrders = orders
        .skip(currentPage * pageSize)
        .take(pageSize)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),

      // ---------- APP BAR ----------
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'KDS',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ),

      // ---------- BODY ----------
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Kitchen name
                  if (kitchenName != null)
                    Text(
                      'Kitchen: $kitchenName',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                  const SizedBox(height: 16),

                  // ================= TABLET WALL SCREEN =================
                  if (isTablet)
                    Expanded(
                      child: orders.isEmpty
                          ? Center(
                              child: Text(
                                'No active orders',
                                style:
                                    GoogleFonts.poppins(color: Colors.grey),
                              ),
                            )
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                                childAspectRatio: 1.4,
                              ),
                              itemCount: orders.length,
                              itemBuilder: (context, index) {
                                return tabletOrderCard(orders[index]);
                              },
                            ),
                    )

                  // ================= MOBILE LIST =================
                  else ...[
                    Expanded(
                      child: paginatedOrders.isEmpty
                          ? Center(
                              child: Text(
                                'No active orders',
                                style:
                                    GoogleFonts.poppins(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: paginatedOrders.length,
                              itemBuilder: (context, index) {
                                return mobileOrderCard(
                                    paginatedOrders[index]);
                              },
                            ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: currentPage == 0
                              ? null
                              : () {
                                  setState(() {
                                    currentPage--;
                                  });
                                },
                          child: const Text('Previous'),
                        ),
                        Text(
                          'Page ${currentPage + 1}',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w500),
                        ),
                        TextButton(
                          onPressed: (currentPage + 1) * pageSize >=
                                  orders.length
                              ? null
                              : () {
                                  setState(() {
                                    currentPage++;
                                  });
                                },
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                  ]
                ],
              ),
            ),
    );
  }

  // ================= MOBILE CARD =================
  Widget mobileOrderCard(Map<String, dynamic> order) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: statusColor(order['kds_status']),
          width: 2,
        ),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          'Order ID: ${order['id']}',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          order['table'] ?? '',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
  final changed = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => KdsOrderDetailPage(order: order),
    ),
  );

  if (changed == true) {
    await loadOrders(); // refresh after status update
  }
},
      ),
    );
  }

  // ================= TABLET WALL CARD =================
Widget tabletOrderCard(Map<String, dynamic> order) {
  return Card(
    elevation: 4,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: statusColor(order['kds_status']),
        width: 3,
      ),
    ),
    child: Padding( 
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ORDER ID
          Text(
            'Order ${order['id']}',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 4),

          // TABLE + TIME
          Text(
            '${order['table']} • ${order['time']}',
            style: GoogleFonts.poppins(fontSize: 13),
          ),

          const SizedBox(height: 12),

          // ITEMS
          Expanded(
            child: ListView.builder(
              itemCount: order['items'].length,
              itemBuilder: (context, index) {
                final item = order['items'][index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${item['qty']}x ${item['name']}',
                    style: GoogleFonts.poppins(fontSize: 14),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // ACTION BUTTON
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                await KdsApi.advanceOrderStatus(
                  orderId: order['id'],
                  currentStatus: order['kds_status'],
                );
                await loadOrders();
              },
              child: Text(
                actionText(order['kds_status']),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  // ================= HELPERS =================
  String actionText(String status) {
    switch (status) {
      case 'pending':
        return 'Accept';
      case 'in-progress':
        return 'Complete';
      case 'preparing':
        return 'Complete';
      default:
        return 'Done';
    }
  }

  Color statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.red;
      case 'in-progress':
        return Colors.orange;
      case 'preparing':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
