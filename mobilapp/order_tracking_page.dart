import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OrderTrackingPage extends StatefulWidget {
  final Map<String, dynamic> orderData;

  const OrderTrackingPage({
    super.key,
    required this.orderData,
  });

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage> {
  int? selectedOrderIndex;
  late List<Map<String, dynamic>> orders;

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

  @override
  void initState() {
    super.initState();

    orders = [
      {
        "table": widget.orderData["table_number"] ??
         widget.orderData["table_info"]?["table_number"] ??
         widget.orderData["table_id"] ??
         0,
        "orderNo": widget.orderData["id"] ?? 1,
        "customer": widget.orderData["customer"] ??
            widget.orderData["customer_name"] ??
            "Walk-in Customer",
        "status": widget.orderData["status"] ?? "pending",
        "items": (widget.orderData["items"] ?? []).map((it) {
          return {
            "product_name": it["product_name"] ??
                it["name"] ??
                it["product"] ??
                "Unknown Item",
            "quantity": toInt(it["quantity"] ?? it["qty"]),
            "unit_price": toInt(it["unit_price"] ?? it["price"]),
          };
        }).toList(),
        "subtotal": toInt(widget.orderData["subtotal"] ??
            widget.orderData["total_amount"]),
        "tax": toInt(widget.orderData["tax"] ?? 0),
        "total": toInt(
            widget.orderData["total"] ?? widget.orderData["total_amount"]),
        "date": DateTime.now().toString(),
      }
    ];

    selectedOrderIndex = 0;
  }

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
      body: isMobile ? _mobileView() : _desktopView(),
    );
  }

  Widget _mobileView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: _orderDetailsView(orders[selectedOrderIndex!]),
    );
  }

  Widget _desktopView() {
    return Row(
      children: [
        _leftSideOrderList(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: _orderDetailsView(orders[selectedOrderIndex!]),
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
                    "Table ${ord["table"]} - #${ord["orderNo"]}",
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
                      _statusTag(ord["status"]!),
                      Text(
                        "Rs ${ord["subtotal"]}",
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
          "Table ${order["table"]} - Order #${order["orderNo"]}",
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
        const SizedBox(height: 18),

        _paymentSummaryCard(
          order["subtotal"],
          order["tax"],
          order["total"],
        ),
      ],
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
                _progressStep("Pending", Icons.inventory_2,
                    status == "pending"),
                _progressStep("Kitchen", Icons.cookie, false),
                _progressStep("Preparing", Icons.restaurant, false),
                _progressStep("Pay", Icons.attach_money, false),
                _progressStep("Completed", Icons.verified, false),
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
                  border: Border(
                      bottom: BorderSide(color: Colors.grey, width: .2)),
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

  Widget _paymentSummaryCard(int subtotal, int tax, int total) {
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
          _summaryRow("Main Order Subtotal", subtotal),
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
              "Payment Pending",
              style: GoogleFonts.poppins(color: primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String title, int amount,
      {bool isBold = false, bool isBlue = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: GoogleFonts.poppins(fontSize: 12)),
          Text(
            "Rs $amount",
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
