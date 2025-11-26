import 'package:flutter/material.dart';

import '../services/qctrade_api.dart';

class BranchSettingsPage extends StatefulWidget {
  const BranchSettingsPage({super.key});

  @override
  State<BranchSettingsPage> createState() => _BranchSettingsPageState();
}

class _BranchSettingsPageState extends State<BranchSettingsPage> {
  List<dynamic> branches = [];
  String? selectedBranchId;
  String? selectedBranchName;

  @override
  void initState() {
    super.initState();
    loadInitialData();
  }

  // ================================================================
  //                   LOAD BRANCH LIST + ACTIVE BRANCH
  // ================================================================
  Future<void> loadInitialData() async {
    await fetchBranches();
    await fetchActiveBranch();
  }

  // ------------------------ GET ALL BRANCHES -----------------------
  Future<void> fetchBranches() async {
    final res = await SettingsApi.getBranches();

    setState(() {
      branches = res;
    });
  }

  // ------------------------ GET ACTIVE BRANCH -----------------------
  Future<void> fetchActiveBranch() async {
    final data = await SettingsApi.getActiveBranch();

    if (data.isNotEmpty) {
      setState(() {
        selectedBranchId = data["id"];
        selectedBranchName = data["name"];
      });
    }
  }

  // ------------------------ SAVE ACTIVE BRANCH ---------------------
  Future<void> saveActiveBranch() async {
    if (selectedBranchId == null || selectedBranchName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a branch")),
      );
      return;
    }

    final ok = await SettingsApi.saveActiveBranch({
      "id": selectedBranchId,
      "name": selectedBranchName,
    }); // PUT settings

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Active branch set to: $selectedBranchName")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Branch")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Branch Management",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),

              const Text(
                "Select Active Branch",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    hint: const Text("Select a branch"),
                    value: selectedBranchId,
                    isExpanded: true,
                    items: branches.map((b) {
                      return DropdownMenuItem<String>(
                        value: b["id"].toString(),
                        child: Text(b["name"].toString()),
                      );
                    }).toList(),
                    onChanged: (value) {
                      final branch =
                          branches.firstWhere((b) => b["id"] == value);
                      setState(() {
                        selectedBranchId = branch["id"];
                        selectedBranchName = branch["name"];
                      });
                    },
                  ),
                ),
              ),

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: saveActiveBranch,
                  child: const Text("Set as Active Branch"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
