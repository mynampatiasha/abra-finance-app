// ============================================================================
// NEW PROJECT SCREEN — UPDATED (Task deadline + status + completion + staff)
// ============================================================================
// File: lib/screens/billing/pages/new_project.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/project_service.dart';
import '../../../../core/services/billing_customers_service.dart';
import '../../../../app/config/api_config.dart';

const Color _npNavy   = Color(0xFF1e3a8a);
const Color _npGreen  = Color(0xFF27AE60);
const Color _npBlue   = Color(0xFF2980B9);
const Color _npOrange = Color(0xFFE67E22);
const Color _npRed    = Color(0xFFE74C3C);
const Color _npPurple = Color(0xFF9B59B6);

class NewProjectScreen extends StatefulWidget {
  final String? projectId;
  const NewProjectScreen({Key? key, this.projectId}) : super(key: key);
  @override
  State<NewProjectScreen> createState() => _NewProjectScreenState();
}

class _NewProjectScreenState extends State<NewProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false, _isSaving = false;

  final _projectNameCtrl  = TextEditingController();
  final _descriptionCtrl  = TextEditingController();
  final _fixedAmountCtrl  = TextEditingController();
  final _hourlyRateCtrl   = TextEditingController();
  final _budgetAmountCtrl = TextEditingController();
  final _notesCtrl        = TextEditingController();
  final _termsCtrl        = TextEditingController();

  String? _selectedCustomerId, _selectedCustomerName, _selectedCustomerEmail, _selectedCustomerPhone;
  String _billingMethod = 'Fixed Cost';
  String _budgetType    = 'Cost';
  String _status        = 'Active';
  String _currency      = 'INR';
  DateTime _startDate   = DateTime.now();
  DateTime? _endDate;

  List<_TaskRow>  _tasks = [];
  List<_StaffRow> _staff = [];
  List<Map<String, dynamic>> _availableStaff = [];
  bool _loadingStaff = false;

  final List<String> _billingMethods = ['Fixed Cost', 'Based on Project Hours', 'Based on Task Hours', 'Based on Staff Hours'];
  final List<String> _budgetTypes    = ['Cost', 'Revenue', 'Hours'];
  final List<String> _statusOptions  = ['Active', 'Inactive', 'Completed', 'On Hold'];
  final List<String> _currencies     = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD'];
  final List<String> _taskStatuses   = ['Open', 'In Progress', 'Completed'];

  @override
  void initState() {
    super.initState();
    _loadStaff();
    if (widget.projectId != null) _loadProject();
  }

  @override
  void dispose() {
    _projectNameCtrl.dispose(); _descriptionCtrl.dispose();
    _fixedAmountCtrl.dispose(); _hourlyRateCtrl.dispose();
    _budgetAmountCtrl.dispose(); _notesCtrl.dispose(); _termsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() => _loadingStaff = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('finance_jwt_token') ?? prefs.getString('jwt_token') ?? '';
      final res   = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/finance/users'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});
      final body  = json.decode(res.body) as Map<String, dynamic>;
      if (body['success'] == true) {
        setState(() { _availableStaff = List<Map<String, dynamic>>.from(body['data'] ?? []); _loadingStaff = false; });
      } else { setState(() => _loadingStaff = false); }
    } catch (_) { setState(() => _loadingStaff = false); }
  }

  Future<void> _loadProject() async {
    setState(() => _isLoading = true);
    try {
      final project = await ProjectService.getProject(widget.projectId!);
      setState(() {
        _selectedCustomerId    = project.customerId;
        _selectedCustomerName  = project.customerName;
        _selectedCustomerEmail = project.customerEmail;
        _selectedCustomerPhone = project.customerPhone;
        _projectNameCtrl.text  = project.projectName;
        _descriptionCtrl.text  = project.description;
        _billingMethod         = project.billingMethod;
        _fixedAmountCtrl.text  = project.fixedAmount  > 0 ? project.fixedAmount.toStringAsFixed(2)  : '';
        _hourlyRateCtrl.text   = project.hourlyRate   > 0 ? project.hourlyRate.toStringAsFixed(2)   : '';
        _budgetType            = project.budgetType;
        _budgetAmountCtrl.text = project.budgetAmount > 0 ? project.budgetAmount.toStringAsFixed(2) : '';
        _currency              = project.currency;
        _startDate             = project.startDate;
        _endDate               = project.endDate;
        _status                = project.status;
        _notesCtrl.text        = project.notes;
        _tasks = project.tasks.map((t) => _TaskRow(
          taskId: t.taskId, taskName: t.taskName, hourlyRate: t.hourlyRate,
          estimatedHours: t.estimatedHours, taskStatus: t.status,
          completionPercent: (t as dynamic).completionPercent?.toDouble() ?? 0,
          deadline: (t as dynamic).deadline,
          assignedStaffId: (t as dynamic).assignedStaffId ?? '',
          assignedStaffName: (t as dynamic).assignedStaffName ?? '',
        )).toList();
        _staff = project.staff.map((s) => _StaffRow(userId: s.userId, name: s.name, email: s.email, role: s.role, hourlyRate: s.hourlyRate)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load project: $e');
    }
  }

  double get _estimatedAmount {
    switch (_billingMethod) {
      case 'Fixed Cost': return double.tryParse(_fixedAmountCtrl.text) ?? 0;
      case 'Based on Project Hours': return (double.tryParse(_hourlyRateCtrl.text) ?? 0) * _tasks.fold(0.0, (s, t) => s + t.estimatedHours);
      case 'Based on Task Hours':   return _tasks.fold(0.0, (s, t) => s + t.hourlyRate * t.estimatedHours);
      case 'Based on Staff Hours':  return _staff.fold(0.0, (s, m) => s + m.hourlyRate * 40);
      default: return 0;
    }
  }

  double get _estimatedHours => _tasks.fold(0.0, (s, t) => s + t.estimatedHours);

  Future<void> _save(String status) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) { _showError('Please select a customer'); return; }
    setState(() => _isSaving = true);
    try {
      final data = {
        'projectName':        _projectNameCtrl.text.trim(),
        'customerId':         _selectedCustomerId,
        'customerName':       _selectedCustomerName,
        'customerEmail':      _selectedCustomerEmail ?? '',
        'customerPhone':      _selectedCustomerPhone ?? '',
        'description':        _descriptionCtrl.text.trim(),
        'billingMethod':      _billingMethod,
        'fixedAmount':        double.tryParse(_fixedAmountCtrl.text)  ?? 0,
        'hourlyRate':         double.tryParse(_hourlyRateCtrl.text)   ?? 0,
        'budgetType':         _budgetType,
        'budgetAmount':       double.tryParse(_budgetAmountCtrl.text) ?? 0,
        'currency':           _currency,
        'startDate':          _startDate.toIso8601String(),
        'endDate':            _endDate?.toIso8601String(),
        'status':             status,
        'notes':              _notesCtrl.text.trim(),
        'termsAndConditions': _termsCtrl.text.trim(),
        'tasks': _tasks.where((t) => t.taskName.isNotEmpty).map((t) => t.toJson()).toList(),
        'staff': _staff.where((s) => s.userId.isNotEmpty).map((s) => s.toJson()).toList(),
      };
      if (widget.projectId != null) {
        await ProjectService.updateProject(widget.projectId!, data);
      } else {
        await ProjectService.createProject(data);
      }
      _showSuccess(widget.projectId != null ? 'Project updated!' : 'Project created!');
      if (mounted) Navigator.pop(context, true);
    } catch (e) { _showError(e.toString()); }
    finally    { setState(() => _isSaving = false); }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: _npRed, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: _npGreen, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(widget.projectId != null ? 'Edit Project' : 'New Project', style: const TextStyle(fontSize: 16)),
        backgroundColor: _npNavy, foregroundColor: Colors.white,
        actions: [
          TextButton.icon(onPressed: _isSaving ? null : () => _save('Inactive'), icon: const Icon(Icons.save_outlined, color: Colors.white70, size: 18), label: const Text('Save as Draft', style: TextStyle(color: Colors.white70, fontSize: 13))),
          const SizedBox(width: 6),
          Padding(padding: const EdgeInsets.only(right: 10), child: ElevatedButton.icon(
            onPressed: _isSaving ? null : () => _save('Active'),
            icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check_circle_outline, size: 16),
            label: Text(_isSaving ? 'Saving…' : 'Save & Activate', style: const TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(backgroundColor: _npGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
          )),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              return Form(key: _formKey, child: isWide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 3, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _buildCustomerSection(), const SizedBox(height: 20),
                        _buildProjectDetailsSection(), const SizedBox(height: 20),
                        _buildTasksSection(), const SizedBox(height: 20),
                        _buildStaffSection(), const SizedBox(height: 20),
                        _buildNotesSection(), const SizedBox(height: 20),
                      ]))),
                      Container(width: 340, color: Colors.white, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _buildBillingMethodSection(), const Divider(height: 32),
                        _buildBudgetSection(), const Divider(height: 32),
                        _buildSummarySection(),
                      ]))),
                    ])
                  : SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _buildCustomerSection(), const SizedBox(height: 16),
                      _buildProjectDetailsSection(), const SizedBox(height: 16),
                      _buildBillingMethodSection(), const SizedBox(height: 16),
                      _buildBudgetSection(), const SizedBox(height: 16),
                      _buildTasksSection(), const SizedBox(height: 16),
                      _buildStaffSection(), const SizedBox(height: 16),
                      _buildNotesSection(), const SizedBox(height: 16),
                      _buildSummarySection(), const SizedBox(height: 24),
                    ])));
            }),
    );
  }

  Widget _buildCustomerSection() {
    return _card('Customer Information', Icons.person_outline, _npBlue, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(onTap: _showCustomerSelector, child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Icon(Icons.person_outline, color: _npBlue),
          const SizedBox(width: 12),
          Expanded(child: Text(_selectedCustomerName ?? 'Select Customer *', style: TextStyle(fontSize: 16, color: _selectedCustomerName != null ? const Color(0xFF2C3E50) : Colors.grey[600], fontWeight: _selectedCustomerName != null ? FontWeight.w500 : FontWeight.normal))),
          const Icon(Icons.arrow_drop_down, color: Colors.grey),
        ]))),
      if (_selectedCustomerEmail != null) ...[const SizedBox(height: 8), Row(children: [const Icon(Icons.email_outlined, size: 16, color: Colors.grey), const SizedBox(width: 8), Text(_selectedCustomerEmail!, style: TextStyle(color: Colors.grey[700]))])],
    ]));
  }

  Widget _buildProjectDetailsSection() {
    return _card('Project Details', Icons.folder_outlined, _npNavy, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(controller: _projectNameCtrl, decoration: _dec('Project Name *', Icons.folder_outlined), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
      const SizedBox(height: 14),
      TextFormField(controller: _descriptionCtrl, decoration: _dec('Description', Icons.notes_outlined), maxLines: 3),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Start Date *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50))),
          const SizedBox(height: 6),
          InkWell(onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _startDate, firstDate: DateTime(2020), lastDate: DateTime(2035));
            if (d != null) setState(() => _startDate = d);
          }, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [const Icon(Icons.calendar_today, size: 16, color: _npNavy), const SizedBox(width: 8), Text(DateFormat('dd MMM yyyy').format(_startDate))]))),
        ])),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('End Date', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50))),
          const SizedBox(height: 6),
          InkWell(onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _endDate ?? DateTime.now().add(const Duration(days: 30)), firstDate: DateTime(2020), lastDate: DateTime(2035));
            if (d != null) setState(() => _endDate = d);
          }, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [const Icon(Icons.calendar_today, size: 16, color: Colors.grey), const SizedBox(width: 8), Text(_endDate != null ? DateFormat('dd MMM yyyy').format(_endDate!) : 'No end date', style: TextStyle(color: _endDate != null ? null : Colors.grey[500]))]))),
        ])),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(value: _status, decoration: _dec('Status', Icons.info_outline), items: _statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) { if (v != null) setState(() => _status = v); })),
        const SizedBox(width: 12),
        Expanded(child: DropdownButtonFormField<String>(value: _currency, decoration: _dec('Currency', Icons.currency_rupee_outlined), items: _currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) { if (v != null) setState(() => _currency = v); })),
      ]),
    ]));
  }

  Widget _buildBillingMethodSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Billing Method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 12),
      ..._billingMethods.map((method) {
        final isSelected = _billingMethod == method;
        final descriptions = { 'Fixed Cost': 'One flat fee', 'Based on Project Hours': 'Total hours × one rate', 'Based on Task Hours': 'Hours × per-task rate', 'Based on Staff Hours': 'Hours × per-staff rate' };
        return GestureDetector(onTap: () => setState(() => _billingMethod = method),
          child: AnimatedContainer(duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: isSelected ? _npNavy.withOpacity(0.07) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: isSelected ? _npNavy : Colors.grey[300]!, width: isSelected ? 2 : 1)),
            child: Row(children: [
              Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: isSelected ? _npNavy : Colors.grey[400]!, width: 2), color: isSelected ? _npNavy : Colors.white), child: isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(method, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? _npNavy : const Color(0xFF2C3E50))),
                Text(descriptions[method] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ])),
            ])));
      }).toList(),
      if (_billingMethod == 'Fixed Cost') ...[const SizedBox(height: 12), TextFormField(controller: _fixedAmountCtrl, decoration: _dec('Fixed Amount (₹) *', Icons.currency_rupee_outlined), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) => _billingMethod == 'Fixed Cost' && (v == null || v.isEmpty) ? 'Required' : null)],
      if (_billingMethod == 'Based on Project Hours') ...[const SizedBox(height: 12), TextFormField(controller: _hourlyRateCtrl, decoration: _dec('Hourly Rate (₹/hr) *', Icons.access_time_outlined), keyboardType: const TextInputType.numberWithOptions(decimal: true))],
    ]);
  }

  Widget _buildBudgetSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Budget', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: _budgetType, decoration: _dec('Budget Type', Icons.account_balance_wallet_outlined), items: _budgetTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(), onChanged: (v) { if (v != null) setState(() => _budgetType = v); }),
      const SizedBox(height: 12),
      TextFormField(controller: _budgetAmountCtrl, decoration: _dec('Budget Amount', Icons.attach_money_outlined), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
    ]);
  }

  // ── TASKS SECTION — UPDATED ────────────────────────────────────────────────
  Widget _buildTasksSection() {
    return _card('Tasks', Icons.task_outlined, _npBlue, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${_tasks.length} task(s)', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ElevatedButton.icon(onPressed: () => setState(() => _tasks.add(_TaskRow())), icon: const Icon(Icons.add, size: 16), label: const Text('Add Task'),
            style: ElevatedButton.styleFrom(backgroundColor: _npBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: Size.zero)),
      ]),
      if (_tasks.isEmpty) ...[const SizedBox(height: 16), Center(child: Text('No tasks added yet.', style: TextStyle(color: Colors.grey[500], fontSize: 13)))]
      else ...[const SizedBox(height: 12), ..._tasks.asMap().entries.map((e) => _buildTaskRow(e.key, e.value)).toList()],
    ]));
  }

  Widget _buildTaskRow(int index, _TaskRow task) {
    return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF7F9FC), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Row 1: Name + delete
        Row(children: [
          Expanded(child: TextFormField(initialValue: task.taskName, decoration: InputDecoration(labelText: 'Task Name', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onChanged: (v) => task.taskName = v)),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.delete_outline, color: _npRed, size: 20), onPressed: () => setState(() => _tasks.removeAt(index)), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ]),
        const SizedBox(height: 8),
        // Row 2: Hours + Rate (conditional) + Status
        Row(children: [
          Expanded(child: TextFormField(initialValue: task.estimatedHours > 0 ? task.estimatedHours.toStringAsFixed(1) : '', decoration: InputDecoration(labelText: 'Est. Hrs', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) { task.estimatedHours = double.tryParse(v) ?? 0; setState(() {}); })),
          const SizedBox(width: 8),
          if (_billingMethod == 'Based on Task Hours') ...[
            Expanded(child: TextFormField(initialValue: task.hourlyRate > 0 ? task.hourlyRate.toStringAsFixed(2) : '', decoration: InputDecoration(labelText: '₹/hr', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) { task.hourlyRate = double.tryParse(v) ?? 0; setState(() {}); })),
            const SizedBox(width: 8),
          ],
          Expanded(child: DropdownButtonFormField<String>(value: task.taskStatus, decoration: InputDecoration(labelText: 'Status', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              items: _taskStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(), onChanged: (v) { if (v != null) setState(() => task.taskStatus = v); })),
        ]),
        const SizedBox(height: 8),
        // Row 3: Assign Staff + Deadline
        Row(children: [
          Expanded(child: _loadingStaff
              ? const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : DropdownButtonFormField<String>(
                  value: task.assignedStaffId.isNotEmpty ? task.assignedStaffId : null,
                  decoration: InputDecoration(labelText: 'Assign Staff', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  items: [const DropdownMenuItem(value: null, child: Text('Unassigned', style: TextStyle(fontSize: 13))), ..._availableStaff.map((u) => DropdownMenuItem<String>(value: u['_id']?.toString() ?? '', child: Text(u['name']?.toString() ?? 'Unknown', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))))],
                  onChanged: (v) {
                    setState(() {
                      task.assignedStaffId = v ?? '';
                      if (v != null && v.isNotEmpty) {
                        final user = _availableStaff.firstWhere((u) => u['_id']?.toString() == v, orElse: () => {});
                        task.assignedStaffName = user['name']?.toString() ?? '';
                      } else { task.assignedStaffName = ''; }
                    });
                  })),
          const SizedBox(width: 8),
          Expanded(child: InkWell(onTap: () async {
            final d = await showDatePicker(context: context, initialDate: task.deadline ?? DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2035));
            if (d != null) setState(() => task.deadline = d);
          }, child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), decoration: BoxDecoration(border: Border.all(color: Colors.grey[400]!), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [const Icon(Icons.calendar_today, size: 14, color: _npNavy), const SizedBox(width: 6), Expanded(child: Text(task.deadline != null ? DateFormat('dd MMM yy').format(task.deadline!) : 'Deadline', style: TextStyle(fontSize: 12, color: task.deadline != null ? const Color(0xFF2C3E50) : Colors.grey[500])))])))),
        ]),
        const SizedBox(height: 8),
        // Completion slider
        Row(children: [
          const Text('Completion:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          Expanded(child: Slider(
            value: task.completionPercent.clamp(0.0, 100.0),
            min: 0, max: 100, divisions: 20,
            activeColor: task.completionPercent >= 100 ? _npGreen : _npBlue,
            onChanged: (v) => setState(() => task.completionPercent = v),
          )),
          Container(width: 42, alignment: Alignment.center, child: Text('${task.completionPercent.toInt()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _npNavy))),
        ]),
      ]));
  }

  Widget _buildStaffSection() {
    return _card('Staff Assignments', Icons.people_outline, _npPurple, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${_staff.length} staff member(s)', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ElevatedButton.icon(onPressed: () => setState(() => _staff.add(_StaffRow())), icon: const Icon(Icons.person_add, size: 16), label: const Text('Add Staff'),
            style: ElevatedButton.styleFrom(backgroundColor: _npPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: Size.zero)),
      ]),
      if (_staff.isEmpty) ...[const SizedBox(height: 16), Center(child: Text('No staff assigned.', style: TextStyle(color: Colors.grey[500], fontSize: 13)))]
      else ...[const SizedBox(height: 12), ..._staff.asMap().entries.map((e) => _buildStaffRow(e.key, e.value)).toList()],
    ]));
  }

  Widget _buildStaffRow(int index, _StaffRow staffRow) {
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF7F9FC), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
      child: Row(children: [
        Expanded(flex: 3, child: _loadingStaff
            ? const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            : DropdownButtonFormField<String>(
                value: staffRow.userId.isNotEmpty ? staffRow.userId : null,
                decoration: InputDecoration(labelText: 'Staff Member', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                items: _availableStaff.map((u) => DropdownMenuItem<String>(value: u['_id']?.toString() ?? '', child: Text(u['name']?.toString() ?? 'Unknown', overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) {
                  if (v != null) {
                    final user = _availableStaff.firstWhere((u) => u['_id']?.toString() == v, orElse: () => {});
                    setState(() { staffRow.userId = v; staffRow.name = user['name']?.toString() ?? ''; staffRow.email = user['email']?.toString() ?? ''; final orgs = user['organizations'] as List? ?? []; staffRow.role = orgs.isNotEmpty ? (orgs.first['role']?.toString() ?? 'staff') : 'staff'; });
                  }
                })),
        const SizedBox(width: 8),
        if (_billingMethod == 'Based on Staff Hours') ...[
          SizedBox(width: 100, child: TextFormField(initialValue: staffRow.hourlyRate > 0 ? staffRow.hourlyRate.toStringAsFixed(2) : '', decoration: InputDecoration(labelText: '₹/hr', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) { staffRow.hourlyRate = double.tryParse(v) ?? 0; setState(() {}); })),
          const SizedBox(width: 8),
        ],
        IconButton(icon: const Icon(Icons.delete_outline, color: _npRed, size: 20), onPressed: () => setState(() => _staff.removeAt(index)), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
      ]));
  }

  Widget _buildNotesSection() {
    return _card('Additional Information', Icons.notes_outlined, Colors.grey, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(controller: _notesCtrl, decoration: _dec('Notes / Instructions', Icons.notes_outlined), maxLines: 3),
      const SizedBox(height: 14),
      TextFormField(controller: _termsCtrl, decoration: _dec('Terms & Conditions', Icons.gavel_outlined), maxLines: 3),
    ]));
  }

  Widget _buildSummarySection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Project Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 16),
      _summaryRow('Tasks', '${_tasks.length}'),
      const SizedBox(height: 8),
      _summaryRow('Staff Assigned', '${_staff.length}'),
      const SizedBox(height: 8),
      _summaryRow('Est. Total Hours', '${_estimatedHours.toStringAsFixed(1)} hrs'),
      const Divider(height: 24, thickness: 2),
      _summaryRow('Est. Billable Amount', '₹${_estimatedAmount.toStringAsFixed(2)}', isTotal: true),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _isSaving ? null : () => _save('Active'), icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check_circle_outline, size: 16),
          label: Text(_isSaving ? 'Saving…' : 'Save & Activate'), style: ElevatedButton.styleFrom(backgroundColor: _npGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))))),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _isSaving ? null : () => _save('Inactive'), icon: const Icon(Icons.save_outlined, size: 16), label: const Text('Save as Draft'),
          style: OutlinedButton.styleFrom(foregroundColor: _npNavy, side: const BorderSide(color: _npNavy), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))))),
    ]);
  }

  Widget _summaryRow(String label, String value, {bool isTotal = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: isTotal ? 16 : 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, color: isTotal ? const Color(0xFF2C3E50) : const Color(0xFF7F8C8D))),
      Text(value, style: TextStyle(fontSize: isTotal ? 18 : 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.w500, color: isTotal ? _npNavy : const Color(0xFF2C3E50))),
    ]);
  }

  Widget _card(String title, IconData icon, Color color, Widget child) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)))]),
        const SizedBox(height: 16), child,
      ]));
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label, prefixIcon: Icon(icon, size: 20, color: Colors.grey[500]),
    filled: true, fillColor: const Color(0xFFF7F9FC),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _npNavy, width: 2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );

  Future<void> _showCustomerSelector() async {
    final TextEditingController searchCtrl = TextEditingController();
    List<dynamic> customers = []; List<dynamic> filtered = []; bool isLoading = true;
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setD) {
      if (isLoading && customers.isEmpty) {
        BillingCustomersService.getAllCustomers(limit: 200, skipStats: true).then((r) { setD(() { customers = r.customers; filtered = customers; isLoading = false; }); }).catchError((e) => setD(() => isLoading = false));
      }
      return AlertDialog(
        title: const Text('Select Customer'),
        content: SizedBox(width: 500, height: 400, child: Column(children: [
          TextField(controller: searchCtrl, decoration: InputDecoration(hintText: 'Search customers…', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onChanged: (v) => setD(() { filtered = v.isEmpty ? customers : customers.where((c) => (c as dynamic).customerDisplayName.toLowerCase().contains(v.toLowerCase())).toList(); })),
          const SizedBox(height: 12),
          Expanded(child: isLoading ? const Center(child: CircularProgressIndicator()) : filtered.isEmpty ? const Center(child: Text('No customers found'))
              : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
                  final c = filtered[i] as BillingCustomer;
                  return ListTile(leading: CircleAvatar(backgroundColor: _npBlue, child: Text(c.customerDisplayName.isNotEmpty ? c.customerDisplayName[0].toUpperCase() : 'C', style: const TextStyle(color: Colors.white))),
                    title: Text(c.customerDisplayName), subtitle: Text(c.primaryEmail),
                    onTap: () { setState(() { _selectedCustomerId = c.id; _selectedCustomerName = c.customerDisplayName; _selectedCustomerEmail = c.primaryEmail; _selectedCustomerPhone = c.primaryPhone; }); Navigator.pop(context); });
                })),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      );
    }));
  }
}

// ── Models ─────────────────────────────────────────────────────────────────────

class _TaskRow {
  String taskId;
  String taskName;
  double hourlyRate;
  double estimatedHours;
  String taskStatus;
  double completionPercent;
  DateTime? deadline;
  String assignedStaffId;
  String assignedStaffName;

  _TaskRow({
    this.taskId = '', this.taskName = '', this.hourlyRate = 0,
    this.estimatedHours = 0, this.taskStatus = 'Open',
    this.completionPercent = 0, this.deadline,
    this.assignedStaffId = '', this.assignedStaffName = '',
  });

  Map<String, dynamic> toJson() => {
    'taskId':            taskId.isNotEmpty ? taskId : 'TASK-${DateTime.now().millisecondsSinceEpoch}',
    'taskName':          taskName,
    'hourlyRate':        hourlyRate,
    'estimatedHours':    estimatedHours,
    'status':            taskStatus,
    'completionPercent': completionPercent,
    'deadline':          deadline?.toIso8601String(),
    'assignedStaffId':   assignedStaffId,
    'assignedStaffName': assignedStaffName,
  };
}

class _StaffRow {
  String userId; String name; String email; String role; double hourlyRate;
  _StaffRow({this.userId = '', this.name = '', this.email = '', this.role = 'staff', this.hourlyRate = 0});
  Map<String, dynamic> toJson() => {'userId': userId, 'name': name, 'email': email, 'role': role, 'hourlyRate': hourlyRate};
}