import 'dart:convert';

import 'package:http/http.dart' as http;

/// =============================================================
/// AUTH + SESSION SERVICE
/// Handles:
/// - Login (QCAuth)
/// - JWT parsing
/// - QCTrade branch fetch
/// - Session variables
/// =============================================================
class AuthService {
  // ================= SESSION VARIABLES =================
  static String? accessToken;
  static String? tenantId;
  static String? userId;
  static String? branchId;
  static String? refreshToken;

  // ================= LOGIN =================
  static Future<Map<String, dynamic>> login({
  required String username,
  required String password,
}) async {
  final url = Uri.parse(
    'https://qcauth_backend.qcetl.com/api/v1/auth/login',
  );

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

    // STORE SESSION LOCALLY (IMPORTANT)
    accessToken = data['access_token'];
    tenantId = data['tenant_id'];
    userId = data['userId']?.toString(); 
    refreshToken = data['refresh_token'];

    // DEBUG (TEMP)
    print("SESSION AFTER LOGIN:");
    print("Token: $accessToken");
    print("Tenant: $tenantId");
    print("User: $userId");

    return data;
  } else {
    throw Exception("Login failed");
  }
}

  // ================= QC TRADE : GET USER BRANCH =================
  static Future<void> fetchAndSetDefaultBranch() async {
    if (accessToken == null || tenantId == null || userId == null) {
      throw Exception("Session not initialized");
    }

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
        print("QC DEFAULT BRANCH SET → $branchId");
        return;
      }
    }

    throw Exception("No QCTrade branches found");
  }

  // ================= SIGNUP WITH TENANT =================
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

  // ================= LOGOUT =================
  static void clearSession() {
    accessToken = null;
    tenantId = null;
    userId = null;
    branchId = null;
  }

  // ================= SESSION CHECK =================
  static bool isLoggedIn() {
    return accessToken != null &&
        tenantId != null &&
        userId != null &&
        branchId != null;
  }
}
