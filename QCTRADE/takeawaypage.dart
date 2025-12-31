import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../OrdersPages/takeaway_cart_page.dart';
import '../core/responsive.dart';
import '../services/qctrade_api.dart';

class TakeAwayPage extends StatefulWidget {
  const TakeAwayPage({super.key});

  @override
  State<TakeAwayPage> createState() => _TakeAwayPageState();
}

class _TakeAwayPageState extends State<TakeAwayPage> {
  final TextEditingController searchController = TextEditingController();
  final Map<String, int> cart = {};

  List<Map<String, dynamic>> menuItems = [];
  List<String> categories = ["All"];

  String selectedCategory = "All";

  @override
  void initState() {
    super.initState();
    fetchCategories();
    fetchMenuItems();
  }
  Future<void> fetchCategories() async {
  try {
    final res = await QcTradeApi.get(
      "${QcTradeApi.baseUrl}/categories/realtime",
    );

    if (res is Map && res["data"] is List) {
      final List list = res["data"];

      setState(() {
        categories = [
          "All",
          ...list
              .map((c) => c["name"]?.toString() ?? "")
              .where((c) => c.isNotEmpty)
              .toList(),
        ];

        // safety reset
        if (!categories.contains(selectedCategory)) {
          selectedCategory = "All";
        }
      });
    }
  } catch (e) {
    debugPrint("CATEGORY FETCH ERROR: $e");
  }
}

  Future<void> fetchMenuItems() async {
    try {
      final response = await QcTradeApi.getProducts();

      if (response is List) {
        List<Map<String, dynamic>> updated = [];

        for (var item in response) {
          updated.add({
            "product_id": item["product_id"],
            "product_name": item["product_name"],
            "price": (item["selling_price"] ?? 0).toInt(),
            "category": item["category"] ?? "",
            "stock": item["stock"] ?? 0,
          });
        }

        setState(() => menuItems = updated);
      }
    } catch (e) {
      print("Menu fetch error: $e");
    }
  }

  int get total {
    return cart.entries.fold(0, (sum, e) {
      final item = menuItems.firstWhere(
        (i) => i["product_name"] == e.key,
        orElse: () => {"price": 0},
      );
      return sum + ((item["price"] as num).toInt() * e.value);
    });
  }

  void addToCart(String name) {
    setState(() => cart[name] = (cart[name] ?? 0) + 1);
  }

  void removeFromCart(String name) {
    if (!cart.containsKey(name)) return;
    setState(() {
      cart[name] == 1 ? cart.remove(name) : cart[name] = cart[name]! - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      backgroundColor: const Color(0xFFE0F2F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00695C),
        elevation: 0,
        title: Text(
          "Take Away Orders",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            width: Responsive.getMaxWidth(context),
            padding: const EdgeInsets.all(18),
            child: isMobile ? _mobileLayout() : _desktopLayout(),
          ),
        ),
      ),
    );
  }

  // ------------------ MOBILE UI ------------------
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

  // ------------------ DESKTOP UI ------------------
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

  // ------------------ FILTERS ------------------
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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: categories.map((cat) {
              final active = selectedCategory == cat;
              return GestureDetector(
                onTap: () => setState(() => selectedCategory = cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF00897B) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF00897B).withOpacity(.5)),
                  ),
                  child: Text(
                    cat,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      color: active ? Colors.white : const Color(0xFF00695C),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ------------------ MENU GRID ------------------
  Widget _menuGrid() {
    final filtered = menuItems.where((item) {
      bool matchCat =
    selectedCategory == "All" ||
    item["category"].toString().toLowerCase() ==
        selectedCategory.toLowerCase();

      bool matchSearch = searchController.text.isEmpty ||
          item["product_name"]
              .toLowerCase()
              .contains(searchController.text.toLowerCase());

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
      children: filtered.map(_menuCard).toList(),
    );
  }

  Widget _menuCard(Map<String, dynamic> item) {
    return GestureDetector(
      onTap: item["stock"] > 0
    ? () => addToCart(item["product_name"])
    : null,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF00897B).withOpacity(.3)),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFB2DFDB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                    child: Icon(Icons.fastfood,
                        size: 32, color: Color(0xFF00695C))),
              ),
            ),
            const SizedBox(height: 8),
            Text(item["product_name"],
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            Text("Rs ${item["price"]}",
                style: GoogleFonts.poppins(
                    color: const Color(0xFF00695C), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // ------------------ CART (DESKTOP ONLY) ------------------
  Widget _cartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Order List",
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Expanded(
          child: cart.isEmpty
              ? Center(
                  child: Text("Empty cart",
                      style: GoogleFonts.poppins(color: Colors.grey)))
              : ListView(
                  children: cart.entries.map((e) {
                    final item = menuItems.firstWhere(
                      (i) => i["product_name"] == e.key,
                      orElse: () => {"price": 0},
                    );
                    return Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2F1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF00897B).withOpacity(.3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(e.key,
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w500)),
                          ),
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
              backgroundColor: const Color(0xFF00897B),
              elevation: 0,
            ),
            onPressed: cart.isEmpty ? null : _createOrder,
            child: Text("Place Order",
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  // ------------------ MOBILE BOTTOM BAR ------------------
  Widget _bottomCartBar() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TakeAwayCartPage(
              cart: cart,
              menuItems: menuItems,
            ),
          ),
        );
      },
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: const Color(0xFF00695C),
        child: Row(
          children: [
            Text("View Cart • Rs $total",
                style: GoogleFonts.poppins(color: Colors.white)),
            const Spacer(),
            const Icon(Icons.shopping_cart, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Future<void> _createOrder() async {
  print("PLACE ORDER BUTTON CLICKED");
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => TakeAwayCartPage(
        cart: cart,
        menuItems: menuItems,
      ),
    ),
  );
}
}
