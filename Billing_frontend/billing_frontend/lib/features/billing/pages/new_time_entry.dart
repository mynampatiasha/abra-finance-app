// ============================================================================
// NEW TIME ENTRY SCREEN — Time Tracking Module
// ============================================================================
// File: lib/screens/billing/pages/new_time_entry.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/timesheet_service.dart';
import '../../../../core/services/project_service.dart';
import '../../../../app/config/api_config.dart';

const Color _teNavy   = Color(0xFF1e3a8a);
const Color _teGreen  = Color(0xFF27AE60);
const Color _teBlue   = Color(0xFF2980B9);
const Color _teOrange = Color(0xFFE67E22);
const Color _teRed    = Color(0xFFE74C3C);

class NewTimeEntryScreen extends StatefulWidget {
  final String? entryId;
  const NewTimeEntryScreen({Key? key, this.entryId}) : super(key: key);
  @override
  State<NewTimeEntryScreen> createState() => _NewTimeEntryScreenState();
}

class _NewTimeEntryScreenState extends State<NewTimeEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false, _isSaving = false;

  // ── all projects / staff ───────────────────────────────────────────────────
  List<Project>             _allProjects = [];
  List<ProjectTask>         _projectTasks = [];
  List<ProjectStaff>        _projectStaff = [];
  List<Map<String, dynamic>> _allStaff    = [];
  bool _loadingProjects = true, _loadingStaff = true;

  // ── form fields ────────────────────────────────────────────────────────────
  Project?        _selectedProject;
  ProjectTask?    _selectedTask;
  String?         _selectedUserId, _selectedUserName, _selectedUserEmail;
  DateTime        _date         = DateTime.now();
  double          _hours        = 0;
  bool            _isBillable   = true;
  final _hoursCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _loadStaffList();
    if (widget.entryId != null) _loadEntry();
  }

  @override
  void dispose() { _hoursCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  Future<void> _loadProjects() async {
    setState(() => _loadingProjects = true);
    try {
      final resp = await ProjectService.getProjects(status: 'Active', limit: 200);
      if (mounted) setState(() { _allProjects = resp.projects; _loadingProjects = false; });
    } catch (_) { setState(() => _loadingProjects = false); }
  }

  Future<void> _loadStaffList() async {
    setState(() => _loadingStaff = true);
    try {
      // Re-use same billing_users endpoint
      final prefs = await _getPrefs();
      final token = prefs['token'] ?? '';
      final base  = prefs['base'] ?? '';
      final url   = '$base/api/finance/users';
      final resp  = await _httpGet(url, token);
      if (resp['success'] == true && mounted) {
        setState(() { _allStaff = List<Map<String, dynamic>>.from(resp['data'] ?? []); _loadingStaff = false; });
      } else { setState(() => _loadingStaff = false); }
    } catch (_) { setState(() => _loadingStaff = false); }
  }

  Future<Map<String, String>> _getPrefs() async {
    final p = await SharedPreferences.getInstance();
    return {
      'token': p.getString('finance_jwt_token') ?? p.getString('jwt_token') ?? '',
      'base':  ApiConfig.baseUrl,
    };
  }

  Future<Map<String, dynamic>> _httpGet(String url, String token) async {
    final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});
    return json.decode(res.body) as Map<String, dynamic>;
  }

  Future<void> _loadEntry() async {
    setState(() => _isLoading = true);
    try {
      final entry = await TimesheetService.getTimesheet(widget.entryId!);
      // Find matching project
      if (_allProjects.isNotEmpty) {
        final proj = _allProjects.firstWhere((p) => p.id == entry.projectId, orElse: () => _allProjects.first);
        _setProject(proj);
        if (entry.taskId.isNotEmpty) {
          final task = _projectTasks.firstWhere((t) => t.taskId == entry.taskId, orElse: () => _projectTasks.first);
          _selectedTask = task;
        }
      }
      setState(() {
        _selectedUserId   = entry.userId;
        _selectedUserName = entry.userName;
        _selectedUserEmail = entry.userEmail;
        _date             = entry.date;
        _hours            = entry.hours;
        _hoursCtrl.text   = entry.hours.toStringAsFixed(2);
        _isBillable       = entry.isBillable;
        _notesCtrl.text   = entry.notes;
        _isLoading = false;
      });
    } catch (e) { setState(() => _isLoading = false); _showError('Failed to load entry: $e'); }
  }

  void _setProject(Project p) {
    setState(() {
      _selectedProject  = p;
      _projectTasks     = p.tasks.where((t) => t.status == 'Active').toList();
      _projectStaff     = p.staff;
      _selectedTask     = null;
      // If billing method is Staff Hours, pre-select staff from project staff if available
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProject == null) { _showError('Please select a project'); return; }
    final hours = double.tryParse(_hoursCtrl.text) ?? 0;
    if (hours <= 0) { _showError('Hours must be greater than 0'); return; }

    setState(() => _isSaving = true);
    try {
      final data = {
        'projectId':   _selectedProject!.id,
        'projectName': _selectedProject!.projectName,
        'taskId':      _selectedTask?.taskId ?? '',
        'taskName':    _selectedTask?.taskName ?? '',
        'userId':      _selectedUserId ?? '',
        'userName':    _selectedUserName ?? '',
        'userEmail':   _selectedUserEmail ?? '',
        'date':        _date.toIso8601String(),
        'hours':       hours,
        'isBillable':  _isBillable,
        'notes':       _notesCtrl.text.trim(),
      };

      if (widget.entryId != null) {
        await TimesheetService.updateTimeEntry(widget.entryId!, data);
      } else {
        await TimesheetService.createTimeEntry(data);
      }

      _showSuccess(widget.entryId != null ? 'Time entry updated!' : 'Time logged successfully!');
      if (mounted) Navigator.pop(context, true);
    } catch (e) { _showError(e.toString()); }
    finally    { setState(() => _isSaving = false); }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: _teRed, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: _teGreen, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(widget.entryId != null ? 'Edit Time Entry' : 'Log Time', style: const TextStyle(fontSize: 16)),
        backgroundColor: _teNavy, foregroundColor: Colors.white,
        actions: [
          Padding(padding: const EdgeInsets.only(right: 12), child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check, size: 16),
            label: Text(_isSaving ? 'Saving…' : 'Save Entry'),
            style: ElevatedButton.styleFrom(backgroundColor: _teGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
          )),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680),
              child: SingleChildScrollView(padding: const EdgeInsets.all(20),
                child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // ── Project ────────────────────────────────────────────────
                  _section('Project & Task', Icons.folder_outlined, _teNavy, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Project *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50))),
                    const SizedBox(height: 6),
                    _loadingProjects
                        ? const SizedBox(height: 50, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                        : DropdownButtonFormField<Project>(
                            value: _selectedProject,
                            decoration: _dec('Select Project', Icons.folder_outlined),
                            items: _allProjects.map((p) => DropdownMenuItem(value: p, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text(p.projectName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(p.customerName, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            ]))).toList(),
                            onChanged: (p) { if (p != null) _setProject(p); },
                            validator: (v) => v == null ? 'Project required' : null,
                          ),
                    if (_selectedProject != null && _projectTasks.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text('Task (Optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50))),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<ProjectTask?>(
                        value: _selectedTask,
                        decoration: _dec('Select Task', Icons.task_outlined),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('No specific task')),
                          ..._projectTasks.map((t) => DropdownMenuItem(value: t, child: Text(t.taskName, overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (t) => setState(() => _selectedTask = t),
                      ),
                    ],
                    if (_selectedProject != null && _projectTasks.isEmpty) ...[
                      const SizedBox(height: 8), Text('No tasks assigned to this project', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ])),
                  const SizedBox(height: 16),

                  // ── Staff ──────────────────────────────────────────────────
                  _section('Staff Member', Icons.person_outline, _teBlue, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Staff Member (Optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50))),
                    const SizedBox(height: 6),
                    _loadingStaff
                        ? const SizedBox(height: 50, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                        : DropdownButtonFormField<String>(
                            value: _selectedUserId,
                            decoration: _dec('Select Staff Member', Icons.person_outline),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Not assigned')),
                              ..._allStaff.map((u) {
                                final id   = u['_id']?.toString() ?? '';
                                final name = u['name']?.toString() ?? '';
                                final orgs = u['organizations'] as List? ?? [];
                                final role = orgs.isNotEmpty ? (orgs.first['role']?.toString() ?? 'staff') : 'staff';
                                return DropdownMenuItem(value: id, child: Row(children: [
                                  CircleAvatar(radius: 12, backgroundColor: _teNavy, child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                                  const SizedBox(width: 8),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)), Text(role, style: TextStyle(fontSize: 11, color: Colors.grey[600]))])),
                                ]));
                              }),
                            ],
                            onChanged: (v) {
                              if (v == null) { setState(() { _selectedUserId = null; _selectedUserName = null; _selectedUserEmail = null; }); return; }
                              final user = _allStaff.firstWhere((u) => u['_id']?.toString() == v, orElse: () => {});
                              setState(() { _selectedUserId = v; _selectedUserName = user['name']?.toString() ?? ''; _selectedUserEmail = user['email']?.toString() ?? ''; });
                            },
                          ),
                  ])),
                  const SizedBox(height: 16),

                  // ── Date & Hours ───────────────────────────────────────────
                  _section('Date & Time', Icons.schedule_outlined, _teOrange, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Date *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50))),
                        const SizedBox(height: 6),
                        InkWell(onTap: () async {
                          final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
                          if (d != null) setState(() => _date = d);
                        }, child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8), color: const Color(0xFFF7F9FC)),
                            child: Row(children: [const Icon(Icons.calendar_today, size: 16, color: _teNavy), const SizedBox(width: 8), Text(DateFormat('dd MMM yyyy').format(_date), style: const TextStyle(fontWeight: FontWeight.w500))]))),
                      ])),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Hours *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50))),
                        const SizedBox(height: 6),
                        TextFormField(controller: _hoursCtrl, decoration: _dec('e.g. 8 or 2.5', Icons.timer_outlined),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (v) => setState(() => _hours = double.tryParse(v) ?? 0),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              final h = double.tryParse(v);
                              if (h == null || h <= 0) return 'Must be > 0';
                              if (h > 24) return 'Max 24 hrs/day';
                              return null;
                            }),
                      ])),
                    ]),
                    const SizedBox(height: 14),
                    Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFF7F9FC), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Billable', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          Text(_isBillable ? 'This time will be included in invoices' : 'Non-billable — excluded from invoices', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ]),
                        Switch(value: _isBillable, onChanged: (v) => setState(() => _isBillable = v), activeColor: _teGreen),
                      ])),
                  ])),
                  const SizedBox(height: 16),

                  // ── Notes ──────────────────────────────────────────────────
                  _section('Notes', Icons.notes_outlined, Colors.grey, Column(children: [
                    TextFormField(controller: _notesCtrl, decoration: _dec('What did you work on? (Optional)', Icons.notes_outlined), maxLines: 4),
                  ])),
                  const SizedBox(height: 16),

                  // ── Summary ────────────────────────────────────────────────
                  Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: _teNavy.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: _teNavy.withOpacity(0.15))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Entry Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _teNavy)),
                      const SizedBox(height: 12),
                      if (_selectedProject != null) _summaryRow('Project', _selectedProject!.projectName),
                      if (_selectedTask != null) _summaryRow('Task', _selectedTask!.taskName),
                      if (_selectedUserName != null) _summaryRow('Staff', _selectedUserName!),
                      _summaryRow('Date', DateFormat('dd MMM yyyy').format(_date)),
                      _summaryRow('Hours', '${_hours.toStringAsFixed(2)} hrs'),
                      _summaryRow('Billable', _isBillable ? 'Yes' : 'No'),
                      const Divider(height: 20, thickness: 1.5),
                      _summaryRow('Est. Amount', _selectedProject != null ? _estimateAmount() : '—', bold: true),
                    ])),
                  const SizedBox(height: 24),

                  // ── Save Button ────────────────────────────────────────────
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _isSaving ? null : _save,
                    icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check, size: 18),
                    label: Text(_isSaving ? 'Saving…' : (widget.entryId != null ? 'Update Entry' : 'Save Entry'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: _teGreen, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 52), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(foregroundColor: _teNavy, side: const BorderSide(color: _teNavy), minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Cancel'))),
                  const SizedBox(height: 20),
                ]))),
            )),
    );
  }

  String _estimateAmount() {
    if (_selectedProject == null || _hours <= 0) return '—';
    switch (_selectedProject!.billingMethod) {
      case 'Fixed Cost':             return 'Fixed: ₹${_selectedProject!.fixedAmount.toStringAsFixed(2)}';
      case 'Based on Project Hours': return '₹${(_hours * _selectedProject!.hourlyRate).toStringAsFixed(2)}';
      case 'Based on Task Hours':    return _selectedTask != null ? '₹${(_hours * _selectedTask!.hourlyRate).toStringAsFixed(2)}' : 'Select task for estimate';
      case 'Based on Staff Hours': {
        if (_selectedUserId != null) {
          final member = _selectedProject!.staff.firstWhere((s) => s.userId == _selectedUserId, orElse: () => ProjectStaff(userId: '', name: '', email: '', role: 'staff', hourlyRate: 0));
          return '₹${(_hours * member.hourlyRate).toStringAsFixed(2)}';
        }
        return 'Select staff for estimate';
      }
      default: return '—';
    }
  }

  Widget _section(String title, IconData icon, Color color, Widget child) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)))]),
        const SizedBox(height: 14), child,
      ]));
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: bold ? 14 : 13, color: Colors.grey[700])),
      Flexible(child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontSize: bold ? 16 : 13, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: bold ? _teNavy : const Color(0xFF2C3E50)), overflow: TextOverflow.ellipsis)),
    ]));
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label, prefixIcon: Icon(icon, size: 18, color: Colors.grey[500]),
    filled: true, fillColor: const Color(0xFFF7F9FC),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _teNavy, width: 2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}