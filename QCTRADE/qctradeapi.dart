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
static Future<Map<String, dynamic>> getPaymentMethodsReport({
  required String dateRange,
  String? startDate,
  String? endDate,
}) async {
  final queryParams = <String, String>{
    "date_range": dateRange.toLowerCase().trim(),
  };

  if (dateRange == "custom" && startDate != null && endDate != null) {
    queryParams["start_date"] = startDate;
    queryParams["end_date"] = endDate;
  }

  final uri = Uri.parse("$baseUrl/reports/payment-methods")
      .replace(queryParameters: queryParams);

  final res = await get(uri.toString());

  if (res is Map<String, dynamic>) {
    return res;
  }

  return {};
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
    headers: tenantHeadersOnly(),
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
  required String inventoryBranchId,
  required String mode,
  required int priority,
  required int weight,
}) async {
  final url = "$baseUrl/qc-branches/$branchId/inventory-links";

  final body = {
    "inventory_branch_id": inventoryBranchId,
    "mode": mode,
    "priority": priority,
    "weight": weight,
  };

  final res = await http.post(
    Uri.parse(url),
    headers: headers(),
    body: jsonEncode(body),
  );

  return res.statusCode == 200 || res.statusCode == 201;
}

// ============================================================
// QC TRADE – ORDERS (DINE-IN + TAKE-AWAY)
// ============================================================

// Get active orders (with sub-orders)
static Future<dynamic> getActiveOrders({
  int page = 1,
  int limit = 5,
  String status = "all",
  String search = "",
}) async {
  final uri = Uri.parse("$baseUrl/orders/active-with-sub-orders").replace(
    queryParameters: {
      "page": page.toString(),
      "limit": limit.toString(),
      "status_filter": status,
      "search": search,
    },
  );
  return get(uri.toString());
}

// Get order basic details
static Future<dynamic> getOrder(int orderId) async {
  return get("$baseUrl/orders/$orderId");
}

// Get order with sub-orders
static Future<dynamic> getOrderWithSubOrders(int orderId) async {
  return get("$baseUrl/orders/$orderId/with-sub-orders");
}

// Full order summary (items + totals)
static Future<dynamic> getFullOrderSummary(int orderId) async {
  return get("$baseUrl/orders/$orderId/full-order-summary");
}

// ============================================================
// PAYMENT VALIDATION (CRITICAL)
// ============================================================

// Dine-In | Payment-First
static Future<dynamic> validateDineInPaymentFirst(int orderId) async {
  return get("$baseUrl/orders/$orderId/validate-dinein-payment-first");
}

// Take-Away | Payment-First
static Future<dynamic> validateTakeawayPaymentFirst(int orderId) async {
  return get("$baseUrl/orders/$orderId/validate-takeaway-payment-first");
}

// Take-Away | Settlement (Kitchen First)
static Future<dynamic> validateTakeawaySettlement(int orderId) async {
  return get("$baseUrl/orders/$orderId/validate-takeaway-settlement");
}

// Dine-In | Kitchen First (with sub-orders)
static Future<dynamic> validatePaymentWithSubOrders(int orderId) async {
  return post(
    "$baseUrl/orders/$orderId/validate-payment-with-sub-orders",
    {},
  );
}

// ============================================================
// PAYMENT – CASH / CARD / QR (MULTIPLE PAYMENT)
// ============================================================

static Future<dynamic> processMultiplePayment({
  required int orderId,
  required double totalAmount,
  required List<Map<String, dynamic>> paymentMethods,
}) async {
  final body = {
    "order_id": orderId,
    "total_amount": totalAmount,
    "payment_methods": paymentMethods,
    "return_amount": 0,
  };
  return post("$baseUrl/multiple-payment", body);
}

// ============================================================
// PAYMENT APIs (CASH + CREDIT ONLY)
// ============================================================

/// ------------------------------------------------------------
/// CASH PAYMENT (WITH BACKEND VALIDATION)
/// API: POST /payments/cash-payment-with-validation
/// Used for: Dine-in / Takeaway cash payments
/// Handles: validation + payment + settlement in one call
/// ------------------------------------------------------------
static Future<dynamic> cashPaymentWithValidation({
  required int orderId,
  required double totalAmount,
  required double receivedAmount,
}) async {
  final double paymentAmount = totalAmount;
  final double returnAmount =
      receivedAmount > totalAmount ? receivedAmount - totalAmount : 0;

  final body = {
    "order_id": orderId,
    "total_amount": totalAmount,
    "payment_amount": paymentAmount,
    "received_amount": receivedAmount,
    "return_amount": returnAmount,
  };

  print("CASH PAYMENT WITH VALIDATION => $body");

  final res = await post(
    "$baseUrl/payments/cash-payment-with-validation",
    body,
  );

  print("CASH PAYMENT RESPONSE => $res");

  return res;
}

/// Used for: Credit customers
/// ------------------------------------------------------------
static Future<dynamic> creditPaymentProcess({
  required int orderId,
  required int customerId,
  required double totalAmount,
  double cashPaid = 0,
  String flowType = "traditional", // or "payment_first"
}) async {
  final body = {
    "order_id": orderId,
    "customer_id": customerId,
    "total_amount": totalAmount,
    "cash_paid": cashPaid,
    "flow_type": flowType,
  };

  print("CREDIT PAYMENT => $body");

  return post("$baseUrl/credit-payment-process", body);
}
// ============================================================
// SEND TO KITCHEN 
// ============================================================

static Future<dynamic> sendToKitchenAfterPayment(int orderId) async {
  return post(
    "$baseUrl/orders/$orderId/send-to-kitchen-after-payment",
    {},
  );
}
static Future<Map<String, dynamic>?> takeawayCashPayment({
  required int orderId,
  required double totalAmount,
  required double receivedAmount,
}) async {
  final payload = {
    "order_id": orderId,
    "total_amount": totalAmount,
    "payment_amount": totalAmount,
    "received_amount": receivedAmount,
    "return_amount": receivedAmount - totalAmount,
  };

  print("TAKEAWAY CASH PAYMENT => $payload");

  final res = await post(
    "$baseUrl/payments/cash-payment", //  QC Trade takeaway cash API
    payload,
  );

  print("TAKEAWAY CASH PAYMENT RESPONSE => $res");
  return res;
}


// ============================================================
// CUSTOMER (PAYMENT RELATED)
// ============================================================

// Get customers for credit payment
static Future<dynamic> getCustomersForCreditPayment() async {
  return get("$baseUrl/customers/for-credit-payment");
}

// Check customer credit eligibility
static Future<dynamic> checkCustomerPaymentEligibility(int customerId) async {
  return get("$baseUrl/customers/$customerId/payment-eligibility");
}

// ============================================================
// ORDER SETTLEMENT (CRITICAL)
// ============================================================
static Future<dynamic> settleOrder(int orderId) async {
  return post(
    "$baseUrl/orders/$orderId/settle-order",
    {},
  );
}
//=============================================================

  // ============================================================
//                     TABLE MANAGEMENT APIs
// ============================================================

// ===================== GET ALL TABLES =====================
static Future<List<dynamic>> getTables() async {
  final url = "$baseUrl/tables";

  print("GET TABLES => $url");

  final res = await http.get(
    Uri.parse(url),
    headers: headers(),
  );

  print("STATUS => ${res.statusCode}");
  print("BODY => ${res.body}");

  if (res.statusCode == 200) {
    final decoded = safeDecode(res.body);
    if (decoded is List) return decoded;
    if (decoded is Map && decoded.containsKey("data")) {
      return decoded["data"];
    }
  }

  return [];
}

// ===================== CREATE TABLE =========================
static Future<bool> createTable(Map<String, dynamic> data) async {
  final url = "$baseUrl/tables";

  print("CREATE TABLE URL => $url");
  print("CREATE TABLE BODY => $data");

  final res = await post(url, data);

  print("CREATE TABLE RESPONSE => $res");

  return res != null;
}
// ===================== UPDATE TABLE (EDIT) =====================
static Future<bool> updateTable({
  required String tableId,
  required String tableNumber,
  required int seatingCapacity,
  required String status,
  required String section,
}) async {
  final url = "$baseUrl/tables/$tableId";

  final body = {
    "table_number": tableNumber,
    "seating_capacity": seatingCapacity,
    "status": status,
    "section": section,
  };

  print("UPDATE TABLE => $body");

  final res = await http.put(
    Uri.parse(url),
    headers: headers(),
    body: jsonEncode(body),
  );

  print("STATUS => ${res.statusCode}");
  print("BODY => ${res.body}");

  return res.statusCode == 200;
}

// ===================== DELETE TABLE =====================
static Future<bool> deleteTable(String tableId) async {
  final url = "$baseUrl/tables/$tableId";

  print("DELETE TABLE => $url");

  final res = await http.delete(
    Uri.parse(url),
    headers: headers(),
  );

  print("STATUS => ${res.statusCode}");

  return res.statusCode == 200 || res.statusCode == 204;
}

// ===================== MARK TABLE AS AVAILABLE =====================
// ONLY FOR CLEANING TABLES
static Future<bool> markTableAsAvailable(String tableId) async {
  final url = "$baseUrl/tables/$tableId/mark-available";

  print("MARK TABLE AVAILABLE => $url");

  final res = await http.post(
    Uri.parse(url),
    headers: headers(),
  );

  print("STATUS => ${res.statusCode}");
  print("BODY => ${res.body}");

  return res.statusCode == 200;
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
// ============================================================
// OCCUPIED TABLE FLOW (WEB UI MATCH)
// ============================================================

//  Get table status (Available / Occupied / Cleaning)
static Future<Map<String, dynamic>?> getTableStatus(int tableId) async {
  final url = "$baseUrl/tables/$tableId/status";

  print("GET TABLE STATUS => $url");

  final res = await get(url);

  if (res is Map<String, dynamic>) return res;
  return null;
}

//  Check existing order for a table
static Future<Map<String, dynamic>?> checkExistingOrderByTable(int tableId) async {
  final url = "$baseUrl/orders/table/$tableId/check-existing";

  print("CHECK EXISTING ORDER => $url");

  final res = await get(url);

  if (res is Map<String, dynamic>) return res;
  return null;
}
// ADD sub-order
static Future<Map<String, dynamic>?> addSubOrder(
  int orderId,
  List<Map<String, dynamic>> items,
  double totalAmount,
) async {
  final res = await post(
    "$baseUrl/orders/$orderId/add-sub-order",
    {
      "items": items,
      "total_amount": totalAmount,
      "send_to_kitchen": false,
    },
  );

  if (res is Map<String, dynamic>) return res;
  return null;
}
// SEND sub-order to kitchen
static Future<Map<String, dynamic>?> sendSubOrderToKitchen(
    int orderId,
    int subOrderId,
) async {
  final url =
      "$baseUrl/orders/$orderId/send-sub-order-to-kitchen?sub_order_id=$subOrderId";

  print("SEND SUB ORDER TO KITCHEN => $url");

  final res = await http.post(
    Uri.parse(url),
    headers: headers(),
  );

  print("SEND KITCHEN STATUS => ${res.statusCode}");
  print("SEND KITCHEN BODY => ${res.body}");

  if (res.statusCode == 200) {
    return jsonDecode(res.body);
  }

  throw Exception("Send to kitchen failed");
}
}
