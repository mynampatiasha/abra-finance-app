import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// NEW TIME ENTRY SCREEN — UPDATED (Timer widget + Submit for approval)
// ============================================================================
// File: lib/screens/billing/pages/new_time_entry.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/finance_secure_storage.dart';
import '../../../../core/services/timesheet_service.dart';
import '../../../../core/services/project_service.dart';
import '../../../../core/services/timer_service.dart';
import '../../../../app/config/api_config.dart';

const Color _teNavy = Color(0xFF1e3a8a);
const Color _teGreen = Color(0xFF27AE60);
const Color _teBlue = Color(0xFF2980B9);
const Color _teOrange = Color(0xFFE67E22);
const Color _teRed = Color(0xFFE74C3C);

class NewTimeEntryScreen extends StatefulWidget {
  final String? entryId;
  final String? preselectedProjectId; // for starting timer from project list
  const NewTimeEntryScreen({Key? key, this.entryId, this.preselectedProjectId})
      : super(key: key);
  @override
  State<NewTimeEntryScreen> createState() => _NewTimeEntryScreenState();
}

class _NewTimeEntryScreenState extends State<NewTimeEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false, _isSaving = false;

  List<Project> _allProjects = [];
  List<ProjectTask> _projectTasks = [];
  List<ProjectStaff> _projectStaff = [];
  List<Map<String, dynamic>> _allStaff = [];
  bool _loadingProjects = true, _loadingStaff = true;

  Project? _selectedProject;
  ProjectTask? _selectedTask;
  String? _selectedUserId, _selectedUserName, _selectedUserEmail;
  DateTime _date = DateTime.now();
  double _hours = 0;
  bool _isBillable = true;
  bool _submitForApproval = false;
  final _hoursCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // ── Timer state ─────────────────────────────────────────────────────────────
  bool _timerMode = false;
  bool _timerRunning = false;
  bool _timerPaused = false;
  int _elapsedSeconds = 0;
  Timer? _tickTimer;
  String? _activeTimerId;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _loadStaffList();
    if (widget.entryId != null) _loadEntry();
    _restoreActiveTimer();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _hoursCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Restore active timer on screen load ─────────────────────────────────────
  Future<void> _restoreActiveTimer() async {
    try {
      final timers = await TimerService.getActiveTimers();
      if (timers.isEmpty) return;
      // Find timer matching preselected project if any, else take first running
      ActiveTimer? match;
      if (widget.preselectedProjectId != null) {
        match = timers
            .where((t) => t.projectId == widget.preselectedProjectId)
            .firstOrNull;
      }
      match ??=
          timers.where((t) => t.isRunning).firstOrNull ?? timers.firstOrNull;
      if (match == null) return;
      if (mounted) {
        setState(() {
          _activeTimerId = match!.id;
          _elapsedSeconds = match.elapsedSeconds;
          _timerRunning = match.isRunning;
          _timerPaused = match.isPaused;
          _timerMode = true;
        });
        if (match.isRunning) _startTick();
      }
    } catch (_) {}
  }

  // ── Start local tick ───────────────────────────────────────────────────────
  void _startTick() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timerRunning && !_timerPaused) setState(() => _elapsedSeconds++);
    });
  }

  void _stopTick() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  String get _timerDisplay => TimerService.formatDuration(_elapsedSeconds);

  // ── Timer actions ──────────────────────────────────────────────────────────
  Future<void> _handleStartTimer() async {
    if (_selectedProject == null) {
      _showError('Select a project first');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final t = await TimerService.startTimer(
        projectId: _selectedProject!.id,
        projectName: _selectedProject!.projectName,
        taskId: _selectedTask?.taskId ?? '',
        taskName: _selectedTask?.taskName ?? '',
        userId: _selectedUserId ?? '',
        userName: _selectedUserName ?? '',
        userEmail: _selectedUserEmail ?? '',
        isBillable: _isBillable,
        notes: _notesCtrl.text.trim(),
      );
      setState(() {
        _activeTimerId = t.id;
        _elapsedSeconds = t.elapsedSeconds;
        _timerRunning = true;
        _timerPaused = false;
      });
      _startTick();
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _handlePauseTimer() async {
    if (_activeTimerId == null) return;
    try {
      final result = await TimerService.pauseTimer(_activeTimerId!);
      _stopTick();
      setState(() {
        _timerRunning = false;
        _timerPaused = true;
        _elapsedSeconds = result['elapsedSeconds'] as int? ?? _elapsedSeconds;
      });
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _handleResumeTimer() async {
    if (_activeTimerId == null) return;
    try {
      await TimerService.resumeTimer(_activeTimerId!);
      setState(() {
        _timerRunning = true;
        _timerPaused = false;
      });
      _startTick();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _handleStopTimer() async {
    if (_activeTimerId == null) return;
    _stopTick();
    setState(() => _isSaving = true);
    try {
      final result = await TimerService.stopTimer(_activeTimerId!,
          notes: _notesCtrl.text.trim(), isBillable: _isBillable);
      _showSuccess('${result.hours} hrs logged successfully!');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isSaving = false);
      _showError(e.toString());
    }
  }

  Future<void> _handleDiscardTimer() async {
    if (_activeTimerId == null) {
      setState(() {
        _timerMode = false;
        _timerRunning = false;
        _timerPaused = false;
        _elapsedSeconds = 0;
      });
      _stopTick();
      return;
    }
    try {
      await TimerService.discardTimer(_activeTimerId!);
      _stopTick();
      setState(() {
        _activeTimerId = null;
        _timerMode = false;
        _timerRunning = false;
        _timerPaused = false;
        _elapsedSeconds = 0;
      });
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _loadProjects() async {
    setState(() => _loadingProjects = true);
    try {
      final resp =
          await ProjectService.getProjects(status: 'Active', limit: 200);
      if (mounted) {
        setState(() {
          _allProjects = resp.projects;
          _loadingProjects = false;
        });
        // Preselect project if passed
        if (widget.preselectedProjectId != null) {
          final match = _allProjects
              .where((p) => p.id == widget.preselectedProjectId)
              .firstOrNull;
          if (match != null) _setProject(match);
        }
      }
    } catch (_) {
      setState(() => _loadingProjects = false);
    }
  }

  Future<void> _loadStaffList() async {
    setState(() => _loadingStaff = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('finance_jwt_token') ??
          prefs.getString('jwt_token') ??
          '';
      final branchHdr = await FinanceSecureStorage.getBranchHeader();
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/users'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'x-branch-ids': branchHdr,
        },
      );
      final body = json.decode(res.body) as Map<String, dynamic>;
      if (body['success'] == true && mounted) {
        setState(() {
          _allStaff = List<Map<String, dynamic>>.from(body['data'] ?? []);
          _loadingStaff = false;
        });
      } else {
        setState(() => _loadingStaff = false);
      }
    } catch (_) {
      setState(() => _loadingStaff = false);
    }
  }

  Future<void> _loadEntry() async {
    setState(() => _isLoading = true);
    try {
      final entry = await TimesheetService.getTimesheet(widget.entryId!);
      if (_allProjects.isNotEmpty) {
        final proj = _allProjects.firstWhere((p) => p.id == entry.projectId,
            orElse: () => _allProjects.first);
        _setProject(proj);
        if (entry.taskId.isNotEmpty) {
          final task = _projectTasks.firstWhere((t) => t.taskId == entry.taskId,
              orElse: () => _projectTasks.first);
          setState(() => _selectedTask = task);
        }
      }
      setState(() {
        _selectedUserId = entry.userId;
        _selectedUserName = entry.userName;
        _selectedUserEmail = entry.userEmail;
        _date = entry.date;
        _hours = entry.hours;
        _hoursCtrl.text = entry.hours.toStringAsFixed(2);
        _isBillable = entry.isBillable;
        _notesCtrl.text = entry.notes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load: $e');
    }
  }

  void _setProject(Project p) {
    setState(() {
      _selectedProject = p;
      _projectTasks = p.tasks.where((t) => t.status == 'Active').toList();
      _projectStaff = p.staff;
      _selectedTask = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProject == null) {
      _showError('Please select a project');
      return;
    }
    final hours = double.tryParse(_hoursCtrl.text) ?? 0;
    if (hours <= 0) {
      _showError('Hours must be > 0');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final data = {
        'projectId': _selectedProject!.id,
        'projectName': _selectedProject!.projectName,
        'taskId': _selectedTask?.taskId ?? '',
        'taskName': _selectedTask?.taskName ?? '',
        'userId': _selectedUserId ?? '',
        'userName': _selectedUserName ?? '',
        'userEmail': _selectedUserEmail ?? '',
        'date': _date.toIso8601String(),
        'hours': hours,
        'isBillable': _isBillable,
        'notes': _notesCtrl.text.trim(),
        'submitForApproval': _submitForApproval,
      };
      if (widget.entryId != null) {
        await TimesheetService.updateTimeEntry(widget.entryId!, data);
      } else {
        await TimesheetService.createTimeEntry(data);
      }
      _showSuccess(_submitForApproval
          ? 'Time entry submitted for approval!'
          : (widget.entryId != null ? 'Time entry updated!' : 'Time logged!'));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) => AppSnackbar.show(context, message: msg);
  void _showSuccess(String msg) => AppSnackbar.show(context, message: msg);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(widget.entryId != null ? 'Edit Time Entry' : 'Log Time',
            style: const TextStyle(fontSize: 16)),
        backgroundColor: _teNavy,
        foregroundColor: Colors.white,
        actions: [
          if (!_timerMode)
            Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check, size: 16),
                  label: Text(_isSaving
                      ? 'Saving…'
                      : (_submitForApproval ? 'Submit' : 'Save Entry')),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _teGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10)),
                )),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                      key: _formKey,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Mode toggle ────────────────────────────────────────────
                            if (widget.entryId == null) ...[
                              Container(
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border:
                                          Border.all(color: Colors.grey[200]!)),
                                  child: Row(children: [
                                    Expanded(
                                        child: GestureDetector(
                                            onTap: () {
                                              _stopTick();
                                              setState(() {
                                                _timerMode = false;
                                                _timerRunning = false;
                                                _timerPaused = false;
                                              });
                                            },
                                            child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 12),
                                                decoration: BoxDecoration(
                                                    color: !_timerMode
                                                        ? _teNavy
                                                        : Colors.transparent,
                                                    borderRadius:
                                                        const BorderRadius
                                                            .horizontal(
                                                            left:
                                                                Radius.circular(
                                                                    10))),
                                                child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(Icons.edit_outlined,
                                                          size: 18,
                                                          color: !_timerMode
                                                              ? Colors.white
                                                              : Colors
                                                                  .grey[600]),
                                                      const SizedBox(width: 6),
                                                      Text('Manual Entry',
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: !_timerMode
                                                                  ? Colors.white
                                                                  : Colors.grey[
                                                                      600]))
                                                    ])))),
                                    Expanded(
                                        child: GestureDetector(
                                            onTap: () => setState(
                                                () => _timerMode = true),
                                            child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 12),
                                                decoration: BoxDecoration(
                                                    color: _timerMode
                                                        ? _teNavy
                                                        : Colors.transparent,
                                                    borderRadius:
                                                        const BorderRadius
                                                            .horizontal(
                                                            right:
                                                                Radius.circular(
                                                                    10))),
                                                child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(Icons.timer_outlined,
                                                          size: 18,
                                                          color: _timerMode
                                                              ? Colors.white
                                                              : Colors
                                                                  .grey[600]),
                                                      const SizedBox(width: 6),
                                                      Text('Start Timer',
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: _timerMode
                                                                  ? Colors.white
                                                                  : Colors.grey[
                                                                      600]))
                                                    ])))),
                                  ])),
                              const SizedBox(height: 16),
                            ],

                            // ── Timer widget ───────────────────────────────────────────
                            if (_timerMode) ...[
                              _buildTimerWidget(),
                              const SizedBox(height: 16),
                            ],

                            // ── Project & Task ─────────────────────────────────────────
                            _section(
                                'Project & Task',
                                Icons.folder_outlined,
                                _teNavy,
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Project *',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF2C3E50))),
                                      const SizedBox(height: 6),
                                      _loadingProjects
                                          ? const SizedBox(
                                              height: 50,
                                              child: Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2)))
                                          : DropdownButtonFormField<Project>(
                                              value: _selectedProject,
                                              decoration: _dec('Select Project',
                                                  Icons.folder_outlined),
                                              items: _allProjects
                                                  .map((p) => DropdownMenuItem(
                                                      value: p,
                                                      child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text(p.projectName,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600)),
                                                            Text(p.customerName,
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    color: Colors
                                                                            .grey[
                                                                        600])),
                                                          ])))
                                                  .toList(),
                                              onChanged: (p) {
                                                if (p != null) _setProject(p);
                                              },
                                              validator: (v) => v == null
                                                  ? 'Project required'
                                                  : null,
                                            ),
                                      if (_selectedProject != null &&
                                          _projectTasks.isNotEmpty) ...[
                                        const SizedBox(height: 14),
                                        DropdownButtonFormField<ProjectTask?>(
                                            value: _selectedTask,
                                            decoration: _dec('Task (Optional)',
                                                Icons.task_outlined),
                                            items: [
                                              const DropdownMenuItem(
                                                  value: null,
                                                  child:
                                                      Text('No specific task')),
                                              ..._projectTasks.map((t) =>
                                                  DropdownMenuItem(
                                                      value: t,
                                                      child: Text(t.taskName)))
                                            ],
                                            onChanged: (t) => setState(
                                                () => _selectedTask = t)),
                                      ],
                                    ])),
                            const SizedBox(height: 16),

                            // ── Staff ──────────────────────────────────────────────────
                            _section(
                                'Staff Member',
                                Icons.person_outline,
                                _teBlue,
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _loadingStaff
                                          ? const SizedBox(
                                              height: 50,
                                              child: Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2)))
                                          : DropdownButtonFormField<String>(
                                              value: _selectedUserId,
                                              decoration: _dec(
                                                  'Staff Member (Optional)',
                                                  Icons.person_outline),
                                              items: [
                                                const DropdownMenuItem(
                                                    value: null,
                                                    child:
                                                        Text('Not assigned')),
                                                ..._allStaff.map((u) {
                                                  final id =
                                                      u['_id']?.toString() ??
                                                          '';
                                                  final name =
                                                      u['name']?.toString() ??
                                                          '';
                                                  return DropdownMenuItem(
                                                      value: id,
                                                      child: Row(children: [
                                                        CircleAvatar(
                                                            radius: 12,
                                                            backgroundColor:
                                                                _teNavy,
                                                            child: Text(
                                                                name.isNotEmpty
                                                                    ? name[0]
                                                                        .toUpperCase()
                                                                    : 'U',
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontSize:
                                                                        11))),
                                                        const SizedBox(
                                                            width: 8),
                                                        Expanded(
                                                            child: Text(name,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis)),
                                                      ]));
                                                }),
                                              ],
                                              onChanged: (v) {
                                                if (v == null) {
                                                  setState(() {
                                                    _selectedUserId = null;
                                                    _selectedUserName = null;
                                                    _selectedUserEmail = null;
                                                  });
                                                  return;
                                                }
                                                final user =
                                                    _allStaff.firstWhere(
                                                        (u) =>
                                                            u['_id']
                                                                ?.toString() ==
                                                            v,
                                                        orElse: () => {});
                                                setState(() {
                                                  _selectedUserId = v;
                                                  _selectedUserName =
                                                      user['name']
                                                              ?.toString() ??
                                                          '';
                                                  _selectedUserEmail =
                                                      user['email']
                                                              ?.toString() ??
                                                          '';
                                                });
                                              },
                                            ),
                                    ])),
                            const SizedBox(height: 16),

                            // ── Date & Hours (only in manual mode) ────────────────────
                            if (!_timerMode) ...[
                              _section(
                                  'Date & Time',
                                  Icons.schedule_outlined,
                                  _teOrange,
                                  Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                const Text('Date *',
                                                    style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            Color(0xFF2C3E50))),
                                                const SizedBox(height: 6),
                                                InkWell(
                                                    onTap: () async {
                                                      final d =
                                                          await showDatePicker(
                                                              context: context,
                                                              initialDate:
                                                                  _date,
                                                              firstDate:
                                                                  DateTime(
                                                                      2020),
                                                              lastDate: DateTime
                                                                  .now());
                                                      if (d != null)
                                                        setState(
                                                            () => _date = d);
                                                    },
                                                    child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(14),
                                                        decoration: BoxDecoration(
                                                            border: Border.all(
                                                                color:
                                                                    Colors.grey[
                                                                        300]!),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8),
                                                            color: const Color(
                                                                0xFFF7F9FC)),
                                                        child: Row(children: [
                                                          const Icon(
                                                              Icons
                                                                  .calendar_today,
                                                              size: 16,
                                                              color: _teNavy),
                                                          const SizedBox(
                                                              width: 8),
                                                          Text(DateFormat(
                                                                  'dd MMM yyyy')
                                                              .format(_date))
                                                        ]))),
                                              ])),
                                          const SizedBox(width: 12),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                const Text('Hours *',
                                                    style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            Color(0xFF2C3E50))),
                                                const SizedBox(height: 6),
                                                TextFormField(
                                                    controller: _hoursCtrl,
                                                    decoration: _dec(
                                                        'e.g. 8 or 2.5',
                                                        Icons.timer_outlined),
                                                    keyboardType:
                                                        const TextInputType
                                                            .numberWithOptions(
                                                            decimal: true),
                                                    onChanged: (v) => setState(
                                                        () => _hours =
                                                            double.tryParse(
                                                                    v) ??
                                                                0),
                                                    validator: (v) {
                                                      if (v == null ||
                                                          v.isEmpty)
                                                        return 'Required';
                                                      final h =
                                                          double.tryParse(v);
                                                      if (h == null || h <= 0)
                                                        return '> 0';
                                                      if (h > 24)
                                                        return 'Max 24';
                                                      return null;
                                                    }),
                                              ])),
                                        ]),
                                        const SizedBox(height: 14),
                                        // Billable toggle
                                        _buildBillableToggle(),
                                        const SizedBox(height: 10),
                                        // Submit for approval toggle
                                        _buildSubmitToggle(),
                                      ])),
                              const SizedBox(height: 16),
                            ],

                            // ── Billable + submit in timer mode ────────────────────────
                            if (_timerMode) ...[
                              _section(
                                  'Options',
                                  Icons.settings_outlined,
                                  Colors.grey,
                                  Column(children: [
                                    _buildBillableToggle(),
                                    const SizedBox(height: 10),
                                    _buildSubmitToggle()
                                  ])),
                              const SizedBox(height: 16),
                            ],

                            // ── Notes ──────────────────────────────────────────────────
                            _section(
                                'Notes',
                                Icons.notes_outlined,
                                Colors.grey,
                                Column(children: [
                                  TextFormField(
                                      controller: _notesCtrl,
                                      decoration: _dec(
                                          'What did you work on? (Optional)',
                                          Icons.notes_outlined),
                                      maxLines: 4),
                                ])),
                            const SizedBox(height: 16),

                            // ── Summary ────────────────────────────────────────────────
                            if (!_timerMode) ...[
                              Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                      color: _teNavy.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: _teNavy.withOpacity(0.15))),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('Entry Summary',
                                            style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: _teNavy)),
                                        const SizedBox(height: 12),
                                        if (_selectedProject != null)
                                          _summaryRow('Project',
                                              _selectedProject!.projectName),
                                        if (_selectedTask != null)
                                          _summaryRow(
                                              'Task', _selectedTask!.taskName),
                                        if (_selectedUserName != null)
                                          _summaryRow(
                                              'Staff', _selectedUserName!),
                                        _summaryRow(
                                            'Date',
                                            DateFormat('dd MMM yyyy')
                                                .format(_date)),
                                        _summaryRow('Hours',
                                            '${_hours.toStringAsFixed(2)} hrs'),
                                        _summaryRow('Billable',
                                            _isBillable ? 'Yes' : 'No'),
                                        _summaryRow(
                                            'Status',
                                            _submitForApproval
                                                ? 'Will be Submitted'
                                                : 'Saved as Unbilled'),
                                        const Divider(
                                            height: 20, thickness: 1.5),
                                        _summaryRow(
                                            'Est. Amount', _estimateAmount(),
                                            bold: true),
                                      ])),
                              const SizedBox(height: 16),
                              SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                      onPressed: _isSaving ? null : _save,
                                      icon: _isSaving
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  color: Colors.white,
                                                  strokeWidth: 2))
                                          : Icon(
                                              _submitForApproval
                                                  ? Icons.send_outlined
                                                  : Icons.check,
                                              size: 18),
                                      label: Text(
                                          _isSaving
                                              ? 'Saving…'
                                              : (_submitForApproval
                                                  ? 'Submit for Approval'
                                                  : (widget.entryId != null
                                                      ? 'Update Entry'
                                                      : 'Save Entry')),
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: _submitForApproval
                                              ? _teBlue
                                              : _teGreen,
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size(double.infinity, 52),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
                              const SizedBox(height: 8),
                              SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: OutlinedButton.styleFrom(
                                          foregroundColor: _teNavy,
                                          side:
                                              const BorderSide(color: _teNavy),
                                          minimumSize:
                                              const Size(double.infinity, 48),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12))),
                                      child: const Text('Cancel'))),
                            ],
                            const SizedBox(height: 20),
                          ]))),
            )),
    );
  }

  // ── Timer widget ───────────────────────────────────────────────────────────
  Widget _buildTimerWidget() {
    return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [_teNavy, _teNavy.withOpacity(0.85)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Text(_timerDisplay,
              style: const TextStyle(
                  fontSize: 52,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 4)),
          const SizedBox(height: 8),
          Text(
              _timerRunning
                  ? '⏱ Running…'
                  : _timerPaused
                      ? '⏸ Paused'
                      : 'Ready to start',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.8), fontSize: 14)),
          const SizedBox(height: 20),
          if (!_timerRunning && !_timerPaused) ...[
            SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _handleStartTimer,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: _teNavy, strokeWidth: 2))
                        : const Icon(Icons.play_arrow_rounded, size: 24),
                    label: const Text('Start Timer',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _teGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))))),
          ] else ...[
            Row(children: [
              Expanded(
                  child: ElevatedButton.icon(
                onPressed:
                    _timerRunning ? _handlePauseTimer : _handleResumeTimer,
                icon: Icon(
                    _timerRunning
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 20),
                label: Text(_timerRunning ? 'Pause' : 'Resume',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _teOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
              )),
              const SizedBox(width: 12),
              Expanded(
                  child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _handleStopTimer,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.stop_rounded, size: 20),
                label: const Text('Stop & Save',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _teRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
              )),
            ]),
            const SizedBox(height: 8),
            SizedBox(
                width: double.infinity,
                child: TextButton(
                    onPressed: _handleDiscardTimer,
                    child: Text('Discard Timer',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 13)))),
          ],
        ]));
  }

  Widget _buildBillableToggle() {
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFF7F9FC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!)),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Billable',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            Text(
                _isBillable ? 'Included in invoices' : 'Excluded from invoices',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ]),
          Switch(
              value: _isBillable,
              onChanged: (v) => setState(() => _isBillable = v),
              activeColor: _teGreen),
        ]));
  }

  Widget _buildSubmitToggle() {
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _submitForApproval
                ? _teBlue.withOpacity(0.06)
                : const Color(0xFFF7F9FC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: _submitForApproval
                    ? _teBlue.withOpacity(0.4)
                    : Colors.grey[300]!)),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Submit for Approval',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            Text(
                _submitForApproval
                    ? 'Will be sent to manager for approval'
                    : 'Saved as draft (Unbilled)',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ]),
          Switch(
              value: _submitForApproval,
              onChanged: (v) => setState(() => _submitForApproval = v),
              activeColor: _teBlue),
        ]));
  }

  String _estimateAmount() {
    if (_selectedProject == null || _hours <= 0) return '—';
    switch (_selectedProject!.billingMethod) {
      case 'Fixed Cost':
        return 'Fixed: ₹${_selectedProject!.fixedAmount.toStringAsFixed(2)}';
      case 'Based on Project Hours':
        return '₹${(_hours * _selectedProject!.hourlyRate).toStringAsFixed(2)}';
      case 'Based on Task Hours':
        return _selectedTask != null
            ? '₹${(_hours * _selectedTask!.hourlyRate).toStringAsFixed(2)}'
            : 'Select task';
      case 'Based on Staff Hours':
        {
          if (_selectedUserId != null) {
            final m = _selectedProject!.staff.firstWhere(
                (s) => s.userId == _selectedUserId,
                orElse: () => ProjectStaff(
                    userId: '',
                    name: '',
                    email: '',
                    role: 'staff',
                    hourlyRate: 0));
            return '₹${(_hours * m.hourlyRate).toStringAsFixed(2)}';
          }
          return 'Select staff';
        }
      default:
        return '—';
    }
  }

  Widget _section(String title, IconData icon, Color color, Widget child) {
    return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50)))
          ]),
          const SizedBox(height: 14),
          child,
        ]));
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style:
                  TextStyle(fontSize: bold ? 14 : 13, color: Colors.grey[700])),
          Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: bold ? 16 : 13,
                      fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                      color: bold ? _teNavy : const Color(0xFF2C3E50)),
                  overflow: TextOverflow.ellipsis)),
        ]));
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: Colors.grey[500]),
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _teNavy, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );
}
