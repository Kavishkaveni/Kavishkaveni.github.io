import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qcitrack/app_selector/app_selector_page.dart';

import 'package:qcitrack/qc_trade/CustomerPages/customers_main_page.dart';
import 'package:qcitrack/qc_trade/OrderStatusPages/order_status_main_page.dart';
import 'package:qcitrack/qc_trade/OrdersPages/orders_page.dart';
import 'package:qcitrack/qc_trade/PaymentProcessing/payment_processing_main_page.dart';
import 'package:qcitrack/qc_trade/RefundPages/return_refunds_main_page.dart';
import 'package:qcitrack/qc_trade/ReportsPages/summary_page.dart';
import 'package:qcitrack/qc_trade/ReservationsPages/reservation_main_page.dart';
import 'package:qcitrack/qc_trade/SettingsPages/settings_main_page.dart';

class DashboardPage extends StatelessWidget {
  final String username;

  const DashboardPage({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          "QC Trade",
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => AppSelectorPage(username: username),
                ),
                (route) => false,
              );
            },
            child: const Text(
              "Switch Application",
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Welcome, $username",
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: GridView(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isTablet ? 4 : 3,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                ),
                children: [
                  _appIcon(context, "Orders", Icons.shopping_cart,
                      Colors.green, OrdersPage()),

                  _appIcon(context, "Order Status", Icons.track_changes,
                      Colors.blue, OrderStatusMainPage()),

                  _appIcon(context, "Reservations", Icons.event_seat,
                      Colors.deepPurple, ReservationsMainPage()),

                  _appIcon(context, "Customers", Icons.people_alt,
                      Colors.indigo, CustomersMainPage()),

                  _appIcon(context, "Returns", Icons.refresh,
                      Colors.orange, ReturnRefundsMainPage()),

                  _appIcon(context, "Payment", Icons.credit_card,
                      Colors.purple, PaymentProcessingPage()),

                  _appIcon(context, "Settings", Icons.settings,
                      Colors.grey, SettingsMainPage()),

                  _appIcon(context, "Reports", Icons.bar_chart,
                      Colors.red, SummaryPage()),

                  _appIcon(context, "Inventory", Icons.inventory_2,
                      Colors.deepOrange, const SizedBox()),

                  // -------- CENTERED LAST MODULE --------
                  Center(
                    child: _appIcon(
                      context,
                      "Branches",
                      Icons.apartment,
                      Colors.teal,
                      const SizedBox(), // replace later with Trade Branch page
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- APP ICON ----------------
  Widget _appIcon(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    Widget page,
  ) {
    return InkWell(
      onTap: () {
        if (page is SizedBox) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
      },
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
