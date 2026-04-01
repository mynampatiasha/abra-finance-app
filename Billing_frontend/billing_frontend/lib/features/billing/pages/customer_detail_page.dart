// ============================================================================
// CUSTOMER DETAIL PAGE
// ============================================================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'customers_list_page.dart' show CustomerData, UploadedDocument;
import 'new_customer.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class CustomerDetailPage extends StatefulWidget {
  final CustomerData customer;
  const CustomerDetailPage({Key? key, required this.customer}) : super(key: key);

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  late CustomerData _customer;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async { Navigator.pop(context, _changed); return false; },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: _buildAppBar(),
        body: _buildBody(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_navyDark, _navyMid, _navyLight],
            begin: Alignment.centerLeft, end: Alignment.centerRight,
          ),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Text(_customer.name,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final r = await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => NewCustomerPage(customerId: _customer.id)));
                if (r == true) setState(() => _changed = true);
              },
              icon: const Icon(Icons.edit, color: Colors.white70, size: 18),
              label: const Text('Edit', style: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final c = _customer;
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      if (isWide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: _buildMainScroll(c)),
          SizedBox(
            width: 300,
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildSidebar(c),
              ),
            ),
          ),
        ]);
      } else {
        return SingleChildScrollView(child: Column(children: [
          _buildMainScroll(c, isScrollable: false),
          Container(color: Colors.white, padding: const EdgeInsets.all(20),
              child: _buildSidebar(c)),
        ]));
      }
    });
  }

  Widget _buildMainScroll(CustomerData c, {bool isScrollable = true}) {
    final content = Column(children: [
      // Header card
      Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_navyDark, _navyMid],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: _navyDark.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Center(
                child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              if (c.companyName.isNotEmpty)
                Text(c.companyName, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              Text(c.email, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ])),
            _glowBadge(c.status),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 24, runSpacing: 8, children: [
            _headerInfo('Phone', c.workPhone.isNotEmpty ? c.workPhone : '—'),
            _headerInfo('Type', c.type),
            _headerInfo('Tier', c.tier),
            _headerInfo('Since', DateFormat('dd MMM yyyy').format(c.createdDate)),
          ]),
        ]),
      ),

      const SizedBox(height: 16),

      // Contact Details
      _detailCard(
        title: 'Contact Information', icon: Icons.contact_mail,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _infoRow(Icons.email, 'Email', c.email),
            const SizedBox(height: 12),
            _infoRow(Icons.phone, 'Phone', c.workPhone.isNotEmpty ? c.workPhone : '—'),
            const SizedBox(height: 12),
            _infoRow(Icons.business, 'Company', c.companyName.isNotEmpty ? c.companyName : '—'),
            const SizedBox(height: 12),
            _infoRow(Icons.person, 'Type', c.type),
          ]),
        ),
      ),

      const SizedBox(height: 16),

      // Documents
      if (c.uploadedDocuments.isNotEmpty)
        _detailCard(
          title: 'Documents (${c.documentCount})', icon: Icons.folder,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: c.uploadedDocuments.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
            itemBuilder: (_, i) {
              final doc = c.uploadedDocuments[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _navyAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(_docIcon(doc.fileExtension), color: _navyAccent, size: 20),
                ),
                title: Text(doc.originalName, style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
                subtitle: Text('${doc.category} • ${doc.fileSizeFormatted}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                trailing: Text(DateFormat('dd MMM yyyy').format(doc.uploadedAt),
                    style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              );
            },
          ),
        ),

      const SizedBox(height: 24),
    ]);

    if (isScrollable) return SingleChildScrollView(child: content);
    return content;
  }

  IconData _docIcon(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'jpg': case 'jpeg': case 'png': return Icons.image;
      case 'xlsx': case 'xls': return Icons.table_chart;
      default: return Icons.insert_drive_file;
    }
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 18, color: _navyAccent),
      const SizedBox(width: 10),
      Text('$label: ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis)),
    ]);
  }

  Widget _buildSidebar(CustomerData c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_navyDark, _navyLight]),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.person, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 8),
        const Text('Customer Info',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
      ]),
      const SizedBox(height: 16),

      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_navyDark.withOpacity(0.06), _navyLight.withOpacity(0.08)]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _navyAccent.withOpacity(0.2)),
        ),
        child: Column(children: [
          _sidebarRow('Status', c.status, _statusColor(c.status)),
          const SizedBox(height: 8),
          _sidebarRow('Type', c.type, _navyDark),
          const SizedBox(height: 8),
          _sidebarRow('Tier', c.tier, _tierColor(c.tier)),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _sidebarRow('Documents', '${c.documentCount}', _navyAccent, isBold: true),
        ]),
      ),

      const SizedBox(height: 16),

      // Tier badge
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _tierColor(c.tier).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _tierColor(c.tier).withOpacity(0.3)),
        ),
        child: Column(children: [
          Icon(Icons.star, color: _tierColor(c.tier), size: 28),
          const SizedBox(height: 6),
          Text(c.tier, style: TextStyle(
              color: _tierColor(c.tier), fontWeight: FontWeight.bold, fontSize: 16)),
          Text('Customer Tier', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        ]),
      ),

      const SizedBox(height: 16),

      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, _changed),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to List'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _navyMid,
            side: BorderSide(color: _navyMid),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    ]);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Active': return Colors.green;
      case 'Inactive': return Colors.grey;
      default: return _navyAccent;
    }
  }

  Color _tierColor(String tier) {
    switch (tier) {
      case 'Gold':     return Colors.amber[700]!;
      case 'Platinum': return Colors.blueGrey[700]!;
      case 'Silver':   return Colors.blueGrey[400]!;
      default:         return _navyAccent;
    }
  }

  Widget _sidebarRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13,
          fontWeight: isBold ? FontWeight.w600 : FontWeight.normal, color: Colors.grey[700])),
      Text(value, style: TextStyle(fontSize: 13,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: color)),
    ]);
  }

  Widget _detailCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_navyDark, _navyLight]),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
          ]),
        ),
        const Divider(height: 1),
        child,
      ]),
    );
  }

  Widget _headerInfo(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
    ]);
  }

  Widget _glowBadge(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(status, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}
