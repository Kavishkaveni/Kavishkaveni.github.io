import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:qcitrack/auth/auth_service.dart';

class QcTradeApi {
  // ===================== BASE BACKEND URL =====================
  static const String baseUrl = "https://qctrade_backend.qcetl.com/api/v1";

  static Map<String, String> headers() {
  return {
    "Content-Type": "application/json",

    // REQUIRED
    "Authorization": "Bearer ${AuthService.accessToken}",
    "X-Tenant-Id": AuthService.tenantId!,
    "X-QC-Branch-Id": AuthService.branchId!,
  };
}
static Map<String, String> tenantHeadersOnly() {
  return {
    "Content-Type": "application/json",
    "Authorization": "Bearer ${AuthService.accessToken}",
    "X-Tenant-Id": AuthService.tenantId!,
  };
}

  // ===================== SAFE JSON DECODER ====================
  static dynamic safeDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (e) {
      print("JSON DECODE ERROR");
      print("RESPONSE => $body");
      return null;
    }
  }

  // ===================== GENERIC GET ==========================
  static Future<dynamic> get(String url) async {
    final res = await http.get(Uri.parse(url), headers: headers());
    return safeDecode(res.body);
  }

  // ===================== GENERIC POST =========================
  static Future<dynamic> post(String url, Map data) async {
    final res = await http.post(
      Uri.parse(url),
      headers: headers(),
      body: jsonEncode(data),
    );
    return safeDecode(res.body);
  }

  // ===================== GENERIC PUT =========================
  static Future<dynamic> put(String url, Map data) async {
    final res = await http.put(
      Uri.parse(url),
      headers: headers(),
      body: jsonEncode(data),
    );
    return safeDecode(res.body);
  }

  // ===================== GENERIC DELETE ======================
  static Future<bool> delete(String url) async {
    final res = await http.delete(
      Uri.parse(url),
      headers: headers(),
    );
    return res.statusCode == 200;
  }

  // ============================================================
//                     CUSTOMER APIs
// ============================================================

// --------------------- GET ALL CUSTOMERS ---------------------
static Future<List<dynamic>> getCustomers() async {
  final String url = "$baseUrl/customers/";

  print("GET CUSTOMERS => $url");

  final response = await http.get(
    Uri.parse(url),
    headers: headers(),
  );

  print("STATUS => ${response.statusCode}");
  print("BODY => ${response.body}");

  if (response.statusCode == 200) {
    final decoded = safeDecode(response.body);

    if (decoded is List) return decoded;
    if (decoded is Map && decoded.containsKey("data")) {
      return decoded["data"];
    }
  }

  return [];
}

// --------------------- CREATE CUSTOMER ---------------------
static Future<Map<String, dynamic>> createCustomer(
    Map<String, dynamic> data) async {
  final String url = "$baseUrl/customers/";

  print("CREATE CUSTOMER => $data");

  final response = await http.post(
    Uri.parse(url),
    headers: headers(),
    body: jsonEncode(data),
  );

  print("STATUS => ${response.statusCode}");
  print("BODY => ${response.body}");

  if (response.statusCode == 200 || response.statusCode == 201) {
    final decoded = safeDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
  }

  throw Exception("Create customer failed");
}

// --------------------- UPDATE CUSTOMER ---------------------
static Future<Map<String, dynamic>> updateCustomer(
    String customerId, Map<String, dynamic> data) async {
  final String url = "$baseUrl/customers/$customerId";

  print("UPDATE CUSTOMER => $data");

  final response = await http.put(
    Uri.parse(url),
    headers: headers(),
    body: jsonEncode(data),
  );

  print("STATUS => ${response.statusCode}");
  print("BODY => ${response.body}");

  if (response.statusCode == 200) {
    final decoded = safeDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
  }

  throw Exception("Update customer failed");
}

// --------------------- DELETE CUSTOMER ---------------------
static Future<bool> deleteCustomer(String customerId) async {
  final String url = "$baseUrl/customers/$customerId";

  print("DELETE CUSTOMER => $url");

  final response = await http.delete(
    Uri.parse(url),
    headers: headers(),
  );

  print("STATUS => ${response.statusCode}");

  return response.statusCode == 200 || response.statusCode == 204;
}

// --------------------- IDENTIFY CUSTOMER BY CARD ---------------------
static Future<Map<String, dynamic>> identifyCustomerByCard(
    String customerId, Map<String, dynamic> data) async {
  final String url =
      "$baseUrl/customers/$customerId/identify-by-card";

  print("IDENTIFY CUSTOMER BY CARD => $data");

  final response = await http.post(
    Uri.parse(url),
    headers: headers(),
    body: jsonEncode(data),
  );

  print("STATUS => ${response.statusCode}");
  print("BODY => ${response.body}");

  if (response.statusCode == 200) {
    final decoded = safeDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
  }

  throw Exception("Customer card identification failed");
}

// ============================================================
//                     RESERVATION APIs
// ============================================================

// --------------------- GET RESERVATIONS (WITH FILTERS) ---------------------
static Future<List<dynamic>> getReservations({
  String? reservationDate,
  String? status,
  String? search,
}) async {
  final queryParams = <String, String>{};

  if (reservationDate != null && reservationDate.isNotEmpty) {
    queryParams["reservation_date"] = reservationDate;
  }
  if (status != null && status.isNotEmpty) {
    queryParams["status"] = status;
  }
  if (search != null && search.isNotEmpty) {
    queryParams["search"] = search;
  }

  final uri = Uri.parse("$baseUrl/reservations").replace(
    queryParameters: queryParams.isEmpty ? null : queryParams,
  );

  final res = await http.get(uri, headers: headers());

  if (res.statusCode == 200) {
    final decoded = safeDecode(res.body);
    if (decoded is Map && decoded.containsKey("data")) {
      return decoded["data"];
    }
    if (decoded is List) return decoded;
  }

  return [];
}

// --------------------- GET RESERVATION STATS ---------------------
static Future<Map<String, dynamic>> getReservationStats() async {
  final res = await http.get(
    Uri.parse("$baseUrl/reservations/stats"),
    headers: headers(),
  );

  if (res.statusCode == 200) {
    return safeDecode(res.body) ?? {};
  }

  return {};
}

// --------------------- CREATE RESERVATION ---------------------
static Future<Map<String, dynamic>> createReservation(
    Map<String, dynamic> data) async {
  final res = await http.post(
    Uri.parse("$baseUrl/reservations"),
    headers: headers(),
    body: jsonEncode(data),
  );

  if (res.statusCode == 200 || res.statusCode == 201) {
    return safeDecode(res.body) ?? {};
  }

  throw Exception("Create reservation failed");
}

// --------------------- UPDATE RESERVATION ---------------------
static Future<Map<String, dynamic>> updateReservation(
    String reservationId, Map<String, dynamic> data) async {
  final res = await http.put(
    Uri.parse("$baseUrl/reservations/$reservationId"),
    headers: headers(),
    body: jsonEncode(data),
  );

  if (res.statusCode == 200) {
    return safeDecode(res.body) ?? {};
  }

  throw Exception("Update reservation failed");
}

// --------------------- DELETE RESERVATION ---------------------
static Future<bool> deleteReservation(String reservationId) async {
  final res = await http.delete(
    Uri.parse("$baseUrl/reservations/$reservationId"),
    headers: headers(),
  );

  return res.statusCode == 200 || res.statusCode == 204;
}

// --------------------- UPDATE RESERVATION STATUS ---------------------
static Future<bool> updateReservationStatus(
    String reservationId, String status) async {
  final res = await http.put(
    Uri.parse("$baseUrl/reservations/$reservationId/status"),
    headers: headers(),
    body: jsonEncode({"status": status}),
  );

  return res.statusCode == 200;
}

// --------------------- GET AVAILABLE TABLES ---------------------
static Future<List<dynamic>> getAvailableTables({
  required String reservationDate,
  required String reservationTime,
  String? reservationEndTime,
  int? partySize,
}) async {
  final queryParams = <String, String>{
    "reservation_date": reservationDate,
    "reservation_time": reservationTime,
  };

  if (reservationEndTime != null) {
    queryParams["reservation_end_time"] = reservationEndTime;
  }
  if (partySize != null) {
    queryParams["party_size"] = partySize.toString();
  }

  final uri = Uri.parse("$baseUrl/reservations/available-tables")
      .replace(queryParameters: queryParams);

  final res = await http.get(uri, headers: headers());

  if (res.statusCode == 200) {
    final decoded = safeDecode(res.body);
    if (decoded is Map && decoded.containsKey("data")) {
      return decoded["data"];
    }
    if (decoded is List) return decoded;
  }

  return [];
}

// ============================================================
//                     SETTINGS APIs
// ============================================================
static Future<Map<String, dynamic>> getNotificationSettings() async {
  final url = "$baseUrl/proxy/qctrade/settings?key=notifications";
  final res = await get(url);

  if (res is Map && res.containsKey("value")) {
    return res["value"] ?? {};
  }
  return {};
}

static Future<bool> saveNotificationSettings(Map value) async {
  final url = "$baseUrl/proxy/qctrade/settings";
  final body = {
    "key": "notifications",
    "value": value,
  };

  final res = await put(url, body);
  return res != null;
}
// ===================== GENERAL SETTINGS =====================

// GET General Settings
static Future<Map<String, dynamic>> getGeneralSettings() async {
  final url =
      "$baseUrl/proxy/qctrade/settings?key=general";

  final res = await get(url);

  if (res is Map && res.containsKey("value")) {
    return res["value"] ?? {};
  }

  return {};
}

// SAVE General Settings
static Future<bool> saveGeneralSettings(
    Map<String, dynamic> value) async {
  final url = "$baseUrl/proxy/qctrade/settings";

  final body = {
    "key": "general",
    "value": value,
  };

  final res = await put(url, body);
  return res != null;
}

// ===================== PRINTING SETTINGS =====================

// GET Printing Settings
static Future<Map<String, dynamic>> getPrintingSettings() async {
  final url =
      "$baseUrl/proxy/qclpsa/settings?key=printing";

  final res = await get(url);

  if (res is Map && res.containsKey("value")) {
    return res["value"] ?? {};
  }

  return {};
}

// SAVE Printing Settings
static Future<bool> savePrintingSettings(
    Map<String, dynamic> value) async {
  final url = "$baseUrl/proxy/qclpsa/settings";

  final body = {
    "key": "printing",
    "value": value,
  };

  final res = await put(url, body);
  return res != null;
}

// ===================== DEVICES & PRINTERS =====================

// GET Connected Devices
static Future<List<dynamic>> getPrinterDevices() async {
  final url =
      "$baseUrl/proxy/qclpsa/devices";

  final res = await get(url);

  if (res is List) return res;
  if (res is Map && res.containsKey("data")) return res["data"];

  return [];
}

// GET Printers for a Device
static Future<List<dynamic>> getPrinters(String deviceId) async {
  final url =
      "$baseUrl/proxy/qclpsa/devices/$deviceId/printers";

  final res = await get(url);

  if (res is List) return res;
  if (res is Map && res.containsKey("data")) return res["data"];

  return [];
}

// TEST Printer Configuration
static Future<bool> testPrinterConfiguration(
    List<String> printers) async {
  final url =
      "$baseUrl/proxy/qclpsa/test-configuration";

  final body = {
    "printers": printers,
  };

  final res = await post(url, body);
  return res != null;
}

// ===================== BRANCH SETTINGS =====================

// GET Branches (already used elsewhere, safe to reuse)
static Future<List<dynamic>> getBranchesForSettings() async {
  final url = "$baseUrl/branches";

  final res = await get(url);

  if (res is List) return res;
  if (res is Map && res.containsKey("data")) return res["data"];

  return [];
}

// SAVE Active Branch
static Future<bool> saveActiveBranchSetting(
    Map<String, dynamic> value) async {
  final url = "$baseUrl/settings";

  final body = {
    "key": "branch",
    "value": value,
  };

  final res = await put(url, body);
  return res != null;
}


// ============================================================
//                REFUND & RETURNS APIs
// ============================================================

// --------------------- VALIDATE ORDER ---------------------
static Future<bool> validateOrder(String orderNumber) async {
  final url = "$baseUrl/validate-order/$orderNumber";

  final res = await get(url);

  return res != null;
}

// --------------------- GET ORDER DETAILS (FOR REFUND) ---------------------
static Future<Map<String, dynamic>> getRefundOrderDetails(
    String orderNumber) async {
  final url = "$baseUrl/order-details/$orderNumber";

  final res = await get(url);

  if (res is Map<String, dynamic>) {
    return res;
  }

  return {};
}

// --------------------- PROCESS REFUND ---------------------
static Future<bool> processRefund(Map<String, dynamic> data) async {
  final url = "$baseUrl/process-refund";

  final res = await post(url, data);

  return res != null;
}

// ============================================================
//                     REPORTS & ANALYTICS APIs
// ============================================================

// ===================== SALES SUMMARY =====================
static Future<Map<String, dynamic>> getSalesSummary({
  required String dateRange,
  String? startDate,
  String? endDate,
}) async {
  final queryParams = <String, String>{
    "date_range": dateRange,
  };

  if (dateRange == "custom" && startDate != null && endDate != null) {
    queryParams["start_date"] = startDate;
    queryParams["end_date"] = endDate;
  }

  final uri = Uri.parse("$baseUrl/reports/sales-summary")
      .replace(queryParameters: queryParams);

  final res = await get(uri.toString());
  return res ?? {};
}

// ===================== DAILY SALES REPORT =====================
static Future<List<dynamic>> getDailySales({
  required String dateRange,
  String? startDate,
  String? endDate,
}) async {
  final queryParams = <String, String>{
    "date_range": dateRange,
  };

  if (dateRange == "custom" && startDate != null && endDate != null) {
    queryParams["start_date"] = startDate;
    queryParams["end_date"] = endDate;
  }

  final uri = Uri.parse("$baseUrl/reports/daily-sales")
      .replace(queryParameters: queryParams);

  final res = await get(uri.toString());

  if (res is Map && res.containsKey("daily_sales")) {
    return res["daily_sales"];
  }

  return [];
}

// ===================== DETAILED SALES REPORT =====================
static Future<List<dynamic>> getDetailedSales({
  required String dateRange,
  String? startDate,
  String? endDate,
}) async {
  final queryParams = <String, String>{
    "date_range": dateRange,
  };

  if (dateRange == "custom" && startDate != null && endDate != null) {
    queryParams["start_date"] = startDate;
    queryParams["end_date"] = endDate;
  }

  final uri = Uri.parse("$baseUrl/reports/detailed-sales")
      .replace(queryParameters: queryParams);

  final res = await get(uri.toString());

  if (res is Map && res.containsKey("detailed_sales")) {
    return res["detailed_sales"];
  }

  return [];
}

// ===================== PAYMENT METHODS REPORT =====================
static Future<List<dynamic>> getPaymentMethodsReport({
  required String dateRange,
  String? startDate,
  String? endDate,
}) async {
  final queryParams = <String, String>{
    "date_range": dateRange,
  };

  if (dateRange == "custom" && startDate != null && endDate != null) {
    queryParams["start_date"] = startDate;
    queryParams["end_date"] = endDate;
  }

  final uri = Uri.parse("$baseUrl/reports/payment-methods")
      .replace(queryParameters: queryParams);

  final res = await get(uri.toString());

  if (res is Map && res.containsKey("payment_methods")) {
    return res["payment_methods"];
  }

  return [];
}

// ============================================================
//                 QC TRADE BRANCH MANAGEMENT APIs
// ============================================================

// --------------------- GET QC TRADE BRANCHES ---------------------
static Future<List<dynamic>> getQcTradeBranches() async {
  final url = "$baseUrl/qc-branches";

  print("QC BRANCH API CALL => $url");

  final res = await http.get(
    Uri.parse(url),
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer ${AuthService.accessToken}",
      "X-Tenant-Id": AuthService.tenantId!,
      "X-User-Id": AuthService.userId.toString(),
    },
  );

  print("QC BRANCH STATUS => ${res.statusCode}");
  print("QC BRANCH BODY => ${res.body}");

  if (res.statusCode == 200) {
    final decoded = jsonDecode(res.body);
    if (decoded is List) return decoded;
  }

  return [];
}
// --------------------- CREATE QC TRADE BRANCH ---------------------
static Future<bool> createQcTradeBranch({
  required String code,
  required String name,
}) async {
  final url = "$baseUrl/qc-branches";

  final body = {
    "code": code,
    "name": name,
  };

  final res = await http.post(
    Uri.parse(url),
    headers: headers(),
    body: jsonEncode(body),
  );

  return res.statusCode == 200 || res.statusCode == 201;
}

// --------------------- GET TENANT USERS ---------------------
static Future<List<dynamic>> getTenantUsers() async {
  final url = "$baseUrl/users/tenant-users";

  final res = await http.get(
    Uri.parse(url),
    headers: headers(),
  );

  if (res.statusCode == 200) {
    return jsonDecode(res.body);
  }

  return [];
}

// --------------------- ASSIGN USER TO QC TRADE BRANCH ---------------------
static Future<bool> assignUserToQcBranch({
  required String branchId,
  required String userId,
  bool setAsDefault = false,
}) async {
  final url = "$baseUrl/qc-branches/$branchId/assign-user";

  final body = {
    "user_id": userId,
    "set_as_default": setAsDefault,
  };

  final res = await http.post(
    Uri.parse(url),
    headers: headers(),
    body: jsonEncode(body),
  );

  return res.statusCode == 200 || res.statusCode == 201;
}

// --------------------- LINK INVENTORY SOURCE ---------------------
static Future<bool> linkInventorySourceToBranch({
  required String branchId,
  required String mode, // primary | overflow | parallel
  required int quantity,
}) async {
  final url = "$baseUrl/qc-branches/$branchId/inventory-links";

  final body = {
    "mode": mode,
    "quantity": quantity,
  };

  final res = await http.post(
    Uri.parse(url),
    headers: headers(),
    body: jsonEncode(body),
  );

  return res.statusCode == 200 || res.statusCode == 201;
}

// ============================================================
// QC TRADE ORDERS / DINE-IN / TAKE-AWAY / PAYMENT APIs
// ============================================================

// ============================================================
//  ORDERS  DINE-IN (TABLE PAGE)
// ============================================================

// Get active dine-in orders + tables
// Used in: Orders → Dine-In → Table Page
static Future<List<dynamic>> getActiveDineInOrders() async {
  final url = "$baseUrl/orders/active-with-sub-orders";

  final res = await http.get(
    Uri.parse(url),
    headers: headers(),
  );

  if (res.statusCode == 200) {
    final decoded = safeDecode(res.body);
    if (decoded is Map && decoded.containsKey("orders")) {
      return decoded["orders"];
    }
  }
  return [];
}

// ============================================================
// ORDER DETAILS
// ============================================================

// Get full order details (items, totals, status)
// Used after selecting a table
static Future<Map<String, dynamic>> getOrderDetails(int orderId) async {
  final url = "$baseUrl/orders/$orderId";

  final res = await http.get(
    Uri.parse(url),
    headers: headers(),
  );

  if (res.statusCode == 200) {
    return safeDecode(res.body) ?? {};
  }

  return {};
}

// ============================================================
// ADD ITEMS TO ORDER 
// ============================================================

// Add items to order (Dine-In / Take-Away cart)
static Future<dynamic> addItemsToOrder(
  int orderId,
  List<Map<String, dynamic>> items,
) async {
  final url = "$baseUrl/orders/$orderId/add-items";

  final body = {
    "items": items,
  };

  final res = await http.post(
    Uri.parse(url),
    headers: headers(),
    body: jsonEncode(body),
  );

  return safeDecode(res.body);
}

// ============================================================
//  KITCHEN FLOW (ORDER STATUS)
// ============================================================

// Send order to kitchen
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

// Preparing
static Future<bool> preparing(int orderId) async {
  final res = await post("$baseUrl/orders/$orderId/preparing", {});
  return res != null;
}

// Ready to pay
static Future<bool> readyToPay(int orderId) async {
  final res = await post("$baseUrl/orders/$orderId/ready-to-pay", {});
  return res != null;
}

// ============================================================
//  PAYMENT VALIDATION 
// ============================================================

// Validate takeaway / dine-in before payment
static Future<dynamic> validatePayment(int orderId) async {
  final url =
      "$baseUrl/orders/$orderId/validate-takeaway-payment-first";

  final res = await http.get(
    Uri.parse(url),
    headers: headers(),
  );

  return safeDecode(res.body);
}

// ============================================================
//  PAYMENT – CASH
// ============================================================

// Cash payment
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
    "flow_type": "cash",
  };

  final res = await post(url, body);
  return res;
}

// ============================================================
// PAYMENT – CARD / QR
// ============================================================

// Card or QR payment
static Future<bool> cardOrQrPayment({
  required int orderId,
  required int totalAmount,
  required String method, // "card" or "qr"
}) async {
  final url = "$baseUrl/cash-payment-with-validation";

  final body = {
    "order_id": orderId,
    "total_amount": totalAmount,
    "payment_amount": totalAmount,
    "return_amount": 0,
    "flow_type": method,
  };

  final res = await post(url, body);
  return res != null;
}

// ============================================================
// PAYMENT – CREDIT
// ============================================================

// Credit payment
static Future<bool> creditPayment({
  required int orderId,
  required int totalAmount,
  required int customerId,
}) async {
  final url = "$baseUrl/credit-payment-process";

  final body = {
    "order_id": orderId,
    "total_amount": totalAmount,
    "customer_id": customerId,
  };

  final res = await post(url, body);

  return res != null && res["payment_completed"] == true;
}

// ============================================================
// COMPLETE ORDER
// ============================================================

// Complete order after successful payment
static Future<bool> completeOrder(int orderId) async {
  final res = await post("$baseUrl/orders/$orderId/completed", {});
  return res != null;
}

// ============================================================
// TAKE-AWAY  CREATE ORDER
// ============================================================

// Create takeaway order
static Future<dynamic> createTakeawayOrder(
  Map<String, dynamic> data,
) async {
  final url = "$baseUrl/orders/";

  final res = await http.post(
    Uri.parse(url),
    headers: headers(),
    body: jsonEncode(data),
  );

  return safeDecode(res.body);
}
//=============================================================

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

  // ===================== ORDERS, PAYMENTS, CUSTOMERS =====================

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
  return res;  
}

}
