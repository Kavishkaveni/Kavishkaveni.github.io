import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/qctrade_api.dart';

class OrderTrackingPage extends StatefulWidget {
  final int orderId;

  const OrderTrackingPage({
    super.key,
    required this.orderId,
  });

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage> {
  int? selectedOrderIndex;
  late List<Map<String, dynamic>> orders;
  Timer? timer;

  final Color primaryBlue = const Color(0xFF1565C0);
  final Color lightBlue = const Color(0xFFE3F2FD);
  final Color accentBlue = const Color(0xFF1E88E5);
  final Color tagBlue = const Color(0xFF64B5F6);

  int toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // ================= PAYMENT STATUS =================

  String resolvePaymentStatus(dynamic o) {
    final paymentStatus =
        (o["payment_status"] ?? "").toString().toLowerCase();
    final status =
        (o["status"] ?? "").toString().toLowerCase();

    if (paymentStatus == "paid") return "Payment Completed";
    if (status == "pay" || status.contains("ready"))
      return "Payment Ready";

    return "Payment Pending";
  }

  bool isPaidFromBackend(dynamic o) {
    final paymentStatus =
        (o["payment_status"] ?? "").toString().toLowerCase();
    final status =
        (o["status"] ?? "").toString().toLowerCase();

    return paymentStatus == "paid" ||
        status.contains("payment_completed");
  }

  // ================= STATUS =================

  String normalizeStatus(dynamic o) {
    final status = (o["status"] ?? "").toString().toLowerCase();

    if (status == "completed") return "completed";
    if (status.contains("kitchen")) return "kitchen_in_progress";
    if (status.contains("preparing")) return "preparing";
    if (status == "pay" || status.contains("ready"))
      return "ready_to_pay";

    return "pending";
  }

  String prettyStatus(dynamic raw) {
    final s = (raw ?? "").toString();
    if (s.isEmpty) return "Pending";

    return s
        .split('_')
        .map((e) => e[0].toUpperCase() + e.substring(1))
        .join(' ');
  }

  // ================= TOTALS =================

  double calcSubtotalFromItems(List<Map<String, dynamic>> items) {
  double sum = 0.0;
  for (final it in items) {
    sum += toDouble(it["quantity"]) * toDouble(it["unit_price"]);
  }
  return sum;
}

  // ================= MAP ORDER =================

  Map<String, dynamic> _mapOrder(dynamic o) {
    final items = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> subOrderItems = [];
double subOrderTotal = 0.0;

    if (o["items"] is List) {
      for (final it in o["items"]) {
        items.add({
          "product_name": it["product_name"],
          "quantity": toInt(it["quantity"]),
          "unit_price": toInt(it["unit_price"]),
        });
      }
    }

    if (o["sub_orders"] is List) {
  for (final sub in o["sub_orders"]) {
    if (sub["items"] is List) {
      for (final it in sub["items"]) {
        final qty = toInt(it["quantity"]);
        final price = toDouble(it["unit_price"]);

        subOrderItems.add({
          "product_name": it["product_name"],
          "quantity": qty,
          "unit_price": price,
        });

        subOrderTotal += qty * price;
      }
    }
  }
}

    final double mainSubtotal = calcSubtotalFromItems(items);
final double combinedSubtotal =
    toDouble(o["combined_total"] ?? (mainSubtotal + subOrderTotal));

final double tax =
    double.parse((combinedSubtotal * 0.10).toStringAsFixed(2));

final double total =
    double.parse((combinedSubtotal + tax).toStringAsFixed(2));

    final tableValue =
        o["table_info"]?["number"] ?? o["table_number"];

    return {
      "showTable": tableValue != null,
      "table": tableValue,
      "orderNo": o["id"],
      "customer": o["customer_name"] ?? "Walk-in Customer",
      "status": normalizeStatus(o),
      "raw_status": o["status"],
      "raw_status_label": prettyStatus(o["status"]),
      "items": items,
      "sub_items": subOrderItems,
"main_subtotal": mainSubtotal,
"sub_total": subOrderTotal,
"combined_subtotal": combinedSubtotal,
      "tax": tax,
      "total": total,
      "payment_status": resolvePaymentStatus(o),
      "date": o["created_at"],
    };
  }

  // ================= API REFRESH =================

  @override
  void initState() {
    super.initState();

    orders = [];
    selectedOrderIndex = 0;

    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshOrder();
    });

    _refreshOrder();
  }

  Future<void> _refreshOrder() async {
    try {
      final res = await QcTradeApi.getActiveOrders(
        page: 1,
        limit: 20,
        status: "all",
      );

      if (res == null || res["orders"] == null) return;

      final found = (res["orders"] as List)
          .firstWhere((e) => e["id"] == widget.orderId,
              orElse: () => null);

      if (found == null) return;

      final mapped = _mapOrder(found);

      setState(() {
        if (orders.isEmpty) {
          orders.add(mapped);
        } else {
          orders[0] = mapped;
        }
      });
    } catch (e) {
      debugPrint("ORDER REFRESH ERROR: $e");
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  // ================= UI (UNCHANGED) =================

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 850;

    return Scaffold(
      backgroundColor: lightBlue,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: primaryBlue,
        title: Text(
          "Order Tracking",
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: orders.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : (isMobile ? _mobileView() : _desktopView()),
    );
  }

  Widget _mobileView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: _orderDetailsView(orders[0]),
    );
  }

  Widget _desktopView() {
    return Row(
      children: [
        _leftSideOrderList(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: _orderDetailsView(orders[0]),
          ),
        ),
      ],
    );
  }

  Widget _leftSideOrderList() {
    return Container(
      width: 300,
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: ListView.builder(
        itemCount: orders.length,
        itemBuilder: (_, i) {
          final ord = orders[i];
          final bool active = selectedOrderIndex == i;

          return GestureDetector(
            onTap: () => setState(() => selectedOrderIndex = i),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: active ? lightBlue : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active ? primaryBlue : Colors.grey.shade300,
                  width: active ? 1.3 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ord["showTable"] == true
                        ? "Table ${ord["table"]} - #${ord["orderNo"]}"
                        : "Order #${ord["orderNo"]}",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    ord["customer"],
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _statusTag(ord["raw_status_label"]),
                      Text(
                        "Rs ${ord["subtotal"].toStringAsFixed(2)}",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusTag(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tagBlue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: accentBlue,
        ),
      ),
    );
  }

  Widget _orderDetailsView(Map order) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          order["showTable"] == true
              ? "Table ${order["table"]} - Order #${order["orderNo"]}"
              : "Order #${order["orderNo"]}",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 19,
            color: primaryBlue,
          ),
        ),
        Text(order["customer"],
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
        Text(order["date"],
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 14),
        _orderProgressCard(order["status"]),
        const SizedBox(height: 18),
        _orderItemsCard(order["items"]),
        if ((order["sub_items"] as List).isNotEmpty) ...[
  const SizedBox(height: 18),
  _subOrderItemsCard(order["sub_items"]),
],
        const SizedBox(height: 18),
        _paymentSummaryCard(
  order["main_subtotal"],
  order["sub_total"],
  order["combined_subtotal"],
  order["tax"],
  order["total"],
  order["payment_status"],
),
        if (order["payment_status"] != "Payment Completed")
  _cancelOrderButton(order["orderNo"]),
      ],
    );
  }

  Widget _subOrderItemsCard(List items) {
  return _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Sub-Order Items",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: primaryBlue,
          ),
        ),
        const SizedBox(height: 12),
        Column(
          children: items.map((item) {
            final qty = toInt(item["quantity"]);
            final price = toDouble(item["unit_price"]);

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey, width: .2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("${item["product_name"]} × $qty"),
                  Text(
                    "Rs ${(qty * price).toStringAsFixed(2)}",
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    ),
  );
}

  // ================= REMAINING UI UNCHANGED =================

  Widget _cancelOrderButton(int orderId) {
  return Padding(
    padding: const EdgeInsets.only(top: 16),
    child: SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade600,
        ),
        onPressed: () => _showCancelDialog(orderId),
        child: const Text("Cancel Order"),
      ),
    ),
  );
}

void _showCancelDialog(int orderId) {
  final reasonController = TextEditingController();

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Cancel Order"),
      content: TextField(
        controller: reasonController,
        decoration: const InputDecoration(
          labelText: "Cancellation Reason *",
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Back"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          onPressed: () async {
            if (reasonController.text.trim().isEmpty) return;

            await QcTradeApi.post(
              "${QcTradeApi.baseUrl}/orders/$orderId/cancel",
              {
                "reason": reasonController.text.trim(),
              },
            );

            Navigator.pop(context); // dialog
            Navigator.pop(context); // order tracking page
          },
          child: const Text("Confirm Cancel"),
        ),
      ],
    ),
  );
}

  Widget _orderProgressCard(String status) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Order Progress",
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: primaryBlue)),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _progressStep("Pending", Icons.inventory_2, status == "pending"),
                _progressStep("Kitchen", Icons.cookie,
                    status == "kitchen_in_progress"),
                _progressStep(
                    "Preparing", Icons.restaurant, status == "preparing"),
                _progressStep(
                    "Pay", Icons.attach_money, status == "ready_to_pay"),
                _progressStep(
                    "Completed", Icons.verified, status == "completed"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressStep(String label, IconData icon, bool active) {
    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: active ? primaryBlue : Colors.grey.shade300,
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: active ? primaryBlue : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderItemsCard(List items) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Order Items",
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: primaryBlue)),
          const SizedBox(height: 12),
          Column(
            children: items.map((item) {
              final name = item["product_name"] ?? "Item";
              final qty = toInt(item["quantity"]);
              final price = toInt(item["unit_price"]);

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: Colors.grey, width: .2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("$name × $qty", style: GoogleFonts.poppins()),
                    Text("Rs ${qty * price}",
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _paymentSummaryCard(
  double mainSubtotal,
  double subTotal,
  double combinedSubtotal,
  double tax,
  double total,
  String paymentStatus,
) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Payment Summary",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: primaryBlue,
            ),
          ),
          const SizedBox(height: 10),
          _summaryRow("Main Order Subtotal", mainSubtotal),
if (subTotal > 0)
  _summaryRow("Sub-Order Total", subTotal),
const Divider(),
_summaryRow("Combined Subtotal", combinedSubtotal),
_summaryRow("Tax (10%)", tax),
const Divider(),
_summaryRow("Total", total, isBold: true, isBlue: true),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.lightBlue.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              paymentStatus,
              style: GoogleFonts.poppins(color: primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String title, double amount,
      {bool isBold = false, bool isBlue = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: GoogleFonts.poppins(fontSize: 12)),
          Text("Rs ${amount.toStringAsFixed(2)}",
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBlue ? primaryBlue : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 6,
            offset: const Offset(2, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}
