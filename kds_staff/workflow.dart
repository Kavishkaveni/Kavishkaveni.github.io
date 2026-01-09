import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/kds_admin_api.dart';

class WorkflowSettingsPage extends StatefulWidget {
  const WorkflowSettingsPage({super.key});

  @override
  State<WorkflowSettingsPage> createState() => _WorkflowSettingsPageState();
}

class _WorkflowSettingsPageState extends State<WorkflowSettingsPage> {
  bool loading = true;
  bool saving = false;

  List<Map<String, dynamic>> actions = [];
  bool actionsLoading = true;

  final TextEditingController moduleNameCtrl = TextEditingController();
  final TextEditingController descriptionCtrl = TextEditingController();

  bool showTable = false;
  bool showOrderType = false;
  bool showCustomer = false;
  bool playSound = false;

  int? configId;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  // ================= LOAD CONFIG =================
  Future<void> _loadConfig() async {
    try {
      final res = await KdsAdminApi.getWorkflowConfig();
      final config = res['config'];
      final List actionList = res['actions'] ?? [];
      actions = actionList.cast<Map<String, dynamic>>();

      moduleNameCtrl.text = config['module_name'] ?? '';
      descriptionCtrl.text = config['module_description'] ?? '';

      showTable = config['show_table'] ?? false;
      showOrderType = config['show_order_type'] ?? false;
      showCustomer = config['show_customer'] ?? false;
      playSound = config['play_sound_on_new'] ?? false;

      configId = config['id'];
    } catch (e) {
      _snack('Failed to load workflow config');
    } finally {
      setState(() => loading = false);
    }
  }

  // ================= SAVE CONFIG =================
  Future<void> _saveConfig() async {
    try {
      setState(() => saving = true);

      await KdsAdminApi.updateWorkflowConfig(
        payload: {
          'id': configId,
          'module_name': moduleNameCtrl.text.trim(),
          'module_description': descriptionCtrl.text.trim(),
          'show_table': showTable,
          'show_order_type': showOrderType,
          'show_customer': showCustomer,
          'play_sound_on_new': playSound,
        },
      );

      _snack('Configuration saved');
    } catch (e) {
      _snack('Failed to save configuration');
    } finally {
      setState(() => saving = false);
    }
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return DefaultTabController(
  length: 3,
  child: Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
  backgroundColor: Colors.white,
  elevation: 0,
  title: Text(
    'Workflow Settings',
    style: GoogleFonts.poppins(
      color: Colors.black,
      fontWeight: FontWeight.w600,
    ),
  ),
  iconTheme: const IconThemeData(color: Colors.black),

  bottom: TabBar(
    labelColor: Colors.black,
    unselectedLabelColor: Colors.grey,
    indicatorColor: Colors.blue,
    tabs: const [
      Tab(text: 'Configuration'),
      Tab(text: 'Actions'),
      Tab(text: 'Preview'),
    ],
  ),
),
      body: loading
    ? const Center(child: CircularProgressIndicator())
    : TabBarView(
        children: [
          // TAB 1 — Module Configuration 
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width >= 600
                      ? 700
                      : double.infinity,
                ),
                child: _configCard(),
              ),
            ),
          ),
          _actionsTab(),

          // TAB 3 — Workflow Preview 
          _previewTab(),
        ],
      ),
    ),
    );
  }

  Widget _previewTab() {
  // sort by sequence
  final previewActions = List<Map<String, dynamic>>.from(actions)
    ..sort((a, b) => a['sequence'].compareTo(b['sequence']));

  return Padding(
    padding: const EdgeInsets.all(16),
    child: Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            Text(
              'Workflow Preview',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),

            // PREVIEW FLOW 
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: previewActions.map((a) {
                final disabled = a['is_active'] == false;

                return Container(
                  width: 120,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 10,
                  ),
                  decoration: BoxDecoration(
                    color: disabled
                        ? Colors.grey.shade300
                        : _hexColor(a['color']),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        a['icon'],
                        style: const TextStyle(fontSize: 22),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        a['label'],
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: disabled
                              ? Colors.black54
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _configCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Module Configuration',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),

            _field('Module Name', moduleNameCtrl),
            _field('Description', descriptionCtrl),

            const SizedBox(height: 12),
            _switch('Show Table Number', showTable, (v) => setState(() => showTable = v)),
            _switch('Show Order Type', showOrderType, (v) => setState(() => showOrderType = v)),
            _switch('Show Customer Info', showCustomer, (v) => setState(() => showCustomer = v)),
            _switch('Sound on New Order', playSound, (v) => setState(() => playSound = v)),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving ? null : _saveConfig,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(saving ? 'Saving...' : 'Save Configuration'),
              ),
            ),
          ],
        ),
      ),
    );
  }

Widget _actionsTab() {
  bool selectMode = false;
  String? actionMode; // 'edit' | 'toggle'
  Set<int> selectedIds = {};

  return StatefulBuilder(
    builder: (context, setLocal) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              // HEADER
              ListTile(
  title: Text(
    'Workflow Actions',
    style: GoogleFonts.poppins(
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
  ),
                trailing: selectMode
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () {
                              setLocal(() {
                                selectMode = false;
                                actionMode = null;
                                selectedIds.clear();
                              });
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () async {
                              if (selectedIds.isEmpty) return;

                              if (actionMode == 'edit') {
                                _editActionDialog(
                                  actions.firstWhere(
                                    (a) => a['id'] == selectedIds.first,
                                  ),
                                );
                              }

                              if (actionMode == 'toggle') {
                                for (final id in selectedIds) {
                                  final item =
                                      actions.firstWhere((a) => a['id'] == id);
                                  await KdsAdminApi.updateWorkflowAction(
                                    actionId: id,
                                    payload: {
                                      ...item,
                                      'is_active': !(item['is_active'] ?? true),
                                    },
                                  );
                                }
                                await _loadConfig();
                                setLocal(() {
                                  selectMode = false;
                                  actionMode = null;
                                  selectedIds.clear();
                                });
                              }
                              if (actionMode == 'delete') {
  if (selectedIds.isEmpty) return;

  final id = selectedIds.first;
  final item = actions.firstWhere((a) => a['id'] == id);

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Delete Action'),
      content: Text(
        'Do you want to delete "${item['label']}"?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () async {
            await KdsAdminApi.deleteWorkflowAction(actionId: id);
            Navigator.pop(context);
            await _loadConfig();
            setLocal(() {
              selectMode = false;
              actionMode = null;
              selectedIds.clear();
            });
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
                            },
                          ),
                        ],
                      )
                    : PopupMenuButton<String>(
                        onSelected: (v) {
                          setLocal(() {
                            selectMode = true;
                            actionMode = v;
                          });
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(
                              value: 'toggle', child: Text('Disable / Enable')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
              ),
              const Divider(),

              // LIST
              Expanded(
                child: ListView.builder(
                  itemCount: actions.length,
                  itemBuilder: (c, i) {
                    final a = actions[i];
                    final disabled = a['is_active'] == false;

                    return ListTile(
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (selectMode)
                            Checkbox(
                              value: selectedIds.contains(a['id']),
                              onChanged: (v) {
                                setLocal(() {
                                  v == true
                                      ? selectedIds.add(a['id'])
                                      : selectedIds.remove(a['id']);
                                });
                              },
                            )
                          else
                            Text('${a['sequence']}'),
                          const SizedBox(width: 8),
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _hexColor(a['color']),
                              shape: BoxShape.circle,
                            ),
                            child: Text(a['icon'],
                                style: const TextStyle(fontSize: 18)),
                          ),
                        ],
                      ),
                      title: Text(
                        a['label'],
                        style: TextStyle(
                          color: disabled ? Colors.grey : Colors.black,
                        ),
                      ),
                      subtitle:
                          disabled ? const Text('Disabled') : Text(a['action_key']),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_upward),
                            onPressed:
                                i == 0 ? null : () => _moveAction(i, i - 1),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_downward),
                            onPressed: i == actions.length - 1
                                ? null
                                : () => _moveAction(i, i + 1),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // ADD
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: FloatingActionButton(
                    onPressed: _addActionDialog,
                    child: const Icon(Icons.add),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _addActionDialog() {
  final keyCtrl = TextEditingController();
  final labelCtrl = TextEditingController();
  final iconCtrl = TextEditingController();
  bool isTerminal = false;

  final colorMap = {
    'Gray': '#6c757d',
    'Yellow': '#ffc107',
    'Red': '#dc3545',
    'Blue': '#0d6efd',
    'Green': '#198754',
    'Purple': '#6f42c1',
    'Orange': '#fd7e14',
    'Teal': '#20c997',
  };

  String selectedColorName = 'Gray';
  String selectedColor = colorMap[selectedColorName]!;

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Add Action'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyCtrl,
              decoration: const InputDecoration(labelText: 'Action Key'),
            ),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            TextField(
              controller: iconCtrl,
              decoration: const InputDecoration(labelText: 'Icon (emoji)'),
            ),
            DropdownButtonFormField<String>(
              value: selectedColorName,
              decoration: const InputDecoration(labelText: 'Color'),
              items: colorMap.keys
                  .map((k) => DropdownMenuItem(
                        value: k,
                        child: Text(k),
                      ))
                  .toList(),
              onChanged: (v) {
                selectedColorName = v!;
                selectedColor = colorMap[v]!;
              },
            ),
            CheckboxListTile(
              value: isTerminal,
              onChanged: (v) => isTerminal = v ?? false,
              title: const Text('End / Terminate State'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final actionKey = keyCtrl.text
                .trim()
                .toLowerCase()
                .replaceAll(' ', '-');

            final maxSeq = actions
                .map((a) => a['sequence'] as int)
                .fold(0, (p, c) => c > p ? c : p);

            await KdsAdminApi.createWorkflowAction(
              payload: {
                'action_key': actionKey,
                'label': labelCtrl.text.trim(),
                'icon': iconCtrl.text.trim(),
                'color': selectedColor,
                'sequence': maxSeq + 1,
                'is_terminal': isTerminal,
                'is_active': true,
                'is_system': false, 
              },
            );

            Navigator.pop(context);
            await _loadConfig();
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}


  Widget _field(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _moveAction(int from, int to) async {
  setState(() {
    final temp = actions[from];
    actions[from] = actions[to];
    actions[to] = temp;

    for (int i = 0; i < actions.length; i++) {
      actions[i]['sequence'] = i + 1;
    }
  });

  try {
    final updated = await KdsAdminApi.reorderWorkflowActions(
      actions: actions,
    );
    setState(() => actions = updated);
  } catch (_) {
    _snack('Failed to reorder actions');
  }
}

Future<void> _handleActionMenu(
  String action,
  Map<String, dynamic> item,
) async {
  if (action == 'toggle') {
    try {
      final updated = await KdsAdminApi.updateWorkflowAction(
        actionId: item['id'],
        payload: {
          ...item,
          'is_active': !(item['is_active'] ?? true),
        },
      );

      setState(() {
        final i = actions.indexWhere((a) => a['id'] == item['id']);
        actions[i] = updated;
      });
    } catch (_) {
      _snack('Failed to update action');
    }
  }

  if (action == 'edit') {
    _editActionDialog(item);
  }
}

void _editActionDialog(Map<String, dynamic> item) {
  final labelCtrl = TextEditingController(text: item['label']);
  final iconCtrl = TextEditingController(text: item['icon']);
  bool isTerminal = item['is_terminal'] ?? false;

  final colorMap = {
    'Gray': '#6c757d',
    'Yellow': '#ffc107',
    'Red': '#dc3545',
    'Blue': '#0d6efd',
    'Green': '#198754',
    'Purple': '#6f42c1',
    'Orange': '#fd7e14',
    'Teal': '#20c997',
  };

  String selectedColor = item['color'];
  String selectedColorName =
      colorMap.entries.firstWhere((e) => e.value == selectedColor).key;

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Edit Action'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: 'Label')),
            TextField(
                controller: iconCtrl,
                decoration: const InputDecoration(labelText: 'Icon (emoji)')),
            DropdownButtonFormField<String>(
              value: selectedColorName,
              decoration: const InputDecoration(labelText: 'Color'),
              items: colorMap.keys
                  .map((k) =>
                      DropdownMenuItem(value: k, child: Text(k)))
                  .toList(),
              onChanged: (v) {
                selectedColorName = v!;
                selectedColor = colorMap[v]!;
              },
            ),
            CheckboxListTile(
              value: isTerminal,
              onChanged: (v) => isTerminal = v ?? false,
              title: const Text('End / Terminate State'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            await KdsAdminApi.updateWorkflowAction(
              actionId: item['id'],
              payload: {
                ...item,
                'label': labelCtrl.text.trim(),
                'icon': iconCtrl.text.trim(),
                'color': selectedColor,
                'is_terminal': isTerminal,
              },
            );
            Navigator.pop(context);
            await _loadConfig();
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
Color _hexColor(String hex) {
  return Color(int.parse(hex.replaceFirst('#', '0xff')));
}
}
