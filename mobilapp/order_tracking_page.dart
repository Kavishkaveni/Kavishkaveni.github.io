import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OrderTrackingPage extends StatefulWidget {
  const OrderTrackingPage({super.key});

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage> {
  int? selectedOrderIndex;

  final List<Map<String, dynamic>> orders = [
    {
      "table": 150,
      "orderNo": 4,
      "customer": "Walk-in Customer",
      "status": "Pending",
      "items": [
        {"name": "Burger", "qty": 1, "price": 100}
      ],
      "subtotal": 100,
      "tax": 10,
      "total": 110,
      "date": "11/18/2025, 7:24:55 AM"
    },
    {
      "table": 900,
      "orderNo": 3,
      "customer": "Walk-in Customer",
      "status": "Pending",
      "items": [
        {"name": "Rice", "qty": 2, "price": 100}
      ],
      "subtotal": 200,
      "tax": 20,
      "total": 220,
      "date": "11/18/2025, 7:25:55 AM"
    },
    {
      "table": 400,
      "orderNo": 2,
      "customer": "Walk-in Customer",
      "status": "Pending",
      "items": [
        {"name": "Cheese", "qty": 1, "price": 100}
      ],
      "subtotal": 100,
      "tax": 10,
      "total": 110,
      "date": "11/18/2025, 7:27:55 AM"
    }
  ];

  Color brown = const Color(0xFF4A2C2A);
  Color beige = const Color(0xFFF7EFE5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: beige,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: brown,
        title: Text(
          "Order Tracking",
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: Row(
        children: [
          _leftSideOrderList(),
          Expanded(
            child: selectedOrderIndex == null
                ? _emptyRightSideView()
                : _orderDetailsView(),
          ),
        ],
      ),
    );
  }

  // ================= LEFT SIDE ORDER LIST =================
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
                color: active ? beige : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active ? brown : Colors.grey.shade300,
                  width: active ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(.05),
                      blurRadius: 4,
                      offset: const Offset(1, 2))
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Table ${ord["table"]} - #${ord["orderNo"]}",
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(ord["customer"],
                        style: GoogleFonts.poppins(
                            fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _statusTag(ord["status"]!),
                        Text("Rs ${ord["subtotal"]}",
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600))
                      ],
                    )
                  ]),
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
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: GoogleFonts.poppins(
            fontSize: 10, fontWeight: FontWeight.w500, color: Colors.orange),
      ),
    );
  }

  // ================= WHEN NOTHING SELECTED =================
  Widget _emptyRightSideView() {
    return Center(
      child: Text(
        "Select an Order",
        style: GoogleFonts.poppins(
            fontSize: 18, color: Colors.grey, fontWeight: FontWeight.w500),
      ),
    );
  }

  // ================= RIGHT SIDE MAIN CONTENT =================
  Widget _orderDetailsView() {
    final order = orders[selectedOrderIndex!];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          "Table ${order["table"]} - Order #${order["orderNo"]}",
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700, fontSize: 19, color: brown),
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

        _paymentSummaryCard(order["subtotal"], order["tax"], order["total"]),
      ]),
    );
  }

  // ================= ORDER PROGRESS CARD =================
  Widget _orderProgressCard(String status) {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Order Progress",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, fontSize: 15, color: brown)),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _progressStep("Pending", Icons.inventory_2, status == "Pending"),
            _progressStep("Kitchen In Progress", Icons.cookie, false),
            _progressStep("Preparing", Icons.restaurant, false),
            _progressStep("Pay", Icons.attach_money, false),
            _progressStep("Completed", Icons.verified, false),
          ],
        ),
      ]),
    );
  }

  Widget _progressStep(String label, IconData icon, bool active) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: active ? brown : Colors.grey.shade300,
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: active ? brown : Colors.grey)),
      ],
    );
  }

  // ================= ORDER ITEMS CARD =================
  Widget _orderItemsCard(List items) {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Order Items",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, fontSize: 15, color: brown)),
        const SizedBox(height: 12),
        Column(
          children: items.map((item) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: Colors.grey, width: .2))),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${item["name"]} × ${item["qty"]}",
                        style: GoogleFonts.poppins()),
                    Text("Rs ${item["qty"] * item["price"]}",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600))
                  ]),
            );
          }).toList(),
        ),
      ]),
    );
  }

  // ================= PAYMENT SUMMARY CARD =================
  Widget _paymentSummaryCard(int subtotal, int tax, int total) {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Payment Summary",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, fontSize: 15, color: brown)),
        const SizedBox(height: 10),
        _summaryRow("Main Order Subtotal", subtotal),
        _summaryRow("Tax (10%)", tax),
        const Divider(),
        _summaryRow("Total", total, isBold: true, isGreen: true),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: Colors.yellow.shade100,
              borderRadius: BorderRadius.circular(8)),
          child: Text("Payment Pending",
              style: GoogleFonts.poppins(color: Colors.orange)),
        ),
      ]),
    );
  }

  Widget _summaryRow(String title, int amount,
      {bool isBold = false, bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: GoogleFonts.poppins(fontSize: 12)),
        Text("Rs $amount",
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isGreen ? Colors.green : Colors.black,
            ))
      ]),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.06),
              blurRadius: 6,
              offset: const Offset(2, 3)),
        ],
      ),
      child: child,
    );
  }
}
