import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/qctrade_api.dart';

class TakeAwayPaymentPage extends StatefulWidget {
  final int orderId;
  final double totalAmount;

  final Map<String, int>? cartData;                        // ✅ ADD THIS
  final List<Map<String, dynamic>>? menuItems;             // ✅ ADD THIS

  const TakeAwayPaymentPage({
    super.key,
    required this.orderId,
    required this.totalAmount,
    this.cartData,
    this.menuItems,
  });

  @override
  State<TakeAwayPaymentPage> createState() =>
      _TakeAwayPaymentPageState();
}
class _TakeAwayPaymentPageState extends State<TakeAwayPaymentPage> {
  bool loading = true;

  Map<String, dynamic>? settlementData;
  List<dynamic> orderItems = [];

  String selectedPayment = "";

  @override
  void initState() {
    super.initState();
    loadAllData();
  }

  Future<void> loadAllData() async {
    // 1️⃣ Get settlement message
    settlementData = await QcTradeApi.get(
      "${QcTradeApi.baseUrl}/orders/${widget.orderId}/validate-for-settlement",
    );

    // 2️⃣ Get backend order items
    final itemsRes = await QcTradeApi.get(
      "${QcTradeApi.baseUrl}/orders/${widget.orderId}",
    );

    orderItems = itemsRes?["items"] ?? [];

    loading = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    double subtotal =
        (settlementData?["total_amount"] as num?)?.toDouble() ??
            widget.totalAmount;

    String validationMsg =
        settlementData?["validation_message"] ?? "No message";

    return Scaffold(
      appBar: AppBar(
        title: Text("Payment",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _paymentSummary(subtotal, validationMsg),
            const SizedBox(height: 18),
            _backendOrderItems(),
            const SizedBox(height: 18),
            _paymentMethodCard(),
          ],
        ),
      ),
    );
  }

  // PAYMENT SUMMARY CARD
  Widget _paymentSummary(double subtotal, String msg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Payment Summary",
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w700)),

          const SizedBox(height: 10),

          Row(
            children: [
              Icon(Icons.info, color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  msg,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.green.shade800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Main Order Subtotal",
                  style: GoogleFonts.poppins(fontSize: 14)),
              Text("Rs ${subtotal.toStringAsFixed(2)}",
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
        ],
      ),
    );
  }

  // BACKEND ORDER ITEMS
  Widget _backendOrderItems() {
    if (orderItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _box(),
        child: Text("No items found",
            style: GoogleFonts.poppins()),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Main Order Items",
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),

          ...orderItems.map((it) {
            String name = it["product_name"] ?? "Item";
            int qty = (it["quantity"] as num?)?.toInt() ?? 0;
            double price = (it["unit_price"] as num?)?.toDouble() ?? 0.0;
            double total = qty * price;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("$name × $qty",
                      style: GoogleFonts.poppins(fontSize: 14)),
                  Text("Rs ${total.toStringAsFixed(2)}",
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // PAYMENT METHOD
  Widget _paymentMethodCard() {
    List<String> methods = ["Cash", "Card", "QR", "Credit"];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Select Payment Method",
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),

          
        ],
      ),
    );
  }

  Widget _paymentButton(String type) {
    bool selected = selectedPayment == type;

    return GestureDetector(
      onTap: () => setState(() => selectedPayment = type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 22),
        decoration: BoxDecoration(
          color: selected ? Colors.teal : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.teal),
        ),
        child: Text(
          type,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.teal,
          ),
        ),
      ),
    );
  }

  BoxDecoration _box() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black12,
          blurRadius: 6,
          offset: const Offset(0, 3),
        )
      ],
    );
  }
}
