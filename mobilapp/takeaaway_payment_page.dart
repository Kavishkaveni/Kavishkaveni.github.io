import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';

import '../printing/payment_pdf.dart';
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
  bool loading = true;

  Map<String, dynamic>? settlementData;
  List<dynamic> orderItems = [];

  String selectedPayment = "";

  // Discount
  int selectedDiscount = 0;
  final TextEditingController customDiscountController = TextEditingController();

  // Split bill
  int? splitWays;

  // Cash popup
  final TextEditingController cashController = TextEditingController();
  double? returnAmount;

  @override
  void initState() {
    super.initState();
    loadAllData();
  }


  Future<void> loadAllData() async {
    settlementData = await QcTradeApi.get(
      "${QcTradeApi.baseUrl}/orders/${widget.orderId}/validate-for-settlement",
    );

    final itemsRes = await QcTradeApi.get(
      "${QcTradeApi.baseUrl}/orders/${widget.orderId}",
    );

    orderItems = itemsRes?["items"] ?? [];

    loading = false;
    setState(() {});
  }

  // --------------------- CASH POPUP --------------------------
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
                  Text("Total Amount: \$${finalTotal.toStringAsFixed(2)}",
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
                      "Return Amount: \$${returnAmount!.toStringAsFixed(2)}",
                      style: GoogleFonts.poppins(
                          color: Colors.green,
                          fontWeight: FontWeight.w700),
                    ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () async {
                double received = double.tryParse(cashController.text) ?? 0;
                if (received < finalTotal) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Received amount is less than total!"),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                double balance = received - finalTotal;

                final res = await QcTradeApi.post(
                  "${QcTradeApi.baseUrl}/orders/${widget.orderId}/payments/cash",
                  {
                    "received_amount": received,
                    "return_amount": balance,
                    "total_amount": finalTotal
                  },
                );

                Navigator.pop(context);

                bool success = res != null && res["status"] == "success";

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? "Payment Successful — Return \$${balance.toStringAsFixed(2)}"
                        : "Payment Failed"),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              },
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );
  }

  // --------------------- QR POPUP --------------------------
  void _showQrPopup() {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text("QR Payment",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Scan the QR code below",
                style: GoogleFonts.poppins(fontSize: 14),
              ),
              const SizedBox(height: 15),
              Container(
                width: 180,
                height: 180,
                color: Colors.grey.shade300,
                child: const Center(child: Text("QR CODE")),
              )
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  // --------------------- UI BUILD --------------------------
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    double subtotal =
        (settlementData?["total_amount"] as num?)?.toDouble() ??
            widget.totalAmount;

    String msg =
        settlementData?["validation_message"] ?? "No message";

    // ---------- DISCOUNT ----------
    double discountAmount = subtotal * (selectedDiscount / 100);

    if (customDiscountController.text.trim().isNotEmpty) {
      double custom = double.tryParse(customDiscountController.text) ?? 0;
      discountAmount = subtotal * (custom / 100);
    }

    double afterDiscount = subtotal - discountAmount;

    // ---------- TAX ----------
    double tax = subtotal * 0.10;

    // ---------- FINAL TOTAL ----------
    double finalTotal = afterDiscount + tax;

    // ---------- SPLIT ----------
    double splitValue =
        splitWays != null ? finalTotal / splitWays! : finalTotal;

    Future<void> _printReceipt() async {
  final pdf = await PaymentPDF.generate(
    orderItems: orderItems.cast<Map<String, dynamic>>(),
    subtotal: subtotal,
    discount: discountAmount,
    tax: tax,
    finalTotal: finalTotal,
    orderId: widget.orderId,
  );

  await Printing.layoutPdf(
    onLayout: (format) async => pdf.save(),
  );
}

    return Scaffold(
      appBar: AppBar(
        title: Text("Payment",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: Colors.teal,
        actions: [
    IconButton(
      icon: const Icon(Icons.print, color: Colors.white),
      onPressed: () {
        // we'll add the print function next step
        _printReceipt();
      },
    )
  ],
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

  // --------------------- WIDGETS --------------------------

  Widget _paymentSummary(double subtotal, String msg) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Payment Summary",
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(msg,
              style: GoogleFonts.poppins(color: Colors.green.shade800)),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Main Order Subtotal"),
              Text("\$${subtotal.toStringAsFixed(2)}",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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
          Text("Main Order Items",
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ...orderItems.map((it) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${it["product_name"]} × ${it["quantity"]}"),
                Text("\$${(it["unit_price"] * it["quantity"]).toStringAsFixed(2)}"),
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
                  setState(() {
                    customDiscountController.clear();
                    selectedDiscount = d;
                  });
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          TextField(
            controller: customDiscountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: "Custom Discount %",
                border: OutlineInputBorder()),
            onChanged: (_) =>
                setState(() => selectedDiscount = 0),
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
    setState(() {
      splitWays = v;
    });
  },
),
const SizedBox(height: 10),

if (splitWays != null)
  Text(
    "Each person pays: \$${(finalTotal / splitWays!).toStringAsFixed(2)}",
    style: GoogleFonts.poppins(
      fontWeight: FontWeight.w700,
      color: Colors.teal,
    ),
  ),
        ],
      ),
    );
  }

  Widget _finalTotals(double subtotal, double discount, double tax, double finalTotal) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row("Subtotal", subtotal),
          _row("Discount", -discount),
          _row("Tax (10%)", tax),
          const Divider(),
          _row("Final Total",
              finalTotal,
              isBold: true),
        ],
      ),
    );
  }

  Widget _orderIdCard() {
    return _card(
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Order ID:",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          Text("#${widget.orderId}",
              style: GoogleFonts.poppins(fontSize: 16)),
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
          Text("Select Payment Method",
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: methods.map((m) {
              return GestureDetector(
                onTap: () {
                  setState(() => selectedPayment = m);
                  if (m == "Cash") _showCashPopup(finalTotal);
                  if (m == "QR") _showQrPopup();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 22),
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

  // ----------------- HELPERS -------------------

  Widget _card(Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6)
          ]),
      child: child,
    );
  }

  Widget _row(String title, double value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: GoogleFonts.poppins(
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w500)),
          Text("\$${value.toStringAsFixed(2)}",
              style: GoogleFonts.poppins(
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
  
}
