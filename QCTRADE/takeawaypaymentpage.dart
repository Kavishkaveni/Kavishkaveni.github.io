import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';

import '../OrdersPages/order_tracking_page.dart';
import '../printing/payment_pdf.dart';
import '../services/qctrade_api.dart';

class TakeAwayPaymentPage extends StatefulWidget {
  final int orderId;

  const TakeAwayPaymentPage({super.key, required this.orderId});

  @override
  State<TakeAwayPaymentPage> createState() => _TakeAwayPaymentPageState();
}

class _TakeAwayPaymentPageState extends State<TakeAwayPaymentPage> {
  bool loading = true;

  // In TAKEAWAY flow, we can read subtotal from order response itself
  Map<String, dynamic>? orderData;
  List<dynamic> orderItems = [];

  String selectedPayment = "";

  // Discount
  int selectedDiscount = 0;
  final TextEditingController customDiscountController = TextEditingController();

  // Split bill dropdown
  int? splitWays;

  // Cash popup
  final TextEditingController cashController = TextEditingController();
  double? returnAmount;

  @override
  void initState() {
    super.initState();
    loadAllData();
  }

  // ---------------------------------------------------------
  // LOAD ORDER DATA (CORRECT FOR TAKEAWAY)
  // ---------------------------------------------------------
  Future<void> loadAllData() async {
    try {
      // Correct: load order details
      // (No validate-for-settlement for TAKEAWAY payment_first flow)
      final res = await QcTradeApi.get(
        "${QcTradeApi.baseUrl}/orders/${widget.orderId}",
      );

      orderData = res ?? {};

      // Items list
      orderItems = (orderData?["items"] as List?) ?? [];

      setState(() {
        loading = false;
      });
    } catch (e) {
      debugPrint("LOAD ORDER ERROR: $e");
      setState(() => loading = false);
    }
  }

  // ---------------------------------------------------------
  // SUCCESS POPUP
  // ---------------------------------------------------------
  Future<void> _showPaymentSuccessPopup({
  required double paidAmount,
  required double returnAmount,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: Colors.green,
            child: Icon(Icons.check, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 14),

          Text(
            "Payment Successful!",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 6),
          Text(
            "Your transaction has been completed successfully",
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13),
          ),

          const SizedBox(height: 16),

          _successRow("Payment Amount", paidAmount),
          const SizedBox(height: 6),
          _successRow("Return Amount", returnAmount),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
              ),
              onPressed: () {
                Navigator.pop(context); // close popup

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrderTrackingPage(
                      orderData: {
                        "id": widget.orderId,
                      },
                    ),
                  ),
                );
              },
              child: Text(
                "Continue →",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),
          Text(
            "Thank you for your business",
            style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    ),
  );
}

Widget _successRow(String label, double value) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: GoogleFonts.poppins(fontSize: 13)),
      Text(
        "Rs ${value.toStringAsFixed(2)}",
        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

  // ---------------------------------------------------------
  // PAY API (USED FOR CASH/CARD/QR/CREDIT)
  // ---------------------------------------------------------
  Future<Map<String, dynamic>?> _payOrder({
    required String method, // cash/card/qr/credit
    double? receivedAmount,
    double? returnAmount,
  }) async {
    // One unified endpoint for takeaway payment flow
    // If your backend uses a different path, only change this endpoint.
    final url = "${QcTradeApi.baseUrl}/orders/${widget.orderId}/pay";

    final payload = <String, dynamic>{
      "payment_method": method.toLowerCase(),
    };

    // For cash only
    if (method.toLowerCase() == "cash") {
      payload["received_amount"] = receivedAmount ?? 0;
      payload["return_amount"] = returnAmount ?? 0;
    }

    debugPrint("PAY URL => $url");
    debugPrint("PAY PAYLOAD => $payload");

    final res = await QcTradeApi.post(url, payload);

    // Some backends return {id:..., paid:true}, some return success msg.
    // We only treat NULL as fail.
    return res;
  }

  // ---------------------------------------------------------
  // CASH POPUP
  // ---------------------------------------------------------
  void _showCashPopup(double finalTotal) {
    returnAmount = null;
    cashController.clear();

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text("Cash Payment",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: StatefulBuilder(
            builder: (context, setStatePopup) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Total Amount: Rs ${finalTotal.toStringAsFixed(2)}",
                      style: GoogleFonts.poppins(fontSize: 15)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: cashController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Enter received amount",
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      double entered = double.tryParse(val) ?? 0;
                      setStatePopup(() {
                        returnAmount =
                            entered >= finalTotal ? entered - finalTotal : null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (returnAmount != null)
                    Text(
                      "Return Amount: Rs ${returnAmount!.toStringAsFixed(2)}",
                      style: const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.w700),
                    ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
              ),
              child: const Text("Confirm"),
              onPressed: () async {
                final received = double.tryParse(cashController.text) ?? 0;

                if (received < finalTotal) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Received amount is less than total!"),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final balance = received - finalTotal;

                // Correct: Pay using unified pay API
                final res = await _payOrder(
                  method: "cash",
                  receivedAmount: received,
                  returnAmount: balance,
                );

                Navigator.pop(context);

                if (res == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Payment Failed"),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // PRINT RECEIPT + SUCCESS POPUP
                await _printReceipt(finalTotal: finalTotal);

await _showPaymentSuccessPopup(
  paidAmount: finalTotal,
  returnAmount: balance,
);
              },
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------
  // SIMPLE PAYMENT CONFIRM (CARD / QR / CREDIT)
  // ---------------------------------------------------------
  Future<void> _confirmNonCashPayment(String method, double finalTotal) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("$method Payment",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text("Confirm $method payment for Rs ${finalTotal.toStringAsFixed(2)}?",
            style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Confirm"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    // Pay
    final res = await _payOrder(method: method);

    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Payment Failed"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await _printReceipt(finalTotal: finalTotal);

await _showPaymentSuccessPopup(
  paidAmount: finalTotal,
  returnAmount: 0,
);
  }

  // ---------------------------------------------------------
  // PRINT RECEIPT
  // ---------------------------------------------------------
  Future<void> _printReceipt({required double finalTotal}) async {
    // Subtotal from order (fallback to 0)
    final subtotal = _getSubtotalFromOrder().toDouble();

    final pdf = await PaymentPDF.generate(
      orderItems: orderItems.cast<Map<String, dynamic>>(),
      subtotal: subtotal,
      discount: selectedDiscount.toDouble(),
      tax: 0,
      finalTotal: finalTotal,
      orderId: widget.orderId,
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }

  // ---------------------------------------------------------
  // GET SUBTOTAL FROM ORDER (SAFE)
  // ---------------------------------------------------------
  double _getSubtotalFromOrder() {
    // Prefer total_amount from order if available
    final totalAmount = orderData?["total_amount"];
    if (totalAmount is num) return totalAmount.toDouble();

    // Else calculate from items
    double sum = 0;
    for (final it in orderItems) {
      final qty = (it["quantity"] is num) ? (it["quantity"] as num).toDouble() : 0;
      final price = (it["unit_price"] is num) ? (it["unit_price"] as num).toDouble() : 0;
      sum += qty * price;
    }
    return sum;
  }

  // ---------------------------------------------------------
  // UI
  // ---------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Subtotal from order (correct for takeaway)
    double subtotal = _getSubtotalFromOrder();

    // Message (keep UI same)
    String msg = "Ready for payment";

    // Discount
    double discountAmount = subtotal * (selectedDiscount / 100);

    if (customDiscountController.text.trim().isNotEmpty) {
      double custom = double.tryParse(customDiscountController.text) ?? 0;
      discountAmount = subtotal * (custom / 100);
    }

    double afterDiscount = subtotal - discountAmount;

    double tax = afterDiscount * 0.10;

    double finalTotal = afterDiscount + tax;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal.shade700,
        title: Text("Payment",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _paymentSummary(subtotal, msg),
            const SizedBox(height: 18),
            _orderItems(),
            const SizedBox(height: 18),
            _discountSection(),
            const SizedBox(height: 18),
            _splitBillSection(finalTotal),
            const SizedBox(height: 18),
            _finalTotals(subtotal, discountAmount, tax, finalTotal),
            const SizedBox(height: 18),
            _orderIdCard(),
            const SizedBox(height: 18),
            _paymentMethodCard(finalTotal),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // WIDGETS
  // ---------------------------------------------------------

  Widget _paymentSummary(double subtotal, String msg) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Payment Summary",
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(msg, style: TextStyle(color: Colors.green.shade800)),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Subtotal"),
              Text("Rs ${subtotal.toStringAsFixed(2)}",
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _orderItems() {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Order Items",
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ...orderItems.map((it) {
            final qty = (it["quantity"] is num) ? (it["quantity"] as num) : 0;
            final unit = (it["unit_price"] is num) ? (it["unit_price"] as num) : 0;
            final lineTotal = (qty.toDouble() * unit.toDouble());

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${it["product_name"]} × $qty"),
                Text("Rs ${lineTotal.toStringAsFixed(2)}"),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _discountSection() {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Discount",
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [0, 5, 10, 15, 20].map((d) {
              return ChoiceChip(
                label: Text("$d%"),
                selected: selectedDiscount == d,
                onSelected: (_) {
                  customDiscountController.clear();
                  setState(() => selectedDiscount = d);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: customDiscountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Custom Discount %",
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => selectedDiscount = 0),
          ),
        ],
      ),
    );
  }

  Widget _splitBillSection(double finalTotal) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Split Bill",
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            decoration: const InputDecoration(border: OutlineInputBorder()),
            hint: const Text("Select ways"),
            value: splitWays,
            items: [2, 3, 4, 5, 6].map((e) {
              return DropdownMenuItem(
                value: e,
                child: Text("$e ways"),
              );
            }).toList(),
            onChanged: (v) {
              setState(() => splitWays = v);
            },
          ),
          const SizedBox(height: 10),
          if (splitWays != null)
            Text(
              "Each pays: Rs ${(finalTotal / splitWays!).toStringAsFixed(2)}",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: Colors.teal,
              ),
            ),
        ],
      ),
    );
  }

  Widget _finalTotals(
      double subtotal, double discount, double tax, double finalTotal) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row("Subtotal", subtotal),
          _row("Discount", -discount),
          _row("Tax (10%)", tax),
          const Divider(),
          _row("Final Total", finalTotal, bold: true),
        ],
      ),
    );
  }

  Widget _orderIdCard() {
    return _card(
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Order ID"),
          Text("#${widget.orderId}",
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _paymentMethodCard(double finalTotal) {
    List<String> methods = ["Cash", "Card", "QR", "Credit"];

    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Payment Method",
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: methods.map((m) {
              return GestureDetector(
                onTap: () async {
                  setState(() => selectedPayment = m);

                  if (m == "Cash") {
                    _showCashPopup(finalTotal);
                  } else if (m == "Card") {
                    await _confirmNonCashPayment("card", finalTotal);
                  } else if (m == "QR") {
                    await _confirmNonCashPayment("qr", finalTotal);
                  } else if (m == "Credit") {
                    await _confirmNonCashPayment("credit", finalTotal);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 22),
                  decoration: BoxDecoration(
                    color: selectedPayment == m ? Colors.teal : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.teal),
                  ),
                  child: Text(
                    m,
                    style: TextStyle(
                      color: selectedPayment == m ? Colors.white : Colors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------
  Widget _card(Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: child,
    );
  }

  Widget _row(String title, double value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            "Rs ${value.toStringAsFixed(2)}",
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
