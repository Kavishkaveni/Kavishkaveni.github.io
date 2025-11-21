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
      backgroundColor: const Color(0xFFE0F2F1),       // TEAL BG
      appBar: AppBar(
        backgroundColor: const Color(0xFF00695C),     // DARK TEAL
        elevation: 0,
        title: Text(
          "Payment",
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
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

  // ---------- LEFT SUMMARY ----------
  Widget _leftSummary(int tax, int finalTotal) {
    return Container(
      width: 330,
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(color: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Order Items", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),

          Expanded(
            child: ListView(
              children: widget.cartData.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("${e.key}  x${e.value}", style: GoogleFonts.poppins()),
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
          Text("Subtotal: Rs ${widget.totalAmount}", style: GoogleFonts.poppins()),
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

  // PAYMENT BUTTON WITH TEAL THEME
  Widget _paymentButton(String label) {
    final selected = selectedPayment == label;

    return GestureDetector(
      onTap: () => setState(() => selectedPayment = label),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF00695C) : Colors.white, // TEAL ACTIVE
          border: Border.all(color: const Color(0xFF00897B).withOpacity(.5)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              color: selected ? Colors.white : const Color(0xFF00695C),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- RIGHT SIDE ----------
  Widget _rightSideDetails(int finalTotal) {
    if (selectedPayment == "") {
      return Center(
        child: Text(
          "Select payment method",
          style: GoogleFonts.poppins(color: const Color(0xFF00695C)),
        ),
      );
    }

    if (selectedPayment == "Cash") return _cashUI(finalTotal);
    if (selectedPayment == "Card") return creditCardSummary();
    if (selectedPayment == "QR") {
      return Center(child: Text("QR Payment", style: GoogleFonts.poppins()));
    }
    if (selectedPayment == "Credit") return creditCardSummary();

    return const SizedBox();
  }

  // ---------- CASH UI ----------
  Widget _cashUI(int finalTotal) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Cash Payment", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),

          Text("Total Amount: Rs $finalTotal", style: GoogleFonts.poppins()),
          const SizedBox(height: 15),

          TextField(
            controller: cashAmount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: "Enter received amount",
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 20),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00695C),   // TEAL
              minimumSize: const Size(160, 45),
            ),
            onPressed: () async {
  if (cashAmount.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Enter cash amount")),
    );
    return;
  }

  int received = int.parse(cashAmount.text);
  int tax = (widget.totalAmount * 0.10).toInt();
  int finalTotal = widget.totalAmount + tax;

  if (received < finalTotal) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Received amount is less than total")),
    );
    return;
  }

  int returnAmount = received - finalTotal;

  // VALIDATE FIRST
  final eligibility =
      await QcTradeApi.validateTakeawayPaymentFirst(widget.orderId);

  if (eligibility == false) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Payment not eligible")),
    );
    return;
  }

  // CASH PAYMENT API (correct URL + correct payload)
  final result = await QcTradeApi.cashPayment(
    orderId: widget.orderId,
    paymentAmount: received,
    returnAmount: returnAmount,
    flowType: "takeaway",
  );

  if (result != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Payment Successful!")),
    );
    Navigator.pop(context);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Payment Failed")),
    );
  }
},
            child: Text(
              "Confirm",
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.w500),
            ),
          )
        ],
      ),
    );
  }

  // ---------- CARD / CREDIT ----------
  Widget creditCardSummary() {
    final double tax = widget.totalAmount * 0.10;
    final double grandTotal = widget.totalAmount + tax;

    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00897B).withOpacity(.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Payment Summary",
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF00695C),
              )),
          const SizedBox(height: 10),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFB2DFDB), // LIGHT TEAL
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "✔ Payment Ready — Proceed with Card Payment",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                color: const Color(0xFF00695C),
              ),
            ),
          ),

          const SizedBox(height: 14),
          Text("Main Order Items",
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: const Color(0xFF00695C))),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF00897B).withOpacity(.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Items", style: GoogleFonts.poppins(fontSize: 14)),
                Text("Rs ${widget.totalAmount}",
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: const Color(0xFF00695C))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
