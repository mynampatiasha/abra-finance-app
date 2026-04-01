// lib/screens/tms/raise_ticket_screen.dart
// ============================================================================
// 🎫 RAISE TICKET SCREEN - Simple Modern UI with Animations
// ============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../core/services/tms_service.dart';



class RaiseTicketScreen extends StatefulWidget {
  /// Optional pre-fill data for re-raising a ticket back to the original creator.
  final String? prefillSubject;
  final String? prefillMessage;
  final String? prefillPriority;
  final int?    prefillTimeline;
  final String? prefillAssignedToId;
  final String? prefillAssignedToName;

  const RaiseTicketScreen({
    Key? key,
    this.prefillSubject,
    this.prefillMessage,
    this.prefillPriority,
    this.prefillTimeline,
    this.prefillAssignedToId,
    this.prefillAssignedToName,
  }) : super(key: key);

  @override
  State<RaiseTicketScreen> createState() => _RaiseTicketScreenState();
}

class _RaiseTicketScreenState extends State<RaiseTicketScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  final _employeeSearchController = TextEditingController();
  final _tmsService = TMSService();

  String _priority = 'Medium';
  int? _timeline;
  String? _assignedTo;
  String? _assignedToName;
  File? _attachment;
  String? _attachmentName;

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  bool _loadingEmployees = true;

  DateTime? _calculatedDeadline;

  final List<Map<String, dynamic>> _timelineOptions = [
    {'label': '10 Minutes', 'value': 10},
    {'label': '30 Minutes', 'value': 30},
    {'label': '1 Hour', 'value': 60},
    {'label': '3 Hours', 'value': 180},
    {'label': '4 Hours', 'value': 240},
    {'label': '24 Hours (1 Day)', 'value': 1440},
    {'label': '48 Hours (2 Days)', 'value': 2880},
    {'label': '1 Week', 'value': 10080},
    {'label': '1 Month (30 Days)', 'value': 43200},
  ];

  bool _isSubmitting = false;

  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // Custom color scheme
  static const Color darkBlue = Color(0xFF042E45);    // Header gradient dark
  static const Color mediumBlue = Color(0xFF186285);  // Header gradient medium
  static const Color lightBlue = Color(0xFFEBF2F5);   // Background color
  static const Color accentBlue = Color(0xFF186285);  // Accent color

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _fetchEmployees();
    // Apply pre-fill if provided (re-raise flow)
    if (widget.prefillSubject != null) {
      _subjectController.text = widget.prefillSubject!;
    }
    if (widget.prefillMessage != null) {
      _messageController.text = widget.prefillMessage!;
    }
    if (widget.prefillPriority != null) {
      _priority = widget.prefillPriority!;
    }
    if (widget.prefillTimeline != null) {
      _timeline = widget.prefillTimeline;
      _calculateDeadline(_timeline);
    }
    if (widget.prefillAssignedToId != null) {
      _assignedTo     = widget.prefillAssignedToId;
      _assignedToName = widget.prefillAssignedToName;
    }
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );

    _fadeController.forward();
    _scaleController.forward();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _employeeSearchController.dispose();
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _fetchEmployees() async {
    setState(() => _loadingEmployees = true);
    final response = await _tmsService.fetchEmployees();

    if (response['success'] == true && response['data'] != null) {
      setState(() {
        _employees = List<Map<String, dynamic>>.from(response['data']);
        _filteredEmployees = _employees;
        _loadingEmployees = false;
      });
      // Auto-select employee if pre-fill name/email was provided
      if (widget.prefillAssignedToId == null &&
          widget.prefillAssignedToName != null &&
          widget.prefillAssignedToName!.isNotEmpty) {
        _autoSelectEmployee(widget.prefillAssignedToName!);
      }
    } else {
      setState(() => _loadingEmployees = false);
      _showErrorSnackbar('Failed to load employees');
    }
  }

  /// Tries to match an employee by name or email for the re-raise pre-fill.
  void _autoSelectEmployee(String nameOrEmail) {
    final query = nameOrEmail.toLowerCase();
    final match = _employees.firstWhere(
      (e) =>
          (e['name_parson'] ?? '').toString().toLowerCase() == query ||
          (e['email'] ?? '').toString().toLowerCase() == query ||
          (e['username'] ?? '').toString().toLowerCase() == query,
      orElse: () => {},
    );
    if (match.isNotEmpty && match['_id'] != null) {
      setState(() {
        _assignedTo     = match['_id'].toString();
        _assignedToName = match['name_parson'] ?? match['username'] ?? nameOrEmail;
      });
    }
  }

  void _filterEmployees(String query) {
    if (query.isEmpty) {
      setState(() => _filteredEmployees = _employees);
      return;
    }

    setState(() {
      _filteredEmployees = _employees.where((emp) {
        final name = (emp['name_parson'] ?? '').toString().toLowerCase();
        final email = (emp['email'] ?? '').toString().toLowerCase();
        final username = (emp['username'] ?? '').toString().toLowerCase();
        final searchQuery = query.toLowerCase();
        return name.contains(searchQuery) || email.contains(searchQuery) || username.contains(searchQuery);
      }).toList();
    });
  }

  void _calculateDeadline(int? minutes) {
    if (minutes == null || minutes <= 0) {
      setState(() => _calculatedDeadline = null);
      return;
    }
    setState(() => _calculatedDeadline = DateTime.now().add(Duration(minutes: minutes)));
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx', 'txt'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.single.path!);
        final sizeInBytes = await file.length();
        final sizeInMB = sizeInBytes / (1024 * 1024);

        if (sizeInMB > 5) {
          _showErrorSnackbar('File size exceeds 5MB limit');
          return;
        }

        setState(() {
          _attachment = file;
          _attachmentName = result.files.single.name;
        });
      }
    } catch (e) {
      _showErrorSnackbar('Failed to pick file: $e');
    }
  }

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;

    if (_timeline == null) {
      _showErrorSnackbar('Please select a timeline');
      return;
    }

    if (_assignedTo == null) {
      _showErrorSnackbar('Please assign to an employee');
      return;
    }

    setState(() => _isSubmitting = true);

    final response = await _tmsService.createTicket(
      subject: _subjectController.text.trim(),
      message: _messageController.text.trim(),
      priority: _priority,
      timeline: _timeline!,
      assignedTo: _assignedTo!,
      attachment: _attachment,
    );

    setState(() => _isSubmitting = false);

    if (response['success'] == true) {
      _showSuccessSnackbar('Ticket created successfully!');
      Navigator.pop(context, true);
    } else {
      _showErrorSnackbar(response['message'] ?? 'Failed to create ticket');
    }
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: mediumBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBlue,
      appBar: AppBar(
        backgroundColor: darkBlue,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.prefillAssignedToId != null ? 'Re-raise Ticket' : 'Create New Ticket',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 24),
                  _buildSectionLabel('Subject', Icons.text_fields, true),
                  const SizedBox(height: 8),
                  _buildSubjectField(),
                  const SizedBox(height: 20),
                  _buildSectionLabel('Message', Icons.message, true),
                  const SizedBox(height: 8),
                  _buildMessageField(),
                  const SizedBox(height: 20),
                  _buildSectionLabel('Priority', Icons.flag, true),
                  const SizedBox(height: 8),
                  _buildPrioritySelector(),
                  const SizedBox(height: 20),
                  _buildSectionLabel('Timeline', Icons.schedule, true),
                  const SizedBox(height: 8),
                  _buildTimelineDropdown(),
                  const SizedBox(height: 12),
                  if (_calculatedDeadline != null) ...[
                    _buildDeadlinePreview(),
                    const SizedBox(height: 20),
                  ],
                  _buildSectionLabel('Assign To', Icons.person, true),
                  const SizedBox(height: 8),
                  _buildAssignToField(),
                  const SizedBox(height: 20),
                  _buildSectionLabel('Attachment', Icons.attach_file, false),
                  const SizedBox(height: 8),
                  _buildAttachmentField(),
                  const SizedBox(height: 32),
                  _buildSubmitButton(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [darkBlue, mediumBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: mediumBlue.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.confirmation_number_rounded, size: 40, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            widget.prefillAssignedToId != null ? 'Re-raise Ticket' : 'Raise a New Ticket',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            widget.prefillAssignedToId != null
                ? 'Pre-filled from original ticket — review and submit'
                : 'Fill in the details below to create your ticket',
            style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label, IconData icon, bool required) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: accentBlue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: mediumBlue),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: darkBlue),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          const Text('*', style: TextStyle(color: Color(0xFFEF4444), fontSize: 16)),
        ],
      ],
    );
  }

  Widget _buildSubjectField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: _subjectController,
        style: TextStyle(color: darkBlue, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Enter ticket subject',
          hintStyle: TextStyle(color: const Color(0xFF64748B).withOpacity(0.6)),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: accentBlue.withOpacity(0.3), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: mediumBlue, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        validator: (value) => value == null || value.isEmpty ? 'Please enter a subject' : null,
      ),
    );
  }

  Widget _buildMessageField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: _messageController,
        maxLines: 5,
        style: TextStyle(color: darkBlue, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Describe the issue in detail',
          hintStyle: TextStyle(color: const Color(0xFF64748B).withOpacity(0.6)),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: accentBlue.withOpacity(0.3), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: mediumBlue, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        validator: (value) => value == null || value.isEmpty ? 'Please enter a message' : null,
      ),
    );
  }

  Widget _buildPrioritySelector() {
    return Row(
      children: ['Low', 'Medium', 'High'].map((priority) {
        final isSelected = _priority == priority;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => setState(() => _priority = priority),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          colors: [
                            _getPriorityColor(priority),
                            _getPriorityColor(priority).withOpacity(0.8),
                          ],
                        )
                      : null,
                  color: isSelected ? null : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? _getPriorityColor(priority) : accentBlue.withOpacity(0.3),
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: _getPriorityColor(priority).withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _getPriorityIcon(priority),
                      size: 18,
                      color: isSelected ? Colors.white : _getPriorityColor(priority),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      priority,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority) {
      case 'High':
        return Icons.priority_high;
      case 'Medium':
        return Icons.remove;
      case 'Low':
        return Icons.arrow_downward;
      default:
        return Icons.flag;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'High':
        return const Color(0xFFEF4444);
      case 'Medium':
        return const Color(0xFFF59E0B);
      case 'Low':
        return const Color(0xFF10B981);
      default:
        return Colors.grey;
    }
  }

  Widget _buildTimelineDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentBlue.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonFormField<int>(
        value: _timeline,
        dropdownColor: Colors.white,
        style: TextStyle(color: darkBlue, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Select timeline',
          hintStyle: TextStyle(color: const Color(0xFF64748B).withOpacity(0.6)),
          prefixIcon: Icon(Icons.timer, color: mediumBlue),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        items: _timelineOptions.map((option) {
          return DropdownMenuItem<int>(
            value: option['value'],
            child: Text(option['label']),
          );
        }).toList(),
        onChanged: (value) {
          setState(() => _timeline = value);
          _calculateDeadline(value);
        },
        validator: (value) => value == null ? 'Please select a timeline' : null,
      ),
    );
  }

  Widget _buildDeadlinePreview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentBlue.withOpacity(0.15),
            mediumBlue.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentBlue.withOpacity(0.5), width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: mediumBlue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.access_time_filled, color: mediumBlue, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deadline',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMM dd, yyyy \'at\' hh:mm a').format(_calculatedDeadline!),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: darkBlue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignToField() {
    return _loadingEmployees
        ? Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accentBlue.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(mediumBlue),
              ),
            ),
          )
        : InkWell(
            onTap: _showEmployeeSearchDialog,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _assignedTo == null
                      ? const Color(0xFFEF4444).withOpacity(0.5)
                      : accentBlue.withOpacity(0.4),
                  width: _assignedTo == null ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _assignedTo == null
                          ? const Color(0xFFEF4444).withOpacity(0.1)
                          : accentBlue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _assignedTo == null ? Icons.person_add : Icons.person,
                      color: _assignedTo == null ? const Color(0xFFEF4444) : mediumBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _assignedTo == null ? 'Select Employee' : 'Assigned To',
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFF64748B).withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _assignedToName ?? 'Tap to select',
                          style: TextStyle(
                            fontSize: 15,
                            color: _assignedTo == null ? const Color(0xFF94A3B8) : darkBlue,
                            fontWeight: _assignedTo == null ? FontWeight.normal : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Color(0xFF94A3B8), size: 16),
                ],
              ),
            ),
          );
  }

  void _showEmployeeSearchDialog() {
    _employeeSearchController.clear();
    _filteredEmployees = _employees;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 600),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [darkBlue, mediumBlue]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.people, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Select Employee',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: darkBlue),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: lightBlue.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accentBlue.withOpacity(0.4)),
                    ),
                    child: TextField(
                      controller: _employeeSearchController,
                      style: TextStyle(color: darkBlue),
                      decoration: InputDecoration(
                        hintText: 'Search employees...',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        prefixIcon: Icon(Icons.search, color: mediumBlue),
                        suffixIcon: _employeeSearchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Color(0xFF64748B)),
                                onPressed: () {
                                  setDialogState(() {
                                    _employeeSearchController.clear();
                                    _filteredEmployees = _employees;
                                  });
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onChanged: (value) {
                        setDialogState(() => _filterEmployees(value));
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _filteredEmployees.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: 64, color: accentBlue.withOpacity(0.4)),
                                const SizedBox(height: 16),
                                const Text(
                                  'No employees found',
                                  style: TextStyle(color: Color(0xFF64748B), fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _filteredEmployees.length,
                            itemBuilder: (context, index) {
                              final employee = _filteredEmployees[index];
                              final isSelected = _assignedTo == employee['_id'].toString();

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? accentBlue.withOpacity(0.15)
                                      : lightBlue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? mediumBlue : accentBlue.withOpacity(0.3),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: ListTile(
                                  onTap: () {
                                    setState(() {
                                      _assignedTo = employee['_id'].toString();
                                      _assignedToName = employee['name_parson'] ?? 'Unknown';
                                    });
                                    Navigator.pop(context);
                                  },
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected ? mediumBlue : accentBlue.withOpacity(0.3),
                                    child: Text(
                                      (employee['name_parson'] ?? 'U')[0].toUpperCase(),
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : darkBlue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    employee['name_parson'] ?? 'Unknown',
                                    style: TextStyle(color: darkBlue, fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (employee['email'] != null)
                                        Text(
                                          employee['email'],
                                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                        ),
                                      if (employee['role'] != null)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: accentBlue.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            employee['role'].toString().toUpperCase(),
                                            style: TextStyle(
                                              color: mediumBlue,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: isSelected ? Icon(Icons.check_circle, color: mediumBlue) : null,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttachmentField() {
    return InkWell(
      onTap: _pickFile,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentBlue.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _attachment == null
                    ? accentBlue.withOpacity(0.2)
                    : const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _attachment == null ? Icons.cloud_upload : Icons.insert_drive_file,
                color: _attachment == null ? mediumBlue : const Color(0xFF10B981),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _attachment == null ? 'Upload File' : 'File Attached',
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF64748B).withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _attachmentName ?? 'JPG, PNG, PDF, DOC (Max 5MB)',
                    style: TextStyle(
                      fontSize: 14,
                      color: _attachment == null ? const Color(0xFF94A3B8) : darkBlue,
                      fontWeight: _attachment == null ? FontWeight.normal : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (_attachment != null)
              IconButton(
                icon: const Icon(Icons.close, color: Color(0xFFEF4444)),
                onPressed: () => setState(() {
                  _attachment = null;
                  _attachmentName = null;
                }),
              )
            else
              const Icon(Icons.arrow_forward_ios, color: Color(0xFF94A3B8), size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [darkBlue, mediumBlue]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: mediumBlue.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitTicket,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isSubmitting
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'Submit Ticket',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}