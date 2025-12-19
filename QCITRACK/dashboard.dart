import 'package:flutter/material.dart';

import '../branch_management/branch_list_page.dart';
import '../eod_reconciliation/eod_list_page.dart';
import '../inventory_audit/inventory_audit_list_page.dart';
import '../operation_logs/operation_logs_list_page.dart';
import '../product_management/product_list_page.dart';
import '../purchase_order/purchase_order_list_page.dart';
import '../purchase_order_items/purchase_order_item_list_page.dart';
import '../report_analytics/report_list_page.dart';
import '../return_management/return_list_page.dart';
import '../stock_management/stock_list_page.dart';
import '../stock_movements/stock_move_list_page.dart';
import '../supplier/supplier_list_page.dart';

class DashboardPage extends StatelessWidget {
  final String username;

  const DashboardPage({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isTablet = width >= 600;

    final double cardHeight = isTablet ? 180 : 120;
    final double cardWidth = isTablet ? 280 : double.infinity;

    // MODULE COLORS
    const Color branchColor = Colors.blueAccent;
    const Color supplierColor = Colors.deepPurpleAccent;
    const Color purchaseOrderColor = Color(0xFF0D47A1);
    const Color purchaseOrderItemColor = Color(0xFF9E9E9E);
    const Color productColor = Color(0xFFB63A48);
    const Color stockManagementColor = Color(0xFF0F766E); // teal
    const Color operationLogsColor = Color(0xFF0FA4AF);
    const Color eodColor = Color(0xFF8B3A2E); // EOD brown 
    const Color stockMovementColor = Color(0xFF1F7EA8); // Stock Movements (blue-teal)
    const Color returnManagementColor = Color(0xFFE67E22);
    const Color reportAnalyticsColor = Color(0xFFC0392B); // Reports & Analytics (red)
    const Color inventoryAuditColor = Color(0xFF7CB342); // Inventory Audit (green)

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          "QCI Track",
          style: TextStyle(
            color: Colors.black,
            fontSize: isTablet ? 28 : 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Text(
                "Welcome, $username !!",
                style: TextStyle(
                  fontSize: isTablet ? 28 : 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),

              const SizedBox(height: 24),

              _dashboardCard(
                context,
                height: cardHeight,
                width: cardWidth,
                color: branchColor,
                icon: Icons.apartment_rounded,
                title: "Branch Management",
                isTablet: isTablet,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BranchListPage()),
                ),
              ),

              const SizedBox(height: 20),

              _dashboardCard(
                context,
                height: cardHeight,
                width: cardWidth,
                color: supplierColor,
                icon: Icons.local_shipping_rounded,
                title: "Supplier Management",
                isTablet: isTablet,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SupplierListPage()),
                ),
              ),

              const SizedBox(height: 20),

              _dashboardCard(
                context,
                height: cardHeight,
                width: cardWidth,
                color: productColor,
                icon: Icons.inventory_rounded,
                title: "Product Management",
                isTablet: isTablet,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProductListPage()),
                ),
              ),

              const SizedBox(height: 20),

              _dashboardCard(
                context,
                height: cardHeight,
                width: cardWidth,
                color: purchaseOrderColor,
                icon: Icons.shopping_cart_rounded,
                title: "Purchase Order Management",
                isTablet: isTablet,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PurchaseOrderListPage(),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              _dashboardCard(
                context,
                height: cardHeight,
                width: cardWidth,
                color: purchaseOrderItemColor,
                icon: Icons.inventory_2_rounded,
                title: "Purchase Order Items",
                isTablet: isTablet,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PurchaseOrderItemListPage(),
                  ),
                ),
              ),
              const SizedBox(height: 20),

_dashboardCard(
  context,
  height: cardHeight,
  width: cardWidth,
  color: stockManagementColor,
  icon: Icons.inventory_rounded,
  title: "Stock Management",
  isTablet: isTablet,
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const StockListPage(),
    ),
  ),
),
const SizedBox(height: 20),

_dashboardCard(
  context,
  height: cardHeight,
  width: cardWidth,
  color: eodColor,
  icon: Icons.inventory_outlined,
  title: "EOD Reconciliation",
  isTablet: isTablet,
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const EODListPage(),
    ),
  ),
),

const SizedBox(height: 20),

_dashboardCard(
  context,
  height: cardHeight,
  width: cardWidth,
  color: stockMovementColor,
  icon: Icons.local_shipping_rounded, // truck icon like web
  title: "Stock Movements",
  isTablet: isTablet,
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const StockMoveListPage(),
    ),
  ),
),

const SizedBox(height: 20),

_dashboardCard(
  context,
  height: cardHeight,
  width: cardWidth,
  color: returnManagementColor,
  icon: Icons.assignment_return_rounded,
  title: "Return Management",
  isTablet: isTablet,
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const ReturnListPage(),
    ),
  ),
),

              const SizedBox(height: 20),

              // OPERATION LOGS CARD
              _dashboardCard(
                context,
                height: cardHeight,
                width: cardWidth,
                color: operationLogsColor,
                icon: Icons.event_note_rounded,
                title: "Operation Logs",
                isTablet: isTablet,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OperationLogListPage(),
                  ),
                ),
              ),

              const SizedBox(height: 20),

_dashboardCard(
  context,
  height: cardHeight,
  width: cardWidth,
  color: inventoryAuditColor,
  icon: Icons.fact_check_rounded, // audit/check icon
  title: "Inventory Audit",
  isTablet: isTablet,
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const InventoryAuditListPage(),
    ),
  ),
),

              const SizedBox(height: 20),

_dashboardCard(
  context,
  height: cardHeight,
  width: cardWidth,
  color: reportAnalyticsColor,
  icon: Icons.bar_chart_rounded, // matches web analytics icon
  title: "Reports & Analytics",
  isTablet: isTablet,
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const ReportListPage(),
    ),
  ),
),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboardCard(
    BuildContext context, {
    required double height,
    required double width,
    required Color color,
    required IconData icon,
    required String title,
    required bool isTablet,
    required VoidCallback onTap,
  }) {
    return Center(
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          width: width,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: isTablet ? 60 : 40,
                color: Colors.white,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isTablet ? 24 : 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
