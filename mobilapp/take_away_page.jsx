import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../OrdersPages/takeaway_payment_page.dart';
import '../core/responsive.dart';

class TakeAwayPage extends StatefulWidget {
  const TakeAwayPage({super.key});

  @override
  State<TakeAwayPage> createState() => _TakeAwayPageState();
}

class _TakeAwayPageState extends State<TakeAwayPage> {
  final TextEditingController searchController = TextEditingController();
  final Map<String, int> cart = {};
  String selectedCategory = "All";

  final List<Map<String, dynamic>> menuItems = [
    {"name": "Burger", "price": 450, "stock": 12, "type": "Food"},
    {"name": "Chicken Rice", "price": 650, "stock": 6, "type": "Food"},
    {"name": "Coke", "price": 180, "stock": 45, "type": "Drink"},
    {"name": "Sprite", "price": 100, "stock": 30, "type": "Drink"},
  ];

  void addToCart(String name) {
    setState(() => cart[name] = (cart[name] ?? 0) + 1);
  }

  void removeFromCart(String name) {
    if (!cart.containsKey(name)) return;
    setState(() {
      final qty = cart[name]!;
      qty <= 1 ? cart.remove(name) : cart[name] = qty - 1;
    });
  }

  int get total {
    return cart.entries.fold(0, (sum, e) {
      final item = menuItems.firstWhere((i) => i["name"] == e.key);
      final int price = (item["price"] as num).toInt();
      final int qty = (e.value as num).toInt();
      return sum + (price * qty);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF7EFE5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A2C2A),
        elevation: 0,
        title: Text(
          "Take Away Orders",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: Center(
        child: Container(
          width: Responsive.getMaxWidth(context),
          padding: const EdgeInsets.all(18),
          child: isMobile ? _mobileLayout() : _desktopLayout(),
        ),
      ),
    );
  }

  Widget _mobileLayout() {
    return Column(
      children: [
        _filters(),
        const SizedBox(height: 12),
        Expanded(child: _menuGrid()),
        if (cart.isNotEmpty) _bottomCartBar(),
      ],
    );
  }

  Widget _desktopLayout() {
    return Row(
      children: [
        Container(
          width: 300,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: _cartSection(),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: [
              _filters(),
              const SizedBox(height: 12),
              Expanded(child: _menuGrid()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: "Search menu...",
            prefixIcon: const Icon(Icons.search, size: 18),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: ["All", "Food", "Drink"].map((cat) {
            bool active = selectedCategory == cat;
            return GestureDetector(
              onTap: () => setState(() => selectedCategory = cat),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFB08A58) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.brown.shade200),
                ),
                child: Text(
                  cat,
                  style: GoogleFonts.poppins(
                      color: active ? Colors.white : Colors.brown.shade700,
                      fontWeight: FontWeight.w500),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _menuGrid() {
    final items = menuItems.where((item) {
      bool matchCat = selectedCategory == "All" || item["type"] == selectedCategory;
      bool matchSearch = searchController.text.isEmpty ||
          item["name"].toLowerCase().contains(searchController.text.toLowerCase());
      return matchCat && matchSearch;
    }).toList();

    return GridView.count(
      crossAxisCount: Responsive.isMobile(context)
          ? 2
          : Responsive.isTablet(context)
          ? 3
          : 4,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 0.72,
      children: items.map(_menuCard).toList(),
    );
  }

  Widget _menuCard(Map<String, dynamic> item) {
    return GestureDetector(
      onTap: () => addToCart(item["name"]),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.brown.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.brown.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fastfood, size: 32, color: Colors.brown),
              ),
            ),
            const SizedBox(height: 8),
            Text(item["name"],
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            Text("Rs ${item["price"]}",
                style: GoogleFonts.poppins(color: Colors.brown, fontSize: 12)),
            Text("${item["stock"]} in stock",
                style: GoogleFonts.poppins(color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _cartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Order List",
            style: GoogleFonts.poppins(
                fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Expanded(
          child: cart.isEmpty
              ? Center(
                  child: Text("Empty cart",
                      style: GoogleFonts.poppins(color: Colors.grey)))
              : ListView(
            children: cart.entries.map((e) {
              final price =
              menuItems.firstWhere((i) => i['name'] == e.key)["price"];
              final subtotal = price * e.value;

              return Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF8F4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.brown.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(e.key,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w500))),
                    IconButton(
                      onPressed: () => removeFromCart(e.key),
                      icon: const Icon(Icons.remove_circle,
                          color: Colors.red),
                    ),
                    Text("${e.value}"),
                    IconButton(
                      onPressed: () => addToCart(e.key),
                      icon: const Icon(Icons.add_circle,
                          color: Colors.green),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),

        Text("Total: Rs $total",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB08A58),
              elevation: 0,
            ),
            onPressed: cart.isEmpty
                ? null
                : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TakeAwayPaymentPage(
                    cartData: Map<String, int>.from(cart),
                    totalAmount: total,
                  ),
                ),
              );
            },
            child: Text(
              "Place Order",
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _bottomCartBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFF4A2C2A),
      child: Row(
        children: [
          Text("View Cart • Rs $total",
              style: GoogleFonts.poppins(color: Colors.white)),
          const Spacer(),
          const Icon(Icons.shopping_cart, color: Colors.white),
        ],
      ),
    );
  }
}
