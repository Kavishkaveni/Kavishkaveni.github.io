import 'dart:convert';

import 'package:http/http.dart' as http;

class QcTradeApi {
  // ===================== MAIN BACKEND URL =====================
  static const String baseUrl = "http://135.171.225.197:8002/api/v1";

  // ===================== AUTH DETAILS =========================
  static String accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhZG1pbjFAZ21haWwuY29tIiwidGVuYW50X2lkIjoiN2IxNzdkOWMtZGJlZC00ZTUwLWE0ZGMtN2EyY2RkOWQ2ZTNmIiwiZXhwIjoxNzYzNTM3Mzc2fQ.Dl6lqzb4L5FCpZLQa5KVnRoBO-ST7dWAzgGxBhvMtus";

  static String userId = "1";
  static String tenantId = "7b177d9c-dbed-4e50-a4dc-7a2cdd9d6e3f";

  // ===================== COMMON HEADERS =======================
  static Map<String, String> headers() {
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
      "X-User-Id": userId,
      "X-Tenant-Id": tenantId,
      "X-Branch-Id": "BR101", // MANDATORY FIX
    };
  }

  // ===================== SAFE JSON DECODER ====================
  static dynamic safeDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (e) {
      print("❌ JSON DECODE ERROR: Backend returned HTML");
      print(body);
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

    return safeDecode(res.body);
  }

  // ===================== ORDERS, PAYMENTS, CUSTOMERS (unchanged) =====================
  // (Keeping your original logic)

  static Future<dynamic> createOrder(Map<String, dynamic> data) async {
    final url = "$baseUrl/orders";
    final res = await post(url, data);
    return res;
  }

  static Future<bool> validateTakeawayPaymentFirst(int orderId) async {
  final url = "$baseUrl/orders/$orderId/validate-takeaway-payment-first";
  final res = await get(url);
  return res != null;
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
    print("❌ BACKEND RETURNED NULL (HTML or error)");
    return {};
  }

  print("📥 BACKEND RESPONSE => $res");

  if (res is Map<String, dynamic>) {
    return res;
  }

  return {};
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
  static Future<List> getAvailableTables(String date, String time) async {
    final url =
        "${QcTradeApi.baseUrl}/tables/available?reservation_date=$date&reservation_time=$time";

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${QcTradeApi.accessToken}",
        "X-User-Id": QcTradeApi.userId,
        "X-Tenant-Id": QcTradeApi.tenantId,
        "X-Branch-Id": "BR101",
      },
    );

    try {
      final res = jsonDecode(response.body);

      if (res is List) return res;
      if (res is Map && res.containsKey("data")) return res["data"];

      return [];
    } catch (e) {
      print("❌ AVAILABLE TABLE PARSE ERROR:");
      print(response.body);
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
