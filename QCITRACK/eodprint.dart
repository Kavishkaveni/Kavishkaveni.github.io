import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:qcitrack/qc_track/core/api_service.dart';

class EODPrintPage extends StatefulWidget {
  final String eodId;

  const EODPrintPage({super.key, required this.eodId});

  @override
  State<EODPrintPage> createState() => _EODPrintPageState();
}

class _EODPrintPageState extends State<EODPrintPage> {
  static const Color eodColor = Color(0xFF8B3A2E);

  bool loading = true;
  Map<String, dynamic>? data;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    data = await ApiService.getEODInventoryById(widget.eodId);
    setState(() => loading = false);
  }

  // ---------- DATE FORMATTER ----------
  String _formatDate(dynamic value) {
    if (value == null) return "-";
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return DateFormat('yyyy-MM-dd HH:mm').format(dt);
    } catch (_) {
      return value.toString();
    }
  }

  // ---------- PDF BUILDER ----------
  Future<pw.Document> _buildPdf() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'Inventory Count Record',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),

              _pdfRow("Inventory ID", data!['inventory_id'] ?? data!['id']),
              _pdfRow("Product", data!['product_name']),
              _pdfRow("Batch Number", data!['batch_number'] ?? "N/A"),
              _pdfRow("Quantity In Hand", data!['quantity_in_hand']),
              _pdfRow("Expected Quantity", data!['expected_quantity']),
              _pdfRow("Status", data!['status']),
              _pdfRow("Last Counted", _formatDate(data!['last_counted_date'])),
              _pdfRow("Counted By", data!['counted_by']),
              _pdfRow("Location", data!['stock_location']),
              _pdfRow("Rack", data!['rack_number']),
              _pdfRow("Row", data!['row_number']),
              _pdfRow("Shelf", data!['shelf_number']),
              _pdfRow("Notes", data!['notes'] ?? "No notes"),
              _pdfRow("Created", _formatDate(data!['created_at'])),
              _pdfRow("Last Updated", _formatDate(data!['updated_at'])),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  pw.Widget _pdfRow(String label, dynamic value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 150,
            child: pw.Text(
              "$label:",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(
            child: pw.Text(value?.toString() ?? "-"),
          ),
        ],
      ),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: eodColor,
        title: const Text("Inventory Details"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  _uiRow("Inventory ID", data!['inventory_id'] ?? data!['id']),
                  _uiRow("Product", data!['product_name']),
                  _uiRow("Batch Number", data!['batch_number']),
                  _uiRow("Quantity In Hand", data!['quantity_in_hand']),
                  _uiRow("Expected Quantity", data!['expected_quantity']),
                  _uiRow("Status", data!['status']),
                  _uiRow(
                    "Last Counted",
                    _formatDate(data!['last_counted_date']),
                  ),
                  _uiRow("Counted By", data!['counted_by']),
                  _uiRow("Location", data!['stock_location']),
                  _uiRow("Rack", data!['rack_number']),
                  _uiRow("Row", data!['row_number']),
                  _uiRow("Shelf", data!['shelf_number']),
                  _uiRow("Notes", data!['notes']),
                  _uiRow("Created", _formatDate(data!['created_at'])),
                  _uiRow("Last Updated", _formatDate(data!['updated_at'])),
                ],
              ),
            ),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: eodColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
              icon: const Icon(Icons.print),
              label: const Text("Print"),
              onPressed: () async {
                final pdf = await _buildPdf();
                await Printing.layoutPdf(
                  onLayout: (_) => pdf.save(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _uiRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              "$label:",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value?.toString() ?? "-"),
          ),
        ],
      ),
    );
  }
}
