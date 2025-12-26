import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiService {
  // BASE URL FOR BRANCHES 
  static const String _baseUrl = 'http://qcitrack_backend.qcetl.com/api/v1';

  static String? accessToken;
  static String? tenantId;
  static String? branchId;
  static String? userId;

  // ---------------- LOGIN ----------------
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final url = Uri.parse(
        'https://qcauth_backend.qcetl.com/api/v1/auth/login');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'username': username.trim(),
        'password': password.trim(),
      },
    );

    print("LOGIN STATUS: ${response.statusCode}");
    print("LOGIN BODY: ${response.body}");

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      accessToken = data['access_token'];
      tenantId = data['tenant_id'];
      userId = data['user_id']?.toString();
      return data;
    } else {
      throw Exception("Login failed");
    }
  }

  static void extractUserIdFromToken() {
  final parts = accessToken!.split('.');
  final payload = jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))
  );

  userId = payload['user_id']; // UUID, NOT 2
}

  // ---------------- QC TRADE : GET USER BRANCHES ----------------
static Future<void> fetchAndSetDefaultBranch() async {
  final url = Uri.parse(
    'https://qctrade_backend.qcetl.com/api/v1/qc-branches',
  );

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'X-Tenant-Id': tenantId!,
      'X-User-Id': userId!,
    },
  );

  print("QC BRANCH STATUS: ${response.statusCode}");
  print("QC BRANCH BODY: ${response.body}");

  if (response.statusCode == 200) {
    final List branches = jsonDecode(response.body);

    if (branches.isNotEmpty) {
      branchId = branches.first['id'];
      print("QC DEFAULT BRANCH SET => $branchId");
      return;
    }
  }

  throw Exception("No QC Trade branches found");
}

  // ---------------- SIGNUP WITH TENANT ----------------
static Future<Map<String, dynamic>> signupWithTenant({
  required String firstName,
  required String lastName,
  required String email,
  required String username,
  required String password,
  required String confirmPassword,
  required String organizationName,
}) async {
  final url = Uri.parse(
    'https://qcauth_backend.qcetl.com/api/v1/auth/signup-with-tenant',
  );

  final organizationSlug = organizationName
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9\-]'), '');

  final payload = {
    'first_name': firstName,
    'last_name': lastName,
    'email': email,
    'username': username,
    'password': password,
    'confirm_password': confirmPassword,
    'organization': organizationName,
    'organization_slug': organizationSlug,
  };

  print("SIGNUP URL: $url");
  print("SIGNUP PAYLOAD: $payload");

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: jsonEncode(payload),
  );

  print("SIGNUP STATUS: ${response.statusCode}");
  print("SIGNUP BODY: ${response.body}");

  if (response.statusCode == 200 || response.statusCode == 201) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Signup failed");
  }
}


  // ---------------- GET ALL BRANCHES ----------------
  static Future<List<dynamic>> getBranches() async {
    final url = Uri.parse('$_baseUrl/branches/');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'x-tenant-id': tenantId!,
      },
    );

    print("GET BRANCHES STATUS: ${response.statusCode}");
    print("GET BRANCHES BODY: ${response.body}");

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to load branches");
    }
  }

  // ---------------- VIEW BRANCH ----------------
  static Future<Map<String, dynamic>> getBranchById(String id) async {
    final url = Uri.parse('$_baseUrl/branches/$id');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'x-tenant-id': tenantId!,
      },
    );

    print("VIEW BRANCH STATUS: ${response.statusCode}");
    print("VIEW BRANCH BODY: ${response.body}");

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to load branch info");
    }
  }

  // ---------------- CREATE BRANCH (FULL DEBUG) ----------------
static Future<Map<String, dynamic>> createBranch(Map<String, dynamic> data) async {
  print("");
  print("================ CREATE BRANCH DEBUG START ================");

  // Construct URL
  final url = Uri.parse('$_baseUrl/branches/');
  print("URL → $url");

  // Convert all fields to string (backend expects string)
  final payload = data.map((k, v) => MapEntry(k, v.toString()));
  print("PAYLOAD (MAP) → $payload");

  final jsonBody = jsonEncode(payload);
  print("PAYLOAD (JSON ENCODED) → $jsonBody");

  // Build headers
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $accessToken',
    'x-tenant-id': tenantId!,
    'Accept': 'application/json',
    'Connection': 'keep-alive',
  };

  print("HEADERS → $headers");

  http.Response response;

  try {
    print("SENDING REQUEST…");
    response = await http.post(url, headers: headers, body: jsonBody);
  } catch (e) {
    print("NETWORK ERROR → $e");
    throw Exception("Network error");
  }

  print("STATUS CODE → ${response.statusCode}");
  print("RESPONSE BODY RAW → ${response.body}");
  print("================ CREATE BRANCH DEBUG END ==================");
  print("");

  if (response.statusCode == 201 || response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to create branch");
  }
}

  // ---------------- UPDATE BRANCH ----------------
  static Future<Map<String, dynamic>> updateBranch(
      String id, Map<String, dynamic> data) async {
    final url = Uri.parse('$_baseUrl/branches/$id');

    final cleanData = data.map((k, v) => MapEntry(k, v.toString()));

    final response = await http.put(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'x-tenant-id': tenantId!,
      },
      body: jsonEncode(cleanData),
    );

    print("UPDATE BRANCH STATUS: ${response.statusCode}");
    print("UPDATE BRANCH BODY: ${response.body}");

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to update branch");
    }
  }

  // ---------------- DELETE BRANCH ----------------
  static Future<bool> deleteBranch(String id) async {
    final url = Uri.parse('$_baseUrl/branches/$id');

    final response = await http.delete(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'x-tenant-id': tenantId!,
      },
    );

    print("DELETE BRANCH STATUS: ${response.statusCode}");

    return response.statusCode == 200 || response.statusCode == 204;
  }

  // ---------------- PRINT URL ----------------
  static Future<String> getPrintUrl(String id) async {
    return 'https://qcitrack.qcetl.com/qcitrack/branches/$id/print';
  }

// ================= SUPPLIER APIs =================

// GET ALL SUPPLIERS (with optional search)
static Future<List<dynamic>> getSuppliers({String? search}) async {
  final uri = Uri.parse(
    search == null || search.isEmpty
        ? '$_baseUrl/suppliers/'
        : '$_baseUrl/suppliers/?search=$search',
  );

  final response = await http.get(
    uri,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET SUPPLIERS STATUS: ${response.statusCode}");
  print("GET SUPPLIERS BODY: ${response.body}");

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    return decoded is Map ? decoded['items'] ?? [] : decoded;
  } else {
    throw Exception("Failed to load suppliers");
  }
}

// GET SUPPLIER BY ID
static Future<Map<String, dynamic>> getSupplierById(String id) async {
  final url = Uri.parse('$_baseUrl/suppliers/$id');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("VIEW SUPPLIER STATUS: ${response.statusCode}");
  print("VIEW SUPPLIER BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load supplier");
  }
}

// CREATE SUPPLIER
static Future<Map<String, dynamic>> createSupplier(
    Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/suppliers/');

  final payload = data.map((k, v) => MapEntry(k, v.toString()));

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(payload),
  );

  print("CREATE SUPPLIER STATUS: ${response.statusCode}");
  print("CREATE SUPPLIER BODY: ${response.body}");

  if (response.statusCode == 201 || response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to create supplier");
  }
}

// UPDATE SUPPLIER
static Future<Map<String, dynamic>> updateSupplier(
    String id, Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/suppliers/$id');

  final payload = data.map((k, v) => MapEntry(k, v.toString()));

  final response = await http.put(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(payload),
  );

  print("UPDATE SUPPLIER STATUS: ${response.statusCode}");
  print("UPDATE SUPPLIER BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to update supplier");
  }
}

// DELETE SUPPLIER
static Future<bool> deleteSupplier(String id) async {
  final url = Uri.parse('$_baseUrl/suppliers/$id');

  final response = await http.delete(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("DELETE SUPPLIER STATUS: ${response.statusCode}");
  return response.statusCode == 200 || response.statusCode == 204;
}

// GET ALL PRODUCTS
static Future<List<dynamic>> getProducts() async {
  final url = Uri.parse('$_baseUrl/products/');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET PRODUCTS STATUS: ${response.statusCode}");
  print("GET PRODUCTS BODY: ${response.body}");

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    return decoded is Map ? decoded['items'] ?? [] : decoded;
  } else {
    throw Exception("Failed to load products");
  }
}
// ================= PURCHASE ORDER APIs =================

// GET ALL PURCHASE ORDERS
static Future<List<dynamic>> getPurchaseOrders({
  String? search,
  String? status,
  String? branchId,
}) async {
  final queryParams = <String, String>{};

  if (search != null && search.isNotEmpty) {
    queryParams['search'] = search;
  }
  if (status != null && status.isNotEmpty) {
    queryParams['status'] = status;
  }
  if (branchId != null && branchId.isNotEmpty) {
    queryParams['branch_id'] = branchId;
  }

  final uri = Uri.parse('$_baseUrl/purchase-orders/')
      .replace(queryParameters: queryParams);

  final response = await http.get(
    uri,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET PURCHASE ORDERS STATUS: ${response.statusCode}");
  print("GET PURCHASE ORDERS BODY: ${response.body}");

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    return decoded is Map ? decoded['items'] ?? [] : decoded;
  } else {
    throw Exception("Failed to load purchase orders");
  }
}

// GET PURCHASE ORDER BY ID
static Future<Map<String, dynamic>> getPurchaseOrderById(String id) async {
  final url = Uri.parse('$_baseUrl/purchase-orders/$id');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("VIEW PURCHASE ORDER STATUS: ${response.statusCode}");
  print("VIEW PURCHASE ORDER BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load purchase order");
  }
}

// CREATE PURCHASE ORDER
static Future<Map<String, dynamic>> createPurchaseOrder(
    Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/purchase-orders/');

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("CREATE PURCHASE ORDER STATUS: ${response.statusCode}");
  print("CREATE PURCHASE ORDER BODY: ${response.body}");

  if (response.statusCode == 201 || response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to create purchase order");
  }
}

// UPDATE PURCHASE ORDER
static Future<Map<String, dynamic>> updatePurchaseOrder(
    String id, Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/purchase-orders/$id');

  final response = await http.put(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("UPDATE PURCHASE ORDER STATUS: ${response.statusCode}");
  print("UPDATE PURCHASE ORDER BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to update purchase order");
  }
}

// DELETE PURCHASE ORDER
static Future<bool> deletePurchaseOrder(String id) async {
  final url = Uri.parse('$_baseUrl/purchase-orders/$id');

  final response = await http.delete(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("DELETE PURCHASE ORDER STATUS: ${response.statusCode}");

  return response.statusCode == 200 || response.statusCode == 204;
}

// ================= PURCHASE ORDER ITEM APIs =================

// -------------------------------------------------------------
// GET ALL PURCHASE ORDER ITEMS
// NOTE:
// Backend DOES NOT have /purchase-order-items endpoint.
// Correct logic:
// 1) Call GET /purchase-orders/
// 2) Extract & flatten items from each purchase order
// -------------------------------------------------------------
static Future<List<dynamic>> getPurchaseOrderItems({
  String? search,
  String? status,
}) async {
  final uri = Uri.parse('$_baseUrl/purchase-orders/');

  final response = await http.get(
    uri,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET PURCHASE ORDER ITEMS STATUS: ${response.statusCode}");
  print("GET PURCHASE ORDER ITEMS BODY: ${response.body}");

  if (response.statusCode != 200) {
    throw Exception("Failed to load purchase order items");
  }

  final decoded = jsonDecode(response.body);
  final List<dynamic> orders =
      decoded is Map ? (decoded['items'] ?? []) : decoded;

  // Flatten items from all purchase orders
  List<dynamic> allItems = [];

  for (final order in orders) {
    final List<dynamic> items = order['items'] ?? [];

    for (final item in items) {
      allItems.add({
        ...item,
        "purchase_order_id": order['id'],
        "purchase_order_number": order['id'], // shown in UI
        "supplier_name": order['supplier_name'],
        "branch_name": order['branch_name'],
        "order_status": order['status'],
        "order_date": order['order_date'],
      });
    }
  }

  // Optional filtering (same as React)
  return allItems.where((item) {
    final matchesSearch = search == null || search.isEmpty
        ? true
        : (item['product_name'] ?? '')
            .toString()
            .toLowerCase()
            .contains(search.toLowerCase());

    final matchesStatus = status == null || status.isEmpty
        ? true
        : item['status'] == status;

    return matchesSearch && matchesStatus;
  }).toList();
}

// -------------------------------------------------------------
// GET PURCHASE ORDER ITEM BY ID
// -------------------------------------------------------------
static Future<Map<String, dynamic>> getPurchaseOrderItemById(
    String itemId) async {
  final url = Uri.parse('$_baseUrl/purchase-orders/items/$itemId/');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("VIEW PO ITEM STATUS: ${response.statusCode}");
  print("VIEW PO ITEM BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load purchase order item");
  }
}

// -------------------------------------------------------------
// ADD ITEM TO PURCHASE ORDER
// -------------------------------------------------------------
static Future<Map<String, dynamic>> addPurchaseOrderItem(
    String purchaseOrderId, Map<String, dynamic> data) async {
  final url =
      Uri.parse('$_baseUrl/purchase-orders/$purchaseOrderId/items/');

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("ADD PO ITEM STATUS: ${response.statusCode}");
  print("ADD PO ITEM BODY: ${response.body}");

  if (response.statusCode == 201 || response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to add purchase order item");
  }
}

// =============================================================
// UPDATE PURCHASE ORDER ITEM  (FIXED – NO 307 ERROR)
// =============================================================
static Future<void> updatePurchaseOrderItem(
  String itemId,
  Map<String, dynamic> data,
) async {
  final url = Uri.parse(
    '$_baseUrl/purchase-orders/items/$itemId', // NO trailing slash
  );

  final response = await http.put(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("UPDATE PO ITEM STATUS: ${response.statusCode}");
  print("UPDATE PO ITEM BODY: ${response.body}");

  if (response.statusCode != 200 && response.statusCode != 204) {
    throw Exception("Failed to update purchase order item");
  }
}

// =============================================================
// DELETE PURCHASE ORDER ITEM  (FIXED – NO 307 ERROR)
// =============================================================
static Future<void> deletePurchaseOrderItem(String itemId) async {
  final url = Uri.parse(
    '$_baseUrl/purchase-orders/items/$itemId', // NO trailing slash
  );

  final response = await http.delete(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("DELETE PO ITEM STATUS: ${response.statusCode}");

  if (response.statusCode != 200 && response.statusCode != 204) {
    throw Exception("Failed to delete purchase order item");
  }
}

// ================= PRODUCT APIs =================

// ---------------- GET PRODUCT BY ID ----------------
static Future<Map<String, dynamic>> getProductById(String id) async {
  final url = Uri.parse('$_baseUrl/products/$id');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("VIEW PRODUCT STATUS: ${response.statusCode}");
  print("VIEW PRODUCT BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load product");
  }
}

// ---------------- CREATE PRODUCT (WITH IMAGE) ----------------
static Future<Map<String, dynamic>> createProduct(
  Map<String, dynamic> data,
) async {
  final url = Uri.parse('$_baseUrl/products');

  final request = http.MultipartRequest('POST', url);

  request.headers['Authorization'] = 'Bearer $accessToken';
  request.headers['x-tenant-id'] = tenantId!;

  // Add fields
  data.forEach((key, value) {
    if (value != null && value is! File) {
      request.fields[key] = value.toString();
    }
  });

  // Add image
  if (data['image'] != null && data['image'] is File) {
    request.files.add(
      await http.MultipartFile.fromPath(
        'image',
        data['image'].path,
      ),
    );
  }

  final response = await request.send();
  final body = await response.stream.bytesToString();

  print("CREATE PRODUCT STATUS: ${response.statusCode}");
  print("CREATE PRODUCT BODY: $body");

  if (response.statusCode == 201 || response.statusCode == 200) {
    return jsonDecode(body);
  } else {
    throw Exception("Failed to create product");
  }
}

// ---------------- UPDATE PRODUCT (WITH IMAGE) ----------------
static Future<Map<String, dynamic>> updateProduct(
  String id,
  Map<String, dynamic> data,
) async {
  final url = Uri.parse('$_baseUrl/products/$id');

  final request = http.MultipartRequest('PUT', url);

  request.headers['Authorization'] = 'Bearer $accessToken';
  request.headers['x-tenant-id'] = tenantId!;

  // Add fields
  data.forEach((key, value) {
    if (value != null && value is! File) {
      request.fields[key] = value.toString();
    }
  });

  // Add image (optional)
  if (data['image'] != null && data['image'] is File) {
    request.files.add(
      await http.MultipartFile.fromPath(
        'image',
        data['image'].path,
      ),
    );
  }

  final response = await request.send();
  final body = await response.stream.bytesToString();

  print("UPDATE PRODUCT STATUS: ${response.statusCode}");
  print("UPDATE PRODUCT BODY: $body");

  if (response.statusCode == 200) {
    return jsonDecode(body);
  } else {
    throw Exception("Failed to update product");
  }
}

// ---------------- DELETE PRODUCT ----------------
static Future<bool> deleteProduct(String id) async {
  final url = Uri.parse('$_baseUrl/products/$id');

  final response = await http.delete(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("DELETE PRODUCT STATUS: ${response.statusCode}");
  return response.statusCode == 200 || response.statusCode == 204;
}

// ---------------- GET PRODUCT CATEGORIES ----------------
static Future<List<dynamic>> getProductCategories() async {
  final url = Uri.parse('$_baseUrl/products/categories/all');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET PRODUCT CATEGORIES STATUS: ${response.statusCode}");
  print("GET PRODUCT CATEGORIES BODY: ${response.body}");

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    return decoded is Map ? decoded['items'] ?? [] : decoded;
  } else {
    throw Exception("Failed to load product categories");
  }
}

// =============================================================
// ================= PRODUCT CATEGORY APIs =====================
// =============================================================

// ---------------- CREATE PRODUCT CATEGORY (WITH IMAGE) ----------------
static Future<Map<String, dynamic>> createProductCategory(
  Map<String, dynamic> data,
) async {
  final url = Uri.parse('$_baseUrl/products/categories');

  final request = http.MultipartRequest('POST', url);

  // Headers
  request.headers['Authorization'] = 'Bearer $accessToken';
  request.headers['x-tenant-id'] = tenantId!;

  // Add fields
  data.forEach((key, value) {
    if (value != null && value is! File) {
      request.fields[key] = value.toString();
    }
  });

  // Add image (optional)
  if (data['image'] != null && data['image'] is File) {
    request.files.add(
      await http.MultipartFile.fromPath(
        'image',
        data['image'].path,
      ),
    );
  }

  final response = await request.send();
  final body = await response.stream.bytesToString();

  print("CREATE CATEGORY STATUS: ${response.statusCode}");
  print("CREATE CATEGORY BODY: $body");

  if (response.statusCode == 201 || response.statusCode == 200) {
    return jsonDecode(body);
  } else {
    throw Exception("Failed to create product category");
  }
}

// ---------------- UPDATE PRODUCT CATEGORY (WITH IMAGE) ----------------
static Future<Map<String, dynamic>> updateProductCategory(
  String id,
  Map<String, dynamic> data,
) async {
  final url = Uri.parse('$_baseUrl/products/categories/$id');

  final request = http.MultipartRequest('PUT', url);

  // Headers
  request.headers['Authorization'] = 'Bearer $accessToken';
  request.headers['x-tenant-id'] = tenantId!;

  // Add fields
  data.forEach((key, value) {
    if (value != null && value is! File) {
      request.fields[key] = value.toString();
    }
  });

  // Add image (optional)
  if (data['image'] != null && data['image'] is File) {
    request.files.add(
      await http.MultipartFile.fromPath(
        'image',
        data['image'].path,
      ),
    );
  }

  final response = await request.send();
  final body = await response.stream.bytesToString();

  print("UPDATE CATEGORY STATUS: ${response.statusCode}");
  print("UPDATE CATEGORY BODY: $body");

  if (response.statusCode == 200) {
    return jsonDecode(body);
  } else {
    throw Exception("Failed to update product category");
  }
}

// ---------------- DELETE PRODUCT CATEGORY ----------------
static Future<bool> deleteProductCategory(String id) async {
  final url = Uri.parse('$_baseUrl/products/categories/$id');

  final response = await http.delete(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("DELETE CATEGORY STATUS: ${response.statusCode}");

  return response.statusCode == 200 || response.statusCode == 204;
}

// =============================================================
// ================= OPERATION LOG APIs ========================
// =============================================================

// ---------------- GET ALL OPERATION LOGS ----------------
static Future<List<dynamic>> getOperationLogs({
  String? search,
  String? operationType,
  String? entityType,
  String? status,
  String? startDate, // ISO string
  String? endDate,   // ISO string
}) async {
  final queryParams = <String, String>{};

  if (search != null && search.isNotEmpty) {
    queryParams['search'] = search;
  }
  if (operationType != null && operationType.isNotEmpty) {
    queryParams['operation_type'] = operationType;
  }
  if (entityType != null && entityType.isNotEmpty) {
    queryParams['entity_type'] = entityType;
  }
  if (status != null && status.isNotEmpty) {
    queryParams['status'] = status;
  }
  if (startDate != null && startDate.isNotEmpty) {
    queryParams['date_from'] = startDate;
  }
  if (endDate != null && endDate.isNotEmpty) {
    queryParams['date_to'] = endDate;
  }

  final uri = Uri.parse('$_baseUrl/operation-logs')
      .replace(queryParameters: queryParams);

  final response = await http.get(
    uri,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET OPERATION LOGS STATUS: ${response.statusCode}");
  print("GET OPERATION LOGS BODY: ${response.body}");

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    return decoded is Map ? decoded['items'] ?? [] : decoded;
  } else {
    throw Exception("Failed to load operation logs");
  }
}

// ---------------- GET OPERATION LOG BY ID ----------------
static Future<Map<String, dynamic>> getOperationLogById(String id) async {
  final url = Uri.parse('$_baseUrl/operation-logs/$id');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("VIEW OPERATION LOG STATUS: ${response.statusCode}");
  print("VIEW OPERATION LOG BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load operation log");
  }
}

// ---------------- GET OPERATION TYPES ----------------
static Future<List<String>> getOperationTypes() async {
  final url = Uri.parse('$_baseUrl/operation-logs/operation-types');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET OPERATION TYPES STATUS: ${response.statusCode}");
  print("GET OPERATION TYPES BODY: ${response.body}");

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    return List<String>.from(decoded);
  } else {
    throw Exception("Failed to load operation types");
  }
}

// ---------------- GET ENTITY TYPES ----------------
static Future<List<String>> getEntityTypes() async {
  final url = Uri.parse('$_baseUrl/operation-logs/entity-types');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET ENTITY TYPES STATUS: ${response.statusCode}");
  print("GET ENTITY TYPES BODY: ${response.body}");

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    return List<String>.from(decoded);
  } else {
    throw Exception("Failed to load entity types");
  }
}
// =============================================================
// ======================= STOCK APIs ===========================
// =============================================================

// ---------------- GET ALL STOCKS ----------------
// Used for:
// - Stock List Page
// - Search
// - Filter by Branch, Product, Status
static Future<List<dynamic>> getStocks({
  String? search,
  String? branchId,
  String? productId,
  String? status,
}) async {
  final queryParams = <String, String>{};

  if (search != null && search.isNotEmpty) {
    queryParams['search'] = search;
  }
  if (branchId != null && branchId.isNotEmpty) {
    queryParams['branch_id'] = branchId;
  }
  if (productId != null && productId.isNotEmpty) {
    queryParams['product_id'] = productId;
  }
  if (status != null && status.isNotEmpty) {
    queryParams['status'] = status;
  }

  final uri = Uri.parse('$_baseUrl/stocks/')
      .replace(queryParameters: queryParams);

  final response = await http.get(
    uri,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET STOCKS STATUS: ${response.statusCode}");
  print("GET STOCKS BODY: ${response.body}");

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    return decoded is Map ? decoded['items'] ?? [] : decoded;
  } else {
    throw Exception("Failed to load stocks");
  }
}

// ---------------- GET STOCK BY ID ----------------
// Used for:
// - View Stock
// - Edit Stock
static Future<Map<String, dynamic>> getStockById(String id) async {
  final url = Uri.parse('$_baseUrl/stocks/$id');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("VIEW STOCK STATUS: ${response.statusCode}");
  print("VIEW STOCK BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load stock");
  }
}

// ---------------- CREATE STOCK ----------------
static Future<Map<String, dynamic>> createStock(
    Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/stocks/');

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("CREATE STOCK STATUS: ${response.statusCode}");
  print("CREATE STOCK BODY: ${response.body}");

  if (response.statusCode == 201 || response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to create stock");
  }
}

// ---------------- UPDATE STOCK ----------------
static Future<Map<String, dynamic>> updateStock(
    String id, Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/stocks/$id');

  final response = await http.put(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("UPDATE STOCK STATUS: ${response.statusCode}");
  print("UPDATE STOCK BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to update stock");
  }
}

// ---------------- DELETE STOCK ----------------
static Future<bool> deleteStock(String id) async {
  final url = Uri.parse('$_baseUrl/stocks/$id');

  final response = await http.delete(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("DELETE STOCK STATUS: ${response.statusCode}");

  return response.statusCode == 200 || response.statusCode == 204;
}

// ---------------- PRODUCTS FOR DROPDOWN ----------------
static Future<List<dynamic>> getProductsForDropdown() async {
  final url = Uri.parse('$_baseUrl/products/');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    final items = decoded is Map ? decoded['items'] ?? [] : decoded;

    return items.map((p) {
      return {
        'id': p['id'],
        'name': p['name'],
      };
    }).toList();
  } else {
    throw Exception("Failed to load products");
  }
}
// ---------------- STOCK LOCATIONS ----------------
static Future<List<String>> getStockLocations() async {
  final url = Uri.parse('$_baseUrl/stocks/metadata/locations');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);

    return (decoded as List)
        .map<String>((e) => e['location'].toString())
        .toList();
  } else {
    return [];
  }
}

// =============================================================
// ==================== EOD INVENTORY APIs =====================
// =============================================================

// ---------------- GET ALL EOD INVENTORIES ----------------
// Used for: EOD List Page
static Future<List<dynamic>> getEODInventories({
  String? branchId,
  String? location,
  String? status,
}) async {
  final queryParams = <String, String>{};

  if (branchId != null && branchId.isNotEmpty) {
    queryParams['branch_id'] = branchId;
  }
  if (location != null && location.isNotEmpty) {
    queryParams['location'] = location;
  }
  if (status != null && status.isNotEmpty) {
    queryParams['status'] = status;
  }

  final uri = Uri.parse('$_baseUrl/eod-inventory')
      .replace(queryParameters: queryParams);

  final response = await http.get(
    uri,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET EOD INVENTORIES STATUS: ${response.statusCode}");
  print("GET EOD INVENTORIES BODY: ${response.body}");

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    return decoded is Map ? decoded['items'] ?? [] : decoded;
  } else {
    throw Exception("Failed to load EOD inventories");
  }
}

// ---------------- GET EOD INVENTORY BY ID ----------------
// Used for: View / Edit / Print
static Future<Map<String, dynamic>> getEODInventoryById(String id) async {
  final url = Uri.parse('$_baseUrl/eod-inventory/$id');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("VIEW EOD INVENTORY STATUS: ${response.statusCode}");
  print("VIEW EOD INVENTORY BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load EOD inventory");
  }
}

// ---------------- CREATE EOD INVENTORY ----------------
static Future<Map<String, dynamic>> createEODInventory(
    Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/eod-inventory/');

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("CREATE EOD INVENTORY STATUS: ${response.statusCode}");
  print("CREATE EOD INVENTORY BODY: ${response.body}");

  if (response.statusCode == 201 || response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to create EOD inventory");
  }
}

// ---------------- UPDATE EOD INVENTORY ----------------
static Future<Map<String, dynamic>> updateEODInventory(
    String id, Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/eod-inventory/$id');

  final response = await http.put(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("UPDATE EOD INVENTORY STATUS: ${response.statusCode}");
  print("UPDATE EOD INVENTORY BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to update EOD inventory");
  }
}

// ---------------- DELETE EOD INVENTORY ----------------
static Future<bool> deleteEODInventory(String id) async {
  final url = Uri.parse('$_baseUrl/eod-inventory/$id');

  final response = await http.delete(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("DELETE EOD INVENTORY STATUS: ${response.statusCode}");

  return response.statusCode == 200 || response.statusCode == 204;
}

// ---------------- GET EOD LOCATIONS BY BRANCH ----------------
static Future<List<String>> getEODLocationsByBranch(String branchId) async {
  final url =
      Uri.parse('$_baseUrl/eod-inventory/locations/$branchId');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET EOD LOCATIONS STATUS: ${response.statusCode}");
  print("GET EOD LOCATIONS BODY: ${response.body}");

  if (response.statusCode == 200) {
    return List<String>.from(jsonDecode(response.body));
  } else {
    return [];
  }
}

// ---------------- GET EOD DISCREPANCIES ----------------
static Future<List<dynamic>> getEODDiscrepancies(String branchId) async {
  final url =
      Uri.parse('$_baseUrl/eod-inventory/discrepancies/$branchId');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET EOD DISCREPANCIES STATUS: ${response.statusCode}");
  print("GET EOD DISCREPANCIES BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load EOD discrepancies");
  }
}

// ---------------- RECONCILE EOD INVENTORY ----------------
static Future<void> reconcileEODInventory(
    Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/eod-inventory/reconcile');

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("RECONCILE EOD STATUS: ${response.statusCode}");
  print("RECONCILE EOD BODY: ${response.body}");

  if (response.statusCode != 200 &&
      response.statusCode != 201) {
    throw Exception("Failed to reconcile EOD inventory");
  }
}
// =============================================================
// ================= STOCK MOVEMENT APIs =======================
// =============================================================

// ---------------- GET ALL STOCK MOVEMENTS ----------------
static Future<List<dynamic>> getStockMovements({
  String? search,
  String? movementType, // IN / OUT
}) async {
  final queryParams = <String, String>{};

  if (search != null && search.isNotEmpty) {
    queryParams['search'] = search;
  }
  if (movementType != null && movementType.isNotEmpty) {
    queryParams['movement_type'] = movementType;
  }

  final uri = Uri.parse('$_baseUrl/stock-movements')
      .replace(queryParameters: queryParams);

  final response = await http.get(
    uri,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET STOCK MOVEMENTS STATUS: ${response.statusCode}");
  print("GET STOCK MOVEMENTS BODY: ${response.body}");

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    return decoded is Map ? decoded['items'] ?? [] : decoded;
  } else {
    throw Exception("Failed to load stock movements");
  }
}

// ---------------- GET STOCK MOVEMENT BY ID ----------------
static Future<Map<String, dynamic>> getStockMovementById(String id) async {
  final url = Uri.parse('$_baseUrl/stock-movements/$id');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("VIEW STOCK MOVEMENT STATUS: ${response.statusCode}");
  print("VIEW STOCK MOVEMENT BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load stock movement");
  }
}

// ---------------- CREATE STOCK MOVEMENT ----------------
static Future<Map<String, dynamic>> createStockMovement(
    Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/stock-movements/');

  print("CREATE STOCK MOVEMENT PAYLOAD: $data");

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("CREATE STOCK MOVEMENT STATUS: ${response.statusCode}");
  print("CREATE STOCK MOVEMENT BODY: ${response.body}");

  if (response.statusCode == 201 || response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to create stock movement");
  }
}

// ---------------- GET STOCK DETAILS FOR MOVEMENT ----------------
static Future<Map<String, dynamic>> getStockDetailsForMovement(
    String stockId) async {
  final url =
      Uri.parse('$_baseUrl/stock-movements/stock-details/$stockId');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET STOCK DETAILS STATUS: ${response.statusCode}");
  print("GET STOCK DETAILS BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load stock details");
  }
}

// ---------------- BRANCH TRANSFER ----------------
static Future<Map<String, dynamic>> createBranchTransfer(
    Map<String, dynamic> data) async {
  final url =
      Uri.parse('$_baseUrl/stock-movements/branch-transfer');

  print("CREATE BRANCH TRANSFER PAYLOAD: $data");

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("BRANCH TRANSFER STATUS: ${response.statusCode}");
  print("BRANCH TRANSFER BODY: ${response.body}");

  if (response.statusCode == 201 || response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to create branch transfer");
  }
}
// =============================================================
// ================= RETURN MANAGEMENT APIs ====================
// =============================================================

// ---------------- GET ALL RETURNS ----------------
static Future<List<dynamic>> getInventoryReturns({
  String? search,
  String? status,
  String? startDate,
  String? endDate,
}) async {
  final queryParams = <String, String>{};

  if (search != null && search.isNotEmpty) {
    queryParams['search'] = search;
  }
  if (status != null && status.isNotEmpty) {
    queryParams['status'] = status;
  }
  if (startDate != null && startDate.isNotEmpty) {
    queryParams['start_date'] = startDate;
  }
  if (endDate != null && endDate.isNotEmpty) {
    queryParams['end_date'] = endDate;
  }

  final uri = Uri.parse('$_baseUrl/inventory-returns')
      .replace(queryParameters: queryParams);

  final response = await http.get(
    uri,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    return decoded is Map ? decoded['items'] ?? [] : decoded;
  } else {
    throw Exception("Failed to load returns");
  }
}

// ---------------- GET RETURN BY ID ----------------
static Future<Map<String, dynamic>> getInventoryReturnById(String id) async {
  final url = Uri.parse('$_baseUrl/inventory-returns/$id');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("VIEW RETURN STATUS: ${response.statusCode}");
  print("VIEW RETURN BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load return");
  }
}

// ---------------- CREATE RETURN ----------------
static Future<Map<String, dynamic>> createInventoryReturn(
    Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/inventory-returns/');

  print("CREATE RETURN PAYLOAD: $data");

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("CREATE RETURN STATUS: ${response.statusCode}");
  print("CREATE RETURN BODY: ${response.body}");

  if (response.statusCode == 201 || response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to create return");
  }
}

// ---------------- UPDATE RETURN ----------------
static Future<Map<String, dynamic>> updateInventoryReturn(
    String id, Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/inventory-returns/$id');

  print("UPDATE RETURN PAYLOAD: $data");

  final response = await http.put(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("UPDATE RETURN STATUS: ${response.statusCode}");
  print("UPDATE RETURN BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to update return");
  }
}

// ---------------- DELETE RETURN ----------------
static Future<bool> deleteInventoryReturn(String id) async {
  final url = Uri.parse('$_baseUrl/inventory-returns/$id');

  final response = await http.delete(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("DELETE RETURN STATUS: ${response.statusCode}");

  return response.statusCode == 200 || response.statusCode == 204;
}

// ---------------- RETURN STATISTICS ----------------
static Future<Map<String, dynamic>> getInventoryReturnStatistics() async {
  final url = Uri.parse('$_baseUrl/inventory-returns/statistics');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("RETURN STATS STATUS: ${response.statusCode}");
  print("RETURN STATS BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load return statistics");
  }
}

// ---------------- GET STOCK DETAILS FOR RETURN ----------------
static Future<Map<String, dynamic>> getStockDetailsForReturn(
    String stockId) async {
  final url = Uri.parse(
    '$_baseUrl/inventory-returns/stock-details/$stockId',
  );

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET RETURN STOCK DETAILS STATUS: ${response.statusCode}");
  print("GET RETURN STOCK DETAILS BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load stock details for return");
  }
}
// =============================================================
// ================= INVENTORY AUDIT APIs ======================
// =============================================================

// ---------------- GET ALL INVENTORY AUDITS ----------------
// Used for:
// - Inventory Audit List Page
// - Initial Load
// - After Create / Update / Delete
static Future<List<dynamic>> getInventoryAudits() async {
  final url = Uri.parse('$_baseUrl/inventory-audits/');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET INVENTORY AUDITS STATUS: ${response.statusCode}");
  print("GET INVENTORY AUDITS BODY: ${response.body}");

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    return decoded is Map ? decoded['items'] ?? [] : decoded;
  } else {
    throw Exception("Failed to load inventory audits");
  }
}

// ---------------- GET INVENTORY AUDIT BY ID ----------------
// Used for:
// - View Inventory Audit
// - Edit Inventory Audit
static Future<Map<String, dynamic>> getInventoryAuditById(String id) async {
  final url = Uri.parse('$_baseUrl/inventory-audits/$id');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("VIEW INVENTORY AUDIT STATUS: ${response.statusCode}");
  print("VIEW INVENTORY AUDIT BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to load inventory audit");
  }
}

// ---------------- CREATE INVENTORY AUDIT ----------------
// Used for:
// - Create New Inventory Audit
static Future<Map<String, dynamic>> createInventoryAudit(
    Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/inventory-audits/');

  print("CREATE INVENTORY AUDIT PAYLOAD: $data");

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("CREATE INVENTORY AUDIT STATUS: ${response.statusCode}");
  print("CREATE INVENTORY AUDIT BODY: ${response.body}");

  if (response.statusCode == 201 || response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to create inventory audit");
  }
}

// ---------------- UPDATE INVENTORY AUDIT ----------------
// Used for:
// - Update Inventory Audit
static Future<Map<String, dynamic>> updateInventoryAudit(
    String id, Map<String, dynamic> data) async {
  final url = Uri.parse('$_baseUrl/inventory-audits/$id');

  print("UPDATE INVENTORY AUDIT PAYLOAD: $data");

  final response = await http.put(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(data),
  );

  print("UPDATE INVENTORY AUDIT STATUS: ${response.statusCode}");
  print("UPDATE INVENTORY AUDIT BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to update inventory audit");
  }
}

// ---------------- DELETE INVENTORY AUDIT ----------------
// Used for:
// - Delete Inventory Audit
static Future<bool> deleteInventoryAudit(String id) async {
  final url = Uri.parse('$_baseUrl/inventory-audits/$id');

  final response = await http.delete(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("DELETE INVENTORY AUDIT STATUS: ${response.statusCode}");

  return response.statusCode == 200 || response.statusCode == 204;
}

// ---------------- GET INVENTORY AUDIT STATUS OPTIONS ----------------
// Used for:
// - Status dropdown (Create / Edit)
static Future<List<String>> getInventoryAuditStatusOptions() async {
  final url = Uri.parse('$_baseUrl/inventory-audits/status-options');

  final response = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
  );

  print("GET AUDIT STATUS OPTIONS STATUS: ${response.statusCode}");
  print("GET AUDIT STATUS OPTIONS BODY: ${response.body}");

  if (response.statusCode == 200) {
    return List<String>.from(jsonDecode(response.body));
  } else {
    throw Exception("Failed to load inventory audit status options");
  }
}

// ---------------- ADVANCED SEARCH INVENTORY AUDITS ----------------
// Used for:
// - Product Filter
// - Branch Filter
// - Status Filter
static Future<List<dynamic>> searchInventoryAudits(
    Map<String, dynamic> filters) async {
  final url = Uri.parse('$_baseUrl/inventory-audits/search');

  print("SEARCH INVENTORY AUDITS PAYLOAD: $filters");

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'x-tenant-id': tenantId!,
    },
    body: jsonEncode(filters),
  );

  print("SEARCH INVENTORY AUDITS STATUS: ${response.statusCode}");
  print("SEARCH INVENTORY AUDITS BODY: ${response.body}");

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    return decoded is Map ? decoded['items'] ?? [] : decoded;
  } else {
    throw Exception("Failed to search inventory audits");
  }
}
}
