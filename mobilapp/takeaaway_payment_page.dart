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
  bool loading = true;

  Map<String, dynamic>? settlementData;
  List<dynamic> orderItems = [];

  String selectedPayment = "";

  final TextEditingController cashController = TextEditingController();
  double? returnAmount;

  @override
  void initState() {
    super.initState();
    loadAllData();
  }

  // FETCH BACKEND DATA
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

  // CASH POPUP
void _showCashPopup(double totalAmount) {
  returnAmount = null;        // reset
  cashController.clear();     // reset

  showDialog(
    context: context,
    builder: (_) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "Cash Payment",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: StatefulBuilder(
          builder: (context, setStatePopup) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  "Total Amount:",
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  "\$${totalAmount.toStringAsFixed(2)}",
                  style: GoogleFonts.poppins(fontSize: 15, color: Colors.teal),
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
                    if (entered >= totalAmount) {
                      setStatePopup(() {
                        returnAmount = entered - totalAmount;
                      });
                    } else {
                      setStatePopup(() {
                        returnAmount = null;
                      });
                    }
                  },
                ),

                const SizedBox(height: 12),

                if (returnAmount != null)
                  Text(
                    "Return Amount: \$${returnAmount!.toStringAsFixed(2)}",
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.green,
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

          // CONFIRM BUTTON
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () async {
              final text = cashController.text.trim();
              if (text.isEmpty) return;

              double received = double.tryParse(text) ?? 0;

              if (received < totalAmount) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Received amount is less than total!"),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              double balance = received - totalAmount;

              // ==== CALL CASH PAYMENT API ====
              final res = await QcTradeApi.post(
                "${QcTradeApi.baseUrl}/orders/${widget.orderId}/payments/cash",
                {
                  "received_amount": received,
                  "return_amount": balance,
                  "total_amount": totalAmount
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
void _showQrPopup() {
  showDialog(
    context: context,
    builder: (_) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "QR Payment",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Scan the QR code below to complete the payment",
              style: GoogleFonts.poppins(fontSize: 14),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 15),

            // TEMP BOX FOR QR CODE
            Container(
              width: 180,
              height: 180,
              color: Colors.grey.shade300,
              alignment: Alignment.center,
              child: const Text("QR CODE HERE"),
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

  // UI BUILD
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
            _paymentMethodCard(subtotal),
          ],
        ),
      ),
    );
  }

  // PAYMENT SUMMARY
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
              Text("\$${subtotal.toStringAsFixed(2)}",
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
        ],
      ),
    );
  }

  // ORDER ITEMS
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
                  Text("\$${total.toStringAsFixed(2)}",
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

  // PAYMENT METHOD CARD
  Widget _paymentMethodCard(double subtotal) {
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

          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: methods.map((m) {
              return _paymentButton(m, subtotal);
            }).toList(),
          ),
        ],
      ),
    );
  }

  // PAYMENT BUTTONS
  Widget _paymentButton(String type, double subtotal) {
    bool selected = selectedPayment == type;

    return GestureDetector(
      onTap: () {
  setState(() => selectedPayment = type);

  if (type == "Cash") {
    _showCashPopup(subtotal);
  }

  if (type == "QR") {
    _showQrPopup();
  }
},
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 22),
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

  // BOX STYLE
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
