import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'takeaway_payment_page.dart';
import '../services/qctrade_api.dart';

class TakeAwayCartPage extends StatefulWidget {
  final Map<String, int> cart;
  final List<Map<String, dynamic>> menuItems;

  const TakeAwayCartPage({
    super.key,
    required this.cart,
    required this.menuItems,
  });

  @override
  State<TakeAwayCartPage> createState() => _TakeAwayCartPageState();
}

class _TakeAwayCartPageState extends State<TakeAwayCartPage> {
  // ---------- TOTAL ----------
  int get total {
    int t = 0;
    widget.cart.forEach((name, qty) {
      final item = widget.menuItems.firstWhere(
        (i) => i["product_name"] == name,
        orElse: () => {"price": 0},
      );
      t += (item["price"] as int) * qty;
    });
    return t;
  }

  // ---------- ADD ----------
  void add(String name) {
    setState(() => widget.cart[name] = (widget.cart[name] ?? 0) + 1);
  }

  // ---------- REMOVE ----------
  void remove(String name) {
    if (!widget.cart.containsKey(name)) return;

    setState(() {
      widget.cart[name] == 1
          ? widget.cart.remove(name)
          : widget.cart[name] = widget.cart[name]! - 1;
    });
  }

  // =============================================================
  // PROCEED BUTTON LOGIC (MATCHING REACT UI EXACTLY)
  // =============================================================
  Future<void> _proceedToPayment() async {
  print("STEP 1: Creating TAKEAWAY order with full payload...");

  // Build Items List
  List<Map<String, dynamic>> items = widget.cart.entries.map((e) {
    final product = widget.menuItems.firstWhere(
      (item) => item["product_name"] == e.key,
      orElse: () => {"product_id": "", "price": 0},
    );

    return {
      "product_id": product["product_id"],
      "quantity": e.value,
      "unit_price": product["price"],
      "product_name": e.key,
      "discount_amount": 0,
      "tax_amount": 0,
      "special_instructions": ""
    };
  }).toList();

  final payload = {
    "order_type": "takeaway",
    "flow_type": "payment_first",
    "total_amount": total,
    "items": items
  };

  print("PAYLOAD => $payload");

  final createRes = await QcTradeApi.createOrder(payload);

  if (createRes == null || createRes["id"] == null) {
    print("FAILED TO CREATE TAKEAWAY ORDER");
    return;
  }

  final orderId = createRes["id"];
  print("ORDER CREATED → ID = $orderId");

  // NAVIGATE TO PAYMENT PAGE
  Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => TakeAwayPaymentPage(
      cartData: Map<String, int>.from(widget.cart),
      totalAmount: total.toDouble(),            
      orderId: orderId,
      menuItems: widget.menuItems,
    ),
  ),
);
}

  // =============================================================
  //                           UI
  // =============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF00695C),
        title: Text("Your Cart",
            style: GoogleFonts.poppins(color: Colors.white)),
      ),
      body: widget.cart.isEmpty
          ? Center(
              child: Text("Cart is empty",
                  style: GoogleFonts.poppins(fontSize: 16)))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: widget.cart.entries.map((e) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text(e.key,
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w500))),
                            IconButton(
                                onPressed: () => remove(e.key),
                                icon: const Icon(Icons.remove_circle,
                                    color: Colors.red)),
                            Text("${e.value}",
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600)),
                            IconButton(
                                onPressed: () => add(e.key),
                                icon: const Icon(Icons.add_circle,
                                    color: Colors.green)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // BOTTOM BUTTON
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.teal,
                  child: SafeArea(
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white),
                        onPressed: _proceedToPayment,
                        child: Text("Proceed",
                            style: GoogleFonts.poppins(
                                color: Colors.teal,
                                fontWeight: FontWeight.w600,
                                fontSize: 16)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
