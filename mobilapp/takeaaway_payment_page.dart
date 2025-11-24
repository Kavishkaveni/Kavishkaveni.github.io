import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/qctrade_api.dart';

class TakeAwayPaymentPage extends StatefulWidget {
  final Map<String, int> cartData;
  final int totalAmount;
  final int orderId;
  final List<Map<String, dynamic>> menuItems;

  const TakeAwayPaymentPage({
    super.key,
    required this.cartData,
    required this.totalAmount,
    required this.orderId,
    required this.menuItems,
  });

  @override
  State<TakeAwayPaymentPage> createState() => _TakeAwayPaymentPageState();
}

class _TakeAwayPaymentPageState extends State<TakeAwayPaymentPage> {
  String selectedPayment = "";
  String inlineMessage = "";
  bool inlineMessageSuccess = false;

  TextEditingController cashAmount = TextEditingController();

  void showInlineMessage(String msg, bool success) {
    setState(() {
      inlineMessage = msg;
      inlineMessageSuccess = success;
    });
  }

  @override
  Widget build(BuildContext context) {
    int tax = (widget.totalAmount * 0.10).toInt();
    int finalTotal = widget.totalAmount + tax;

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
            _orderSummary(finalTotal, tax),
            const SizedBox(height: 20),
            _paymentOptions(),
            const SizedBox(height: 20),

            if (selectedPayment == "Cash") _cashUI(finalTotal),
            if (selectedPayment == "Card") _cardUI(finalTotal),
            if (selectedPayment == "QR") _qrUI(finalTotal),
            if (selectedPayment == "Credit") _creditUI(finalTotal),
          ],
        ),
      ),
    );
  }

  // ORDER SUMMARY
  Widget _orderSummary(int finalTotal, int tax) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Order Summary",
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w600)),

          const SizedBox(height: 12),

          ...widget.cartData.entries.map((e) {
            final item = widget.menuItems.firstWhere(
              (i) => i["product_name"] == e.key,
              orElse: () => {"price": 0},
            );

            int price = item["price"];
            int qty = e.value;
            int total = price * qty;

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${e.key} x$qty",
                    style: GoogleFonts.poppins(fontSize: 15)),
                Text("Rs $total",
                    style: GoogleFonts.poppins(fontSize: 15)),
              ],
            );
          }),

          const Divider(height: 25),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Subtotal:", style: GoogleFonts.poppins()),
              Text("Rs ${widget.totalAmount}", style: GoogleFonts.poppins()),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Tax (10%):", style: GoogleFonts.poppins()),
              Text("Rs $tax", style: GoogleFonts.poppins()),
            ],
          ),

          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Total:",
                  style: GoogleFonts.poppins(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              Text("Rs $finalTotal",
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.green)),
            ],
          ),
        ],
      ),
    );
  }

  // PAYMENT OPTIONS
  Widget _paymentOptions() {
    List<String> options = ["Cash", "Card", "QR", "Credit"];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Select Payment Method",
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),

          Wrap(
            spacing: 12,
            children: options.map((o) => _paymentButton(o)).toList(),
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
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 22),
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

  // CASH UI
  Widget _cashUI(int finalTotal) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Cash Payment",
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w700)),

          const SizedBox(height: 10),
          Text("Total Amount: Rs $finalTotal",
              style: GoogleFonts.poppins(fontSize: 16)),

          const SizedBox(height: 15),
          TextField(
            controller: cashAmount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Enter paid amount",
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 15),

          if (inlineMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: inlineMessageSuccess
                    ? Colors.green.shade100
                    : Colors.red.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                inlineMessage,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    color: inlineMessageSuccess
                        ? Colors.green.shade900
                        : Colors.red.shade900),
              ),
            ),

          const SizedBox(height: 15),
          ElevatedButton(
            onPressed: () => _handleCashPayment(finalTotal),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal, minimumSize: const Size(200, 45)),
            child: Text("Confirm", style: GoogleFonts.poppins()),
          )
        ],
      ),
    );
  }

  Future<void> _handleCashPayment(int finalTotal) async {
    if (cashAmount.text.isEmpty) {
      showInlineMessage("Enter cash amount", false);
      return;
    }

    int received = int.parse(cashAmount.text);
    if (received < finalTotal) {
      showInlineMessage("Paid amount is less than total", false);
      return;
    }

    int balance = received - finalTotal;

    final validateRes = await QcTradeApi.validateTakeaway(widget.orderId);

if (validateRes == null || validateRes["can_process_payment"] != true) {
  showInlineMessage("Payment not eligible", false);
  return;
}

    final res = await QcTradeApi.cashPayment(
      orderId: widget.orderId,
      totalAmount: finalTotal,
      paymentAmount: received,
      returnAmount: balance,
    );

    if (res != null) {
      showInlineMessage("Payment Successful! Balance Rs $balance", true);
    } else {
      showInlineMessage("Payment Failed", false);
    }
  }

  // CARD UI
  Widget _cardUI(int finalTotal) {
    return _genericPaymentUI("Card Payment", "card", finalTotal);
  }

  // QR UI
  Widget _qrUI(int finalTotal) {
    return _genericPaymentUI("QR Payment", "qr", finalTotal);
  }

  Widget _genericPaymentUI(String title, String method, int finalTotal) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text("Total Amount: Rs $finalTotal",
              style: GoogleFonts.poppins(fontSize: 16)),
          const SizedBox(height: 15),

          ElevatedButton(
            onPressed: () async {
              bool ok = await QcTradeApi.processCardOrQrPayment(
                orderId: widget.orderId,
                totalAmount: finalTotal,
                method: method,
              );

              if (ok) {
                showInlineMessage("$title Successful!", true);
              } else {
                showInlineMessage("$title Failed!", false);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal, minimumSize: const Size(200, 45)),
            child: Text("Pay", style: GoogleFonts.poppins()),
          ),

          if (inlineMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                inlineMessage,
                style: TextStyle(
                    color: inlineMessageSuccess ? Colors.green : Colors.red),
              ),
            ),
        ],
      ),
    );
  }

  // CREDIT UI
  Widget _creditUI(int finalTotal) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Credit Payment",
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),

          Text("Select Customer (Pending UI)",
              style: GoogleFonts.poppins(color: Colors.grey)),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  BoxDecoration _box() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(color: Colors.black12, blurRadius: 6, offset: const Offset(0, 3))
      ],
    );
  }
}
