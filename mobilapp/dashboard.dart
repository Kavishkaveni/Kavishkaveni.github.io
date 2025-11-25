import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../CustomerPages/customers_main_page.dart';
import '../OrderStatusPages/order_status_main_page.dart';
import '../OrdersPages/orders_page.dart';
import '../PaymentProcessing/payment_processing_main_page.dart';
import '../RefundPages/return_refunds_main_page.dart';
import '../ReportsPages/summary_page.dart';
import '../ReservationsPages/reservation_main_page.dart';
import '../SettingsPages/settings_main_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff1f3f5),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          "QCTrade Dashboard",
          style: GoogleFonts.poppins(
            color: Colors.deepPurple,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      body: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.count(
          crossAxisCount: 3,                 // 🔥 3 CARDS PER ROW
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.85,            // 🔥 Makes cards smaller
          children: [
            dashboardCard(
              context,
              title: "Orders",
              icon: Icons.shopping_cart,
              colors: [const Color(0xff00e676), const Color(0xff00c853)],
              page: const OrdersPage(),
            ),
            dashboardCard(
              context,
              title: "Order Status",
              icon: Icons.track_changes,
              colors: [const Color(0xff42a5f5), const Color(0xff1e88e5)],
              page: const OrderStatusMainPage(),
            ),
            dashboardCard(
              context,
              title: "Reservations",
              icon: Icons.event_seat,
              colors: [const Color(0xffd500f9), const Color(0xffaa00ff)],
              page: const ReservationsMainPage(),
            ),
            dashboardCard(
              context,
              title: "Customers",
              icon: Icons.people_alt,
              colors: [const Color(0xff2979ff), const Color(0xff2962ff)],
              page: const CustomersMainPage(),
            ),
            dashboardCard(
              context,
              title: "Returns",
              icon: Icons.refresh,
              colors: [const Color(0xffffc107), const Color(0xffffa000)],
              page: const ReturnRefundsMainPage(),
            ),
            dashboardCard(
              context,
              title: "Payment",
              icon: Icons.credit_card,
              colors: [const Color(0xff7b1fa2), const Color(0xff9c27b0)],
              page: const PaymentProcessingPage(),
            ),
            dashboardCard(
              context,
              title: "Settings",
              icon: Icons.settings,
              colors: [const Color(0xff424242), const Color(0xff212121)],
              page: const SettingsMainPage(),
            ),
            dashboardCard(
              context,
              title: "Reports",
              icon: Icons.bar_chart_rounded,
              colors: [Colors.red, Colors.red.shade700],
              page: const SummaryPage(),
            ),
            dashboardCard(
  context,
  title: "Inventory",
  icon: Icons.inventory_2_rounded,
  colors: [const Color(0xffff7043), const Color(0xfff4511e)], 
  page: const SizedBox(), 
),
          ],
        ),
      ),
    );
  }

  Widget dashboardCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Color> colors,
    required Widget page,
  }) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => page),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.white),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            )
          ],
        ),
      ),
    );
  }
}
