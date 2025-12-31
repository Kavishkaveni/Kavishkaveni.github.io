import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';

import "../OrdersPages/orders_page.dart";
import '../printing/payment_pdf.dart';
import '../services/qctrade_api.dart';
import '../PaymentProcessing/credit_payment_page.dart';

class DineInPaymentPage extends StatefulWidget {
  final Map<String, dynamic> order;

  const DineInPaymentPage({
  super.key,
  required this.order,
});

  @override
  State<DineInPaymentPage> createState() => _DineInPaymentPageState();
}

class _DineInPaymentPageState extends State<DineInPaymentPage> {
  bool loading = true;

  Map<String, dynamic>? settlementData;
  List<dynamic> orderItems = [];
  List<dynamic> subOrderItems = [];

double mainSubtotal = 0;
double subSubtotal = 0;

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
      "${QcTradeApi.baseUrl}/orders/${widget.order["id"]}/validate-for-settlement",
    );

final activeOrder = widget.order;
    
// MAIN ORDER ITEMS (FROM ACTIVE ORDER)
orderItems = [];

if (activeOrder != null && activeOrder["items"] is List) {
  orderItems = activeOrder["items"];
}
subOrderItems = [];

mainSubtotal = 0;
subSubtotal = 0;

// MAIN ORDER
for (final it in orderItems) {
  mainSubtotal +=
    (it["unit_price"] as num).toDouble() *
    (it["quantity"] as num).toDouble();
}

//CORRECT SOURCE
if (activeOrder["sub_orders"] != null &&
    activeOrder["sub_orders"] is List) {
  for (final sub in activeOrder["sub_orders"]) {
    if (sub["items"] is List) {
      for (final it in sub["items"]) {
        subOrderItems.add(it);
        subSubtotal +=
    (it["unit_price"] as num).toDouble() *
    (it["quantity"] as num).toDouble();
      }
    }
  }
}

debugPrint("OPEN ORDER ID: ${widget.order["id"]}");
debugPrint("MAIN ITEMS COUNT: ${orderItems.length}");
debugPrint("SUB ORDERS COUNT: ${subOrderItems.length}");
debugPrint("MAIN SUBTOTAL: $mainSubtotal");
debugPrint("SUB SUBTOTAL: $subSubtotal");

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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Text(
            "Cash Payment",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          content: StatefulBuilder(
            builder: (context, setStatePopup) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Total Amount: \$${finalTotal.toStringAsFixed(2)}",
                    style: GoogleFonts.poppins(fontSize: 15),
                  ),
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
                        fontWeight: FontWeight.w700,
                      ),
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
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () async {
                final received =
                    double.tryParse(cashController.text) ?? 0;

                if (received < finalTotal) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Received amount is less than total!"),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                //  CASH PAYMENT API
final res = await QcTradeApi.cashPaymentWithValidation(
  orderId: widget.order["id"],
  totalAmount: finalTotal,
  receivedAmount: received,
);

//CHECK BACKEND SUCCESS CORRECTLY
if (res == null || res["payment_completed"] != true) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text("Payment failed"),
      backgroundColor: Colors.red,
    ),
  );
  return;
}

// PRINT RECEIPT
await _printReceipt(
  subtotal: finalTotal,
  discount: 0,
  tax: 0,
  finalTotal: finalTotal,
);

if (!mounted) return;

// CLOSE CASH POPUP ONLY
Navigator.pop(context);

if (!mounted) return;

// SHOW SUCCESS POPUP
_showPaymentSuccessDialog();
              },
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );
  }

  void _showPaymentSuccessDialog() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: const Text("Payment Successful !!!"),
        content: const Text(
          "Payment completed successfully.\nPlease click Continue.",
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
  MaterialPageRoute(builder: (_) => OrdersPage()),
  (route) => route.isFirst, 
);
            },
            child: const Text("Continue"),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Text(
            "QR Payment",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
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
              ),
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

  Future<void> _printReceipt({
    required double subtotal,
    required double discount,
    required double tax,
    required double finalTotal,
  }) async {
    final pdf = await PaymentPDF.generate(
      orderItems: orderItems.cast<Map<String, dynamic>>(),
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      finalTotal: finalTotal,
      orderId: widget.order["id"],
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }

  // --------------------- UI BUILD --------------------------
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    double combinedSubtotal = mainSubtotal + subSubtotal;

    String msg =
        settlementData?["validation_message"] ?? "Payment Ready";

    double tax = combinedSubtotal * 0.10;
double taxableTotal = combinedSubtotal + tax;

    double discountPercent = selectedDiscount.toDouble();
    if (customDiscountController.text.trim().isNotEmpty) {
      discountPercent =
          double.tryParse(customDiscountController.text) ?? 0;
    }

    double discountAmount = taxableTotal * (discountPercent / 100);
    double finalTotal = taxableTotal - discountAmount;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Payment",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
  children: [
    _paymentSummary(combinedSubtotal, msg),
    const SizedBox(height: 18),

    _orderItems(),            // MAIN + SUB ITEMS
    const SizedBox(height: 18),

    _discountSection(),       // DISCOUNT
    const SizedBox(height: 18),

    _splitBillSection(finalTotal),
    const SizedBox(height: 18),

    _combinedSummary(tax, discountAmount),      
    const SizedBox(height: 18),

    _finalTotals(finalTotal), // UPDATED
    const SizedBox(height: 18),

    _orderIdCard(),
    const SizedBox(height: 18),

    _paymentMethodCard(finalTotal),
  ],
)
      ),
    );
  }

  // --------------------- WIDGETS --------------------------

  Widget _paymentSummary(double subtotal, String msg) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Payment Summary",
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(msg, style: GoogleFonts.poppins(color: Colors.green)),
          const Divider(),
          _row("Main Order Subtotal", subtotal),
        ],
      ),
    );
  }

  Widget _orderItems() {
  return Column(
    children: [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Main Order Items",
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ...orderItems.map(_itemRow),
          ],
        ),
      ),

      if (subOrderItems.isNotEmpty) ...[
        const SizedBox(height: 18),
        _card(
  Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text("Sub-Order Items",
          style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),

      ...subOrderItems.map(_itemRow),

      const Divider(),
      _row("Sub-Order Total", subSubtotal, isBold: true),
    ],
  ),
),
      ],
    ],
  );
}

  Widget _discountSection() {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Discount",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
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
              border: OutlineInputBorder(),
            ),
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
          Text(
            "Split Bill",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            hint: const Text("Select ways"),
            value: splitWays,
            items: [2, 3, 4, 5, 6].map((e) {
              return DropdownMenuItem(
                value: e,
                child: Text("$e ways"),
              );
            }).toList(),
            onChanged: (v) => setState(() => splitWays = v),
          ),
          if (splitWays != null) ...[
            const SizedBox(height: 10),
            Text(
              "Each person pays: \$${(finalTotal / splitWays!).toStringAsFixed(2)}",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: Colors.teal,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _combinedSummary(double tax, double discountAmount) {
  return _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Combined Subtotal",
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),

        _row("Main Order", mainSubtotal),
        _row("Sub-Orders (${subOrderItems.length})", subSubtotal),

        const Divider(),
        _row("Subtotal + Tax", mainSubtotal + subSubtotal + tax),
        _row("Discount (${selectedDiscount}%)", -discountAmount),
      ],
    ),
  );
}

  Widget _finalTotals(double finalTotal) {
  return _card(
    Column(
      children: [
        _row("Total", finalTotal, isBold: true),
      ],
    ),
  );
}

  Widget _orderIdCard() {
    return _card(
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Order ID",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          Text(
            "#${widget.order["id"]}",
            style: GoogleFonts.poppins(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _paymentMethodCard(double finalTotal) {
    final methods = ["Cash", "Card", "QR", "Credit"];

    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Select Payment Method",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: methods.map((m) {
              return GestureDetector(
                onTap: () async {
                  setState(() => selectedPayment = m);

                  if (m == "Cash") {
                    _showCashPopup(finalTotal);
                  }

                  if (m == "Credit") {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CreditPaymentPage(
        orderId: widget.order["id"],
        orderTotal: finalTotal,
      ),
    ),
  );
  return;
}

                  if (m == "QR") {
                    _showQrPopup();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 22,
                  ),
                  decoration: BoxDecoration(
                    color:
                        selectedPayment == m ? Colors.teal : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.teal),
                  ),
                  child: Text(
                    m,
                    style: TextStyle(
                      color: selectedPayment == m
                          ? Colors.white
                          : Colors.teal,
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
          BoxShadow(color: Colors.black12, blurRadius: 6),
        ],
      ),
      child: child,
    );
  }

  Widget _row(String title, double value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontWeight:
                  isBold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            "\$${value.toStringAsFixed(2)}",
            style: GoogleFonts.poppins(
              fontWeight:
                  isBold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  Widget _itemRow(dynamic it) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text("${it["product_name"]} × ${it["quantity"]}"),
      Text("\$${(it["unit_price"] * it["quantity"]).toStringAsFixed(2)}"),
    ],
  );
}
}
