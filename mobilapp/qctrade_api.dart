import 'dart:convert';

import 'package:http/http.dart' as http;

class QcTradeApi {
  // ===================== MAIN BACKEND URL =====================
  static const String baseUrl = "http://135.171.225.197:8002/api/v1";

  // ===================== AUTH DETAILS =========================
  static String accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhZG1pbjFAZ21haWwuY29tIiwidGVuYW50X2lkIjoiN2IxNzdkOWMtZGJlZC00ZTUwLWE0ZGMtN2EyY2RkOWQ2ZTNmIiwiZXhwIjoxNzYzODkxODk5fQ.CTZA6cf4yeceQBI7Jq5cwofqwXyn-HVdQPm6TO2EFnM"; 
  static String userId = "1"; 
  static String tenantId = "7b177d9c-dbed-4e50-a4dc-7a2cdd9d6e3f";
  static String branchId = "BR101";

  // ===================== COMMON HEADERS =======================
  static Map<String, String> headers() {
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
      "X-User-Id": userId,
      "X-Tenant-Id": tenantId,
      "X-Branch-Id": branchId,
    };
  }

  // ===================== SAFE JSON DECODER ====================
  static dynamic safeDecode(String body) {
  try {
    return jsonDecode(body);
  } catch (e) {
    print("JSON DECODE ERROR: Backend returned HTML");
    print("----- BACKEND HTML START -----");
    print(body);
    print("----- BACKEND HTML END -----");
    return null;
  }
}

  // ===================== GENERIC GET ============================
  static Future<dynamic> get(String url) async {
    final res = await http.get(Uri.parse(url), headers: headers());
    return safeDecode(res.body);
  }

  // ===================== GENERIC POST ===========================
  static Future<dynamic> post(String url, Map data) async {
    final res = await http.post(Uri.parse(url),
        headers: headers(), body: jsonEncode(data));
    return safeDecode(res.body);
  }

  // ===================== GENERIC PUT ============================
  static Future<dynamic> put(String url, Map data) async {
    final res = await http.put(Uri.parse(url),
        headers: headers(), body: jsonEncode(data));
    return safeDecode(res.body);
  }

  // ===================== GENERIC PATCH ==========================
  static Future<dynamic> patch(String url, Map data) async {
    final res = await http.patch(Uri.parse(url),
        headers: headers(), body: jsonEncode(data));
    return safeDecode(res.body);
  }

  // ===================== GENERIC DELETE =========================
  static Future<bool> delete(String url) async {
    final res = await http.delete(Uri.parse(url), headers: headers());
    return res.statusCode == 200;
  }

  // ===================== GET ALL TABLES =========================
  static Future<List<dynamic>> getTables() async {
    final url = "$baseUrl/tables";
    final res = await get(url);

    if (res is List) return res;
    if (res is Map && res.containsKey("data")) return res["data"];

    return [];
  }

  // ===================== GET REAL TIME PRODUCTS ===============
  static Future<List<dynamic>> getProducts() async {
    final url = "$baseUrl/products/realtime";
    final res = await get(url);

    if (res is Map && res.containsKey("data")) {
      return res["data"];
    }
    return [];
  }

  // ===================== LOGIN ===============================
  static Future<dynamic> login(String username, String password) async {
  final url = "$baseUrl/auth/login";

  final res = await http.post(
    Uri.parse(url),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({
      "username": username,
      "password": password,
      "otp": "",
    }),
  );

  // IMPORTANT: PRINT THE FULL LOGIN RESPONSE
  print(" LOGIN RESPONSE BODY => ${res.body}");

  return safeDecode(res.body);
}

  // ===================== ORDERS, PAYMENTS, CUSTOMERS (unchanged) =====================
  // (Keeping your original logic)

  static Future<dynamic> createOrder(Map<String, dynamic> data) async {
  final url = "$baseUrl/orders/";
  print("CREATE ORDER CALL => $url");
  print("PAYLOAD => $data");

  final res = await http.post(Uri.parse(url),
      headers: headers(), body: jsonEncode(data));

  print("STATUS CODE => ${res.statusCode}");
  print("RESPONSE BODY => ${res.body}");

  return safeDecode(res.body);
}

  // ===================== ADD ITEMS TO AN ORDER =====================
static Future<dynamic> addItems(int orderId, List<Map<String, dynamic>> items) async {
  final url = "$baseUrl/orders/$orderId/add-items";

  final body = {
    "items": items,
  };

  final res = await post(url, body);
  return res;
}

  static Future<dynamic> validateTakeaway(int orderId) async {
  final url = "$baseUrl/orders/$orderId/validate-takeaway-payment-first";

  print(" VALIDATE URL => $url");

  final res = await get(url);

  if (res == null) {
    print(" VALIDATION FAILED: Backend returned null");
    return null;
  }

  print("VALIDATION RESPONSE => $res");
  return res;   // Return full map, not just true/false
}

  static Future<dynamic> cashPayment({
  required int orderId,
  required int totalAmount,
  required int paymentAmount,
  required int returnAmount,
}) async {

  final url = "$baseUrl/cash-payment-with-validation";

  final body = {
    "order_id": orderId,
    "total_amount": totalAmount,
    "payment_amount": paymentAmount,
    "return_amount": returnAmount,
    "flow_type": "cash"
  };

  final res = await post(url, body);
  return res;
}

  static Future<bool> processCardOrQrPayment({
  required int orderId,
  required int totalAmount,
  required String method,    // "card" or "qr"
}) async {

  final url = "$baseUrl/cash-payment-with-validation";

  final body = {
    "order_id": orderId,
    "total_amount": totalAmount,
    "payment_amount": totalAmount,
    "return_amount": 0,
    "flow_type": method  // "card" / "qr"
  };

  final res = await post(url, body);
  return res != null;
}

static Future<bool> creditPayment({
  required int orderId,
  required int totalAmount,
  required int customerId,
}) async {

  final url = "$baseUrl/credit-payment-process";

  final body = {
    "order_id": orderId,
    "total_amount": totalAmount,
    "customer_id": customerId
  };

  final res = await post(url, body);

  return res != null && res["payment_completed"] == true;
}

// ---------------- REPORTS SUMMARY API ----------------
static Future<Map<String, dynamic>> fetchSummary(String dateRange) async {
  final String url =
      "$baseUrl/reports/sales-summary?date_range=$dateRange";

  final res = await http.get(
    Uri.parse(url),
    headers: headers(),
  );

  if (res.statusCode == 200) {
    return jsonDecode(res.body);
  } else {
    print("SUMMARY ERROR => ${res.body}");
    throw Exception("Failed to load summary");
  }
}

// ============================================================
//                  DINE-IN PAYMENT FLOW
// ============================================================

// ===================== GET ACTIVE ORDERS (CORRECT URL) =====================
static Future<List<dynamic>> getActiveOrders() async {
  final url = "$baseUrl/orders/active-with-sub-orders";

  final res = await get(url);

  if (res == null) return [];

  // The backend returns:
  // { "orders": [ ... ] }
  if (res is Map && res.containsKey("orders")) {
    return res["orders"];
  }

  return [];
}

//  Get full details of a selected table/order
static Future<dynamic> getOrderDetails(int orderId) async {
  return await get("$baseUrl/orders/$orderId");
}

//  Send order to kitchen (after placing order)
static Future<bool> sendToKitchen(int orderId) async {
  final res = await post("$baseUrl/orders/$orderId/send-to-kitchen", {});
  return res != null;
}

// Kitchen in progress
static Future<bool> kitchenInProgress(int orderId) async {
  final res =
      await post("$baseUrl/orders/$orderId/kitchen-in-progress", {});
  return res != null;
}

//  Preparing
static Future<bool> preparing(int orderId) async {
  final res = await post("$baseUrl/orders/$orderId/preparing", {});
  return res != null;
}

// Order ready — move to payment page
static Future<bool> readyToPay(int orderId) async {
  final res = await post("$baseUrl/orders/$orderId/ready-to-pay", {});
  return res != null;
}

// Complete order after payment
static Future<bool> completeOrder(int orderId) async {
  final res = await post("$baseUrl/orders/$orderId/completed", {});
  return res != null;
}

  static Future<List<dynamic>> getCustomers() async {
    final res = await get("$baseUrl/customers");

    if (res is List) return res;
    if (res is Map && res.containsKey("data")) return res["data"];
    return [];
  }

  static Future<Map<String, dynamic>> createCustomer(
    Map<String, dynamic> data) async {
  final url = "$baseUrl/customers";

  print("📤 SENDING CUSTOMER DATA => $data");

  final res = await post(url, data);

  if (res == null) {
    print(" BACKEND RETURNED NULL (HTML or error)");
    return {};
  }

  print("📥 BACKEND RESPONSE => $res");

  if (res is Map<String, dynamic>) {
    return res;
  }

  return {};
}
// ============================================================
//                     REFUND / RETURN APIs
// ============================================================

// Validate Order for refund
static Future<bool> validateOrder(String orderNumber) async {
  final url = "$baseUrl/validate-order/$orderNumber";
  final res = await get(url);
  return res != null; // if 200 = true
}

// Get Order Details for refund
static Future<Map<String, dynamic>> getRefundOrderDetails(String orderNumber) async {
  final url = "$baseUrl/order-details/$orderNumber";

  final res = await get(url);

  if (res is Map<String, dynamic>) {
    return res;
  }
  return {};
}

// Process Refund
static Future<bool> processRefund(Map<String, dynamic> data) async {
  final url = "$baseUrl/process-refund";

  final res = await post(url, data);

  return res != null;  // success when backend returns JSON
}
}

// =======================================================
//               RESERVATION APIs (FINAL WORKING)
// =======================================================
class ReservationApi {
  static const String base = "${QcTradeApi.baseUrl}/reservations";

  // -------------------- GET STATS ------------------------
  static Future<Map<String, dynamic>> getStats() async {
    final res = await QcTradeApi.get("$base/stats/overview");

    if (res is Map<String, dynamic>) return res;
    return {};
  }

  // --------------- GET RESERVATIONS BY DATE ---------------
  static Future<List> getReservationsByDate(String date) async {
    final res = await QcTradeApi.get("$base/date/$date");
    if (res is List) return res;
    if (res is Map && res.containsKey("data")) return res["data"];
    return [];
  }

  // ------------------ GET ALL RESERVATIONS ----------------
  static Future<List> getAllReservations() async {
    final res = await QcTradeApi.get(base);

    if (res is List) return res;
    if (res is Map && res.containsKey("data")) return res["data"];
    return [];
  }

  // ------------------ AVAILABLE TABLES --------------------
  static Future<List> getAvailableTables(
    String date, String time, int partySize) async {

  final url =
      "${QcTradeApi.baseUrl}/reservations/available-tables"
      "?reservation_date=$date"
      "&reservation_time=$time"
      "&party_size=$partySize";

  final response = await http.get(
    Uri.parse(url),
    headers: QcTradeApi.headers(),
  );

  try {
    final res = jsonDecode(response.body);

    if (res is List) return res;
    if (res is Map && res.containsKey("data")) return res["data"];
    return [];
  } catch (e) {
    print("PARSE ERROR => ${response.body}");
    return [];
  }
}

  // ------------------ CREATE RESERVATION ------------------
  static Future<Map<String, dynamic>> createReservation(Map data) async {
    final res = await QcTradeApi.post(base, data);
    if (res is Map<String, dynamic>) return res;
    return {};
  }

  // ------------------ UPDATE RESERVATION ------------------
  static Future<Map<String, dynamic>> updateReservation(
      String id, Map data) async {
    final res = await QcTradeApi.put("$base/$id", data);
    if (res is Map<String, dynamic>) return res;
    return {};
  }

  // ------------------ DELETE RESERVATION ------------------
  static Future<bool> deleteReservation(String id) async {
    return await QcTradeApi.delete("$base/$id");
  }
}

// =======================================================
//                    SETTINGS API (CORRECT)
// =======================================================
class SettingsApi {
  // ---------------------- GET GENERAL SETTINGS ----------------------
  static Future<Map<String, dynamic>> getGeneralSettings() async {
    final url = "${QcTradeApi.baseUrl}/proxy/qctrade/settings?key=general";
    final res = await QcTradeApi.get(url);

    if (res is Map && res.containsKey("data")) {
      return res["data"]["value"] ?? {};
    }
    return {};
  }

  // ---------------------- SAVE GENERAL SETTINGS ----------------------
  static Future<bool> saveGeneralSettings(Map value) async {
    final url = "${QcTradeApi.baseUrl}/proxy/qctrade/settings";

    final body = {"key": "general", "value": value};
    final res = await QcTradeApi.put(url, body);
    return res != null;
  }

  // ---------------------- GET BRANCHES -------------------------
  static Future<List<dynamic>> getBranches() async {
    final url = "${QcTradeApi.baseUrl}/branches";
    final res = await QcTradeApi.get(url);

    if (res is List) return res;
    if (res is Map && res.containsKey("data")) return res["data"];
    return [];
  }

  // ---------------------- GET ACTIVE BRANCH ---------------------
  static Future<Map<String, dynamic>> getActiveBranch() async {
    final url =
        "${QcTradeApi.baseUrl}/proxy/qctrade/settings?key=branch";

    final res = await QcTradeApi.get(url);

    if (res is Map && res.containsKey("value")) {
      return res["value"] ?? {};
    }
    return {};
  }

  // ---------------------- SAVE ACTIVE BRANCH ---------------------
  static Future<bool> saveActiveBranch(Map<String, dynamic> value) async {
    final url = "${QcTradeApi.baseUrl}/proxy/qctrade/settings";

    final body = {
      "key": "branch",
      "value": value,
    };

    final res = await QcTradeApi.put(url, body);
    return res != null;
  }
}
