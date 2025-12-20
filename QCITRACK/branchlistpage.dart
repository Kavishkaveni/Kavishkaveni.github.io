import 'package:flutter/material.dart';
import 'package:qcitrack/qc_track/core/api_service.dart';

import 'branch_form_page.dart';
import 'branch_print_page.dart';

class BranchListPage extends StatefulWidget {
  const BranchListPage({super.key});

  @override
  State<BranchListPage> createState() => _BranchListPageState();
}

class _BranchListPageState extends State<BranchListPage> {
  List<dynamic> branches = [];
  List<dynamic> filteredBranches = []; 
  bool loading = true;
  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    loadBranches();
  }

  Future<void> loadBranches() async {
    setState(() => loading = true);

    try {
      final data = await ApiService.getBranches();
      setState(() {
        branches = data;
        filteredBranches = data; 
      });
    } catch (e) {
      print("ERROR loading branches: $e");
    }

    setState(() => loading = false);
  }

  void _deleteBranch(String id) async {
    final confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Branch"),
        content: const Text("Are you sure you want to delete this branch?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ApiService.deleteBranch(id);
      loadBranches();
    }
  }

  void _openPrint(String id) async {
    try {
      final data = await ApiService.getBranchById(id);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BranchPrintPage(branch: data),
        ),
      );
    } catch (e) {
      print("PRINT ERROR: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Branch Management"),
        backgroundColor: Colors.blueAccent,
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueAccent,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const BranchFormPage(),
            ),
          ).then((_) => loadBranches());
        },
        child: const Icon(Icons.add),
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [

                  // SEARCH BAR (ONLY FILTER BY BRANCH ID)
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Search by Branch Number",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  searchQuery = "";
                                  filteredBranches = branches;
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),

                    onChanged: (text) {
                      setState(() {
                        searchQuery = text;

                        if (text.isEmpty) {
                          filteredBranches = branches;
                        } else {
                          filteredBranches = branches.where((b) {
                            final id = b["id"]?.toString().toLowerCase() ?? "";
                            return id.contains(text.toLowerCase());
                          }).toList();
                        }
                      });
                    },
                  ),

                  const SizedBox(height: 12),

                  // LIST (USE FILTERED LIST NOW)
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredBranches.length,
                      itemBuilder: (_, index) {
                        final b = filteredBranches[index];

                        return Card(
                          elevation: 3,
                          child: ListTile(
                            title: Text(b["name"] ?? "Unknown Branch"),
                            subtitle: Text(b["location"] ?? "Unknown Location"),

                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [

                                // VIEW BUTTON
                                IconButton(
                                  icon: const Icon(Icons.visibility),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => BranchFormPage(
                                          branchId: b["id"],
                                          viewOnly: true,
                                        ),
                                      ),
                                    );
                                  },
                                ),

                                // EDIT BUTTON
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => BranchFormPage(
                                          branchId: b["id"],
                                        ),
                                      ),
                                    ).then((_) => loadBranches());
                                  },
                                ),

                                // DELETE BUTTON
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteBranch(b["id"]),
                                ),

                                // PRINT BUTTON
                                IconButton(
                                  icon: const Icon(Icons.print),
                                  onPressed: () => _openPrint(b["id"]),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  )
                ],
              ),
            ),
    );
  }
}
