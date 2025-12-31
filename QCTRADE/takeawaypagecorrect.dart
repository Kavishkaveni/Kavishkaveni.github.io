import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../OrdersPages/takeaway_payment_page.dart';
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

  bool isLoading = true;

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
            "image": item["image_url"] ?? item["image"] ?? "",
          });
        }

        setState(() {
  menuItems = updated;
  isLoading = false;
});
      }
    } catch (e) {
  setState(() => isLoading = false);
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
  int get cartCount {
  return cart.values.fold<int>(0, (a, b) => a + b);
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

  Future<void> _proceedToPayment() async {
  if (cart.isEmpty) return;

  // Build items
  final items = cart.entries.map((e) {
    final product = menuItems.firstWhere(
      (i) => i["product_name"] == e.key,
      orElse: () => {"product_id": "", "price": 0},
    );

    return {
      "product_id": product["product_id"],
      "quantity": e.value,
      "unit_price": product["price"],
      "product_name": e.key,
      "discount_amount": 0,
      "tax_amount": 0,
      "special_instructions": "",
    };
  }).toList();

  final payload = {
    "order_type": "takeaway",
    "flow_type": "payment_first",
    "total_amount": total,
    "items": items,
  };

  final createRes = await QcTradeApi.createOrder(payload);
  if (createRes == null || createRes["id"] == null) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Failed to create order")),
    );
    return;
  }

  final orderId = createRes["id"];

  if (!mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => TakeAwayPaymentPage(orderId: orderId),
    ),
  );
}

void _openCartDialog() {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Cart Items",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Expanded(
                      child: cart.isEmpty
                          ? Center(
                              child: Text(
                                "No items",
                                style: GoogleFonts.poppins(color: Colors.grey),
                              ),
                            )
                          : ListView(
                              children: cart.entries.map((e) {
                                final item = menuItems.firstWhere(
                                  (i) => i["product_name"] == e.key,
                                  orElse: () => {"price": 0},
                                );
                                final price = (item["price"] ?? 0) as int;

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          e.key,
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle,
                                            color: Colors.red),
                                        onPressed: () {
                                          setModalState(() => removeFromCart(e.key));
                                          setState(() {});
                                        },
                                      ),
                                      Text(
                                        "${e.value}",
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle,
                                            color: Colors.green),
                                        onPressed: () {
                                          setModalState(() => addToCart(e.key));
                                          setState(() {});
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        "Rs ${price * e.value}",
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                    ),

                    const SizedBox(height: 10),
                    Text(
                      "Total: Rs $total",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade400,
                              elevation: 0,
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              "Close",
                              style: GoogleFonts.poppins(
                                color: Colors.black,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00695C),
                              elevation: 0,
                            ),
                            onPressed: cart.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    _proceedToPayment();
                                  },
                            child: Text(
                              "Proceed",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
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
  actions: [
    Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.shopping_cart, color: Colors.white),
            onPressed: _openCartDialog,
          ),
          if (cartCount > 0)
            Positioned(
              right: 6,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "$cartCount",
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  ],
),
      body: isLoading
    ? const Center(child: CircularProgressIndicator())
    : SafeArea(
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
  final String name = item["product_name"]?.toString() ?? "";
  final int qty = cart[name] ?? 0;
  final int stock = item["stock"] ?? 0;

  return GestureDetector(
    onTap: stock > 0 ? () => addToCart(name) : null,
    child: Stack(
      children: [
        // ================= MAIN CARD =================
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF00897B).withOpacity(.3),
            ),
          ),
          child: Column(
            children: [
              // ---------- IMAGE ----------
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: (item["image"] != null &&
                          item["image"].toString().isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: item["image"],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (_, __) => Container(
                            color: const Color(0xFFB2DFDB),
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: const Color(0xFFB2DFDB),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.fastfood,
                              size: 32,
                              color: Color(0xFF00695C),
                            ),
                          ),
                        )
                      : Container(
                          color: const Color(0xFFB2DFDB),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.fastfood,
                            size: 32,
                            color: Color(0xFF00695C),
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 8),

              // ---------- PRODUCT NAME ----------
              Text(
                name,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // ---------- PRICE ----------
              Text(
                "\$${item["price"]}",
                style: GoogleFonts.poppins(
                  color: const Color(0xFF00695C),
                  fontSize: 12,
                ),
              ),

              // ---------- STOCK INFO ----------
              const SizedBox(height: 4),
              Text(
                stock > 0 ? "$stock in stock" : "Out of stock",
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: stock > 0 ? Colors.grey : Colors.red,
                ),
              ),
            ],
          ),
        ),

        // ================= +1 / +2 BADGE =================
        if (qty > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00695C),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "+$qty",
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
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
            onPressed: cart.isEmpty ? null : _openCartDialog,
            child: Text("Place Order",
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
