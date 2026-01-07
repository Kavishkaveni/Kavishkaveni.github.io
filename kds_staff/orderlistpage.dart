import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../kds_staff/order_detail_page.dart';
import '../kds_staff/order_grid_page.dart';
import '../services/kds_api.dart';

class KdsOrderListPage extends StatefulWidget {
  const KdsOrderListPage({super.key});

  @override
  State<KdsOrderListPage> createState() => _KdsOrderListPageState();
}

class _KdsOrderListPageState extends State<KdsOrderListPage> {
  // ================= STATE =================
  Map<String, dynamic>? workflowConfig;
List<Map<String, dynamic>> workflowActions = [];

String searchText = '';
String selectedStatus = 'all'; // default

bool isGridView = false; // false = List, true = Grid

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

      try {
  final wf = await KdsApi.getWorkflowConfig();
  workflowConfig = wf['config'];
  workflowActions = List<Map<String, dynamic>>.from(wf['actions'] ?? [])
      .where((a) => a['is_active'] == true)
      .toList()
    ..sort((a, b) => (a['sequence'] ?? 0).compareTo(b['sequence'] ?? 0));
} catch (e) {
  debugPrint("WORKFLOW CONFIG FAILED: $e");
  workflowConfig = null;
  workflowActions = [];
}

      final orderList = await KdsApi.getActiveOrders(
        kitchenId: kitchenId!,
        excludeCompleted: true,
      );

      if (!mounted) return;

      setState(() {
  orders = orderList.where((o) {
    final kds = (o['kds_status'] ?? '').toString();
    final pay = (o['payment_status'] ?? '').toString();
    return !(kds == 'completed' && pay == 'completed');
  }).toList();

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

  actions: [
    IconButton(
      icon: Icon(
        Icons.list,
        color: isGridView ? Colors.grey : Colors.blue,
      ),
      onPressed: () {
        setState(() => isGridView = false);
      },
    ),
    IconButton(
  icon: Icon(
    Icons.grid_view,
    color: Colors.blue,
  ),
  onPressed: () async {
    if (kitchenId == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KdsOrderGridPage(
          kitchenId: kitchenId!,
          workflowActions: workflowActions,
        ),
      ),
    );

    await loadOrders(); // refresh when coming back
  },
),
  ],
),

      // ---------- BODY ----------
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

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
  final kds = (order['kds_status'] ?? '').toString();
  final pay = (order['payment_status'] ?? '').toString();

  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: statusColor(kds), width: 1.5),
    ),
    child: ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

      title: Text(
        'Order #${order['id']}',
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),

      subtitle: Text(
        'Status: ${kds.toUpperCase()} | Payment: ${pay.toUpperCase()}',
        style: GoogleFonts.poppins(fontSize: 12),
      ),

      trailing: const Icon(Icons.arrow_forward_ios, size: 14),

      onTap: () async {
        final changed = await showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    child: KdsOrderDetailPage(
      order: order,
      workflowActions: workflowActions,
    ),
  ),
);
        if (changed == true) await loadOrders();
      },
    ),
  );
}

Widget _statusChip({
  required String label,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
      ),
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
          buildActionButton(order),
        ],
      ),
    ),
  );
}

Widget buildActionButton(Map<String, dynamic> order) {
  if (workflowActions.isEmpty) return const SizedBox();

  final currentKey = (order['kds_status'] ?? '').toString();

  // Find current action index
  final currentIndex =
      workflowActions.indexWhere((a) => a['action_key'] == currentKey);

  // If not found OR already terminal OR no next step => no button
  if (currentIndex == -1) return const SizedBox();
  if (workflowActions[currentIndex]['is_terminal'] == true) return const SizedBox();
  if (currentIndex + 1 >= workflowActions.length) return const SizedBox();

  final nextAction = workflowActions[currentIndex + 1];

  final String nextKey = (nextAction['action_key'] ?? '').toString();
  final String nextLabel = (nextAction['label'] ?? '').toString();
  final String nextIcon = (nextAction['icon'] ?? '').toString();
  final String nextColorHex = (nextAction['color'] ?? '#6c757d').toString();

  return SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(int.parse(nextColorHex.replaceFirst('#', '0xff'))),
      ),
      onPressed: () async {
        await KdsApi.updateOrderStatus(
          orderId: order['id'].toString(),
          status: nextKey,
        );
        await loadOrders();
      },
      child: Text('$nextIcon $nextLabel'),
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
