import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/qctrade_api.dart';

class TakeAwayPaymentPage extends StatefulWidget {
  final int orderId;
  final double totalAmount;                       
  final Map<String, int>? cartData;
  final List<Map<String, dynamic>>? menuItems;

  const TakeAwayPaymentPage({
    super.key,
    required this.orderId,
    required this.totalAmount,
    this.cartData,
    this.menuItems,
  });

  @override
  State<TakeAwayPaymentPage> createState() => _TakeAwayPaymentPageState();
}

class _TakeAwayPaymentPageState extends State<TakeAwayPaymentPage> {
  Map<String, dynamic>? settlementData;
  bool loading = true;

  String selectedPayment = "";

  @override
  void initState() {
    super.initState();
    loadSettlementMessage();
  }

  Future<void> loadSettlementMessage() async {
    final res = await QcTradeApi.get(
        "${QcTradeApi.baseUrl}/orders/${widget.orderId}/validate-for-settlement"
    );

    settlementData = res;
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

    // FIXED: Backend returns double
    final double subtotal =
        (settlementData?["total_amount"] as num?)?.toDouble() ??
            widget.totalAmount;

    final String validationMsg =
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
            _mainOrderItems(),
            const SizedBox(height: 18),
            _paymentMethodCard(),
          ],
        ),
      ),
    );
  }

  // ---------------- PAYMENT SUMMARY --------------------
  Widget _paymentSummary(double subtotal, String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Payment Summary",
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 16)),

          const SizedBox(height: 8),

          Row(
            children: [
              Icon(Icons.check_circle,
                  color: Colors.green.shade600, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.poppins(
                      color: Colors.green.shade800, fontSize: 14),
                ),
              )
            ],
          ),

          const SizedBox(height: 10),
          Divider(),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Main Order Subtotal",
                  style: GoogleFonts.poppins(fontSize: 14)),
              Text("Rs ${subtotal.toStringAsFixed(2)}",
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- ORDER ITEMS --------------------
  Widget _mainOrderItems() {
    if (widget.cartData == null ||
        widget.menuItems == null ||
        widget.cartData!.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _box(),
        child: Text("No order items available",
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
                  fontSize: 15, fontWeight: FontWeight.w600)),

          const SizedBox(height: 10),

          ...widget.cartData!.entries.map((e) {
            final item = widget.menuItems!.firstWhere(
              (i) => i["product_name"] == e.key,
              orElse: () => {"price": 0},
            );

            // FIXED: price from backend is DOUBLE
            double price =
                (item["price"] as num?)?.toDouble() ?? 0.0;

            int qty = e.value;
            double total = price * qty;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("${e.key} × $qty",
                      style: GoogleFonts.poppins()),
                  Text("Rs ${total.toStringAsFixed(2)}",
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ---------------- PAYMENT METHOD --------------------
  Widget _paymentMethodCard() {
    List<String> methods = ["Cash", "Card", "QR", "Credit"];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Payment Method",
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),

          Wrap(
            spacing: 12,
            children: methods.map((m) => _paymentButton(m)).toList(),
          )
        ],
      ),
    );
  }

  Widget _paymentButton(String type) {
    bool selected = selectedPayment == type;

    return GestureDetector(
      onTap: () => setState(() => selectedPayment = type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        decoration: BoxDecoration(
          color: selected ? Colors.teal : Colors.white,
          border: Border.all(color: Colors.teal),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          type,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.teal),
        ),
      ),
    );
  }

  // ---------------- BOX STYLE --------------------
  BoxDecoration _box() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black12,
          blurRadius: 6,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }
}
