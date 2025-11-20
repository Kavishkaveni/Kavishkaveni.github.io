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

  // ===================== GET ALL TABLES ========================
  static Future<List<dynamic>> getTables() async {
    final url = Uri.parse("$baseUrl/tables");

    final response = await http.get(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
        "X-User-Id": userId,
        "X-Tenant-Id": tenantId,
        "X-Branch-Id": "BR101",
      },
    );

    print("TABLE API RAW = ${response.body}");

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);

      if (decoded is List) {
        return decoded;
      } else if (decoded is Map && decoded.containsKey("data")) {
        return decoded["data"];
      } else {
        return [];
      }
    } else {
      throw Exception("TABLE API FAILED: ${response.statusCode}");
    }
  }

  // ===================== GET REAL TIME PRODUCTS ===============
  static Future<List<dynamic>> getProducts() async {
    final url = Uri.parse("$baseUrl/products/realtime");

    final response = await http.get(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
        "X-User-Id": userId,
        "X-Tenant-Id": tenantId,
      },
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json["data"];
    } else {
      throw Exception("Failed to load products: ${response.statusCode}");
    }
  }

  // =========================== LOGIN ===========================
  static Future<dynamic> login(String username, String password) async {
    final url = Uri.parse("$baseUrl/auth/login");

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "username": username,
        "password": password,
        "otp": "",
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Login failed: ${response.statusCode}");
    }
  }

  // ======================= CREATE ORDER ========================
  static Future<dynamic> createOrder(Map<String, dynamic> data) async {
    const String url = "http://135.171.225.197:8002/api/v1/orders";

    final response = await http.post(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
        "X-User-Id": userId,
        "X-Tenant-Id": tenantId,
        "X-Branch-Id": "BR101",
      },
      body: jsonEncode(data),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      print("Order Created: ${response.body}");
      return jsonDecode(response.body);
    } else {
      print("Order Creation Failed: ${response.body}");
      throw Exception("Order Failed: ${response.body}");
    }
  }

  // ================= VALIDATE TAKEAWAY PAYMENT =================
  static Future<bool> validateTakeawayPaymentFirst(int orderId) async {
    final url = Uri.parse("$baseUrl/orders/$orderId/validate-takeaway-payment-first");

    final response = await http.get(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
        "X-User-Id": userId,
        "X-Tenant-Id": tenantId,
        "X-Branch-Id": "BR101",
      },
    );

    print("ELIGIBILITY RESPONSE = ${response.body}");

    return response.statusCode == 200;
  }

  // ========================== CASH PAYMENT =====================
  static Future<dynamic> confirmCashPayment(int orderId) async {
    final url = Uri.parse("$baseUrl/orders/$orderId/confirm-payment");

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
        "X-User-Id": userId,
        "X-Tenant-Id": tenantId,
        "X-Branch-Id": "BR101",
      },
      body: jsonEncode({}),
    );

    print("CASH PAYMENT RESPONSE = ${response.body}");

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Payment Failed: ${response.body}");
    }
  }

  // ======================= GENERIC HELPERS =====================
  static Future<dynamic> get(String url) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
        "X-User-Id": userId,
        "X-Tenant-Id": tenantId,
        "X-Branch-Id": "BR101",
      },
    );
    return jsonDecode(response.body);
  }

  static Future<dynamic> post(String url, Map data) async {
    final response = await http.post(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
        "X-User-Id": userId,
        "X-Tenant-Id": tenantId,
        "X-Branch-Id": "BR101",
      },
      body: jsonEncode(data),
    );
    return jsonDecode(response.body);
  }

  static Future<dynamic> put(String url, Map data) async {
    final response = await http.put(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
        "X-User-Id": userId,
        "X-Tenant-Id": tenantId,
        "X-Branch-Id": "BR101",
      },
      body: jsonEncode(data),
    );
    return jsonDecode(response.body);
  }

  static Future<dynamic> patch(String url, Map data) async {
    final response = await http.patch(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
        "X-User-Id": userId,
        "X-Tenant-Id": tenantId,
        "X-Branch-Id": "BR101",
      },
      body: jsonEncode(data),
    );
    return jsonDecode(response.body);
  }

  static Future<bool> delete(String url) async {
    final response = await http.delete(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
        "X-User-Id": userId,
        "X-Tenant-Id": tenantId,
        "X-Branch-Id": "BR101",
      },
    );
    return response.statusCode == 200;
  }
}

// ======================= RESERVATION APIs ======================

class ReservationApi {
  static const String base = "${QcTradeApi.baseUrl}/reservations";

  static Future<List> getAvailableTables(String date, String time) async {
    final url =
        "$base/available-tables?reservation_date=$date&reservation_time=$time";

    final res = await QcTradeApi.get(url);

    if (res is Map && res.containsKey("data")) {
      return res["data"];
    }
    return [];
  }

  static Future<Map<String, dynamic>> getStats() async {
    return await QcTradeApi.get("$base/stats/overview");
  }

  static Future<List> getReservationsByDate(String date) async {
    final res = await QcTradeApi.get("$base/date/$date");
    return res["data"] ?? [];
  }

  static Future<List> getAllReservations() async {
    final res = await QcTradeApi.get(base);
    return res["data"] ?? [];
  }

  static Future<Map<String, dynamic>> createReservation(Map data) async {
    return await QcTradeApi.post(base, data);
  }

  static Future<Map<String, dynamic>> getReservation(String id) async {
    return await QcTradeApi.get("$base/$id");
  }

  static Future<Map<String, dynamic>> updateReservation(
      String id, Map data) async {
    return await QcTradeApi.put("$base/$id", data);
  }

  static Future<bool> deleteReservation(String id) async {
    return await QcTradeApi.delete("$base/$id");
  }

  static Future<Map<String, dynamic>> updateStatus(
      String id, Map data) async {
    return await QcTradeApi.patch("$base/$id/status", data);
  }

  static Future<Map<String, dynamic>> confirmReservation(String id) async {
    return await QcTradeApi.post("$base/$id/confirm", {});
  }

  static Future<Map<String, dynamic>> cancelReservation(String id) async {
    return await QcTradeApi.post("$base/$id/cancel", {});
  }

  static Future<Map<String, dynamic>> completeReservation(String id) async {
    return await QcTradeApi.post("$base/$id/complete", {});
  }
}
