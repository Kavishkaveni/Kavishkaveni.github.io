import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/kds_admin_api.dart';
enum ActionMode { view, edit, toggle }

class WorkflowSettingsPage extends StatefulWidget {
  const WorkflowSettingsPage({super.key});

  @override
  State<WorkflowSettingsPage> createState() => _WorkflowSettingsPageState();
}

class _WorkflowSettingsPageState extends State<WorkflowSettingsPage> {
  bool loading = true;
  bool saving = false;

  // actions
  List<Map<String, dynamic>> actions = [];
  final Set<int> selectedActionIds = {};
  bool actionsBusy = false;
  ActionMode actionMode = ActionMode.view;

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
      actions.sort((a, b) => (a['sequence'] ?? 0).compareTo(b['sequence'] ?? 0));

      moduleNameCtrl.text = config['module_name'] ?? '';
      descriptionCtrl.text = config['module_description'] ?? '';

      showTable = config['show_table'] ?? false;
      showOrderType = config['show_order_type'] ?? false;
      showCustomer = config['show_customer'] ?? false;
      playSound = config['play_sound_on_new'] ?? false;

      configId = config['id'];
    } catch (_) {
      _snack('Failed to load workflow config');
    } finally {
      if (mounted) setState(() => loading = false);
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
    } catch (_) {
      _snack('Failed to save configuration');
    } finally {
      if (mounted) setState(() => saving = false);
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
          bottom: const TabBar(
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: [
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
                  // TAB 1 — Configuration
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isTablet ? 700 : double.infinity,
                        ),
                        child: _configCard(),
                      ),
                    ),
                  ),

                  // TAB 2 — Actions
                  _actionsTab(),

                  // TAB 3 — Preview (keep as placeholder)
                  _previewTab(),
                ],
              ),
      ),
    );
  }

  // ================= CONFIG CARD =================
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

  // ================= ACTIONS TAB =================
Widget _actionsTab() {
  final isTablet = MediaQuery.of(context).size.width >= 600;

  return Stack(
    children: [
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isTablet ? 700 : double.infinity,
            ),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // HEADER
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Workflow Actions',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (actionMode == ActionMode.view)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_horiz),
                            onSelected: _handleHeaderMenu,
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit Actions'),
                              ),
                              PopupMenuItem(
                                value: 'toggle',
                                child: Text('Enable / Disable'),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check, color: Colors.green),
                                onPressed: () => _handleHeaderMenu('save'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: () => _handleHeaderMenu('cancel'),
                              ),
                            ],
                          ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    if (actionsBusy) const LinearProgressIndicator(),

                    const SizedBox(height: 12),

                    // ACTION LIST
                    Column(
                      children: actions.map((action) {
                        final int id = action['id'];
                        final int index = _indexOfId(id);
                        final bool isActive = action['is_active'] == true;
                        final bool isTerminal = action['is_terminal'] == true;
                        final bool isSystem = action['is_system'] == true;

                        return InkWell(
  onTap: actionMode == ActionMode.view || isSystem
      ? null
      : () {
          setState(() {
            if (actionMode == ActionMode.edit) {
              selectedActionIds
                ..clear()
                ..add(id);
            } else {
              selectedActionIds.contains(id)
                  ? selectedActionIds.remove(id)
                  : selectedActionIds.add(id);
            }
          });
        },
  borderRadius: BorderRadius.circular(14),
  child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade300),
                            color: Colors.white,
                          ),
                          child: Row(
                            children: [
                              // CHECKBOX
                              if (actionMode != ActionMode.view)
                                Checkbox(
                                  value: selectedActionIds.contains(id),
                                  onChanged: isSystem
                                      ? null
                                      : (v) {
                                          setState(() {
                                            if (actionMode == ActionMode.edit) {
                                              selectedActionIds
                                                ..clear()
                                                ..add(id);
                                            } else {
                                              v == true
                                                  ? selectedActionIds.add(id)
                                                  : selectedActionIds.remove(id);
                                            }
                                          });
                                        },
                                ),

                              // SEQUENCE
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '${action['sequence']}',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),

                              const SizedBox(width: 10),

                              // ICON
                              Text(
                                action['icon'] ?? '',
                                style: const TextStyle(fontSize: 22),
                              ),

                              const SizedBox(width: 12),

                              // LABELS
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            action['label'] ?? '',
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                              color: isActive ? Colors.black : Colors.grey,
                                            ),
                                          ),
                                        ),

                                        if (isTerminal)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: const Text(
                                              'End',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                          ),

                                        if (!isActive)
                                          Container(
                                            margin: const EdgeInsets.only(left: 6),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade100,
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: const Text(
                                              'Disabled',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                          ),
                                      ],
                                    ),
                                    Text(
                                      action['action_key'] ?? '',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // MOVE UP / DOWN
                              Row(
                                children: [
                                  InkWell(
                                    onTap: (actionMode == ActionMode.view &&
        !isSystem &&
        index > 0)
    ? () => _moveAction(index, index - 1)
    : null,
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.arrow_upward, size: 18),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: (actionMode == ActionMode.view &&
        !isSystem &&
        index < actions.length - 1)
    ? () => _moveAction(index, index + 1)
    : null,
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.arrow_downward, size: 18),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),

      // ADD BUTTON
      Positioned(
        bottom: 20,
        right: 20,
        child: FloatingActionButton(
          onPressed: _openAddActionDialog,
          child: const Icon(Icons.add),
        ),
      ),
    ],
  );
}

  int _indexOfId(int id) => actions.indexWhere((a) => (a['id'] ?? -1) == id);

  Widget _previewTab() {
  final isTablet = MediaQuery.of(context).size.width >= 600;

  final previewActions = actions
      .where((a) => a['is_active'] == true)
      .toList()
    ..sort((a, b) => (a['sequence'] ?? 0).compareTo(b['sequence'] ?? 0));

  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isTablet ? 900 : double.infinity),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.remove_red_eye_outlined),
                    const SizedBox(width: 8),
                    Text(
                      'Workflow Preview',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (previewActions.isEmpty)
                  Text(
                    'No workflow actions',
                    style: GoogleFonts.poppins(color: Colors.grey),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final double itemWidth =
                          (constraints.maxWidth - 20) / 2;

                      return Wrap(
                        spacing: 20,
                        runSpacing: 30,
                        children: List.generate(previewActions.length, (i) {
                          final a = previewActions[i];
                          final icon = (a['icon'] ?? '').toString();
                          final label = (a['label'] ?? '').toString();

                          final bool isLast = i == previewActions.length - 1;
                          final bool isEvenRow = (i ~/ 2) % 2 == 0;
                          final bool isLeftItem = i % 2 == 0;

                          return SizedBox(
                            width: itemWidth,
                            child: Column(
                              children: [
                                _previewCard(
                                  icon: icon,
                                  label: label,
                                ),

                                if (!isLast)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: _buildArrow(
                                      isEvenRow: isEvenRow,
                                      isLeftItem: isLeftItem,
                                      hasNextInRow:
                                          i % 2 == 0 && i + 1 < previewActions.length,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _buildArrow({
  required bool isEvenRow,
  required bool isLeftItem,
  required bool hasNextInRow,
}) {
  // Horizontal arrows
  if (hasNextInRow) {
    return Icon(
      isEvenRow ? Icons.arrow_forward : Icons.arrow_back,
      size: 20,
      color: Colors.grey,
    );
  }

  // Vertical arrow (down)
  return const Icon(
    Icons.arrow_downward,
    size: 20,
    color: Colors.grey,
  );
}

Widget _previewCard({
  required String icon,
  required String label,
}) {
  return Container(
    width: 110,
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade300),
      color: Colors.white,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 26)),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

  // ================= HEADER MENU ACTIONS =================
  Future<void> _handleHeaderMenu(String action) async {
  // ENTER EDIT MODE
  if (action == 'edit') {
  setState(() {
    actionMode = ActionMode.edit;
    selectedActionIds.clear();
  });
  return;
}

if (action == 'toggle') {
  setState(() {
    actionMode = ActionMode.toggle;
    selectedActionIds.clear();
  });
  return;
}

  // CANCEL
  if (action == 'cancel') {
    setState(() {
      actionMode = ActionMode.view;
      selectedActionIds.clear();
    });
    return;
  }

  // SAVE
  if (action == 'save') {
    // EDIT MODE → OPEN EDIT DIALOG
    if (actionMode == ActionMode.edit) {
      if (selectedActionIds.length != 1) {
        _snack('Select exactly one action');
        return;
      }

      final id = selectedActionIds.first;
      final item = actions.firstWhere((a) => a['id'] == id);

      _editActionDialog(item);
      return; 
    }

    // TOGGLE MODE → (enable/disable logic later)
    if (actionMode == ActionMode.toggle) {
  if (selectedActionIds.isEmpty) {
    _snack('Select at least one action');
    return;
  }

  try {
    setState(() => actionsBusy = true);

    for (final id in selectedActionIds) {
  final item = actions.firstWhere((a) => a['id'] == id);

  if (item['is_system'] == true) {
    continue; // DO NOT toggle system actions
  }

  await KdsAdminApi.updateWorkflowAction(
    actionId: id,
    payload: {
  'id': item['id'],
  'action_key': item['action_key'],
  'label': item['label'],
  'icon': item['icon'],
  'color': item['color'],
  'sequence': item['sequence'],
  'is_terminal': item['is_terminal'],
  'is_active': !(item['is_active'] == true),
  'is_system': item['is_system'],
},
  );
}

    // reload actions to reflect latest state
    await _loadConfig();

    _snack('Actions updated');
  } catch (_) {
    _snack('Failed to update actions');
  } finally {
    setState(() {
      actionsBusy = false;
      actionMode = ActionMode.view;
      selectedActionIds.clear();
    });
  }

  return;
}
  }
}

  // ================= MOVE ACTION (REORDER API) =================
  Future<void> _moveAction(int from, int to) async {
  if (from < 0 || to < 0 || from >= actions.length || to >= actions.length) return;

  setState(() {
    final item = actions.removeAt(from);
    actions.insert(to, item);

    for (int i = 0; i < actions.length; i++) {
      actions[i]['sequence'] = i + 1;
    }
  });

  try {
    setState(() => actionsBusy = true);

    await KdsAdminApi.reorderWorkflowActions(
      actions: actions.map((a) => {
        'id': a['id'],               // REQUIRED
        'sequence': a['sequence'],   
      }).toList(),
    );

  } catch (e) {
    _snack('Failed to reorder actions');
  } finally {
    if (mounted) setState(() => actionsBusy = false);
  }
}

  // ================= EDIT DIALOG (PUT API) =================
  void _editActionDialog(Map<String, dynamic> item) {
  final labelCtrl = TextEditingController(text: item['label'] ?? '');
  final iconCtrl = TextEditingController(text: item['icon'] ?? '');
  final colorCtrl = TextEditingController(text: item['color'] ?? '');
  bool isTerminal = item['is_terminal'] == true;

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Edit Action'),
      content: StatefulBuilder(
        builder: (ctx, setD) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: iconCtrl,
              decoration: const InputDecoration(
                labelText: 'Icon',
                hintText: 'Example: ✅',
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: colorCtrl,
              decoration: const InputDecoration(
                labelText: 'Color (Hex)',
                hintText: '#20c997',
              ),
            ),

            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: isTerminal,
              onChanged: (v) => setD(() => isTerminal = v ?? false),
              title: const Text('End / Terminal State'),
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
            try {
              setState(() => actionsBusy = true);

              final updated = await KdsAdminApi.updateWorkflowAction(
                actionId: item['id'],
                payload: {
                  'label': labelCtrl.text.trim(),
                  'icon': iconCtrl.text.trim(),
                  'color': colorCtrl.text.trim(),
                  'is_terminal': isTerminal,
                },
              );

              setState(() {
                final i = actions.indexWhere((a) => a['id'] == item['id']);
                if (i != -1) actions[i] = updated;

                selectedActionIds.clear();
                actionMode = ActionMode.view;
              });

              if (mounted) Navigator.pop(context);
              _snack('Updated');
            } catch (_) {
              _snack('Failed to update action');
            } finally {
              if (mounted) setState(() => actionsBusy = false);
            }
          },
          child: const Text('Save Changes'),
        ),
      ],
    ),
  );
}
  // ================= ADD ACTION DIALOG (UI ONLY) =================
  void _openAddActionDialog() {
    // UI only (you said create API not ready)
    final actionKeyCtrl = TextEditingController();
    final labelCtrl = TextEditingController();

    bool endState = false;
    String selectedIcon = '✅';
    String selectedColor = '#6c757d';

    const iconOptions = ['🔔', '✅', '⚙️', '📦', '🚚', '🎉'];
    const colorOptions = {
      'Red': '#dc3545',
      'Yellow': '#ffc107',
      'Blue': '#17a2b8',
      'Green': '#20c997',
      'Gray': '#6c757d',
      'Purple': '#6f42c1',
      'Orange': '#fd7e14',
      'Teal': '#20c997',
    };

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Add Action'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: actionKeyCtrl,
                  decoration: const InputDecoration(labelText: 'Action Key'),
                ),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedIcon,
                  items: iconOptions
                      .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 18))))
                      .toList(),
                  onChanged: (v) => setD(() => selectedIcon = v ?? selectedIcon),
                  decoration: const InputDecoration(labelText: 'Icon'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedColor,
                  items: colorOptions.entries
                      .map((e) => DropdownMenuItem(value: e.value, child: Text(e.key)))
                      .toList(),
                  onChanged: (v) => setD(() => selectedColor = v ?? selectedColor),
                  decoration: const InputDecoration(labelText: 'Color'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: endState,
                  onChanged: (v) => setD(() => endState = v ?? false),
                  title: const Text('End State'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
  onPressed: () async {
    try {
      setState(() => actionsBusy = true);

      final created = await KdsAdminApi.createWorkflowAction(
        payload: {
          'action_key': actionKeyCtrl.text.trim(),
          'label': labelCtrl.text.trim(),
          'icon': selectedIcon,
          'color': selectedColor,
          'sequence': actions.length + 1,
          'is_terminal': endState,
          'is_active': true,
          'is_system': false,
        },
      );

      actions.add(created);

      if (mounted) Navigator.pop(ctx);
      _snack('Action added');
    } catch (_) {
      _snack('Failed to add action');
    } finally {
      setState(() => actionsBusy = false);
    }
  },
  child: const Text('Add'),
),
          ],
        ),
      ),
    );
  }

  // ================= HELPERS =================
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
