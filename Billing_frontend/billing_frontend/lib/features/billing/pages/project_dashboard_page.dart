// ============================================================================
// PROJECT DASHBOARD PAGE — Flutter
// ============================================================================
// File: lib/screens/billing/pages/project_dashboard_page.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/config/api_config.dart';
import '../../../../core/services/timer_service.dart';
import '../app_top_bar.dart';
import 'new_time_entry.dart';

const Color _dbNavy   = Color(0xFF1e3a8a);
const Color _dbGreen  = Color(0xFF27AE60);
const Color _dbBlue   = Color(0xFF2980B9);
const Color _dbOrange = Color(0xFFE67E22);
const Color _dbRed    = Color(0xFFE74C3C);
const Color _dbPurple = Color(0xFF9B59B6);
const Color _dbTeal   = Color(0xFF00897B);

class ProjectDashboardPage extends StatefulWidget {
  final String projectId;
  final String projectName;
  const ProjectDashboardPage({Key? key, required this.projectId, required this.projectName}) : super(key: key);
  @override
  State<ProjectDashboardPage> createState() => _ProjectDashboardPageState();
}

class _ProjectDashboardPageState extends State<ProjectDashboardPage> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('finance_jwt_token') ?? prefs.getString('jwt_token') ?? '';
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/projects/${widget.projectId}/dashboard'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      );
      final body = json.decode(res.body) as Map<String, dynamic>;
      if (body['success'] == true) {
        setState(() { _data = body['data']; _isLoading = false; });
      } else {
        setState(() { _error = body['message']; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _stopTimer(Map<String, dynamic> timer) async {
    try {
      final result = await TimerService.stopTimer(timer['_id'].toString());
      _showSuccess('Timer stopped — ${result.hours} hrs logged');
      _load();
    } catch (e) { _showError('Failed: $e'); }
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: _dbGreen, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: _dbRed, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Project Dashboard'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _dbNavy))
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _buildProjectHeader(),
                      const SizedBox(height: 16),
                      _buildActiveTimers(),
                      const SizedBox(height: 16),
                      _buildKPICards(),
                      const SizedBox(height: 16),
                      _buildBudgetProgress(),
                      const SizedBox(height: 16),
                      LayoutBuilder(builder: (_, c) {
                        if (c.maxWidth > 800) {
                          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: _buildTaskBreakdown()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildStaffBreakdown()),
                          ]);
                        }
                        return Column(children: [
                          _buildTaskBreakdown(), const SizedBox(height: 16), _buildStaffBreakdown(),
                        ]);
                      }),
                      const SizedBox(height: 16),
                      _buildRecentEntries(),
                      const SizedBox(height: 16),
                      _buildQuickActions(),
                      const SizedBox(height: 24),
                    ]),
                  ),
                ),
    );
  }

  // ── Project header ─────────────────────────────────────────────────────────
  Widget _buildProjectHeader() {
    final p = _data?['project'] as Map<String, dynamic>? ?? {};
    final status = p['status']?.toString() ?? 'Active';
    final statusColors = <String, Color>{ 'Active': _dbGreen, 'Completed': _dbBlue, 'On Hold': _dbOrange, 'Inactive': Colors.grey };
    final color = statusColors[status] ?? Colors.grey;
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(
      gradient: LinearGradient(colors: [_dbNavy, _dbNavy.withOpacity(0.85)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(12),
    ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p['projectName']?.toString() ?? widget.projectName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(p['projectNumber']?.toString() ?? '', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
          const SizedBox(height: 4),
          Text('Customer: ${p['customerName'] ?? ''}', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
        ])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.5))),
          child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13))),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        _headerChip(Icons.business_center_outlined, p['billingMethod']?.toString() ?? ''),
        const SizedBox(width: 10),
        _headerChip(Icons.calendar_today_outlined, p['startDate'] != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(p['startDate'])) : '—'),
        if (p['endDate'] != null) ...[const SizedBox(width: 10), _headerChip(Icons.event_outlined, DateFormat('dd MMM yyyy').format(DateTime.parse(p['endDate'])))],
      ]),
    ]));
  }

  Widget _headerChip(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 14, color: Colors.white70), const SizedBox(width: 4),
    Text(text, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
  ]);

  // ── Active timers ──────────────────────────────────────────────────────────
  Widget _buildActiveTimers() {
    final timers = (_data?['activeTimers'] as List? ?? []).cast<Map<String, dynamic>>();
    if (timers.isEmpty) return const SizedBox.shrink();
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(
      color: _dbOrange.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _dbOrange.withOpacity(0.3)),
    ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 10, height: 10, decoration: const BoxDecoration(color: _dbOrange, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text('${timers.length} Active Timer${timers.length > 1 ? 's' : ''}', style: const TextStyle(fontWeight: FontWeight.bold, color: _dbOrange, fontSize: 15)),
      ]),
      const SizedBox(height: 12),
      ...timers.map((t) => _buildTimerRow(t)),
    ]));
  }

  Widget _buildTimerRow(Map<String, dynamic> t) {
    final elapsed = t['currentElapsedFormatted']?.toString() ?? '00:00:00';
    final isRunning = t['status'] == 'running';
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: isRunning ? _dbGreen : _dbOrange, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t['projectName']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if ((t['taskName']?.toString() ?? '').isNotEmpty) Text(t['taskName'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          Text(t['userName']?.toString() ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ])),
        Text(elapsed, style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 16, color: isRunning ? _dbGreen : _dbOrange)),
        const SizedBox(width: 8),
        InkWell(onTap: () => _stopTimer(t), borderRadius: BorderRadius.circular(6),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _dbRed.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: _dbRed.withOpacity(0.3))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.stop_circle_outlined, size: 14, color: _dbRed), const SizedBox(width: 4), const Text('Stop', style: TextStyle(color: _dbRed, fontSize: 12, fontWeight: FontWeight.w600))]))),
      ]));
  }

  // ── KPI Cards ──────────────────────────────────────────────────────────────
  Widget _buildKPICards() {
    final d = _data ?? {};
    final cards = [
      _KPI('Total Hours Logged', '${(d['totalLoggedHours'] ?? 0).toStringAsFixed(1)}h', Icons.access_time_outlined, _dbNavy),
      _KPI('Unbilled Hours', '${(d['unbilledHours'] ?? 0).toStringAsFixed(1)}h', Icons.schedule_outlined, _dbOrange),
      _KPI('Billed Amount', '₹${(d['totalBilledAmount'] ?? 0).toStringAsFixed(0)}', Icons.receipt_outlined, _dbGreen),
      _KPI('Unbilled Amount', '₹${(d['unbilledAmount'] ?? 0).toStringAsFixed(0)}', Icons.money_off_outlined, _dbPurple),
    ];
    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth > 700 ? 4 : 2;
      return GridView.count(
        crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: c.maxWidth > 700 ? 2.2 : 1.8,
        children: cards.map((k) => _buildKPICard(k)).toList(),
      );
    });
  }

  Widget _buildKPICard(_KPI k) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: k.color.withOpacity(0.2)),
      boxShadow: [BoxShadow(color: k.color.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3))],
    ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(k.icon, color: k.color, size: 22),
      const SizedBox(height: 8),
      Text(k.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 4),
      Text(k.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: k.color)),
    ]));
  }

  // ── Budget progress ────────────────────────────────────────────────────────
  Widget _buildBudgetProgress() {
    final d = _data ?? {};
    final budgetPercent = (d['budgetPercent'] ?? 0) as int;
    final budgetAmount  = (d['budgetAmount']  ?? 0).toDouble();
    final budgetUsed    = (d['budgetUsed']    ?? 0).toDouble();
    final remaining     = (d['remainingBudget'] ?? 0).toDouble();
    final p             = d['project'] as Map<String, dynamic>? ?? {};
    final budgetType    = p['budgetType']?.toString() ?? 'Cost';
    if (budgetAmount <= 0) return const SizedBox.shrink();
    final barColor = budgetPercent >= 90 ? _dbRed : budgetPercent >= 70 ? _dbOrange : _dbGreen;
    return _card('Budget Utilization', Icons.account_balance_wallet_outlined, _dbNavy,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$budgetType Budget', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Text('$budgetPercent% used', style: TextStyle(fontWeight: FontWeight.bold, color: barColor, fontSize: 14)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(
          value: budgetPercent / 100, minHeight: 14,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(barColor),
        )),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _budgetStat('Total Budget', budgetType == 'Hours' ? '${budgetAmount.toStringAsFixed(0)}h' : '₹${budgetAmount.toStringAsFixed(0)}', _dbNavy)),
          Expanded(child: _budgetStat('Used', budgetType == 'Hours' ? '${budgetUsed.toStringAsFixed(1)}h' : '₹${budgetUsed.toStringAsFixed(0)}', barColor)),
          Expanded(child: _budgetStat('Remaining', budgetType == 'Hours' ? '${remaining.toStringAsFixed(1)}h' : '₹${remaining.toStringAsFixed(0)}', _dbGreen)),
        ]),
      ]),
    );
  }

  Widget _budgetStat(String label, String value, Color color) => Column(children: [
    Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    const SizedBox(height: 4),
    Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
  ]);

  // ── Task breakdown ─────────────────────────────────────────────────────────
  Widget _buildTaskBreakdown() {
    final tasks = (_data?['taskBreakdown'] as List? ?? []).cast<Map<String, dynamic>>();
    return _card('Task Progress', Icons.task_outlined, _dbBlue,
      tasks.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('No tasks assigned', style: TextStyle(color: Colors.grey[500]))))
          : Column(children: tasks.map((t) => _buildTaskRow(t)).toList()),
    );
  }

  Widget _buildTaskRow(Map<String, dynamic> t) {
    final pct    = (t['completionPercent'] ?? 0).toDouble();
    final status = t['status']?.toString() ?? 'Open';
    final statusColors = <String, Color>{ 'Open': _dbBlue, 'In Progress': _dbOrange, 'Completed': _dbGreen };
    final color  = statusColors[status] ?? Colors.grey;
    return Container(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(t['taskName']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
          child: Text(status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600))),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        Text('${(t['loggedHours'] ?? 0).toStringAsFixed(1)}h / ${(t['estimatedHours'] ?? 0).toStringAsFixed(1)}h', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        if ((t['assignedStaff']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(width: 8),
          Icon(Icons.person_outline, size: 12, color: Colors.grey[500]),
          const SizedBox(width: 2),
          Text(t['assignedStaff'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
        const Spacer(),
        Text('${pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: pct >= 100 ? _dbGreen : _dbNavy)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
        value: pct / 100, minHeight: 6,
        backgroundColor: Colors.grey[200],
        valueColor: AlwaysStoppedAnimation<Color>(pct >= 100 ? _dbGreen : _dbBlue),
      )),
      if (t['deadline'] != null) ...[
        const SizedBox(height: 3),
        Text('Due: ${DateFormat('dd MMM yyyy').format(DateTime.parse(t['deadline']))}', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
      ],
      const Divider(height: 16),
    ]));
  }

  // ── Staff breakdown ────────────────────────────────────────────────────────
  Widget _buildStaffBreakdown() {
    final staff = (_data?['staffBreakdown'] as List? ?? []).cast<Map<String, dynamic>>();
    return _card('Staff Hours', Icons.people_outline, _dbPurple,
      staff.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('No time entries yet', style: TextStyle(color: Colors.grey[500]))))
          : Column(children: staff.map((s) => _buildStaffRow(s)).toList()),
    );
  }

  Widget _buildStaffRow(Map<String, dynamic> s) {
    final total    = (s['totalHours']    ?? 0).toDouble();
    final billable = (s['billableHours'] ?? 0).toDouble();
    final utilPct  = total > 0 ? (billable / total * 100).round() : 0;
    return Container(margin: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CircleAvatar(radius: 16, backgroundColor: _dbPurple.withOpacity(0.15), child: Text(
          (s['userName']?.toString() ?? 'U').isNotEmpty ? s['userName'].toString()[0].toUpperCase() : 'U',
          style: const TextStyle(color: _dbPurple, fontWeight: FontWeight.bold, fontSize: 13),
        )),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['userName']?.toString() ?? 'Unassigned', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text('${total.toStringAsFixed(1)}h total • ${billable.toStringAsFixed(1)}h billable • $utilPct% utilization', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ])),
      ]),
      const Divider(height: 14),
    ]));
  }

  // ── Recent entries ─────────────────────────────────────────────────────────
  Widget _buildRecentEntries() {
    final entries = (_data?['recentEntries'] as List? ?? []).cast<Map<String, dynamic>>();
    if (entries.isEmpty) return const SizedBox.shrink();
    return _card('Recent Time Entries', Icons.history_outlined, _dbTeal,
      Column(children: entries.take(5).map((e) => _buildEntryRow(e)).toList()),
    );
  }

  Widget _buildEntryRow(Map<String, dynamic> e) {
    final status = e['status']?.toString() ?? 'Unbilled';
    final statusColors = <String, Color>{ 'Unbilled': _dbOrange, 'Submitted': _dbBlue, 'Approved': _dbGreen, 'Billed': _dbTeal, 'Rejected': _dbRed };
    final color = statusColors[status] ?? Colors.grey;
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF7F9FC), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e['date'] != null ? DateFormat('dd MMM').format(DateTime.parse(e['date'])) : '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ]),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e['userName']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          if ((e['taskName']?.toString() ?? '').isNotEmpty) Text(e['taskName'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ])),
        Text('${(e['hours'] ?? 0).toStringAsFixed(1)}h', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _dbNavy)),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Text(status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700))),
      ]));
  }

  // ── Quick actions ──────────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    return Row(children: [
      Expanded(child: ElevatedButton.icon(
        onPressed: () async {
          final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => const NewTimeEntryScreen()));
          if (ok == true) _load();
        },
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Log Time'),
        style: ElevatedButton.styleFrom(backgroundColor: _dbNavy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      )),
      const SizedBox(width: 12),
      Expanded(child: OutlinedButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Refresh'),
        style: OutlinedButton.styleFrom(foregroundColor: _dbNavy, side: const BorderSide(color: _dbNavy), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      )),
    ]);
  }

  // ── Error state ────────────────────────────────────────────────────────────
  Widget _buildError() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.error_outline, size: 60, color: _dbRed),
    const SizedBox(height: 16),
    Text(_error ?? 'Unknown error', textAlign: TextAlign.center),
    const SizedBox(height: 16),
    ElevatedButton(onPressed: _load, child: const Text('Retry')),
  ]));

  // ── Card wrapper ───────────────────────────────────────────────────────────
  Widget _card(String title, IconData icon, Color color, Widget child) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
    ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)))]),
      const SizedBox(height: 14),
      child,
    ]));
  }
}

class _KPI {
  final String label, value;
  final IconData icon;
  final Color color;
  const _KPI(this.label, this.value, this.icon, this.color);
}