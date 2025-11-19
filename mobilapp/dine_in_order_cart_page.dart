import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../OrdersPages/order_tracking_page.dart';

class DineInOrderCartPage extends StatefulWidget {
  final int tableNumber;
  final Map<String, int> cartItems;
  final int total;

  const DineInOrderCartPage({
    required this.tableNumber,
    required this.cartItems,
    required this.total,
    super.key,
  });

  @override
  State<DineInOrderCartPage> createState() => _DineInOrderCartPageState();
}

class _DineInOrderCartPageState extends State<DineInOrderCartPage> {
  String selectedCategory = "All";
  TextEditingController searchController = TextEditingController();

  final List<Map<String, dynamic>> menuItems = [
    {"name": "Burger", "price": 450, "stock": 12, "category": "Food", "image": ""},
    {"name": "Chicken Rice", "price": 650, "stock": 6, "category": "Food", "image": ""},
    {"name": "Coke", "price": 180, "stock": 40, "category": "Drink", "image": ""},
    {"name": "Ice Cream", "price": 150, "stock": 20, "category": "Dessert", "image": ""},
  ];

  final Map<String, int> cart = {};

  void addToCart(String name) {
    setState(() {
      cart[name] = (cart[name] ?? 0) + 1;
    });
  }

  void decreaseItem(String name) {
    if (!cart.containsKey(name)) return;
    final qty = cart[name]!;
    if (qty <= 1) {
      setState(() => cart.remove(name));
    } else {
      setState(() => cart[name] = qty - 1);
    }
  }

  int get total {
    int t = 0;
    cart.forEach((key, qty) {
      final item = menuItems.firstWhere((i) => i["name"] == key);
      t += (item["price"] as int) * qty;
    });
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 850;

    return Scaffold(
      backgroundColor: const Color(0xFFF7EFE5), // cream background
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A2C2A), // dark brown
        elevation: 0,
        title: Text(
          "Table ${widget.tableNumber} - Orders",
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: isMobile ? _mobileLayout() : _desktopLayout(),
    );
  }

  // DESKTOP VIEW
  Widget _desktopLayout() {
    return Row(
      children: [
        Expanded(flex: 4, child: _leftOrderSection()),
        Expanded(flex: 7, child: _rightMenuSection()),
      ],
    );
  }

  // MOBILE VIEW
  Widget _mobileLayout() {
    return Column(
      children: [
        Expanded(child: _rightMenuSection()),
        _bottomCartButton(),
      ],
    );
  }

  // LEFT CART (DESKTOP)
  Widget _leftOrderSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Order Details", style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600)),
          Text("Table ${widget.tableNumber}", style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          const SizedBox(height: 14),
          Text("Order Items", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Expanded(child: _cartList()),
          const SizedBox(height: 10),
          Divider(),
          Text("Total: Rs $total",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  // CART LIST
  Widget _cartList() {
    if (cart.isEmpty) {
      return Center(child: Text("Your cart is empty", style: GoogleFonts.poppins(color: Colors.grey)));
    }
    return ListView(
      children: cart.entries.map((e) {
        final item = menuItems.firstWhere((i) => i["name"] == e.key);
        return Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFDF8F4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.brown.shade100),
          ),
          child: Row(
            children: [
              Expanded(child: Text(e.key, style: GoogleFonts.poppins(fontWeight: FontWeight.w500))),
              IconButton(onPressed: () => decreaseItem(e.key),
                  icon: const Icon(Icons.remove_circle, color: Colors.red)),
              Text("${e.value}", style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              IconButton(onPressed: () => addToCart(e.key),
                  icon: const Icon(Icons.add_circle, color: Colors.green)),
              const SizedBox(width: 8),
              Text("Rs ${item["price"] * e.value}",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // RIGHT MENU + FILTERS + BUTTONS
  Widget _rightMenuSection() {
    final filteredMenu = menuItems.where((item) {
      bool catMatch = selectedCategory == "All" || item["category"] == selectedCategory;
      bool searchMatch = searchController.text.isEmpty ||
          item["name"].toLowerCase().contains(searchController.text.toLowerCase());
      return catMatch && searchMatch;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      color: const Color(0xFFFDF8F4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _categories(),
        const SizedBox(height: 10),
        _searchBox(),
        const SizedBox(height: 14),
        Expanded(
          child: GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width < 850 ? 2 : 4,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.73,
            children: filteredMenu.map((item) => _menuCard(item)).toList(),
          ),
        ),
        const SizedBox(height: 12),
        _actionButtons(),
      ]),
    );
  }

  Widget _categories() {
    final cats = ["All", "Food", "Drink", "Dessert"];
    return Row(
      children: cats.map((c) {
        bool active = selectedCategory == c;
        return GestureDetector(
          onTap: () => setState(() => selectedCategory = c),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFB08A58) : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              c,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                color: active ? Colors.white : Colors.black87,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _searchBox() {
    return TextField(
      controller: searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: "Search menu items...",
        prefixIcon: const Icon(Icons.search, size: 18),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _menuCard(Map<String, dynamic> item) {
    return GestureDetector(
      onTap: () => addToCart(item["name"]),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.brown.shade100),
          boxShadow: [
            BoxShadow(color: Colors.brown.withOpacity(.05), blurRadius: 6, offset: const Offset(2, 2)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.brown.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.fastfood, color: Colors.brown, size: 30),
            ),
          ),
          const SizedBox(height: 8),
          Text(item["name"], style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
          Text("Rs ${item["price"]}",
              style: GoogleFonts.poppins(color: Colors.brown.shade700, fontSize: 12)),
          Text("${item["stock"]} in stock",
              style: GoogleFonts.poppins(color: Colors.grey, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _actionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _smallBtn("Back", Colors.grey.shade400, Colors.black),
        const SizedBox(width: 8),
        _smallBtn("Cancel", Colors.red.shade600, Colors.white),
        const SizedBox(width: 8),
        _smallBtn("Settlement", const Color(0xFF4A2C2A), Colors.white),
        const SizedBox(width: 8),
        SizedBox(
  height: 38,
  child: ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFB08A58),
      elevation: 0,
    ),
    onPressed: () async {

      // show loading popup
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF4A2C2A)),
        ),
      );

      // wait 2 seconds (you can reduce later)
      await Future.delayed(const Duration(seconds: 2));

      Navigator.pop(context); // close loading

      // navigate to your existing Order Tracking Page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const OrderTrackingPage(),
        ),
      );
    },
    child: Text(
      "Send to Kitchen",
      style: GoogleFonts.poppins(
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
    ),
  ),
),
      ],
    );
  }

  Widget _smallBtn(String text, Color bg, Color fg) {
    return SizedBox(
      height: 38,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: bg, elevation: 0),
        onPressed: () {},
        child: Text(text, style: GoogleFonts.poppins(color: fg, fontWeight: FontWeight.w500)),
      ),
    );
  }

  // MOBILE BOTTOM BAR
  Widget _bottomCartButton() {
    if (cart.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF4A2C2A),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.2), blurRadius: 10)],
      ),
      child: GestureDetector(
        onTap: () {},
        child: Row(
          children: [
            Text("View Cart • Rs $total",
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.shopping_cart, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
