import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/kds_api.dart';

class KdsOrderDetailPage extends StatefulWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> workflowActions;

  const KdsOrderDetailPage({
    super.key,
    required this.order,
    required this.workflowActions,
  });

  @override
  State<KdsOrderDetailPage> createState() => _KdsOrderDetailPageState();
}

class _KdsOrderDetailPageState extends State<KdsOrderDetailPage> {
  bool updating = false;
  late String currentStatus;

  @override
  void initState() {
    super.initState();
    currentStatus = (widget.order['kds_status'] ?? '').toString();
  }

@override
Widget build(BuildContext context) {
  final order = widget.order;
  final items = List<Map<String, dynamic>>.from(order['items'] ?? []);

  return Dialog(
    insetPadding: const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    child: SizedBox(
      width: 900, // web-like popup width
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(order),
            const SizedBox(height: 16),

            _customerSection(order),
            const SizedBox(height: 16),

            _itemsSection(items),
            const SizedBox(height: 16),

            _notesSection(),
            const SizedBox(height: 16),

            _statusSection(),
            const SizedBox(height: 16),

            _statusActionsSection(),
            const SizedBox(height: 16),

            _paymentSection(order),
            const SizedBox(height: 24),

            _actionButton(),
          ],
        ),
      ),
    ),
  );
}

  // ================= HEADER =================
  Widget _header(Map<String, dynamic> order) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Order #${order['id']}',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  // ================= CUSTOMER =================
  Widget _customerSection(Map<String, dynamic> order) {
    return _card(
      title: 'Customer Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _info('Name', order['customer_name']),
          _info('Phone', order['customer_phone']),
          _info('Address', order['customer_address']),
          _info('Order Type', order['order_type']),
        ],
      ),
    );
  }

  // ================= ITEMS =================
  Widget _itemsSection(List<Map<String, dynamic>> items) {
    return _card(
      title: 'Items',
      child: Column(
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text('${item['qty']}x',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item['name'],
                    style: GoogleFonts.poppins(),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ================= NOTES =================
  Widget _notesSection() {
    return _card(
      title: 'Notes',
      child: TextField(
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Add notes here...',
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  // ================= STATUS =================
  Widget _statusSection() {
    final actions = widget.workflowActions;

    return _card(
      title: 'Order Status',
      child: Column(
        children: actions.map((a) {
          final isDone =
              (a['sequence'] ?? 0) <= _currentSequence(currentStatus);

          return Row(
            children: [
              Icon(
                isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isDone
                    ? _colorFromHex(a['color'])
                    : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                a['label'],
                style: GoogleFonts.poppins(),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _statusActionsSection() {
  final actions = widget.workflowActions;

  return _card(
    title: 'Update Order Status',
    child: Column(
      children: actions.map((a) {
        final bool isCurrent = a['action_key'] == currentStatus;
        final bool isDone =
            (a['sequence'] ?? 0) < _currentSequence(currentStatus);

        // Do not show past or current states
        if (isDone || isCurrent) return const SizedBox();

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _colorFromHex(a['color']),
                side: BorderSide(color: _colorFromHex(a['color'])),
              ),
              onPressed: () => _openStatusConfirmPopup(a),
              child: Text('Mark as ${a['label']}'),
            ),
          ),
        );
      }).toList(),
    ),
  );
}

  // ================= PAYMENT =================
  Widget _paymentSection(Map<String, dynamic> order) {
    final status = (order['payment_status'] ?? '').toString();

    return _card(
      title: 'Payment',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            status.toUpperCase(),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: status == 'paid' ? Colors.green : Colors.red,
            ),
          ),
          if (status != 'paid')
            ElevatedButton(
              onPressed: () => _openPaymentPopup(context),
              child: const Text('Mark as Paid'),
            ),
        ],
      ),
    );
  }

  // ================= ACTION BUTTON =================
  Widget _actionButton() {
    final next = _nextAction();

    if (next == null) return const SizedBox();

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _colorFromHex(next['color']),
        ),
        onPressed: updating
            ? null
            : () async {
                setState(() => updating = true);

                await KdsApi.updateOrderStatus(
                  orderId: widget.order['id'].toString(),
                  status: next['action_key'],
                );

                Navigator.pop(context, true);
              },
        child: Text('${next['icon']} ${next['label']}'),
      ),
    );
  }

  // ================= HELPERS =================
  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }



  Widget _info(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label: ${value ?? '-'}',
        style: GoogleFonts.poppins(),
      ),
    );
  }

  Map<String, dynamic>? _nextAction() {
    final idx = widget.workflowActions
        .indexWhere((a) => a['action_key'] == currentStatus);

    if (idx == -1) return null;
    if (widget.workflowActions[idx]['is_terminal'] == true) return null;

    return widget.workflowActions[idx + 1];
  }

  int _currentSequence(String key) {
    final a = widget.workflowActions
        .firstWhere((e) => e['action_key'] == key, orElse: () => {});
    return a['sequence'] ?? 0;
  }

  Color _colorFromHex(String hex) {
    return Color(int.parse(hex.replaceFirst('#', '0xff')));
  }
  Future<void> _openPaymentPopup(BuildContext context) async {
  String paymentMethod = 'cash';
  final TextEditingController noteCtrl = TextEditingController();
  bool loading = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              width: 420,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---------- HEADER ----------
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Process Payment',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'Order #${widget.order['id']}',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),

                    const SizedBox(height: 16),

                    // ---------- PAYMENT METHOD ----------
                    Text(
                      'Payment Method',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),

                    DropdownButtonFormField<String>(
                      value: paymentMethod,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(
                            value: 'bank_transfer',
                            child: Text('Bank Transfer')),
                        DropdownMenuItem(
                            value: 'online', child: Text('Online Payment')),
                      ],
                      onChanged: (v) => setState(() => paymentMethod = v!),
                    ),

                    const SizedBox(height: 12),

                    // ---------- NOTE ----------
                    Text(
                      'Note (optional)',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),

                    TextField(
                      controller: noteCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Add a payment note...',
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ---------- ACTIONS ----------
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: loading
                              ? null
                              : () async {
                                  setState(() => loading = true);

                                  try {
                                    await KdsApi.updatePaymentStatus(
                                      orderId: widget.order['id'].toString(),
                                      paymentMethod: paymentMethod,
                                    );

                                    Navigator.pop(ctx); // close payment popup
                                    Navigator.pop(context, true); // refresh list
                                  } catch (e) {
                                    setState(() => loading = false);
                                  }
                                },
                          child: loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Confirm Payment'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
Future<void> _openStatusConfirmPopup(Map<String, dynamic> action) async {
  final TextEditingController noteCtrl = TextEditingController();
  bool loading = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Change Order Status',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Text(
                    'Change Order #${widget.order['id']} to "${action['label']}"',
                    style: GoogleFonts.poppins(),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: noteCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: loading
                            ? null
                            : () async {
                                setState(() => loading = true);

                                await KdsApi.updateOrderStatus(
                                  orderId:
                                      widget.order['id'].toString(),
                                  status: action['action_key'],
                                );

                                Navigator.pop(ctx); // close popup
                                Navigator.pop(context, true); // refresh list
                              },
                        child: loading
                            ? const CircularProgressIndicator()
                            : const Text('Confirm'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
}
