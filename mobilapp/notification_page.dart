import 'package:flutter/material.dart';

import '../services/qctrade_api.dart';   // <-- make sure path is correct

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  // ---------------------- Notification Toggles ----------------------
  bool newOrders = false;
  bool lowStock = false;
  bool dailyReport = false;
  bool promotions = false;
  bool systemUpdates = false;

  // ---------------------- Delivery Methods --------------------------
  bool email = false;
  bool pushNotification = false;

  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  // ========================= LOAD SETTINGS ===========================
  Future<void> loadSettings() async {
    final data = await SettingsApi.getGeneralSettings();

    if (data.isNotEmpty && data["notifications"] != null) {
      final n = data["notifications"];
      newOrders = n["newOrders"] ?? false;
      lowStock = n["lowStock"] ?? false;
      dailyReport = n["dailyReport"] ?? false;
      promotions = n["promotions"] ?? false;
      systemUpdates = n["systemUpdates"] ?? false;
    }

    if (data.isNotEmpty && data["delivery"] != null) {
      final d = data["delivery"];
      email = d["email"] ?? false;
      pushNotification = d["push"] ?? false;
    }

    setState(() => loading = false);
  }

  // ========================= SAVE SETTINGS ===========================
  Future<void> saveSettings() async {
    setState(() => saving = true);

    final body = {
      "notifications": {
        "newOrders": newOrders,
        "lowStock": lowStock,
        "dailyReport": dailyReport,
        "promotions": promotions,
        "systemUpdates": systemUpdates
      },
      "delivery": {
        "email": email,
        "push": pushNotification,
      }
    };

    final ok = await SettingsApi.saveGeneralSettings(body);

    setState(() => saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? "Changes Saved!" : "Save Failed!"),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ===================== Notification Preferences =====================
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  const Text(
                    "Notification Preferences",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 10),

                  _toggleTile("New Orders", "Notify when a new order arrives",
                      newOrders, (v) => setState(() => newOrders = v)),

                  _toggleTile("Low Stock", "Notify when stock is low", lowStock,
                      (v) => setState(() => lowStock = v)),

                  _toggleTile("Daily Report", "Daily sales reports", dailyReport,
                      (v) => setState(() => dailyReport = v)),

                  _toggleTile("Promotions", "Marketing & promo alerts",
                      promotions, (v) => setState(() => promotions = v)),

                  _toggleTile("System Updates", "System update alerts",
                      systemUpdates, (v) => setState(() => systemUpdates = v)),
                ],
              ),
            ),

            const SizedBox(height: 25),

            // ======================== Delivery Methods ==========================
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  const Text(
                    "Delivery Methods",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 10),

                  CheckboxListTile(
                    title: const Text("Email Notifications"),
                    value: email,
                    onChanged: (v) => setState(() => email = v!),
                  ),

                  CheckboxListTile(
                    title: const Text("Mobile Push Notifications"),
                    value: pushNotification,
                    onChanged: (v) => setState(() => pushNotification = v!),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            // ============================ Save Button ============================
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: saving ? null : saveSettings,
                child: Text(saving ? "Saving..." : "Save Changes"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleTile(
      String title, String subtitle, bool value, Function(bool) onChanged) {
    return Column(
      children: [
        SwitchListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: onChanged,
        ),
        const Divider(),
      ],
    );
  }
}
