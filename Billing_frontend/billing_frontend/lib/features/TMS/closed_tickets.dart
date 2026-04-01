// lib/screens/tms/closed_tickets_screen.dart
// ============================================================================
// 🎫 CLOSED TICKETS SCREEN - Historical View with Table & Export
// ============================================================================
// Features:
// - Shows tickets with status = "closed"
// - Single row filters (Search, Date Range, Assigned To)
// - Table format with horizontal & vertical scrolling
// - Cell spacing and padding
// - Export to Excel functionality (like invoices_list_page.dart)
// - Reopen functionality
// - Statistics (Total, Today, This Week, This Month)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/services/tms_service.dart';
import '../../core/utils/export_helper.dart';

class ClosedTicketsScreen extends StatefulWidget {
  const ClosedTicketsScreen({Key? key}) : super(key: key);

  @override
  State<ClosedTicketsScreen> createState() => _ClosedTicketsScreenState();
}

class _ClosedTicketsScreenState extends State<ClosedTicketsScreen> {
  final _tmsService = TMSService();
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _filteredTickets = [];
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;
  bool _loadingEmployees = true;
  bool _isExporting = false; // For export button state

  // Filters
  String _assignedToFilter = '';
  String _searchQuery = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  // Statistics
  int _totalClosed = 0;
  int _todayClosed = 0;
  int _weekClosed = 0;
  int _monthClosed = 0;

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
    _fetchTickets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ========================================================================
  // 📦 FETCH EMPLOYEES
  // ========================================================================
  Future<void> _fetchEmployees() async {
    setState(() => _loadingEmployees = true);

    final response = await _tmsService.fetchEmployees();

    if (response['success'] == true && response['data'] != null) {
      setState(() {
        _employees = List<Map<String, dynamic>>.from(response['data']);
        _loadingEmployees = false;
      });
    } else {
      setState(() => _loadingEmployees = false);
    }
  }

  // ========================================================================
  // 📦 FETCH CLOSED TICKETS
  // ========================================================================
  Future<void> _fetchTickets() async {
    setState(() => _isLoading = true);

    final response = await _tmsService.fetchClosedTickets(
      dateFrom: _dateFrom?.toIso8601String(),
      dateTo: _dateTo?.toIso8601String(),
      assignedTo: _assignedToFilter.isEmpty ? null : _assignedToFilter,
    );

    if (response['success'] == true && response['data'] != null) {
      setState(() {
        _tickets = List<Map<String, dynamic>>.from(response['data']);
        _applyFilters();
        _calculateStatistics();
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to load closed tickets');
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredTickets = _tickets.where((ticket) {
        if (_searchQuery.isNotEmpty) {
          final subject = ticket['subject']?.toString().toLowerCase() ?? '';
          final ticketNumber =
              ticket['ticket_number']?.toString().toLowerCase() ?? '';
          final query = _searchQuery.toLowerCase();

          if (!subject.contains(query) && !ticketNumber.contains(query)) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  void _calculateStatistics() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    _totalClosed = _tickets.length;
    _todayClosed = 0;
    _weekClosed = 0;
    _monthClosed = 0;

    for (final ticket in _tickets) {
      final updatedAt = ticket['updated_at'];
      if (updatedAt != null) {
        final date = DateTime.tryParse(updatedAt);
        if (date != null) {
          if (date.isAfter(today)) _todayClosed++;
          if (date.isAfter(weekStart)) _weekClosed++;
          if (date.isAfter(monthStart)) _monthClosed++;
        }
      }
    }
  }

  // ========================================================================
  // 🔄 REOPEN TICKET
  // ========================================================================
  Future<void> _reopenTicket(String ticketId) async {
    final response = await _tmsService.reopenTicket(ticketId);

    if (response['success'] == true) {
      _showSuccessSnackbar('Ticket reopened successfully!');
      setState(() {
        _tickets.removeWhere((t) => t['_id'].toString() == ticketId);
        _applyFilters();
        _calculateStatistics();
      });
    } else {
      _showErrorSnackbar('Failed to reopen ticket');
    }
  }

  void _showReopenConfirmation(String ticketId, String ticketNumber) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reopen Ticket?'),
        content: Text(
          'Are you sure you want to reopen ticket $ticketNumber? Its status will be set to "Open".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _reopenTicket(ticketId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
            ),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // 📅 DATE PICKER
  // ========================================================================
  Future<void> _pickDate(bool isFrom) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_dateFrom ?? DateTime.now())
          : (_dateTo ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (date != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = date;
        } else {
          _dateTo = date;
        }
      });
      _fetchTickets();
    }
  }

  void _clearDateFilters() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
    });
    _fetchTickets();
  }

  // ========================================================================
  // 📤 EXPORT TO EXCEL
  // ========================================================================
  Future<void> _exportToExcel() async {
    if (_filteredTickets.isEmpty) {
      _showErrorSnackbar('No tickets to export');
      return;
    }

    setState(() => _isExporting = true);

    try {
      _showSuccessSnackbar('Preparing Excel export...');

      // Prepare data for export
      List<List<dynamic>> csvData = [
        // Headers
        [
          'Ticket Number',
          'Subject',
          'Priority',
          'Status',
          'Assigned To',
          'Timeline (minutes)',
          'Deadline',
          'Closed Date',
          'Created At',
        ],
      ];

      print('📊 Exporting ${_filteredTickets.length} closed tickets...');

      // Add data rows
      for (var ticket in _filteredTickets) {
        final ticketNumber = ticket['ticket_number'] ?? 'N/A';
        final subject = ticket['subject'] ?? 'No Subject';
        final priority = ticket['priority'] ?? 'Medium';
        final status = 'Closed';
        final assignedToName = ticket['assigned_to_name'] ?? 'Unassigned';
        final timeline = ticket['timeline']?.toString() ?? 'Not Set';
        final deadline = ticket['deadline'] != null
            ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(ticket['deadline']))
            : 'No deadline';
        final closedDate = ticket['updated_at'] != null
            ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(ticket['updated_at']))
            : '';
        final createdAt = ticket['created_at'] != null
            ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(ticket['created_at']))
            : '';

        csvData.add([
          ticketNumber,
          subject,
          priority,
          status,
          assignedToName,
          timeline,
          deadline,
          closedDate,
          createdAt,
        ]);
      }

      // Use ExportHelper to export
      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'closed_tickets_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
      );

      _showSuccessSnackbar('✅ Excel file downloaded with ${_filteredTickets.length} tickets!');
    } catch (e) {
      print('❌ Export Error: $e');
      _showErrorSnackbar('Failed to export: $e');
    } finally {
      setState(() => _isExporting = false);
    }
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        elevation: 0,
        title: const Text(
          'Closed Tickets Archive',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchTickets,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildStatistics(),
                  _buildSingleRowFilters(),
                  _buildTicketsTable(),
                ],
              ),
            ),
    );
  }

  // ========================================================================
  // 📊 STATISTICS - Colorful Cards with Symbols
  // ========================================================================
  Widget _buildStatistics() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Total Closed',
              _totalClosed,
              Icons.archive_rounded,
              const Color(0xFF3B82F6), // Blue
              const Color(0xFFDCEEFF),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Today',
              _todayClosed,
              Icons.today_rounded,
              const Color(0xFF10B981), // Green
              const Color(0xFFD1FAE5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'This Week',
              _weekClosed,
              Icons.date_range_rounded,
              const Color(0xFF8B5CF6), // Purple
              const Color(0xFFEDE9FE),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'This Month',
              _monthClosed,
              Icons.calendar_month_rounded,
              const Color(0xFFEC4899), // Pink
              const Color(0xFFFCE7F3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    int count,
    IconData icon,
    Color iconColor,
    Color bgColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // 🔍 SINGLE ROW FILTERS
  // ========================================================================
  Widget _buildSingleRowFilters() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Search Bar
          Expanded(
            flex: 3,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search tickets...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _applyFilters();
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _applyFilters();
                });
              },
            ),
          ),
          const SizedBox(width: 12),

          // From Date
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _pickDate(true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _dateFrom != null ? const Color(0xFF1E3A8A).withOpacity(0.1) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _dateFrom != null ? const Color(0xFF1E3A8A) : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: _dateFrom != null ? const Color(0xFF1E3A8A) : Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _dateFrom == null
                            ? 'From Date'
                            : DateFormat('MMM dd, yyyy').format(_dateFrom!),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _dateFrom != null ? FontWeight.w600 : FontWeight.normal,
                          color: _dateFrom != null ? const Color(0xFF1E3A8A) : Colors.grey[700],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // To Date
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _pickDate(false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _dateTo != null ? const Color(0xFF1E3A8A).withOpacity(0.1) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _dateTo != null ? const Color(0xFF1E3A8A) : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: _dateTo != null ? const Color(0xFF1E3A8A) : Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _dateTo == null
                            ? 'To Date'
                            : DateFormat('MMM dd, yyyy').format(_dateTo!),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _dateTo != null ? FontWeight.w600 : FontWeight.normal,
                          color: _dateTo != null ? const Color(0xFF1E3A8A) : Colors.grey[700],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Clear Date Filters
          if (_dateFrom != null || _dateTo != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: _clearDateFilters,
              tooltip: 'Clear Dates',
              style: IconButton.styleFrom(
                backgroundColor: Colors.red[50],
                padding: const EdgeInsets.all(8),
              ),
            ),
          ],
          const SizedBox(width: 12),

          // Assigned To Dropdown
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: _assignedToFilter,
              decoration: InputDecoration(
                labelText: 'Assigned To',
                labelStyle: const TextStyle(fontSize: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
              ),
              items: [
                const DropdownMenuItem(
                    value: '', child: Text('All', style: TextStyle(fontSize: 12))),
                const DropdownMenuItem(
                    value: '0', child: Text('Unassigned', style: TextStyle(fontSize: 12))),
                ..._employees.map((emp) {
                  return DropdownMenuItem<String>(
                    value: emp['_id'].toString(),
                    child: Text(
                      emp['name_parson'] ?? 'Unknown',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
              ],
              onChanged: (value) {
                setState(() => _assignedToFilter = value ?? '');
                _fetchTickets();
              },
            ),
          ),
          const SizedBox(width: 12),

          // Export Button
          ElevatedButton.icon(
            onPressed: _isExporting ? null : _exportToExcel,
            icon: _isExporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.file_download, size: 18),
            label: Text(
              _isExporting ? 'Exporting...' : 'Export',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // 📋 TICKETS TABLE - Full Page with All Information
  // ========================================================================
  Widget _buildTicketsTable() {
    if (_filteredTickets.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.archive_outlined, size: 80, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                'No closed tickets found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'There are no tickets with closed status',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E3A8A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.archive_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 12),
                Text(
                  'Closed Tickets (${_filteredTickets.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Table Content with Horizontal & Vertical Scrolling + Cursor Support
          Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height - 400,
            ),
            child: Scrollbar(
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Scrollbar(
                  thumbVisibility: true,
                  trackVisibility: true,
                  notificationPredicate: (notification) => notification.depth == 1,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 32,
                      horizontalMargin: 24,
                      headingRowHeight: 60,
                      dataRowHeight: 80,
                      headingRowColor: MaterialStateProperty.all(
                        const Color(0xFFF9FAFB),
                      ),
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: Colors.grey[200]!,
                          width: 1,
                        ),
                      ),
                      dividerThickness: 1,
                      columns: const [
                  DataColumn(
                    label: Text(
                      'Ticket #',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Subject',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Priority',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Created By',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Assigned To',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Timeline',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Created At',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Deadline',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Closed Date',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Actions',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                ],
                rows: _filteredTickets.map((ticket) {
                  return DataRow(
                    cells: [
                      // Ticket Number
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E3A8A),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            ticket['ticket_number'] ?? 'N/A',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      // Subject
                      DataCell(
                        Container(
                          constraints: const BoxConstraints(maxWidth: 250),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Text(
                            ticket['subject'] ?? 'No Subject',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ),

                      // Priority
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: _buildPriorityBadge(ticket['priority'] ?? 'Medium'),
                        ),
                      ),

                      // Created By
                      DataCell(
                        Container(
                          constraints: const BoxConstraints(maxWidth: 150),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ticket['creator_name'] ?? 'Unknown',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (ticket['creator_email'] != null)
                                Text(
                                  ticket['creator_email'],
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Assigned To
                      DataCell(
                        Container(
                          constraints: const BoxConstraints(maxWidth: 150),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Text(
                            ticket['assigned_to_name'] ?? 'Unassigned',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: ticket['assigned_to_name'] != null
                                  ? const Color(0xFF1F2937)
                                  : Colors.grey[500],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                      // Timeline
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: _buildTimelineBadge(ticket['timeline']),
                        ),
                      ),

                      // Created At
                      DataCell(
                        Container(
                          constraints: const BoxConstraints(maxWidth: 140),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ticket['created_at'] != null
                                    ? DateFormat('MMM dd, yyyy').format(
                                        DateTime.parse(ticket['created_at']))
                                    : 'N/A',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              if (ticket['created_at'] != null)
                                Text(
                                  DateFormat('hh:mm a').format(
                                      DateTime.parse(ticket['created_at'])),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Deadline
                      DataCell(
                        Container(
                          constraints: const BoxConstraints(maxWidth: 140),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ticket['deadline'] != null
                                    ? DateFormat('MMM dd, yyyy').format(
                                        DateTime.parse(ticket['deadline']))
                                    : 'No deadline',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ticket['deadline'] != null
                                      ? const Color(0xFF1F2937)
                                      : Colors.grey[500],
                                ),
                              ),
                              if (ticket['deadline'] != null)
                                Text(
                                  DateFormat('hh:mm a').format(
                                      DateTime.parse(ticket['deadline'])),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Closed Date - Use closed_at if available, otherwise updated_at
                      DataCell(
                        Container(
                          constraints: const BoxConstraints(maxWidth: 140),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getClosedDate(ticket) != null
                                    ? DateFormat('MMM dd, yyyy').format(_getClosedDate(ticket)!)
                                    : 'N/A',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              if (_getClosedDate(ticket) != null)
                                Text(
                                  DateFormat('hh:mm a').format(_getClosedDate(ticket)!),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Actions
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: ElevatedButton.icon(
                            onPressed: () => _showReopenConfirmation(
                              ticket['_id'].toString(),
                              ticket['ticket_number'] ?? 'N/A',
                            ),
                            icon: const Icon(Icons.replay_rounded, size: 16),
                            label: const Text(
                              'Reopen',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A8A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
                    ), // DataTable
                  ), // SingleChildScrollView (horizontal)
                ), // Scrollbar (inner)
              ), // SingleChildScrollView (vertical)
            ), // Scrollbar (outer)
          ), // Container
        ],
      ),
    );
  }

  // ========================================================================
  // 🕒 GET CLOSED DATE - Use closed_at if available, otherwise updated_at
  // ========================================================================
  DateTime? _getClosedDate(Map<String, dynamic> ticket) {
    // First try to get closed_at field (if backend provides it)
    if (ticket['closed_at'] != null) {
      try {
        return DateTime.parse(ticket['closed_at']);
      } catch (e) {
        print('Error parsing closed_at: $e');
      }
    }
    
    // Fallback to updated_at (when ticket status changed to closed)
    if (ticket['updated_at'] != null) {
      try {
        return DateTime.parse(ticket['updated_at']);
      } catch (e) {
        print('Error parsing updated_at: $e');
      }
    }
    
    return null;
  }

  Widget _buildPriorityBadge(String priority) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _getPriorityColor(priority).withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getPriorityColor(priority)),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: _getPriorityColor(priority),
        ),
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return const Color(0xFFDC2626);
      case 'medium':
        return const Color(0xFFD97706);
      case 'low':
        return const Color(0xFF16A34A);
      default:
        return Colors.grey;
    }
  }

  Widget _buildTimelineBadge(int? minutes) {
    if (minutes == null || minutes <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 14, color: Color(0xFF9CA3AF)),
            SizedBox(width: 4),
            Flexible(
              child: Text(
                'Not Set',
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0369A1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, size: 14, color: Color(0xFF0369A1)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _formatTimeline(minutes),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0369A1),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeline(int minutes) {
    if (minutes < 60) return '$minutes min';
    if (minutes < 1440) {
      final hours = (minutes / 60).floor();
      return '$hours hour${hours > 1 ? 's' : ''}';
    }
    if (minutes < 10080) {
      final days = (minutes / 1440).floor();
      return '$days day${days > 1 ? 's' : ''}';
    }
    if (minutes < 43200) {
      final weeks = (minutes / 10080).floor();
      return '$weeks week${weeks > 1 ? 's' : ''}';
    }
    final months = (minutes / 43200).floor();
    return '$months month${months > 1 ? 's' : ''}';
  }
}