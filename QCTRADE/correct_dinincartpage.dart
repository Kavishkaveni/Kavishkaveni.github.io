import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../OrdersPages/order_tracking_page.dart';
import '../services/qctrade_api.dart';

class DineInOrderCartPage extends StatefulWidget {
  final int tableId;
  final String tableNumber;
  final Map<String, int> cartItems;

  const DineInOrderCartPage({
    required this.tableId,
    required this.tableNumber,
    required this.cartItems,
    super.key,
  });

  @override
  State<DineInOrderCartPage> createState() => _DineInOrderCartPageState();
}

class _DineInOrderCartPageState extends State<DineInOrderCartPage> {
  String selectedCategory = "All";
  List<String> categories = ["All"];
  TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> menuItems = [];
  bool isLoading = true;

  final Map<String, int> cart = {};

  int? activeOrderId;

  bool hasExistingOrder = false;

final Map<String, int> existingItems = {};

double existingOrderTotal = 0;
int currentPage = 0;
static const int itemsPerPage = 4;

void _openCartDialog() {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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
                                  (i) => i["name"] == e.key,
                                );
                                final price = item["price"];

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  margin:
                                      const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius:
                                        BorderRadius.circular(10),
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
                                          setModalState(
                                              () => decreaseItem(e.key));
                                          setState(() {});
                                        },
                                      ),
                                      Text(
                                        "${e.value}",
                                        style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle,
                                            color: Colors.green),
                                        onPressed: () {
                                          setModalState(
                                              () => addToCart(e.key));
                                          setState(() {});
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        "Rs ${price * e.value}",
                                        style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                    ),

                    const SizedBox(height: 10),
                    Text(
                      hasExistingOrder
                          ? "New: Rs $newItemsTotal   |   Grand: Rs $grandTotal"
                          : "Total: Rs $grandTotal",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade400,
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Close"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF1E88E5),
                            ),
                            onPressed:
                                cart.isEmpty ? null : submitOrder,
                            child: Text(
  "Send to Kitchen",
  textAlign: TextAlign.center,
  style: GoogleFonts.poppins(
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
  void initState() {
    super.initState();
    cart.addAll(widget.cartItems);
    loadProducts();
    checkActiveOrder(); 
    loadCategories();
  }

  @override
void dispose() {
  searchController.dispose();
  super.dispose();
}

List<List<Map<String, dynamic>>> paginateMenu(List<Map<String, dynamic>> items) {
  List<List<Map<String, dynamic>>> pages = [];

  for (int i = 0; i < items.length; i += itemsPerPage) {
    pages.add(
      items.sublist(
        i,
        i + itemsPerPage > items.length
            ? items.length
            : i + itemsPerPage,
      ),
    );
  }

  return pages;
}

  // ================= CHECK ACTIVE ORDER =================
  Future<void> checkActiveOrder() async {
  try {
    final res =
        await QcTradeApi.checkExistingOrderByTable(widget.tableId);

    if (res == null) return;

    if (res["has_existing_order"] == true) {
      activeOrderId = res["order_id"];
      setState(() {
  hasExistingOrder = true;
});
await loadExistingOrderItems(activeOrderId!);
    }
  } catch (e) {
    // silent
  }
}

  // ================= LOAD EXISTING ORDER ITEMS =================
Future<void> loadExistingOrderItems(int orderId) async {
  try {
    final res = await QcTradeApi.getOrderWithSubOrders(orderId);
    if (res == null) return;

    existingItems.clear();
    existingOrderTotal =
    (res["combined_total"] ?? res["total_amount"] ?? 0).toDouble();

    // MAIN ORDER ITEMS
    if (res["items"] != null) {
      for (final item in res["items"]) {
        final String name = item["product_name"];
        final int qty = item["quantity"];
        existingItems[name] = qty;
      }
    }

    // SUB ORDER ITEMS
    if (res["sub_orders"] != null) {
      for (final sub in res["sub_orders"]) {
        if (sub["items"] == null) continue;

        for (final item in sub["items"]) {
          final String name = item["product_name"];
          final int qty = item["quantity"];

          existingItems[name] =
              (existingItems[name] ?? 0) + qty;
        }
      }
    }

    setState(() {});
  } catch (e) {
    // silent
  }
}
Future<void> loadCategories() async {
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

        // safety
        if (!categories.contains(selectedCategory)) {
          selectedCategory = "All";
        }
      });
    }
  } catch (e) {
    debugPrint("CATEGORY LOAD ERROR: $e");
  }
}

  // ================= LOAD PRODUCTS =================
  Future<void> loadProducts() async {
    try {
      final result = await QcTradeApi.getProducts();
      final List<dynamic> data = result;

      menuItems = data.map<Map<String, dynamic>>((item) {
        return {
          "product_id": item["id"] ?? item["product_id"],
          "name": item["name"] ?? item["product_name"] ?? "",
          "price": (item["selling_price"] ?? 0).toInt(),
          "stock": item["stock"] ?? 0,
          "category": item["category"] ?? "other",
          "image": item["image_url"] ?? "",
        };
      }).toList();

      setState(() => isLoading = false);
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

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
  int get newItemsTotal {
  int t = 0;
  cart.forEach((name, qty) {
    final item = menuItems.firstWhere(
      (i) => i["name"] == name,
      orElse: () => {"price": 0},
    );
    t += (item["price"] as int) * qty;
  });
  return t;
}

int get grandTotal {
  return hasExistingOrder
      ? (existingOrderTotal + newItemsTotal).toInt()
      : newItemsTotal;
}


  List<Map<String, dynamic>> buildItemsPayload() {
    List<Map<String, dynamic>> items = [];

    cart.forEach((name, qty) {
      final product = menuItems.firstWhere((i) => i["name"] == name);

      items.add({
        "product_id": product["product_id"],
        "quantity": qty,
        "unit_price": product["price"],
        "product_name": product["name"],
        "special_instructions": "",
        "discount_amount": 0,
        "tax_amount": 0,
      });
    });

    return items;
  }

  // ================= SUBMIT ORDER (FIXED LOGIC) =================
  Future<void> submitOrder() async {
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please add items to cart")),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF1E88E5)),
      ),
    );

    try {
      int orderId;

      if (activeOrderId != null) {
  //  ADD SUB-ORDER
  final res = await QcTradeApi.addSubOrder(
    activeOrderId!,
    buildItemsPayload(),
    newItemsTotal.toDouble(),
  );

  if (res == null || res["sub_order_id"] == null) {
    throw Exception("Sub-order failed");
  }

  final int subOrderId = res["sub_order_id"];

  //  SEND SUB-ORDER TO KITCHEN
  final kitchenRes = await QcTradeApi.sendSubOrderToKitchen(
  activeOrderId!,
  subOrderId,
);

if (kitchenRes == null) {
  throw Exception("Kitchen dispatch failed");
}

  cart.clear();
await loadExistingOrderItems(activeOrderId!);
setState(() {});

  orderId = activeOrderId!;
}
      else {
        //  CREATE NEW ORDER
        final payload = {
          "order_type": "dinein",
          "table_id": widget.tableId,
          "total_amount": newItemsTotal,
          "items": buildItemsPayload(),
        };

        final res = await QcTradeApi.createOrder(payload);

        if (res == null || res["id"] == null) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to create order")),
          );
          return;
        }

        orderId = res["id"];
      }

      Navigator.pop(context);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => OrderTrackingPage(orderId: orderId),
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Something went wrong")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 850;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FF),
      appBar: AppBar(
  backgroundColor: const Color(0xFF1E88E5),
  elevation: 0,
  title: Text(
    "Table ${widget.tableNumber} - Orders",
    style: GoogleFonts.poppins(
      color: Colors.white,
      fontWeight: FontWeight.w600,
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
            onPressed: cart.isEmpty ? null : _openCartDialog,
          ),
          if (cart.isNotEmpty)
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
                  "${cart.values.fold<int>(0, (a, b) => a + b)}",
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
          : (isMobile ? _mobileLayout() : _desktopLayout()),
    );
  }

  Widget _desktopLayout() {
    return Row(
      children: [
        Expanded(flex: 4, child: _leftOrderSection()),
        Expanded(flex: 7, child: _rightMenuSection()),
      ],
    );
  }

  Widget _mobileLayout() {
    return Column(
      children: [
        Expanded(child: _rightMenuSection()),
      ],
    );
  }

  Widget _leftOrderSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Colors.blue.shade100, width: 1),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Order Items",
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Expanded(child: _cartList()),
          Divider(),
          if (hasExistingOrder) ...[
  _row("Existing Order", existingOrderTotal.toInt()),
  _row("New Items", newItemsTotal),
  const Divider(),
  _row("Grand Total", grandTotal, bold: true),
] else ...[
  _row("Total", newItemsTotal, bold: true),
],
        ],
      ),
    );
  }

  Widget _cartList() {
  if (existingItems.isEmpty && cart.isEmpty) {
    return Center(
      child: Text(
        "No items",
        style: GoogleFonts.poppins(color: Colors.grey),
      ),
    );
  }

  return ListView(
    children: [
      // ================= EXISTING ITEMS (READ ONLY) =================
      if (existingItems.isNotEmpty) ...[
        Text(
          "Existing Orders",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),

        ...existingItems.entries.map((e) {
          final item =
              menuItems.firstWhere((i) => i["name"] == e.key);

          return Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
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
                Text(
                  "x${e.value}",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  "Rs ${item["price"] * e.value}",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),

        const Divider(height: 30),
      ],

      // ================= NEW ITEMS (EDITABLE) =================
      if (cart.isNotEmpty) ...[
        Text(
          "New Items",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.blue.shade700,
          ),
        ),
        const SizedBox(height: 8),

        ...cart.entries.map((e) {
          final item =
              menuItems.firstWhere((i) => i["name"] == e.key);

          return Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
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
                  onPressed: () => decreaseItem(e.key),
                  icon: const Icon(Icons.remove_circle,
                      color: Colors.red),
                ),
                Text(
                  "${e.value}",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  onPressed: () => addToCart(e.key),
                  icon: const Icon(Icons.add_circle,
                      color: Colors.green),
                ),
                const SizedBox(width: 8),
                Text(
                  "Rs ${item["price"] * e.value}",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    ],
  );
}

  Widget _rightMenuSection() {
    final filteredMenu = menuItems.where((item) {
      bool catMatch =
          selectedCategory == "All" || item["category"] == selectedCategory;
      bool searchMatch = searchController.text.isEmpty ||
          item["name"]
              .toLowerCase()
              .contains(searchController.text.toLowerCase());
      return catMatch && searchMatch;
    }).toList();
final pages = paginateMenu(filteredMenu);
    return Container(
      padding: const EdgeInsets.all(18),
      color: const Color(0xFFE9F3FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _categories(),
          const SizedBox(height: 10),
          _searchBox(),
          const SizedBox(height: 14),
Expanded(
  child: PageView.builder(
    itemCount: pages.length,
    onPageChanged: (index) {
      setState(() => currentPage = index);
    },
    itemBuilder: (context, pageIndex) {
      final pageItems = pages[pageIndex];

      return GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount:
            MediaQuery.of(context).size.width < 850 ? 2 : 4,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.75,
        children: pageItems.map((item) => _menuCard(item)).toList(),
      );
    },
  ),
),
if (pages.length > 1)
  Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(
      pages.length,
      (index) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        width: currentPage == index ? 10 : 6,
        height: currentPage == index ? 10 : 6,
        decoration: BoxDecoration(
          color: currentPage == index
              ? Colors.blue
              : Colors.grey.shade400,
          shape: BoxShape.circle,
        ),
      ),
    ),
  ),
          const SizedBox(height: 12),
          _actionButtons(),
        ],
      ),
    );
  }

  Widget _categories() {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: categories.map((c) {
        final bool active = selectedCategory == c;

        return GestureDetector(
          onTap: () => setState(() => selectedCategory = c),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF1E88E5)
                  : const Color(0xFFE3F2FD),
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
    ),
  );
}

  Widget _searchBox() {
    return TextField(
      controller: searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: "Search menu...",
        prefixIcon: const Icon(Icons.search, size: 18),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                BorderSide(color: Colors.blue.shade200)),
      ),
    );
  }

  Widget _menuCard(Map<String, dynamic> item) {
    return GestureDetector(
      onTap: item["stock"] > 0
    ? () => addToCart(item["name"])
    : null,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade100),
          boxShadow: [
            BoxShadow(
                color: Colors.blue.withOpacity(.05),
                blurRadius: 6,
                offset: const Offset(2, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
  child: Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: item["image"] != null && item["image"].toString().isNotEmpty
            ? CachedNetworkImage(
                imageUrl: item["image"],
                fit: BoxFit.cover,
                width: double.infinity,
              )
            : Container(
                color: Colors.blue.shade50,
                alignment: Alignment.center,
                child: const Icon(Icons.fastfood,
                    color: Colors.blue, size: 30),
              ),
      ),

      // QUANTITY BADGE (TOP RIGHT)
      if (cart[item["name"]] != null)
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              "+${cart[item["name"]]}",
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
            const SizedBox(height: 8),
            Text(item["name"],
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            Text("Rs ${item["price"]}",
                style: GoogleFonts.poppins(
                    color: Colors.blue.shade700, fontSize: 12)),
            Text("${item["stock"]} in stock",
                style:
                    GoogleFonts.poppins(color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _actionButtons() {
    final isMobile = MediaQuery.of(context).size.width < 480;

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                  child: _smallBtn(
                      "Back", Colors.grey.shade400, Colors.black,
                      () => Navigator.pop(context))),
              const SizedBox(width: 8),
              Expanded(
                  child: _smallBtn(
                      "Cancel", Colors.red.shade600, Colors.white,
                      () => Navigator.pop(context))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _smallBtn("Settlement",
                    const Color(0xFF1E88E5), Colors.white, () {}),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E88E5),
                      elevation: 0,
                    ),
                    onPressed: cart.isEmpty ? null : submitOrder,
                    child: Text(
                      "Send to Kitchen",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _smallBtn("Back", Colors.grey.shade400, Colors.black,
            () => Navigator.pop(context)),
        const SizedBox(width: 8),
        _smallBtn("Cancel", Colors.red.shade600, Colors.white,
            () => Navigator.pop(context)),
        const SizedBox(width: 8),
        _smallBtn(
            "Settlement", const Color(0xFF1E88E5), Colors.white, () {}),
        const SizedBox(width: 8),
        SizedBox(
          height: 38,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E88E5),
              elevation: 0,
            ),
            onPressed: cart.isEmpty ? null : submitOrder,
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

  Widget _smallBtn(String text, Color bg, Color fg, VoidCallback onTap) {
    return SizedBox(
      height: 38,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: bg, elevation: 0),
        onPressed: onTap,
        child: Text(text,
            style:
                GoogleFonts.poppins(color: fg, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _bottomCartButton() {
    if (cart.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E88E5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.2), blurRadius: 10)
        ],
      ),
      child: GestureDetector(
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) {
              return StatefulBuilder(
                builder: (context, setModalState) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Cart Items",
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            )),
                        const SizedBox(height: 12),
                        ...cart.entries.map((e) {
                          final item = menuItems
                              .firstWhere((i) => i["name"] == e.key);
                          final price = item["price"];

                          return Container(
                            padding: const EdgeInsets.all(12),
                            margin:
                                const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius:
                                  BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Text(e.key,
                                        style:
                                            GoogleFonts.poppins(
                                                fontWeight:
                                                    FontWeight.w500))),
                                IconButton(
  icon: const Icon(Icons.remove_circle, color: Colors.red),
  onPressed: () {
    setModalState(() {
      decreaseItem(e.key);
    });
    setState(() {});
  },
),
Text("${e.value}",
    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
IconButton(
  icon: const Icon(Icons.add_circle, color: Colors.green),
  onPressed: () {
  setModalState(() => addToCart(e.key));
  setState(() {});
},
),
                                Text("Rs ${price * e.value}",
                                    style:
                                        GoogleFonts.poppins(
                                            fontWeight:
                                                FontWeight.w600)),
                              ],
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 10),
                        Text("New: Rs $newItemsTotal   |   Grand: Rs $grandTotal",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            )),
                        const SizedBox(height: 15),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF1E88E5)),
                          onPressed: () =>
                              Navigator.pop(context),
                          child: Text("Close",
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight:
                                      FontWeight.w600)),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
        child: Row(
          children: [
            Text("View Cart • Rs $grandTotal",
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.shopping_cart, color: Colors.white),
          ],
        ),
      ),
    );
  }
  Widget _row(String label, int value, {bool bold = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        Text(
          "Rs $value",
          style: GoogleFonts.poppins(
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    ),
  );
}
}
