// // lib/screens/tms/ticket_detail_screen.dart
// // ============================================================================
// // 🎫 TICKET DETAIL SCREEN - View Single Ticket Details
// // ============================================================================

// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import '../../core/services/tms_service.dart';

// class TicketDetailScreen extends StatefulWidget {
//   final String ticketId;

//   const TicketDetailScreen({Key? key, required this.ticketId}) : super(key: key);

//   @override
//   State<TicketDetailScreen> createState() => _TicketDetailScreenState();
// }

// class _TicketDetailScreenState extends State<TicketDetailScreen> {
//   final _tmsService = TMSService();
//   Map<String, dynamic>? _ticket;
//   bool _isLoading = true;

//   @override
//   void initState() {
//     super.initState();
//     _fetchTicket();
//   }

//   Future<void> _fetchTicket() async {
//     setState(() => _isLoading = true);

//     final response = await _tmsService.fetchTicket(widget.ticketId);

//     if (response['success'] == true && response['data'] != null) {
//       setState(() {
//         _ticket = response['data'];
//         _isLoading = false;
//       });
//     } else {
//       setState(() => _isLoading = false);
//       _showErrorSnackbar('Failed to load ticket');
//     }
//   }

//   void _showErrorSnackbar(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Colors.red,
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF5F7FA),
//       appBar: AppBar(
//         backgroundColor: Colors.white,
//         elevation: 0,
//         leading: IconButton(
//           icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
//           onPressed: () => Navigator.pop(context),
//         ),
//         title: Text(
//           _ticket?['ticket_number'] ?? 'Ticket Details',
//           style: const TextStyle(
//             color: Color(0xFF1E293B),
//             fontWeight: FontWeight.bold,
//           ),
//         ),
//       ),
//       body: _isLoading
//           ? const Center(child: CircularProgressIndicator())
//           : _ticket == null
//               ? const Center(child: Text('Ticket not found'))
//               : SingleChildScrollView(
//                   padding: const EdgeInsets.all(16),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       _buildHeaderCard(),
//                       const SizedBox(height: 16),
//                       _buildDetailsCard(),
//                       const SizedBox(height: 16),
//                       _buildTimelineCard(),
//                       const SizedBox(height: 16),
//                       _buildAssignmentCard(),
//                     ],
//                   ),
//                 ),
//     );
//   }

//   Widget _buildHeaderCard() {
//     final subject = _ticket!['subject'] ?? 'No Subject';
//     final priority = _ticket!['priority'] ?? 'Medium';
//     final status = _ticket!['status'] ?? 'Open';

//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 10,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               _buildPriorityBadge(priority),
//               const SizedBox(width: 12),
//               _buildStatusBadge(status),
//             ],
//           ),
//           const SizedBox(height: 16),
//           Text(
//             subject,
//             style: const TextStyle(
//               fontSize: 20,
//               fontWeight: FontWeight.bold,
//               color: Color(0xFF1E293B),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildDetailsCard() {
//     final message = _ticket!['message'] ?? 'No message';

//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 10,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'Description',
//             style: TextStyle(
//               fontSize: 16,
//               fontWeight: FontWeight.bold,
//               color: Color(0xFF1E293B),
//             ),
//           ),
//           const SizedBox(height: 12),
//           Text(
//             message,
//             style: const TextStyle(
//               fontSize: 14,
//               color: Color(0xFF64748B),
//               height: 1.5,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildTimelineCard() {
//     final timeline = _ticket!['timeline'];
//     final deadline = _ticket!['deadline'];
//     final createdAt = _ticket!['created_at'];

//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 10,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'Timeline',
//             style: TextStyle(
//               fontSize: 16,
//               fontWeight: FontWeight.bold,
//               color: Color(0xFF1E293B),
//             ),
//           ),
//           const SizedBox(height: 16),
//           _buildInfoRow(Icons.access_time, 'Created',
//               _formatDateTime(createdAt)),
//           const SizedBox(height: 12),
//           _buildInfoRow(
//               Icons.timer, 'Timeline', _formatTimeline(timeline)),
//           const SizedBox(height: 12),
//           _buildInfoRow(Icons.event, 'Deadline', _formatDateTime(deadline)),
//         ],
//       ),
//     );
//   }

//   Widget _buildAssignmentCard() {
//     final assignedToName = _ticket!['assigned_to_name'] ?? 'Unassigned';
//     final assignedToEmail = _ticket!['assigned_to_email'] ?? '';
//     final createdByName = _ticket!['created_by_name'] ?? 'Unknown';
//     final createdByEmail = _ticket!['created_by_email'] ?? '';

//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 10,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'Assignment',
//             style: TextStyle(
//               fontSize: 16,
//               fontWeight: FontWeight.bold,
//               color: Color(0xFF1E293B),
//             ),
//           ),
//           const SizedBox(height: 16),
//           _buildInfoRow(
//               Icons.person, 'Assigned To', '$assignedToName\n$assignedToEmail'),
//           const SizedBox(height: 12),
//           _buildInfoRow(
//               Icons.person_outline, 'Created By', '$createdByName\n$createdByEmail'),
//         ],
//       ),
//     );
//   }

//   Widget _buildInfoRow(IconData icon, String label, String value) {
//     return Row(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Icon(icon, color: const Color(0xFF3B82F6), size: 20),
//         const SizedBox(width: 12),
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 label,
//                 style: const TextStyle(
//                   fontSize: 12,
//                   color: Color(0xFF94A3B8),
//                   fontWeight: FontWeight.w500,
//                 ),
//               ),
//               const SizedBox(height: 4),
//               Text(
//                 value,
//                 style: const TextStyle(
//                   fontSize: 14,
//                   color: Color(0xFF1E293B),
//                   fontWeight: FontWeight.w600,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildPriorityBadge(String priority) {
//     Color color;
//     switch (priority.toLowerCase()) {
//       case 'high':
//         color = const Color(0xFFEF4444);
//         break;
//       case 'medium':
//         color = const Color(0xFFF59E0B);
//         break;
//       case 'low':
//         color = const Color(0xFF10B981);
//         break;
//       default:
//         color = Colors.grey;
//     }

//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//       decoration: BoxDecoration(
//         color: color.withOpacity(0.1),
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(color: color),
//       ),
//       child: Text(
//         priority.toUpperCase(),
//         style: TextStyle(
//           fontSize: 12,
//           fontWeight: FontWeight.bold,
//           color: color,
//         ),
//       ),
//     );
//   }

//   Widget _buildStatusBadge(String status) {
//     Color color;
//     switch (status) {
//       case 'Open':
//         color = const Color(0xFFEF4444);
//         break;
//       case 'In Progress':
//         color = const Color(0xFFF59E0B);
//         break;
//       case 'closed':
//         color = const Color(0xFF10B981);
//         break;
//       default:
//         color = Colors.grey;
//     }

//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//       decoration: BoxDecoration(
//         color: color.withOpacity(0.1),
//         borderRadius: BorderRadius.circular(12),
//       ),
//       child: Text(
//         status,
//         style: TextStyle(
//           fontSize: 12,
//           fontWeight: FontWeight.w600,
//           color: color,
//         ),
//       ),
//     );
//   }

//   String _formatTimeline(int? minutes) {
//     if (minutes == null || minutes <= 0) return 'Not Set';
//     if (minutes < 60) return '$minutes minutes';
//     if (minutes < 1440) return '${(minutes / 60).floor()} hours';
//     if (minutes < 10080) return '${(minutes / 1440).floor()} days';
//     return '${(minutes / 10080).floor()} weeks';
//   }

//   String _formatDateTime(String? dateStr) {
//     if (dateStr == null || dateStr.isEmpty) return 'N/A';
//     final date = DateTime.tryParse(dateStr);
//     if (date == null) return 'Invalid';
//     return DateFormat('MMM dd, yyyy \'at\' hh:mm a').format(date);
//   }
// }



// lib/screens/tms/ticket_detail_screen.dart
// ============================================================================
// 🎫 TICKET DETAIL SCREEN - Complete Ticket Information
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/services/tms_service.dart';

class TicketDetailScreen extends StatefulWidget {
  final Map<String, dynamic> ticket;

  const TicketDetailScreen({Key? key, required this.ticket}) : super(key: key);

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen>
    with SingleTickerProviderStateMixin {
  final _tmsService = TMSService();
  late Map<String, dynamic> _ticket;
  bool _isUpdating = false;

  // Custom color scheme
  static const Color darkBlue = Color(0xFF042E45);
  static const Color mediumBlue = Color(0xFF186285);
  static const Color lightBlue = Color(0xFFEBF2F5);
  static const Color accentBlue = Color(0xFF186285);

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _setupAnimation();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _setupAnimation() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _fadeController.forward();
  }

  Future<void> _updateStatus(String newStatus) async {
    if (newStatus == 'closed') {
      _showCloseConfirmation(newStatus);
      return;
    }

    setState(() => _isUpdating = true);

    final response = await _tmsService.updateTicketStatus(
      _ticket['_id'].toString(),
      newStatus,
    );

    setState(() => _isUpdating = false);

    if (response['success'] == true) {
      setState(() {
        _ticket['status'] = newStatus;
      });
      _showSuccessSnackbar('Status updated successfully!');
    } else {
      _showErrorSnackbar('Failed to update status');
    }
  }

  void _showCloseConfirmation(String newStatus) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning, color: Color(0xFFEF4444)),
            ),
            const SizedBox(width: 12),
            const Text(
              'Close Ticket?',
              style: TextStyle(color: Color(0xFF1E293B), fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to close this ticket? This action cannot be easily undone.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isUpdating = true);

              final response = await _tmsService.updateTicketStatus(
                _ticket['_id'].toString(),
                newStatus,
              );

              setState(() => _isUpdating = false);

              if (response['success'] == true) {
                _showSuccessSnackbar('Ticket closed successfully!');
                Navigator.pop(context, true);
              } else {
                _showErrorSnackbar('Failed to close ticket');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Close Ticket', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
            Text(message),
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
    final ticketNumber = _ticket['ticket_number'] ?? 'N/A';
    final subject = _ticket['subject'] ?? 'No Subject';
    final message = _ticket['message'] ?? 'No message';
    final priority = _ticket['priority'] ?? 'Medium';
    final status = _ticket['status'] ?? 'Open';
    final timeline = _ticket['timeline'];
    final deadline = _ticket['deadline'];
    final createdAt = _ticket['created_at'];
    final assignedTo = _ticket['assigned_to'];
    final attachment = _ticket['attachment'];

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
          onPressed: () => Navigator.pop(context, _ticket['status'] != widget.ticket['status']),
        ),
        title: const Text(
          'Ticket Details',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCard(ticketNumber, priority, status),
              const SizedBox(height: 20),
              _buildInfoSection('Subject', subject, Icons.text_fields),
              const SizedBox(height: 16),
              _buildInfoSection('Message', message, Icons.message, isMultiline: true),
              const SizedBox(height: 16),
              _buildPrioritySection(priority),
              const SizedBox(height: 16),
              _buildTimelineSection(timeline, deadline),
              const SizedBox(height: 16),
              _buildDateSection(createdAt, deadline),
              const SizedBox(height: 16),
              if (assignedTo != null) _buildAssignedToSection(assignedTo),
              if (assignedTo != null) const SizedBox(height: 16),
              if (attachment != null && attachment.toString().isNotEmpty)
                _buildAttachmentSection(attachment),
              if (attachment != null && attachment.toString().isNotEmpty)
                const SizedBox(height: 16),
              _buildStatusUpdateSection(status),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(String ticketNumber, String priority, String status) {
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
            ticketNumber,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildHeaderBadge(priority, _getPriorityIcon(priority), _getPriorityColor(priority)),
              const SizedBox(width: 12),
              _buildHeaderBadge(status, Icons.info, _getStatusColor(status)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBadge(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String label, String value, IconData icon, {bool isMultiline = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: mediumBlue),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: darkBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF1E293B),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrioritySection(String priority) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.flag, size: 20, color: mediumBlue),
              ),
              const SizedBox(width: 12),
              Text(
                'Priority Level',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: darkBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: ['Low', 'Medium', 'High'].map((p) {
              final isSelected = p == priority;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              colors: [
                                _getPriorityColor(p),
                                _getPriorityColor(p).withOpacity(0.8),
                              ],
                            )
                          : null,
                      color: isSelected ? null : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? _getPriorityColor(p)
                            : Colors.grey.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _getPriorityIcon(p),
                          size: 16,
                          color: isSelected ? Colors.white : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          p,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineSection(int? timeline, String? deadline) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.timer, size: 20, color: mediumBlue),
              ),
              const SizedBox(width: 12),
              Text(
                'Timeline',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: darkBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentBlue.withOpacity(0.1),
                  mediumBlue.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentBlue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, color: mediumBlue, size: 24),
                const SizedBox(width: 12),
                Text(
                  timeline != null ? _formatTimeline(timeline) : 'Not set',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: darkBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSection(String? createdAt, String? deadline) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.calendar_today, size: 20, color: mediumBlue),
              ),
              const SizedBox(width: 12),
              Text(
                'Important Dates',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: darkBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDateRow('Created', createdAt, Icons.add_circle_outline, const Color(0xFF10B981)),
          if (deadline != null && deadline.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildDateRow('Deadline', deadline, Icons.access_time_filled, _getDeadlineColor(deadline)),
          ],
        ],
      ),
    );
  }

  Widget _buildDateRow(String label, String? dateStr, IconData icon, Color color) {
    final formattedDate = _formatDate(dateStr);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color.withOpacity(0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formattedDate,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedToSection(dynamic assignedTo) {
    String name = 'Not assigned';
    String email = '';

    if (assignedTo is Map) {
      name = assignedTo['name_parson'] ?? assignedTo['name'] ?? 'Not assigned';
      email = assignedTo['email'] ?? '';
    } else if (assignedTo is String) {
      name = assignedTo;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.person, size: 20, color: mediumBlue),
              ),
              const SizedBox(width: 12),
              Text(
                'Assigned To',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: darkBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: mediumBlue,
                child: Text(
                  name[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: darkBlue,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentSection(dynamic attachment) {
    String fileName = 'Attachment';
    if (attachment is String) {
      fileName = attachment.split('/').last;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.attach_file, size: 20, color: mediumBlue),
              ),
              const SizedBox(width: 12),
              Text(
                'Attachment',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: darkBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accentBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentBlue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file, color: mediumBlue, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    fileName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: darkBlue,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.download, color: mediumBlue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusUpdateSection(String currentStatus) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.update, size: 20, color: mediumBlue),
              ),
              const SizedBox(width: 12),
              Text(
                'Update Status',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: darkBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStatusButton('Open', currentStatus, Icons.radio_button_unchecked),
          const SizedBox(height: 8),
          _buildStatusButton('In Progress', currentStatus, Icons.autorenew),
          const SizedBox(height: 8),
          _buildStatusButton('closed', currentStatus, Icons.check_circle, label: 'Close'),
        ],
      ),
    );
  }

  Widget _buildStatusButton(String status, String currentStatus, IconData icon, {String? label}) {
    final isSelected = status == currentStatus;
    final displayLabel = label ?? status;
    final color = _getStatusColor(status);

    return InkWell(
      onTap: isSelected || _isUpdating ? null : () => _updateStatus(status),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [color, color.withOpacity(0.8)],
                )
              : null,
          color: isSelected ? null : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : color,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              displayLabel,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : color,
              ),
            ),
            const Spacer(),
            if (isSelected)
              const Icon(Icons.check, color: Colors.white, size: 20)
            else if (_isUpdating && !isSelected)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Icons.priority_high;
      case 'medium':
        return Icons.remove;
      case 'low':
        return Icons.arrow_downward;
      default:
        return Icons.flag;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFF59E0B);
      case 'low':
        return const Color(0xFF10B981);
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Open':
        return const Color(0xFFEF4444);
      case 'In Progress':
        return const Color(0xFFF59E0B);
      case 'closed':
        return const Color(0xFF10B981);
      default:
        return Colors.grey;
    }
  }

  Color _getDeadlineColor(String deadline) {
    final deadlineDate = DateTime.tryParse(deadline);
    if (deadlineDate == null) return Colors.grey;

    final difference = deadlineDate.difference(DateTime.now());
    if (difference.isNegative) return const Color(0xFFEF4444);
    if (difference.inHours < 4) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  String _formatTimeline(int minutes) {
    if (minutes < 60) return '$minutes minutes';
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

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'Not set';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return 'Invalid date';
    return DateFormat('MMM dd, yyyy \'at\' hh:mm a').format(date);
  }
}