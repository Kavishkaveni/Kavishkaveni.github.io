import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../auth/auth_service.dart';

class KdsApi {
  static const String _baseUrl = 'https://qckds_backend.qcetl.com';

  // ================= COMMON HEADERS =================
  static Map<String, String> _headers() {
    if (AuthService.accessToken == null ||
        AuthService.tenantId == null ||
        AuthService.userId == null) {
      throw Exception('KDS API: Session not initialized');
    }

    return {
      'Authorization': 'Bearer ${AuthService.accessToken}',
      'X-Tenant-Id': AuthService.tenantId!,
      'X-User-Id': AuthService.userId!,
      'Content-Type': 'application/json',
    };
  }

  // ================= GET KITCHENS =================
  /// Fetch kitchens (auto-selected in UI)
  static Future<List<Map<String, dynamic>>> getKitchens() async {
    final url = Uri.parse('$_baseUrl/kitchen/');

    final response = await http.get(url, headers: _headers());

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch kitchens');
    }
  }

  // ================= GET ACTIVE ORDERS =================
  /// Fetch active orders for a kitchen
  static Future<List<Map<String, dynamic>>> getActiveOrders({
    required int kitchenId,
    bool excludeCompleted = true,
  }) async {
    final url = Uri.parse(
      '$_baseUrl/orders?kitchen_id=$kitchenId&exclude_completed=$excludeCompleted',
    );

    final response = await http.get(url, headers: _headers());

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch KDS orders');
    }
  }


  // ================= UPDATE ORDER STATUS =================
static Future<void> updateOrderStatus({
  required String orderId,
  required String status,
}) async {
  final url = Uri.parse('$_baseUrl/orders/$orderId');

  final response = await http.put(
    url,
    headers: _headers(),
    body: jsonEncode({
      'kds_status': status,
    }),
  );

  if (response.statusCode != 200) {
    print('UPDATE FAILED STATUS: ${response.statusCode}');
    print('UPDATE FAILED BODY: ${response.body}');
    throw Exception('Failed to update order status');
  }
}

  /* ================= NEXT STATUS HELPER =================
  /// Determines next KDS status based on current status
  static String? getNextStatus(String currentStatus) {
    switch (currentStatus) {
      case 'pending':
        return 'in-progress'; // Accept
      case 'in-progress':
        return 'completed'; 
      case 'preparing':
        return 'completed';
      default:
        return null; // completed or unknown
    }
  }

  ================= ADVANCE ORDER STATUS =================
  /// Advances order to next logical KDS state
  static Future<void> advanceOrderStatus({
    required String orderId,
    required String currentStatus,
  }) async {
    final nextStatus = getNextStatus(currentStatus);

    if (nextStatus == null) {
      throw Exception('No next status for $currentStatus');
    }

    await updateOrderStatus(
      orderId: orderId,
      status: nextStatus,
    );
  }*/

  // ================= WORKFLOW CONFIG (STAFF) =================
// ================= GET WORKFLOW CONFIG =================
static Future<Map<String, dynamic>> getWorkflowConfig() async {
  final url = Uri.parse('$_baseUrl/workflow/config');

  final response = await http.get(
    url,
    headers: _headers(),
  );

  if (response.statusCode != 200) {
    print('WF CONFIG STATUS: ${response.statusCode}');
    print('WF CONFIG BODY: ${response.body}');
    throw Exception('Failed to load workflow config');
  }

  final data = jsonDecode(response.body);

  return {
    'config': data['config'],
    'actions': List<Map<String, dynamic>>.from(data['actions'] ?? []),
  };
}
}
