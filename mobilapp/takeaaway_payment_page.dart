import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/qctrade_api.dart';

class TakeAwayPaymentPage extends StatefulWidget {
  final Map<String, int> cartData;
  final int totalAmount;
  final int orderId;

  const TakeAwayPaymentPage({
    super.key,
    required this.cartData,
    required this.totalAmount,
    required this.orderId,
  });

  @override
  State<TakeAwayPaymentPage> createState() => _TakeAwayPaymentPageState();
}

class _TakeAwayPaymentPageState extends State<TakeAwayPaymentPage> {
  String selectedPayment = "";
  TextEditingController cashAmount = TextEditingController();

  @override
  Widget build(BuildContext context) {
    int tax = (widget.totalAmount * 0.10).toInt();
    int finalTotal = widget.totalAmount + tax;

    return Scaffold(
      backgroundColor: const Color(0xFFE0F2F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00695C),
        elevation: 0,
        title: Text(
          "Payment",
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: Row(
        children: [
          _leftSummary(tax, finalTotal),
          Expanded(child: _rightSideDetails(finalTotal)),
        ],
      ),
    );
  }

  // LEFT SECTION
  Widget _leftSummary(int tax, int finalTotal) {
    return Container(
      width: 330,
      padding: const EdgeInsets.all(18),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Order Items",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),

          Expanded(
            child: ListView(
              children: widget.cartData.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("${e.key}  x${e.value}",
                          style: GoogleFonts.poppins()),
                      Text(
                        "Rs ${(widget.totalAmount / widget.cartData.length).toInt()}",
                        style: GoogleFonts.poppins(),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 10),
          Text("Subtotal: Rs ${widget.totalAmount}",
              style: GoogleFonts.poppins()),
          Text("Tax (10%): Rs $tax", style: GoogleFonts.poppins()),
          const Divider(),
          Text("Total: Rs $finalTotal",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          Text("Select Payment",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          _paymentButton("Cash"),
          const SizedBox(height: 8),
          _paymentButton("Card"),
          const SizedBox(height: 8),
          _paymentButton("QR"),
          const SizedBox(height: 8),
          _paymentButton("Credit"),
        ],
      ),
    );
  }

  Widget _paymentButton(String label) {
    final selected = selectedPayment == label;

    return GestureDetector(
      onTap: () => setState(() => selectedPayment = label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF00695C) : Colors.white,
          border: Border.all(color: const Color(0xFF00897B).withOpacity(.5)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.poppins(
                color: selected ? Colors.white : const Color(0xFF00695C)),
          ),
        ),
      ),
    );
  }

  // RIGHT SECTION
  Widget _rightSideDetails(int finalTotal) {
    if (selectedPayment == "") {
      return Center(
          child: Text("Select payment method",
              style: GoogleFonts.poppins(color: const Color(0xFF00695C))));
    }

    if (selectedPayment == "Cash") return _cashUI(finalTotal);
    if (selectedPayment == "Card") return _cardUI(finalTotal);
    if (selectedPayment == "QR") return _qrUI(finalTotal);
    if (selectedPayment == "Credit") return _cardUI(finalTotal);

    return const SizedBox();
  }

  // ---------------- CASH UI -----------------
  Widget _cashUI(int finalTotal) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Cash Payment",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),

          Text("Total Amount: Rs $finalTotal",
              style: GoogleFonts.poppins()),
          const SizedBox(height: 15),

          TextField(
            controller: cashAmount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: "Enter received amount",
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 20),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00695C),
              minimumSize: const Size(160, 45),
            ),
            onPressed: () async {
              if (cashAmount.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Enter cash amount")));
                return;
              }

              final received = int.parse(cashAmount.text);
              if (received < finalTotal) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text("Received amount is less than total")),
                );
                return;
              }

              int returnAmount = received - finalTotal;

              // STEP 1 → VALIDATION
              bool eligible = await QcTradeApi
                  .validateTakeawayPaymentFirst(widget.orderId);

              if (!eligible) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Payment not eligible")));
                return;
              }

              // STEP 2 → CASH PAYMENT API
              final result = await QcTradeApi.cashPayment(
                orderId: widget.orderId,
                totalAmount: finalTotal,
                paymentAmount: received,
                returnAmount: returnAmount,
                flowType: "payment_first",
              );

              if (result != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Payment Successful!")));
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Payment Failed")));
              }
            },
            child: Text("Confirm",
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w500)),
          )
        ],
      ),
    );
  }

  // ---------------- CARD UI -----------------
  Widget _cardUI(int finalTotal) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Card Payment",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          const SizedBox(height: 15),

          _paymentSummary(finalTotal),

          const SizedBox(height: 25),

          ElevatedButton(
            onPressed: () async {
              bool ok = await QcTradeApi.processCardOrQrPayment(
                orderId: widget.orderId,
                totalAmount: finalTotal,
                method: "card",
              );

              if (ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Card Payment Successful")));
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Card Payment Failed")));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                minimumSize: const Size(180, 45)),
            child: Text("Pay with Card",
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ---------------- QR UI -----------------
  Widget _qrUI(int finalTotal) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("QR Payment",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          const SizedBox(height: 15),

          _paymentSummary(finalTotal),

          const SizedBox(height: 25),

          ElevatedButton(
            onPressed: () async {
              bool ok = await QcTradeApi.processCardOrQrPayment(
                orderId: widget.orderId,
                totalAmount: finalTotal,
                method: "qr",
              );

              if (ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("QR Payment Successful")));
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("QR Payment Failed")));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                minimumSize: const Size(180, 45)),
            child: Text("Pay with QR",
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _paymentSummary(int finalTotal) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.teal.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text("Total to Pay: Rs $finalTotal",
          style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF00695C))),
    );
  }
}
