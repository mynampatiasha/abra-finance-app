// ============================================================================
// FILE: lib/features/finance_auth/presentation/pages/finance_profile_page.dart
// ✅ REWRITTEN:
//   • Settings grid (4-per-row) with icon cards
//   • Search bar to filter sections
//   • Center dialog/modal for every section
//   • Rename org (pick any owned org) + Leave org (3-step confirmation)
// ============================================================================

import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/finance_secure_storage.dart';
import '../../../data/services/finance_auth_service.dart';
import '../../finance_welcome_screen.dart';
import 'account_deleted_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:io';

import '../../../../app/config/finance_api_config.dart';

// ── Colour palette ────────────────────────────────────────────────────────────
const Color _navy     = Color(0xFF1E3A5F);
const Color _navyDark = Color(0xFF0F172A);
const Color _blue     = Color(0xFF2563EB);
const Color _green    = Color(0xFF27AE60);
const Color _orange   = Color(0xFFE67E22);
const Color _red      = Color(0xFFE74C3C);
const Color _purple   = Color(0xFF9B59B6);
const Color _pageBg   = Color(0xFFF0F4F8);
const Color _white    = Color(0xFFFFFFFF);

const Color _textPrimary   = Color(0xFF0F172A);
const Color _textSecondary = Color(0xFF1E293B);
const Color _textMuted     = Color(0xFF334155);

// ── Setting item model ────────────────────────────────────────────────────────
class _SettingItem {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final List<String> keywords;

  const _SettingItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.keywords,
  });
}

const List<_SettingItem> _allSettings = [
  _SettingItem(
    id: 'personal',
    label: 'Personal Info',
    icon: Icons.person_outline_rounded,
    color: _blue,
    keywords: ['personal', 'name', 'email', 'phone', 'profile'],
  ),
  _SettingItem(
    id: 'password',
    label: 'Change Password',
    icon: Icons.lock_outline_rounded,
    color: _purple,
    keywords: ['password', 'change', 'security', 'lock'],
  ),
  _SettingItem(
    id: 'org_details',
    label: 'Org Details',
    icon: Icons.business_outlined,
    color: _navy,
    keywords: ['organisation', 'org', 'gst', 'address', 'phone', 'details'],
  ),
  _SettingItem(
    id: 'org_logo',
    label: 'Org Logo',
    icon: Icons.image_outlined,
    color: _orange,
    keywords: ['logo', 'image', 'brand', 'invoice note'],
  ),
  _SettingItem(
    id: 'banking',
    label: 'Banking',
    icon: Icons.account_balance_outlined,
    color: _blue,
    keywords: ['bank', 'ifsc', 'upi', 'qr', 'payment', 'account'],
  ),
  _SettingItem(
    id: 'signature',
    label: 'Digital Signature',
    icon: Icons.draw_outlined,
    color: _purple,
    keywords: ['signature', 'sign', 'pdf', 'authorized'],
  ),
  _SettingItem(
    id: 'email',
    label: 'Email Settings',
    icon: Icons.email_outlined,
    color: _orange,
    keywords: ['email', 'smtp', 'mail', 'send'],
  ),
  _SettingItem(
    id: 'whatsapp',
    label: 'WhatsApp Automation',
    icon: Icons.chat_rounded,
    color: Color(0xFF25D366),
    keywords: ['whatsapp', 'meta', 'automation', 'reminder', 'api', 'token'],
  ),
  _SettingItem(
    id: 'payment_gateway',
    label: 'Payment Gateway',
    icon: Icons.payment_outlined,
    color: _blue,
    keywords: ['gateway', 'razorpay', 'stripe', 'payment'],
  ),
  _SettingItem(
    id: 'branches',
    label: 'Branches',
    icon: Icons.account_tree_rounded,
    color: _green,
    keywords: ['branch', 'location', 'city'],
  ),
  _SettingItem(
    id: 'organisations',
    label: 'My Organisations',
    icon: Icons.business_rounded,
    color: _green,
    keywords: ['organisations', 'orgs', 'company', 'rename', 'leave'],
  ),
  _SettingItem(
    id: 'create_org',
    label: 'Create Org',
    icon: Icons.add_business_rounded,
    color: _navy,
    keywords: ['create', 'new', 'organisation', 'org'],
  ),
  _SettingItem(
    id: 'delete_account',
    label: 'Delete Account',
    icon: Icons.delete_forever_rounded,
    color: _red,
    keywords: ['delete', 'account', 'remove', 'close'],
  ),
];

class FinanceProfilePage extends StatefulWidget {
  const FinanceProfilePage({Key? key}) : super(key: key);

  @override
  State<FinanceProfilePage> createState() => _FinanceProfilePageState();
}

class _FinanceProfilePageState extends State<FinanceProfilePage> {
  // ── Session ───────────────────────────────────────────────────────────────
  String  _name          = '';
  String  _email         = '';
  String  _phone         = '';
  String  _role          = '';
  String  _orgId         = '';
  String  _orgName       = '';
  String? _orgLogoUrl;
  String? _createdBy;
  String  _entityName    = '';  // ✅ NEW: Entity/Group name
  List<Map<String, dynamic>> _organizations = [];
  bool    _sessionLoaded = false;

  // ── Profile form ──────────────────────────────────────────────────────────
  final _profileFormKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _entityNameCtrl;  // ✅ NEW: Entity name controller
  bool _savingProfile = false;

  // ── Password form ─────────────────────────────────────────────────────────
  final _pwFormKey     = GlobalKey<FormState>();
  final _currPwCtrl    = TextEditingController();
  final _newPwCtrl     = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  bool _savingPw       = false;
  bool _obscureCurr    = true;
  bool _obscureNew     = true;
  bool _obscureConfirm = true;

  // ── Logo ──────────────────────────────────────────────────────────────────
  bool       _uploadingLogo   = false;
  bool       _deletingLogo    = false;
  Uint8List? _pendingLogoBytes;
  File?      _pendingLogoFile;
  String?    _pendingLogoName;

  // ── Org Profile ───────────────────────────────────────────────────────────
  final _gstCtrl         = TextEditingController();
  final _orgPhoneCtrl    = TextEditingController();
  final _whatsappCtrl    = TextEditingController();
  final _orgEmailCtrl    = TextEditingController();
  final _addressCtrl     = TextEditingController();
  final _invoiceNoteCtrl = TextEditingController();
  bool _savingOrgProfile  = false;
  bool _loadingOrgProfile = false;

  // ── Banking ───────────────────────────────────────────────────────────────
  final _bankHolderCtrl  = TextEditingController();
  final _bankNumberCtrl  = TextEditingController();
  final _bankIfscCtrl    = TextEditingController();
  final _bankNameCtrl    = TextEditingController();
  final _upiCtrl         = TextEditingController();
  final _otherPayCtrl    = TextEditingController();
  bool   _savingBanking  = false;
  String? _qrCodePath;
  bool   _uploadingQr    = false;
  Uint8List? _pendingQrBytes;
  File?      _pendingQrFile;
  String?    _pendingQrName;
  List<Map<String, dynamic>> _orgDocuments = [];
  bool _uploadingDoc = false;

  // ── Digital Signature ─────────────────────────────────────────────────────
  String?    _digitalSignaturePath;
  bool       _uploadingSignature  = false;
  bool       _deletingSignature   = false;
  Uint8List? _pendingSigBytes;
  File?      _pendingSigFile;
  String?    _pendingSigName;

  // ── SMTP ──────────────────────────────────────────────────────────────────
  final _smtpHostCtrl     = TextEditingController();
  final _smtpPortCtrl     = TextEditingController();
  final _smtpUserCtrl     = TextEditingController();
  final _smtpPasswordCtrl = TextEditingController();
  final _smtpFromNameCtrl = TextEditingController();
  bool  _smtpVerified     = false;
  bool  _savingSmtp       = false;
  bool  _testingSmtp      = false;
  bool  _obscureSmtpPass  = true;
  String? _smtpTestResult;
  bool  _smtpTestSuccess  = false;

  // ── WhatsApp Meta ─────────────────────────────────────────────────────────
  final _waPhoneIdCtrl  = TextEditingController();
  final _waTokenCtrl    = TextEditingController();
  final _waWabaIdCtrl   = TextEditingController();
  final _waTestPhoneCtrl = TextEditingController();
  bool   _waVerified    = false;
  bool   _testingWa     = false;
  bool   _savingWa      = false;
  bool   _obscureWaToken = true;
  String? _waTestResult;
  bool   _waTestSuccess = false;

  // ── Branches ──────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _branches        = [];
  bool                       _loadingBranches = false;

  // ── Active branch ─────────────────────────────────────────────────────────
  String? _activeBranchId;

  // ── Payment Gateway ───────────────────────────────────────────────────────
  String  _gatewayType          = 'razorpay';
  bool    _gatewayConnected     = false;
  bool    _gatewayLoading       = false;
  bool    _gatewayTesting       = false;
  bool    _gatewaySaving        = false;
  bool    _gatewaySecretVisible = false;
  bool    _gatewayTestSuccess   = false;
  String? _gatewayTestResult;
  String  _gatewayAccountName   = '';
  String  _gatewayAccountEmail  = '';
  String  _gatewayAccountId     = '';
  String  _gatewayBusinessType  = '';
  String  _gatewayProfileStatus = '';
  String  _gatewayKeyId         = '';
  String  _gatewayConnectedAt   = '';
  final   _gatewayKeyIdCtrl     = TextEditingController();
  final   _gatewaySecretCtrl    = TextEditingController();

  // ── Search ────────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  bool get _canCreateOrg => _role == 'owner' && (_createdBy == null || _createdBy!.isEmpty);

  @override
  void initState() {
    super.initState();
    _nameCtrl       = TextEditingController();
    _emailCtrl      = TextEditingController();
    _phoneCtrl      = TextEditingController();
    _entityNameCtrl = TextEditingController();  // ✅ NEW: Entity name controller
    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()));
    _loadSession();
    _loadActiveBranchThenProfile();
    _loadGatewayStatus();
    _loadBranches();
  }

  Future<void> _loadActiveBranchThenProfile() async {
    final selectedIds = await FinanceSecureStorage.getSelectedBranchIds();
    final allowedIds  = await FinanceSecureStorage.getAllowedBranchIds();

    String? activeBranch;
    if (selectedIds.length == 1) {
      activeBranch = selectedIds.first;
    } else if (selectedIds.isEmpty && allowedIds.length == 1) {
      // User has exactly one allowed branch — use it even if nothing explicitly selected
      activeBranch = allowedIds.first;
    }

    if (mounted) {
      setState(() {
        _activeBranchId = activeBranch;
      });
    }
    await _loadOrgProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _entityNameCtrl.dispose();  // ✅ NEW: Dispose entity name controller
    _currPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    _gatewayKeyIdCtrl.dispose();
    _gatewaySecretCtrl.dispose();
    _gstCtrl.dispose();
    _orgPhoneCtrl.dispose();
    _whatsappCtrl.dispose();
    _orgEmailCtrl.dispose();
    _addressCtrl.dispose();
    _invoiceNoteCtrl.dispose();
    _smtpHostCtrl.dispose();
    _smtpPortCtrl.dispose();
    _smtpUserCtrl.dispose();
    _smtpPasswordCtrl.dispose();
    _smtpFromNameCtrl.dispose();
    _waPhoneIdCtrl.dispose();
    _waTokenCtrl.dispose();
    _waWabaIdCtrl.dispose();
    _waTestPhoneCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Load session ──────────────────────────────────────────────────────────
  Future<void> _loadSession() async {
    final name       = await FinanceSecureStorage.getName()       ?? '';
    final email      = await FinanceSecureStorage.getEmail()      ?? '';
    final phone      = await FinanceSecureStorage.getPhone()      ?? '';
    final role       = await FinanceSecureStorage.getRole()       ?? '';
    final orgId      = await FinanceSecureStorage.getOrgId()      ?? '';
    final orgNm      = await FinanceSecureStorage.getOrgName()    ?? '';
    final orgLogoUrl = await FinanceSecureStorage.getOrgLogoUrl();
    final entityName = await FinanceSecureStorage.getEntityName() ?? '';  // ✅ NEW: Load entity name
    final orgs       = await FinanceSecureStorage.getOrganizations();
    if (mounted) {
      setState(() {
        _name          = name;
        _email         = email;
        _phone         = phone;
        _role          = role;
        _orgId         = orgId;
        _orgName       = orgNm;
        _orgLogoUrl    = orgLogoUrl;
        _entityName    = entityName;  // ✅ NEW: Set entity name
        _organizations = orgs;
        _sessionLoaded = true;
        _nameCtrl.text       = name;
        _emailCtrl.text      = email;
        _phoneCtrl.text      = phone;
        _entityNameCtrl.text = entityName;  // ✅ NEW: Set entity name in controller
      });
    }
  }

  // ── Load Org Profile ──────────────────────────────────────────────────────
  Future<void> _loadOrgProfile() async {
    setState(() => _loadingOrgProfile = true);
    try {
      Map<String, dynamic> res;
      if (_activeBranchId != null) {
        res = await FinanceAuthService.get('/api/finance/branches/$_activeBranchId/profile');
      } else {
        res = await FinanceAuthService.get('/api/finance/auth/org-profile');
      }
      if (res['success'] == true) {
        final d = res['data'] as Map<String, dynamic>? ?? {};
        if (mounted) {
          setState(() {
            _gstCtrl.text         = d['gstNumber']?.toString()           ?? '';
            _orgPhoneCtrl.text    = d['phone']?.toString()               ?? '';
            _whatsappCtrl.text    = d['whatsappNumber']?.toString()      ?? '';
            _orgEmailCtrl.text    = d['email']?.toString()               ?? '';
            _addressCtrl.text     = d['address']?.toString()             ?? '';
            _invoiceNoteCtrl.text = d['invoiceNote']?.toString()         ?? '';
            _bankHolderCtrl.text  = d['bankAccountHolder']?.toString()   ?? '';
            _bankNumberCtrl.text  = d['bankAccountNumber']?.toString()   ?? '';
            _bankIfscCtrl.text    = d['bankIfscCode']?.toString()        ?? '';
            _bankNameCtrl.text    = d['bankName']?.toString()            ?? '';
            _upiCtrl.text         = d['upiId']?.toString()               ?? '';
            _otherPayCtrl.text    = d['otherPaymentOptions']?.toString() ?? '';
            _qrCodePath           = d['qrCodePath']?.toString();
            _orgDocuments         = List<Map<String, dynamic>>.from(
              (d['documents'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
            );
            _digitalSignaturePath = d['digitalSignaturePath']?.toString();
            if (d.containsKey('logoUrl')) _orgLogoUrl = d['logoUrl']?.toString();
            _smtpHostCtrl.text     = d['smtpHost']?.toString()     ?? '';
            _smtpPortCtrl.text     = d['smtpPort']?.toString()     ?? '587';
            _smtpUserCtrl.text     = d['smtpUser']?.toString()     ?? '';
            _smtpFromNameCtrl.text = d['smtpFromName']?.toString() ?? '';
            _smtpVerified          = d['smtpVerified'] == true;
            _waPhoneIdCtrl.text = d['whatsappMetaPhoneNumberId']?.toString() ?? '';
            _waWabaIdCtrl.text  = d['whatsappMetaWabaId']?.toString()        ?? '';
            _waVerified         = d['whatsappMetaVerified'] == true;
            // Access token is encrypted — show masked if already saved
            final waToken = d['whatsappMetaAccessToken']?.toString() ?? '';
            _waTokenCtrl.text = waToken.isNotEmpty ? '••••••••' : '';
          });
        }
      }
    } catch (e) {
      debugPrint('❌ _loadOrgProfile error: $e');
    } finally {
      if (mounted) setState(() => _loadingOrgProfile = false);
    }
  }

  Future<void> _loadGatewayStatus() async {
    setState(() => _gatewayLoading = true);
    try {
      final res = await FinanceAuthService.get('/api/finance/payment-gateway/gateway/status');
      if (res['success'] == true && mounted) {
        final d = res['data'] as Map<String, dynamic>? ?? {};
        setState(() {
          _gatewayConnected     = d['configured'] == true;
          _gatewayType          = d['gateway']?.toString()       ?? 'razorpay';
          _gatewayAccountName   = d['accountName']?.toString()   ?? '';
          _gatewayAccountEmail  = d['accountEmail']?.toString()  ?? '';
          _gatewayAccountId     = d['accountId']?.toString()     ?? '';
          _gatewayBusinessType  = d['businessType']?.toString()  ?? '';
          _gatewayProfileStatus = d['profileStatus']?.toString() ?? '';
          _gatewayKeyId         = d['keyId']?.toString()         ?? '';
          _gatewayConnectedAt   = d['connectedAt']?.toString()   ?? '';
          if (_gatewayConnected) _gatewayKeyIdCtrl.text = _gatewayKeyId;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadGatewayStatus error: $e');
    } finally {
      if (mounted) setState(() => _gatewayLoading = false);
    }
  }

  Future<void> _loadBranches() async {
    setState(() => _loadingBranches = true);
    try {
      final res = await FinanceAuthService.get('/api/finance/branches');
      if (res['success'] == true && mounted) {
        final list = (res['data']?['branches'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() => _branches = list);
        await FinanceSecureStorage.saveBranches(list);
      }
    } catch (e) {
      debugPrint('❌ _loadBranches: $e');
    } finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String get _initials {
    final parts = _name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  Color get _roleColor {
    switch (_role) {
      case 'owner':      return _blue;
      case 'admin':      return _purple;
      case 'accountant': return _green;
      default:           return _orange;
    }
  }

  String? _fullLogoUrl(String? relative) {
    if (relative == null || relative.isEmpty) return null;
    if (relative.startsWith('http')) return relative;
    final base = FinanceApiConfig.baseUrl.replaceAll(RegExp(r'/$'), '');
    return '$base$relative';
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: _white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: _white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: _red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OPEN MODAL
  // ═══════════════════════════════════════════════════════════════════════════
  void _openModal(String id) {
    Widget content;
    String title;
    IconData icon;
    Color iconColor;

    switch (id) {
      case 'personal':
        title = 'Personal Information'; icon = Icons.person_outline_rounded; iconColor = _blue;
        content = _buildPersonalForm();
        break;
      case 'password':
        title = 'Change Password'; icon = Icons.lock_outline_rounded; iconColor = _purple;
        content = _buildPasswordForm();
        break;
      case 'org_details':
        title = 'Organisation Details'; icon = Icons.business_outlined; iconColor = _navy;
        content = _buildOrgDetailsForm();
        break;
      case 'org_logo':
        title = 'Organisation Logo'; icon = Icons.image_outlined; iconColor = _orange;
        content = _buildOrgLogoSection();
        break;
      case 'banking':
        title = 'Banking & Payment'; icon = Icons.account_balance_outlined; iconColor = _blue;
        content = _buildBankingSection();
        break;
      case 'signature':
        title = 'Digital Signature'; icon = Icons.draw_outlined; iconColor = _purple;
        content = _buildSignatureSection();
        break;
      case 'email':
        title = 'Email Settings'; icon = Icons.email_outlined; iconColor = _orange;
        content = _buildEmailSection();
        break;
      case 'whatsapp':
        title = 'WhatsApp Automation'; icon = Icons.chat_rounded; iconColor = const Color(0xFF25D366);
        content = _buildWhatsAppSection();
        break;
      case 'payment_gateway':
        title = 'Payment Gateway'; icon = Icons.payment_outlined; iconColor = _blue;
        content = _buildPaymentGatewaySection();
        break;
      case 'branches':
        title = 'Branches'; icon = Icons.account_tree_rounded; iconColor = _green;
        content = _buildBranchesSection();
        break;
      case 'organisations':
        title = 'My Organisations'; icon = Icons.business_rounded; iconColor = _green;
        content = _buildOrganisationsSection();
        break;
      case 'create_org':
        title = 'Create Organisation'; icon = Icons.add_business_rounded; iconColor = _navy;
        content = _buildCreateOrgSection();
        break;
      case 'delete_account':
        title = 'Delete Account'; icon = Icons.delete_forever_rounded; iconColor = _red;
        content = _buildDeleteAccountSection();
        break;
      default:
        return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ProfileModal(
        title: title,
        icon: icon,
        iconColor: iconColor,
        child: content,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (!_sessionLoaded) {
      return const Scaffold(
        backgroundColor: _pageBg,
        body: Center(child: CircularProgressIndicator(color: _blue)),
      );
    }

    // Filter settings by search
    final visibleSettings = _allSettings.where((s) {
      if (!_canCreateOrg && s.id == 'create_org') return false;
      if (_searchQuery.isEmpty) return true;
      return s.keywords.any((k) => k.contains(_searchQuery)) ||
             s.label.toLowerCase().contains(_searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: _pageBg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Search bar ──────────────────────────────────────────
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE8EEF4)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(fontSize: 15, color: _textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Search settings…',
                            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                            prefixIcon: const Icon(Icons.search_rounded, color: _navy, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 18, color: Color(0xFF94A3B8)),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Grid label ──────────────────────────────────────────
                  if (_searchQuery.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '${visibleSettings.length} result${visibleSettings.length != 1 ? 's' : ''} for "$_searchQuery"',
                        style: const TextStyle(fontSize: 13, color: _textMuted),
                      ),
                    ),

                  // ── Settings grid ───────────────────────────────────────
                  if (visibleSettings.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(children: [
                          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text('No settings found', style: TextStyle(color: _textMuted, fontSize: 15)),
                        ]),
                      ),
                    )
                  else
                    _buildGrid(visibleSettings),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_navyDark, _navy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 28),
      child: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _white, size: 20),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(width: 12),
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: _blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                boxShadow: [BoxShadow(color: _blue.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 4))],
              ),
              child: Center(
                child: Text(_initials,
                    style: const TextStyle(color: _white, fontSize: 23, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_name, style: const TextStyle(color: _white, fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(_email, style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    _roleBadge(_role),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.business, color: _white, size: 12),
                        const SizedBox(width: 5),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(_orgName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _white, fontSize: 12, fontWeight: FontWeight.w500)),
                        ),
                      ]),
                    ),
                  ]),
                ],
              ),
            ),
            IconButton(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded, color: _white, size: 20),
              tooltip: 'Sign Out',
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleBadge(String role) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _roleColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _roleColor.withOpacity(0.5)),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(color: _roleColor, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
      ),
    );
  }

  // ── Settings Grid ─────────────────────────────────────────────────────────
  Widget _buildGrid(List<_SettingItem> items) {
    return LayoutBuilder(builder: (ctx, constraints) {
      // 4 per row on wide screens, 2 per row on narrow
      final crossCount = constraints.maxWidth >= 500 ? 4 : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.95,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _SettingCard(
          item: items[i],
          onTap: () => _openModal(items[i].id),
        ),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODAL CONTENT BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Personal Info ─────────────────────────────────────────────────────────
  Widget _buildPersonalForm() {
    return StatefulBuilder(builder: (ctx, setS) {
      return Form(
        key: _profileFormKey,
        child: Column(children: [
          _formField(ctrl: _nameCtrl, label: 'Full Name', icon: Icons.person_outline_rounded,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null),
          const SizedBox(height: 14),
          _formField(ctrl: _phoneCtrl, label: 'Phone Number', icon: Icons.phone_outlined,
              keyboard: TextInputType.phone,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone is required' : null),
          const SizedBox(height: 14),
          _formField(ctrl: _emailCtrl, label: 'Email Address', icon: Icons.email_outlined,
              keyboard: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Email is required';
                if (!v.contains('@')) return 'Enter a valid email';
                return null;
              }),
          const SizedBox(height: 14),
          // ✅ NEW: Entity/Group Name field
          _formField(
            ctrl: _entityNameCtrl,
            label: 'Entity/Group Name (Optional)',
            icon: Icons.business_center_rounded,
            hint: 'e.g., ABC Group',  // ✅ Add hint text
            validator: null,  // Optional field
          ),
          const SizedBox(height: 20),
          _primaryBtn(
            label: _savingProfile ? 'Saving...' : 'Save Changes',
            icon: _savingProfile ? null : Icons.save_outlined,
            color: _blue,
            loading: _savingProfile,
            onPressed: () async {
              if (!_profileFormKey.currentState!.validate()) return;
              setS(() => _savingProfile = true);
              final res = await FinanceAuthService.put('/api/finance/auth/update-profile', {
                'name': _nameCtrl.text.trim(),
                'email': _emailCtrl.text.trim(),
                'phone': _phoneCtrl.text.trim(),
                'entityName': _entityNameCtrl.text.trim(),  // ✅ NEW: Include entity name
              });
              if (!mounted) return;
              setS(() => _savingProfile = false);
              if (res['success'] == true) {
                final user = (res['data'] as Map?)?['user'] as Map? ?? {};
                final newEntityName = user['entityName']?.toString() ?? _entityNameCtrl.text.trim();
                
                await FinanceSecureStorage.saveSession(
                  token: await FinanceSecureStorage.getToken() ?? '',
                  userId: await FinanceSecureStorage.getUserId() ?? '',
                  name: user['name']?.toString() ?? _nameCtrl.text,
                  email: user['email']?.toString() ?? _emailCtrl.text,
                  phone: user['phone']?.toString() ?? _phoneCtrl.text,
                  role: _role,
                  orgId: _orgId,
                  orgName: _orgName,
                  orgLogoUrl: _orgLogoUrl,
                  entityName: newEntityName,  // ✅ NEW: Save entity name
                );
                
                setState(() {
                  _name       = user['name']?.toString()       ?? _nameCtrl.text;
                  _email      = user['email']?.toString()      ?? _emailCtrl.text;
                  _phone      = user['phone']?.toString()      ?? _phoneCtrl.text;
                  _entityName = newEntityName;  // ✅ NEW: Update local state
                });
                
                if (ctx.mounted) Navigator.pop(ctx);
                _showSuccess('Profile updated successfully. Refreshing...');
                
                // ✅ Reload the app to reflect entity name in sidebar
                await Future.delayed(const Duration(milliseconds: 500));
                if (mounted) {
                  // Navigate to home to trigger reload
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/finance/dashboard',
                    (route) => false,
                  );
                }
              } else {
                _showError(res['message'] ?? 'Failed to update profile');
              }
            },
          ),
        ]),
      );
    });
  }

  // ── Change Password ───────────────────────────────────────────────────────
  Widget _buildPasswordForm() {
    return StatefulBuilder(builder: (ctx, setS) {
      bool obscCurr = true, obscNew = true, obscConf = true;
      bool saving = false;
      return StatefulBuilder(builder: (ctx2, setS2) {
        return Form(
          key: _pwFormKey,
          child: Column(children: [
            _pwField(ctrl: _currPwCtrl, label: 'Current Password', obscure: obscCurr,
                onToggle: () => setS2(() => obscCurr = !obscCurr),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
            const SizedBox(height: 14),
            _pwField(ctrl: _newPwCtrl, label: 'New Password', obscure: obscNew,
                onToggle: () => setS2(() => obscNew = !obscNew),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length < 6) return 'Min 6 characters';
                  return null;
                }),
            const SizedBox(height: 14),
            _pwField(ctrl: _confirmPwCtrl, label: 'Confirm New Password', obscure: obscConf,
                onToggle: () => setS2(() => obscConf = !obscConf),
                validator: (v) => v != _newPwCtrl.text ? 'Passwords do not match' : null),
            const SizedBox(height: 20),
            _primaryBtn(
              label: saving ? 'Updating...' : 'Update Password',
              icon: saving ? null : Icons.lock_reset_rounded,
              color: _purple,
              loading: saving,
              onPressed: () async {
                if (!_pwFormKey.currentState!.validate()) return;
                setS2(() => saving = true);
                final res = await FinanceAuthService.put('/api/finance/auth/change-password', {
                  'currentPassword': _currPwCtrl.text, 'newPassword': _newPwCtrl.text,
                });
                if (!mounted) return;
                setS2(() => saving = false);
                if (res['success'] == true) {
                  _currPwCtrl.clear(); _newPwCtrl.clear(); _confirmPwCtrl.clear();
                  if (ctx.mounted) Navigator.pop(ctx);
                  _showSuccess('Password changed successfully');
                } else {
                  _showError(res['message'] ?? 'Failed to change password');
                }
              },
            ),
          ]),
        );
      });
    });
  }

  // ── Org Details ───────────────────────────────────────────────────────────
  Widget _buildOrgDetailsForm() {
    return StatefulBuilder(builder: (ctx, setS) {
      bool saving = false;
      if (_loadingOrgProfile) return const Center(child: CircularProgressIndicator());
      return Column(children: [
        _formField(ctrl: _gstCtrl, label: 'GST Number', icon: Icons.receipt_long_outlined),
        const SizedBox(height: 12),
        _formField(ctrl: _orgPhoneCtrl, label: 'Phone', icon: Icons.phone_outlined, keyboard: TextInputType.phone),
        const SizedBox(height: 12),
        _formField(ctrl: _whatsappCtrl, label: 'WhatsApp', icon: Icons.chat_outlined, keyboard: TextInputType.phone),
        const SizedBox(height: 12),
        _formField(ctrl: _orgEmailCtrl, label: 'Email', icon: Icons.email_outlined, keyboard: TextInputType.emailAddress),
        const SizedBox(height: 12),
        TextField(
          controller: _addressCtrl,
          maxLines: 3,
          style: const TextStyle(fontSize: 15),
          decoration: _fieldDeco('Address', Icons.location_on_outlined),
        ),
        const SizedBox(height: 16),
        _primaryBtn(
          label: saving ? 'Saving...' : 'Save Organisation Details',
          icon: saving ? null : Icons.save_outlined,
          color: _navy,
          loading: saving,
          onPressed: () async {
            setS(() => saving = true);
            final body = {
              'gstNumber': _gstCtrl.text.trim(), 'phone': _orgPhoneCtrl.text.trim(),
              'whatsappNumber': _whatsappCtrl.text.trim(), 'email': _orgEmailCtrl.text.trim(),
              'address': _addressCtrl.text.trim(),
            };
            Map<String, dynamic> res;
            if (_activeBranchId != null) {
              res = await FinanceAuthService.put('/api/finance/branches/$_activeBranchId/profile', body);
            } else {
              res = await FinanceAuthService.put('/api/finance/auth/update-org-profile', body);
            }
            if (!mounted) return;
            setS(() => saving = false);
            if (res['success'] == true) {
              if (ctx.mounted) Navigator.pop(ctx);
              _showSuccess('Organisation details saved');
            } else {
              _showError(res['message'] ?? 'Failed to save');
            }
          },
        ),
      ]);
    });
  }

  // ── Org Logo ──────────────────────────────────────────────────────────────
  Widget _buildOrgLogoSection() {
    return StatefulBuilder(builder: (ctx, setS) {
      final hasPending = _pendingLogoBytes != null || _pendingLogoFile != null;
      final hasLogo    = _orgLogoUrl != null && _orgLogoUrl!.isNotEmpty;
      final fullUrl    = _fullLogoUrl(_orgLogoUrl);

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Preview
        Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              color: _pageBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: hasPending ? _blue : const Color(0xFFDDE3EE), width: hasPending ? 2 : 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: _buildLogoPreview(hasPending: hasPending, hasLogo: hasLogo, fullUrl: fullUrl),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _infoBadge('Recommended: 300×120 px, PNG or JPEG, max 5 MB.', _blue),
        const SizedBox(height: 14),
        if (hasPending) ...[
          Row(children: [
            Expanded(child: _primaryBtn(
              label: _uploadingLogo ? 'Uploading...' : 'Upload Logo',
              icon: Icons.cloud_upload_outlined, color: _blue, loading: _uploadingLogo,
              onPressed: () async {
                setS(() => _uploadingLogo = true);
                setState(() => _uploadingLogo = true);
                Map<String, dynamic> res;
                if (_activeBranchId != null) {
                  res = await FinanceAuthServiceExtra.uploadBranchLogo(
                    branchId: _activeBranchId!, imageFile: _pendingLogoFile,
                    imageBytes: _pendingLogoBytes, filename: _pendingLogoName ?? 'logo.jpg');
                } else {
                  res = await FinanceAuthService.uploadOrgLogo(
                    imageFile: _pendingLogoFile, imageBytes: _pendingLogoBytes,
                    filename: _pendingLogoName ?? 'logo.jpg');
                }
                if (!mounted) return;
                final newUrl = res['data']?['logoUrl']?.toString();
                setState(() { _uploadingLogo = false; if (res['success'] == true) { _orgLogoUrl = newUrl; _pendingLogoBytes = null; _pendingLogoFile = null; _pendingLogoName = null; } });
                setS(() => _uploadingLogo = false);
                if (res['success'] == true) { if (ctx.mounted) Navigator.pop(ctx); _showSuccess('Logo uploaded successfully!'); }
                else { _showError(res['message'] ?? 'Upload failed'); }
              },
            )),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () { setState(() { _pendingLogoBytes = null; _pendingLogoFile = null; _pendingLogoName = null; }); setS(() {}); },
              icon: const Icon(Icons.close, size: 17),
              label: const Text('Discard'),
              style: OutlinedButton.styleFrom(foregroundColor: _textSecondary, side: BorderSide(color: Colors.grey[300]!), padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ]),
        ] else ...[
          _primaryBtn(
            label: hasLogo ? 'Change Logo' : 'Choose Logo',
            icon: Icons.upload_file_outlined, color: _orange,
            onPressed: () async {
              final picker = ImagePicker();
              final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 600, imageQuality: 90);
              if (picked == null) return;
              if (kIsWeb) {
                final bytes = await picked.readAsBytes();
                setState(() { _pendingLogoBytes = bytes; _pendingLogoFile = null; _pendingLogoName = picked.name; });
              } else {
                setState(() { _pendingLogoFile = File(picked.path); _pendingLogoBytes = null; _pendingLogoName = picked.name; });
              }
              setS(() {});
            },
          ),
          if (hasLogo) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _deletingLogo ? null : () async {
                  setS(() => _deletingLogo = true);
                  setState(() => _deletingLogo = true);
                  Map<String, dynamic> res;
                  if (_activeBranchId != null) {
                    res = await FinanceAuthService.delete('/api/finance/branches/$_activeBranchId/delete-logo');
                  } else {
                    res = await FinanceAuthService.deleteOrgLogo();
                  }
                  if (!mounted) return;
                  setState(() { _deletingLogo = false; if (res['success'] == true) { _orgLogoUrl = null; } });
                  setS(() => _deletingLogo = false);
                  if (res['success'] == true) { if (ctx.mounted) Navigator.pop(ctx); _showSuccess('Logo removed'); }
                  else { _showError(res['message'] ?? 'Failed'); }
                },
                icon: _deletingLogo ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_outline, size: 17),
                label: Text(_deletingLogo ? 'Removing...' : 'Remove Logo'),
                style: OutlinedButton.styleFrom(foregroundColor: _red, side: BorderSide(color: _red.withOpacity(0.4)), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ),
          ],
        ],
        const SizedBox(height: 20),
        const Text('Invoice Note', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
        const SizedBox(height: 6),
        TextField(
          controller: _invoiceNoteCtrl, maxLines: 3,
          style: const TextStyle(fontSize: 13),
          decoration: _fieldDeco('e.g. Thank you for your business.', Icons.notes_outlined),
        ),
        const SizedBox(height: 14),
        _primaryBtn(
          label: _savingOrgProfile ? 'Saving...' : 'Save Note',
          icon: Icons.save_outlined, color: _navy, loading: _savingOrgProfile,
          onPressed: () async {
            setS(() => _savingOrgProfile = true);
            setState(() => _savingOrgProfile = true);
            Map<String, dynamic> res;
            final body = {'invoiceNote': _invoiceNoteCtrl.text.trim()};
            if (_activeBranchId != null) {
              res = await FinanceAuthService.put('/api/finance/branches/$_activeBranchId/profile', body);
            } else {
              res = await FinanceAuthService.put('/api/finance/auth/update-org-profile', body);
            }
            if (!mounted) return;
            setState(() => _savingOrgProfile = false);
            setS(() => _savingOrgProfile = false);
            if (res['success'] == true) { if (ctx.mounted) Navigator.pop(ctx); _showSuccess('Invoice note saved'); }
            else { _showError(res['message'] ?? 'Failed'); }
          },
        ),
      ]);
    });
  }

  // ── Digital Signature ─────────────────────────────────────────────────────
  Widget _buildSignatureSection() {
    return StatefulBuilder(builder: (ctx, setS) {
      final hasPending = _pendingSigBytes != null || _pendingSigFile != null;
      final hasSig     = _digitalSignaturePath != null && _digitalSignaturePath!.isNotEmpty;
      final fullUrl    = _fullLogoUrl(_digitalSignaturePath);

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 120),
            decoration: BoxDecoration(
              color: _pageBg, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: hasPending ? _purple : const Color(0xFFDDE3EE), width: hasPending ? 2 : 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: _buildSigPreview(hasPending: hasPending, hasSig: hasSig, fullUrl: fullUrl),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _infoBadge('Use PNG with transparent background. Recommended: 400×150 px, max 3 MB.', _purple),
        const SizedBox(height: 14),
        if (hasPending) ...[
          Row(children: [
            Expanded(child: _primaryBtn(
              label: _uploadingSignature ? 'Uploading...' : 'Upload Signature',
              icon: Icons.cloud_upload_outlined, color: _purple, loading: _uploadingSignature,
              onPressed: () async {
                setS(() => _uploadingSignature = true);
                setState(() => _uploadingSignature = true);
                Map<String, dynamic> res;
                if (_activeBranchId != null) {
                  res = await FinanceAuthServiceExtra.uploadBranchSignature(
                    branchId: _activeBranchId!, imageFile: _pendingSigFile,
                    imageBytes: _pendingSigBytes, filename: _pendingSigName ?? 'signature.png');
                } else {
                  res = await FinanceAuthServiceExtra.uploadDigitalSignature(
                    imageFile: _pendingSigFile, imageBytes: _pendingSigBytes,
                    filename: _pendingSigName ?? 'signature.png');
                }
                if (!mounted) return;
                setState(() { _uploadingSignature = false; if (res['success'] == true) { _digitalSignaturePath = res['data']?['digitalSignaturePath']?.toString(); _pendingSigBytes = null; _pendingSigFile = null; _pendingSigName = null; } });
                setS(() => _uploadingSignature = false);
                if (res['success'] == true) { if (ctx.mounted) Navigator.pop(ctx); _showSuccess('Signature uploaded'); }
                else { _showError(res['message'] ?? 'Upload failed'); }
              },
            )),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () { setState(() { _pendingSigBytes = null; _pendingSigFile = null; _pendingSigName = null; }); setS(() {}); },
              icon: const Icon(Icons.close, size: 17), label: const Text('Discard'),
              style: OutlinedButton.styleFrom(foregroundColor: _textSecondary, side: BorderSide(color: Colors.grey[300]!), padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ]),
        ] else ...[
          _primaryBtn(
            label: hasSig ? 'Change Signature' : 'Upload Signature',
            icon: Icons.upload_file_outlined, color: _purple,
            onPressed: () async {
              final picker = ImagePicker();
              final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 400, imageQuality: 90);
              if (picked == null) return;
              if (kIsWeb) {
                final bytes = await picked.readAsBytes();
                setState(() { _pendingSigBytes = bytes; _pendingSigFile = null; _pendingSigName = picked.name; });
              } else {
                setState(() { _pendingSigFile = File(picked.path); _pendingSigBytes = null; _pendingSigName = picked.name; });
              }
              setS(() {});
            },
          ),
          if (hasSig) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _deletingSignature ? null : () async {
                  setS(() => _deletingSignature = true);
                  setState(() => _deletingSignature = true);
                  Map<String, dynamic> res;
                  if (_activeBranchId != null) {
                    res = await FinanceAuthService.delete('/api/finance/branches/$_activeBranchId/delete-signature');
                  } else {
                    res = await FinanceAuthServiceExtra.deleteDigitalSignature();
                  }
                  if (!mounted) return;
                  setState(() { _deletingSignature = false; if (res['success'] == true) { _digitalSignaturePath = null; } });
                  setS(() => _deletingSignature = false);
                  if (res['success'] == true) { if (ctx.mounted) Navigator.pop(ctx); _showSuccess('Signature removed'); }
                  else { _showError(res['message'] ?? 'Failed'); }
                },
                icon: _deletingSignature ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_outline, size: 17),
                label: Text(_deletingSignature ? 'Removing...' : 'Remove Signature'),
                style: OutlinedButton.styleFrom(foregroundColor: _red, side: BorderSide(color: _red.withOpacity(0.4)), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ),
          ],
        ],
      ]);
    });
  }

  // ── Email Settings ────────────────────────────────────────────────────────
  Widget _buildEmailSection() {
    return StatefulBuilder(builder: (ctx, setS) {
      bool obscPass = true;
      bool saving = false, testing = false;
      String? testResult; bool testSuccess = false;
      return StatefulBuilder(builder: (ctx2, setS2) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_smtpVerified) ...[
            _successBadge('Emails will send from ${_smtpUserCtrl.text}'),
            const SizedBox(height: 14),
          ],
          _infoBadge('Set up your company email so invoices send from your own address. Get SMTP details from Hostinger → Email → Manage.', _orange),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(flex: 3, child: _field(_smtpHostCtrl, 'SMTP Host', Icons.dns_outlined)),
            const SizedBox(width: 10),
            Expanded(flex: 1, child: _field(_smtpPortCtrl, 'Port', Icons.numbers_outlined)),
          ]),
          const SizedBox(height: 12),
          _field(_smtpFromNameCtrl, 'From Name', Icons.badge_outlined),
          const SizedBox(height: 12),
          _field(_smtpUserCtrl, 'Email Address', Icons.alternate_email_outlined),
          const SizedBox(height: 12),
          TextField(
            controller: _smtpPasswordCtrl,
            obscureText: obscPass,
            style: const TextStyle(fontSize: 15, color: _textPrimary),
            decoration: InputDecoration(
              labelText: _smtpVerified ? 'New Password (leave blank to keep)' : 'Email Password',
              labelStyle: const TextStyle(fontSize: 14, color: _textSecondary),
              prefixIcon: const Icon(Icons.lock_outline, size: 18, color: _navy),
              suffixIcon: IconButton(
                icon: Icon(obscPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: Colors.grey[400]),
                onPressed: () => setS2(() => obscPass = !obscPass),
              ),
              filled: true, fillColor: _pageBg, contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 1.5)),
            ),
          ),
          if (testResult != null) ...[
            const SizedBox(height: 12),
            _resultBadge(testResult!, testSuccess),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: testing ? null : () async {
                if (_smtpUserCtrl.text.trim().isEmpty || _smtpPasswordCtrl.text.trim().isEmpty) {
                  setS2(() { testSuccess = false; testResult = 'Enter email and password first.'; });
                  return;
                }
                setS2(() { testing = true; testResult = null; });
                try {
                  final res = await FinanceAuthService.post('/api/finance/auth/test-smtp', {
                    'smtpHost': _smtpHostCtrl.text.trim(), 'smtpPort': int.tryParse(_smtpPortCtrl.text.trim()) ?? 587,
                    'smtpUser': _smtpUserCtrl.text.trim(), 'smtpPassword': _smtpPasswordCtrl.text.trim(),
                    'smtpFromName': _smtpFromNameCtrl.text.trim(),
                    if (_activeBranchId != null) 'branchId': _activeBranchId!,
                  });
                  if (!mounted) return;
                  setS2(() { testing = false; testSuccess = res['success'] == true; testResult = testSuccess ? 'Connection successful! Emails will send from this address.' : res['message'] ?? 'Connection failed.'; if (testSuccess) { setState(() => _smtpVerified = true); } });
                } catch (e) {
                  setS2(() { testing = false; testSuccess = false; testResult = 'Error: $e'; });
                }
              },
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), side: const BorderSide(color: _orange)),
              child: testing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _orange)) : const Text('Test Connection', style: TextStyle(color: _orange, fontWeight: FontWeight.w600)),
            )),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: _primaryBtn(
              label: saving ? 'Saving...' : 'Save Email Settings',
              color: _navy, loading: saving,
              onPressed: () async {
                setS2(() => saving = true);
                try {
                  final body = <String, dynamic>{
                    'smtpHost': _smtpHostCtrl.text.trim(), 'smtpPort': int.tryParse(_smtpPortCtrl.text.trim()) ?? 587,
                    'smtpUser': _smtpUserCtrl.text.trim(), 'smtpFromName': _smtpFromNameCtrl.text.trim(),
                    if (_smtpPasswordCtrl.text.trim().isNotEmpty) 'smtpPassword': _smtpPasswordCtrl.text.trim(),
                  };
                  Map<String, dynamic> res;
                  if (_activeBranchId != null) {
                    res = await FinanceAuthService.put('/api/finance/branches/$_activeBranchId/profile', body);
                  } else {
                    res = await FinanceAuthService.put('/api/finance/auth/update-org-profile', body);
                  }
                  if (!mounted) return;
                  setS2(() => saving = false);
                  if (res['success'] == true) { setState(() => _smtpPasswordCtrl.clear()); if (ctx.mounted) Navigator.pop(ctx); _showSuccess('Email settings saved'); }
                  else { _showError(res['message'] ?? 'Failed'); }
                } catch (e) { setS2(() => saving = false); _showError('Error: $e'); }
              },
            )),
          ]),
        ]);
      });
    });
  }

  // ── WhatsApp Automation ───────────────────────────────────────────────────
  Widget _buildWhatsAppSection() {
    return StatefulBuilder(builder: (ctx, setS) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Status badge
        if (_waVerified) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: const Row(children: [
              Icon(Icons.check_circle, color: Color(0xFF059669), size: 18),
              SizedBox(width: 8),
              Expanded(child: Text(
                'WhatsApp is connected and verified ✓',
                style: TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w600, fontSize: 13),
              )),
            ]),
          ),
          const SizedBox(height: 14),
        ],

        // Guide box — where to get credentials
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF25D366).withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF25D366).withOpacity(0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.info_outline, size: 16, color: Color(0xFF25D366)),
              SizedBox(width: 8),
              Text('How to get your credentials',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF128C7E))),
            ]),
            const SizedBox(height: 10),
            _waStep('1', 'Go to', 'developers.facebook.com', ' → My Apps → Your App'),
            _waStep('2', 'Click', 'WhatsApp → API Setup', ' in the left menu'),
            _waStep('3', 'Click', 'Generate Access Token', ' — copy it here'),
            _waStep('4', 'Copy', 'Phone Number ID', ' shown below the From number'),
            _waStep('5', 'Copy', 'WhatsApp Business Account ID', ' shown on same page'),
          ]),
        ),
        const SizedBox(height: 16),

        // Phone Number ID
        const Text('Phone Number ID',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
        const SizedBox(height: 6),
        _field(_waPhoneIdCtrl, 'e.g. 1114975131698527', Icons.phone_android_outlined),
        const SizedBox(height: 12),

        // Access Token
        const Text('Access Token',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
        const SizedBox(height: 6),
        StatefulBuilder(builder: (_, ss) => TextField(
          controller:  _waTokenCtrl,
          obscureText: _obscureWaToken,
          style: const TextStyle(fontSize: 15, color: _textPrimary),
          onTap: () {
            // Clear masked value when user taps to enter new token
            if (_waTokenCtrl.text == '••••••••') {
              _waTokenCtrl.clear();
            }
          },
          decoration: InputDecoration(
            hintText:    'Paste your Meta access token',
            hintStyle:   TextStyle(fontSize: 14, color: Colors.grey[400]),
            prefixIcon:  const Icon(Icons.vpn_key_outlined, size: 18, color: _navy),
            suffixIcon:  IconButton(
              icon: Icon(_obscureWaToken
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
                  size: 18, color: Colors.grey[400]),
              onPressed: () { setState(() => _obscureWaToken = !_obscureWaToken); ss(() {}); },
            ),
            filled: true, fillColor: _pageBg,
            contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
            border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF25D366), width: 1.5)),
          ),
        )),
        const SizedBox(height: 12),

        // WABA ID
        const Text('WhatsApp Business Account ID',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
        const SizedBox(height: 6),
        _field(_waWabaIdCtrl, 'e.g. 1549558539833336', Icons.business_outlined),
        const SizedBox(height: 16),

        // Test number
        const Text('Test Phone Number',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
        const SizedBox(height: 4),
        Text('Enter your WhatsApp number to receive a test message and verify the connection.',
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        const SizedBox(height: 6),
        _formField(
          ctrl: _waTestPhoneCtrl,
          label: 'Test Phone Number',
          icon: Icons.phone_outlined,
          keyboard: TextInputType.phone,
          hint: 'e.g. 9876543210 (Indian number)',
        ),

        // Test result
        if (_waTestResult != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _waTestSuccess
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _waTestSuccess
                    ? const Color(0xFFBBF7D0)
                    : const Color(0xFFFECACA),
              ),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(
                _waTestSuccess ? Icons.check_circle_outline : Icons.error_outline,
                size: 18,
                color: _waTestSuccess ? const Color(0xFF059669) : const Color(0xFFDC2626),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(
                _waTestResult!,
                style: TextStyle(
                  fontSize: 12,
                  color: _waTestSuccess ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                  height: 1.5,
                ),
              )),
            ]),
          ),
        ],

        const SizedBox(height: 16),

        // Buttons
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: _testingWa ? null : () async {
              if (_waPhoneIdCtrl.text.trim().isEmpty ||
                  _waTokenCtrl.text.trim().isEmpty   ||
                  _waTokenCtrl.text.trim() == '••••••••' ||
                  _waWabaIdCtrl.text.trim().isEmpty) {
                setS(() {
                  _waTestSuccess = false;
                  _waTestResult  = '❌ Please fill in all three credential fields before testing.';
                });
                return;
              }
              if (_waTestPhoneCtrl.text.trim().isEmpty) {
                setS(() {
                  _waTestSuccess = false;
                  _waTestResult  = '❌ Enter your WhatsApp number in the Test Phone Number field.';
                });
                return;
              }
              setS(() { _testingWa = true; _waTestResult = null; });
              try {
                final res = await FinanceAuthService.post(
                  '/api/finance/auth/test-whatsapp',
                  {
                    'phoneNumberId': _waPhoneIdCtrl.text.trim(),
                    'accessToken':   _waTokenCtrl.text.trim(),
                    'wabaId':        _waWabaIdCtrl.text.trim(),
                    'testPhone':     _waTestPhoneCtrl.text.trim(),
                  },
                );
                if (!mounted) return;
                setS(() {
                  _testingWa    = false;
                  _waTestSuccess = res['success'] == true;
                  _waTestResult  = res['message'] ?? (res['success'] == true
                      ? '✅ Connection successful!'
                      : '❌ Test failed.');
                  if (_waTestSuccess) setState(() => _waVerified = true);
                });
              } catch (e) {
                setS(() {
                  _testingWa    = false;
                  _waTestSuccess = false;
                  _waTestResult  = '❌ Error: $e';
                });
              }
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              side: const BorderSide(color: Color(0xFF25D366)),
            ),
            child: _testingWa
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF25D366)))
                : const Text('Test Connection',
                    style: TextStyle(color: Color(0xFF25D366), fontWeight: FontWeight.w600)),
          )),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: ElevatedButton(
            onPressed: _savingWa ? null : () async {
              if (_waPhoneIdCtrl.text.trim().isEmpty ||
                  _waTokenCtrl.text.trim().isEmpty   ||
                  _waTokenCtrl.text.trim() == '••••••••' ||
                  _waWabaIdCtrl.text.trim().isEmpty) {
                setS(() {
                  _waTestSuccess = false;
                  _waTestResult  = '❌ Please fill in all credential fields before saving.';
                });
                return;
              }
              setS(() => _savingWa = true);
              try {
                final res = await FinanceAuthService.put(
                  '/api/finance/auth/save-whatsapp-credentials',
                  {
                    'phoneNumberId': _waPhoneIdCtrl.text.trim(),
                    'accessToken':   _waTokenCtrl.text.trim(),
                    'wabaId':        _waWabaIdCtrl.text.trim(),
                  },
                );
                if (!mounted) return;
                setS(() => _savingWa = false);
                if (res['success'] == true) {
                  // Mask the token after saving
                  setState(() => _waTokenCtrl.text = '••••••••');
                  if (ctx.mounted) Navigator.pop(ctx);
                  _showSuccess('WhatsApp credentials saved successfully');
                } else {
                  _showError(res['message'] ?? 'Failed to save');
                }
              } catch (e) {
                setS(() => _savingWa = false);
                _showError('Error: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _navy.withOpacity(0.5),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _savingWa
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Credentials',
                    style: TextStyle(fontWeight: FontWeight.w700)),
          )),
        ]),
      ]);
    });
  }

  // ── WhatsApp step helper ──────────────────────────────────────────────────
  Widget _waStep(String num, String prefix, String bold, String suffix) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 20, height: 20,
          margin: const EdgeInsets.only(right: 8, top: 1),
          decoration: BoxDecoration(
            color: const Color(0xFF25D366),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text(num,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
        ),
        Expanded(child: RichText(text: TextSpan(
          style: const TextStyle(fontSize: 12, color: _textSecondary, height: 1.4),
          children: [
            TextSpan(text: prefix),
            TextSpan(text: bold,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF128C7E))),
            TextSpan(text: suffix),
          ],
        ))),
      ]),
    );
  }

  // ── Banking ───────────────────────────────────────────────────────────────
  Widget _buildBankingSection() {
    return StatefulBuilder(builder: (ctx, setS) {
      bool saving = false;
      final hasQr = _qrCodePath != null && _qrCodePath!.isNotEmpty;
      final hasPendingQr = _pendingQrBytes != null || _pendingQrFile != null;
      final docLabelCtrl = TextEditingController();

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _infoBadge('These details appear on invoice PDFs as payment instructions.', _blue),
        const SizedBox(height: 14),
        _field(_bankHolderCtrl, 'Account Holder Name', Icons.person_outline),
        const SizedBox(height: 12),
        _field(_bankNumberCtrl, 'Account Number', Icons.numbers_outlined),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _field(_bankIfscCtrl, 'IFSC Code', Icons.code_outlined)),
          const SizedBox(width: 12),
          Expanded(child: _field(_bankNameCtrl, 'Bank Name', Icons.account_balance_outlined)),
        ]),
        const SizedBox(height: 12),
        _field(_upiCtrl, 'UPI ID', Icons.qr_code_outlined),
        const SizedBox(height: 12),
        _field(_otherPayCtrl, 'Other Payment Options', Icons.info_outline, maxLines: 2),
        const SizedBox(height: 16),
        const Text('Payment QR Code', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _navyDark)),
        const SizedBox(height: 8),
        if (hasPendingQr) ...[
          Container(
            height: 110, width: 110,
            decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
            child: kIsWeb && _pendingQrBytes != null
                ? Image.memory(_pendingQrBytes!, fit: BoxFit.contain)
                : _pendingQrFile != null ? Image.file(_pendingQrFile!, fit: BoxFit.contain) : const SizedBox(),
          ),
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton.icon(
              onPressed: _uploadingQr ? null : () async {
                setS(() => _uploadingQr = true);
                setState(() => _uploadingQr = true);
                try {
                  Map<String, dynamic> res;
                  if (_activeBranchId != null) {
                    res = await FinanceAuthServiceExtra.uploadBranchQr(
                      branchId: _activeBranchId!,
                      imageFile: _pendingQrFile, imageBytes: _pendingQrBytes,
                      filename: _pendingQrName ?? 'qr.png');
                  } else {
                    res = await FinanceAuthServiceExtra.uploadOrgQr(
                      imageFile: _pendingQrFile, imageBytes: _pendingQrBytes,
                      filename: _pendingQrName ?? 'qr.png');
                  }
                  if (!mounted) return;
                  if (res['success'] == true) {
                    setState(() {
                      _qrCodePath = res['data']?['qrCodePath']?.toString();
                      _pendingQrBytes = null; _pendingQrFile = null; _pendingQrName = null;
                    });
                    _showSuccess('QR code uploaded');
                  } else { _showError(res['message'] ?? 'Upload failed'); }
                } catch (e) { _showError('Error: $e'); }
                if (mounted) { setState(() => _uploadingQr = false); setS(() => _uploadingQr = false); }
              },
              icon: _uploadingQr ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload, size: 16),
              label: Text(_uploadingQr ? 'Uploading...' : 'Upload QR'),
              style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () { setState(() { _pendingQrBytes = null; _pendingQrFile = null; _pendingQrName = null; }); setS(() {}); },
              child: const Text('Discard'),
            ),
          ]),
        ] else if (hasQr) ...[
          Row(children: [
            const Icon(Icons.check_circle, color: _green, size: 18),
            const SizedBox(width: 6),
            const Text('QR code uploaded', style: TextStyle(fontSize: 14, color: _green)),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                final picker = ImagePicker();
                final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600, imageQuality: 90);
                if (picked == null) return;
                if (kIsWeb) { final bytes = await picked.readAsBytes(); setState(() { _pendingQrBytes = bytes; _pendingQrFile = null; _pendingQrName = picked.name; }); }
                else { setState(() { _pendingQrFile = File(picked.path); _pendingQrBytes = null; _pendingQrName = picked.name; }); }
                setS(() {});
              },
              icon: const Icon(Icons.edit, size: 16), label: const Text('Change'),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () async {
                setS(() => _uploadingQr = true);
                setState(() => _uploadingQr = true);
                try {
                  Map<String, dynamic> res;
                  if (_activeBranchId != null) {
                    res = await FinanceAuthServiceExtra.deleteBranchQr(_activeBranchId!);
                  } else {
                    res = await FinanceAuthService.delete('/api/finance/auth/delete-org-qr');
                  }
                  if (!mounted) return;
                  if (res['success'] == true) { setState(() => _qrCodePath = null); _showSuccess('QR code removed'); }
                  else { _showError(res['message'] ?? 'Failed'); }
                } catch (e) { _showError('Error: $e'); }
                if (mounted) { setState(() => _uploadingQr = false); setS(() => _uploadingQr = false); }
              },
              icon: const Icon(Icons.delete_outline, size: 16, color: _red),
              label: const Text('Remove', style: TextStyle(color: _red)),
            ),
          ]),
        ] else ...[
          OutlinedButton.icon(
            onPressed: () async {
              final picker = ImagePicker();
              final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600, imageQuality: 90);
              if (picked == null) return;
              if (kIsWeb) { final bytes = await picked.readAsBytes(); setState(() { _pendingQrBytes = bytes; _pendingQrFile = null; _pendingQrName = picked.name; }); }
              else { setState(() { _pendingQrFile = File(picked.path); _pendingQrBytes = null; _pendingQrName = picked.name; }); }
              setS(() {});
            },
            icon: const Icon(Icons.qr_code_2, size: 18), label: const Text('Upload QR Code'),
            style: OutlinedButton.styleFrom(foregroundColor: _blue, side: const BorderSide(color: _blue)),
          ),
        ],
        const SizedBox(height: 16),
        StatefulBuilder(builder: (_, ss) => _primaryBtn(
          label: saving ? 'Saving...' : 'Save Banking Details',
          icon: Icons.save_outlined, color: _navy, loading: saving,
          onPressed: () async {
            ss(() => saving = true);
            try {
              final body = {
                'bankAccountHolder': _bankHolderCtrl.text.trim(), 'bankAccountNumber': _bankNumberCtrl.text.trim(),
                'bankIfscCode': _bankIfscCtrl.text.trim(), 'bankName': _bankNameCtrl.text.trim(),
                'upiId': _upiCtrl.text.trim(), 'otherPaymentOptions': _otherPayCtrl.text.trim(),
              };
              Map<String, dynamic> res;
              if (_activeBranchId != null) {
                res = await FinanceAuthService.put('/api/finance/branches/$_activeBranchId/profile', body);
              } else {
                res = await FinanceAuthService.put('/api/finance/auth/update-org-profile', body);
              }
              if (!mounted) return;
              ss(() => saving = false);
              if (res['success'] == true) { if (ctx.mounted) Navigator.pop(ctx); _showSuccess('Banking details saved'); }
              else { _showError(res['message'] ?? 'Failed'); }
            } catch (e) { ss(() => saving = false); _showError('Error: $e'); }
          },
        )),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Documents', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _navyDark)),
          TextButton.icon(
            onPressed: _uploadingDoc ? null : () {
              showDialog(context: context, builder: (_) => AlertDialog(
                title: const Text('Add Document'),
                content: TextField(controller: docLabelCtrl, decoration: const InputDecoration(labelText: 'Document Label', border: OutlineInputBorder())),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      final label = docLabelCtrl.text.trim();
                      if (label.isEmpty) { _showError('Please enter a label'); return; }
                      try {
                        final picker = FilePicker.platform;
                        final result = await picker.pickFiles(withData: kIsWeb);
                        if (result == null) return;
                        setState(() => _uploadingDoc = true); setS(() {});
                        final res = await FinanceAuthServiceExtra.uploadOrgDocument(
                          docFile: kIsWeb ? null : File(result.files.single.path!),
                          docBytes: kIsWeb ? result.files.single.bytes : null,
                          filename: result.files.single.name, label: label);
                        if (!mounted) return;
                        if (res['success'] == true) { final doc = res['data'] as Map<String, dynamic>; setState(() { _orgDocuments.add(doc); _uploadingDoc = false; }); setS(() {}); _showSuccess('Document uploaded'); }
                        else { setState(() => _uploadingDoc = false); setS(() {}); _showError(res['message'] ?? 'Upload failed'); }
                      } catch (e) { setState(() => _uploadingDoc = false); setS(() {}); _showError('Error: $e'); }
                    },
                    child: const Text('Upload'),
                  ),
                ],
              ));
            },
            icon: const Icon(Icons.add, size: 16), label: const Text('Add Document'),
          ),
        ]),
        if (_orgDocuments.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No documents uploaded yet.', style: TextStyle(fontSize: 13, color: _textMuted)))
        else
          ...(_orgDocuments.map((doc) => ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined, color: _blue, size: 20),
            title: Text(doc['label']?.toString() ?? 'Document', style: const TextStyle(fontSize: 14, color: _textPrimary)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: _red, size: 18),
              onPressed: () async {
                try {
                  final res = await FinanceAuthServiceExtra.deleteOrgDocument(doc['_id']?.toString() ?? '');
                  if (res['success'] == true) { setState(() => _orgDocuments.removeWhere((d) => d['_id']?.toString() == doc['_id']?.toString())); setS(() {}); _showSuccess('Document deleted'); }
                  else { _showError(res['message'] ?? 'Delete failed'); }
                } catch (e) { _showError('Error: $e'); }
              },
            ),
          ))),
      ]);
    });
  }

  // ── Payment Gateway ───────────────────────────────────────────────────────
  Widget _buildPaymentGatewaySection() {
    final isRazorpay = _gatewayType == 'razorpay';
    return StatefulBuilder(builder: (ctx, setS) {
      if (_gatewayLoading) return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: _blue)));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_gatewayConnected) ...[
          Container(
            width: double.infinity, padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFBBF7D0))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.check_circle, color: Color(0xFF059669), size: 20),
                const SizedBox(width: 8),
                Text('${isRazorpay ? 'Razorpay' : 'Stripe'} Connected', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF065F46), fontSize: 15)),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      title: const Row(children: [Icon(Icons.link_off, color: _red), SizedBox(width: 10), Text('Disconnect Gateway')]),
                      content: const Text('Your payment gateway will be disconnected. Existing payment links will stop working.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: _white), child: const Text('Disconnect')),
                      ],
                    ));
                    if (confirm != true || !mounted) return;
                    setS(() => _gatewaySaving = true);
                    final res = await FinanceAuthService.delete('/api/finance/payment-gateway/gateway/disconnect');
                    if (!mounted) return;
                    if (res['success'] == true) {
                      setState(() { _gatewayConnected = false; _gatewayAccountName = ''; _gatewayAccountEmail = ''; _gatewayAccountId = ''; _gatewayBusinessType = ''; _gatewayProfileStatus = ''; _gatewayKeyId = ''; _gatewayConnectedAt = ''; _gatewayKeyIdCtrl.clear(); _gatewaySecretCtrl.clear(); _gatewayTestResult = null; _gatewayTestSuccess = false; });
                      setS(() { _gatewaySaving = false; });
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showSuccess('Gateway disconnected.');
                    } else { setS(() => _gatewaySaving = false); _showError(res['message'] ?? 'Failed'); }
                  },
                  child: const Text('Disconnect', style: TextStyle(color: _red, fontWeight: FontWeight.w600)),
                ),
              ]),
              const Divider(height: 16),
              if (_gatewayAccountName.isNotEmpty) _gwDetailRow(Icons.business_outlined, 'Account Name', _gatewayAccountName),
              if (_gatewayAccountEmail.isNotEmpty) _gwDetailRow(Icons.email_outlined, 'Email', _gatewayAccountEmail),
              if (_gatewayKeyId.isNotEmpty) _gwDetailRow(Icons.vpn_key_outlined, 'Key ID', _gatewayKeyId),
            ]),
          ),
          const SizedBox(height: 16),
        ] else ...[
          Row(children: [
            _gatewayOption('razorpay', 'Razorpay', 'India', Icons.payment, setS),
            const SizedBox(width: 10),
            _gatewayOption('stripe', 'Stripe', 'Global', Icons.credit_card, setS),
          ]),
          const SizedBox(height: 14),
        ],
        _infoBadge(isRazorpay ? 'Get Key ID & Secret from Razorpay Dashboard → Settings → API Keys.' : 'Get keys from Stripe Dashboard → Developers → API Keys', const Color(0xFFD97706)),
        const SizedBox(height: 14),
        _field(_gatewayKeyIdCtrl, isRazorpay ? 'Key ID (rzp_live_...)' : 'Publishable Key (pk_live_...)', Icons.vpn_key_outlined),
        const SizedBox(height: 12),
        StatefulBuilder(builder: (_, ss) => TextField(
          controller: _gatewaySecretCtrl,
          obscureText: !_gatewaySecretVisible,
          style: const TextStyle(fontSize: 15, color: _textPrimary),
          decoration: InputDecoration(
            labelText: isRazorpay ? 'Key Secret' : 'Secret Key (sk_live_...)',
            labelStyle: const TextStyle(fontSize: 14, color: _textSecondary),
            prefixIcon: const Icon(Icons.lock_outline, size: 18, color: _navy),
            suffixIcon: IconButton(
              icon: Icon(_gatewaySecretVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: Colors.grey[400]),
              onPressed: () { setState(() => _gatewaySecretVisible = !_gatewaySecretVisible); ss(() {}); },
            ),
            filled: true, fillColor: _pageBg, contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 1.5)),
          ),
        )),
        if (_gatewayTestResult != null) ...[
          const SizedBox(height: 12),
          _resultBadge(_gatewayTestResult!, _gatewayTestSuccess),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: _gatewayTesting ? null : () async {
              if (_gatewayKeyIdCtrl.text.trim().isEmpty || _gatewaySecretCtrl.text.trim().isEmpty) {
                setState(() { _gatewayTestSuccess = false; _gatewayTestResult = 'Enter both Key ID and Key Secret.'; });
                setS(() {}); return;
              }
              setState(() { _gatewayTesting = true; _gatewayTestResult = null; }); setS(() {});
              try {
                final res = await FinanceAuthService.post('/api/finance/payment-gateway/gateway/test', {'gateway': _gatewayType, 'keyId': _gatewayKeyIdCtrl.text.trim(), 'keySecret': _gatewaySecretCtrl.text.trim()});
                if (!mounted) return;
                if (res['success'] == true && res['data']?['valid'] == true) {
                  final d = res['data'] as Map<String, dynamic>;
                  setState(() { _gatewayTestSuccess = true; _gatewayAccountName = d['accountName']?.toString() ?? ''; _gatewayAccountEmail = d['accountEmail']?.toString() ?? ''; _gatewayAccountId = d['accountId']?.toString() ?? ''; _gatewayTestResult = 'Connection successful! Account verified.'; });
                } else {
                  setState(() { _gatewayTestSuccess = false; _gatewayTestResult = res['message']?.toString() ?? 'Invalid credentials.'; });
                }
              } catch (e) { setState(() { _gatewayTestSuccess = false; _gatewayTestResult = 'Failed: $e'; }); }
              finally { if (mounted) { setState(() => _gatewayTesting = false); setS(() {}); } }
            },
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), side: const BorderSide(color: _blue)),
            child: _gatewayTesting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _blue)) : const Text('Test Connection', style: TextStyle(color: _blue, fontWeight: FontWeight.w600)),
          )),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _primaryBtn(
            label: _gatewaySaving ? 'Saving...' : (_gatewayConnected ? 'Update & Save' : 'Save & Connect'),
            color: _navy, loading: _gatewaySaving,
            onPressed: () async {
              if (_gatewayKeyIdCtrl.text.trim().isEmpty || _gatewaySecretCtrl.text.trim().isEmpty) { _showError('Enter both Key ID and Key Secret.'); return; }
              setState(() => _gatewaySaving = true); setS(() {});
              try {
                final res = await FinanceAuthService.post('/api/finance/payment-gateway/gateway/save', {'gateway': _gatewayType, 'keyId': _gatewayKeyIdCtrl.text.trim(), 'keySecret': _gatewaySecretCtrl.text.trim(), 'accountName': _gatewayAccountName, 'accountEmail': _gatewayAccountEmail, 'accountId': _gatewayAccountId, 'businessType': _gatewayBusinessType, 'profileStatus': _gatewayProfileStatus});
                if (!mounted) return;
                if (res['success'] == true) {
                  setState(() { _gatewayConnected = true; _gatewayKeyId = _gatewayKeyIdCtrl.text.trim(); _gatewaySecretCtrl.clear(); _gatewayTestResult = null; _gatewaySaving = false; });
                  setS(() {});
                  if (ctx.mounted) Navigator.pop(ctx);
                  _showSuccess('Payment gateway connected successfully ✓');
                } else { setState(() => _gatewaySaving = false); setS(() {}); _showError(res['message'] ?? 'Failed'); }
              } catch (e) { setState(() => _gatewaySaving = false); setS(() {}); _showError('Error: $e'); }
            },
          )),
        ]),
      ]);
    });
  }

  Widget _gatewayOption(String value, String name, String subtitle, IconData icon, void Function(void Function()) setS) {
    final selected = _gatewayType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () { setState(() => _gatewayType = value); setS(() {}); },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEFF6FF) : _white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? _blue : Colors.grey[200]!, width: selected ? 2 : 1),
          ),
          child: Column(children: [
            Icon(icon, color: selected ? _blue : Colors.grey[400], size: 24),
            const SizedBox(height: 4),
            Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? _blue : _navyDark, fontSize: 13)),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            if (selected) const Icon(Icons.check_circle, color: _blue, size: 14),
          ]),
        ),
      ),
    );
  }

  Widget _gwDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 14, color: const Color(0xFF059669)),
        const SizedBox(width: 6),
        SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF065F46)))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF064E3B)), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  // ── Branches ──────────────────────────────────────────────────────────────
  Widget _buildBranchesSection() {
    final isOwnerOrAdmin = _role == 'owner' || _role == 'admin';
    return StatefulBuilder(builder: (ctx, setS) {
      if (_loadingBranches) return const Center(child: CircularProgressIndicator());
      return Column(children: [
        _infoBadge('Branches belong to "$_orgName". Switch org from sidebar to manage another org\'s branches.', _blue),
        const SizedBox(height: 14),
        if (_branches.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: _pageBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDE3EE))),
            child: Column(children: [
              const Icon(Icons.account_tree_outlined, size: 36, color: Color(0xFF94A3B8)),
              const SizedBox(height: 10),
              const Text('No branches yet', style: TextStyle(fontWeight: FontWeight.w600, color: _textPrimary)),
              const SizedBox(height: 4),
              Text('Add branches to separate data by location.', style: TextStyle(fontSize: 13, color: _textMuted), textAlign: TextAlign.center),
            ]),
          )
        else
          ..._branches.map((branch) {
            final name = branch['branchName'] as String? ?? '';
            final city = branch['city']       as String? ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _pageBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDDE3EE))),
              child: Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [_navy, _blue], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(9)),
                  child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'B', style: const TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w800))),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _textPrimary)),
                  if (city.isNotEmpty) Row(children: [const Icon(Icons.location_on_outlined, size: 11, color: Color(0xFF64748B)), const SizedBox(width: 2), Text(city, style: const TextStyle(fontSize: 12, color: _textMuted))]),
                ])),
                if (isOwnerOrAdmin) ...[
                  IconButton(icon: const Icon(Icons.edit_outlined, size: 18, color: _blue), onPressed: () async { await _showAddEditBranchDialog(existing: branch); setS(() {}); }),
                  IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: _red), onPressed: () async { await _deleteBranch(branch); setS(() {}); }),
                ],
              ]),
            );
          }),
        if (isOwnerOrAdmin) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async { await _showAddEditBranchDialog(); setS(() {}); },
              icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add Branch'),
              style: OutlinedButton.styleFrom(foregroundColor: _blue, side: const BorderSide(color: _blue), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ),
        ],
      ]);
    });
  }

  // ── My Organisations (with Rename + Leave) ────────────────────────────────
  Widget _buildOrganisationsSection() {
    return StatefulBuilder(builder: (ctx, setS) {
      return Column(
        children: _organizations.map((org) {
          final orgId    = org['orgId']?.toString()   ?? '';
          final orgName  = org['orgName']?.toString() ?? '';
          final role     = org['role']?.toString()    ?? '';
          final logoUrl  = org['logoUrl']?.toString();
          final isCurrent = orgId == _orgId;
          final isOwner   = role == 'owner';

          Color roleColor;
          switch (role) {
            case 'owner':      roleColor = _blue;   break;
            case 'admin':      roleColor = _purple; break;
            case 'accountant': roleColor = _green;  break;
            default:           roleColor = _orange;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isCurrent ? _blue.withOpacity(0.05) : _pageBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isCurrent ? _blue : const Color(0xFFDDE3EE), width: isCurrent ? 1.5 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(color: isCurrent ? _blue : Colors.grey[200], borderRadius: BorderRadius.circular(10)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: (logoUrl != null && logoUrl.isNotEmpty)
                        ? Image.network(_fullLogoUrl(logoUrl) ?? '', fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.business_rounded, color: isCurrent ? _white : Colors.grey[600], size: 20))
                        : Icon(Icons.business_rounded, color: isCurrent ? _white : Colors.grey[600], size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(orgName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: isCurrent ? _blue : _navyDark)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: roleColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(role.toUpperCase(), style: TextStyle(color: roleColor, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                ])),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: _blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Active', style: TextStyle(color: _blue, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                // ── Rename button ─────────────────────────────────────────
                if (isOwner)
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => _showRenameOrgDialog(orgId: orgId, currentName: orgName, setS: setS),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Rename', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _blue,
                      side: BorderSide(color: _blue.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  )),
                if (isOwner) const SizedBox(width: 10),
                // ── Leave button ──────────────────────────────────────────
                Expanded(child: OutlinedButton.icon(
                  onPressed: isCurrent
                      ? null
                      : () => _showLeaveOrgDialog(orgId: orgId, orgName: orgName, setS: setS, ctx: ctx),
                  icon: const Icon(Icons.exit_to_app_outlined, size: 15),
                  label: Text(isCurrent ? 'Active Org' : 'Leave', style: const TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isCurrent ? Colors.grey : _red,
                    side: BorderSide(color: isCurrent ? Colors.grey[300]! : _red.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                )),
              ]),
            ]),
          );
        }).toList(),
      );
    });
  }

  // ── Rename Org Dialog ─────────────────────────────────────────────────────
  void _showRenameOrgDialog({
    required String orgId,
    required String currentName,
    required void Function(void Function()) setS,
  }) {
    final ctrl   = TextEditingController(text: currentName);
    bool saving  = false;
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (dCtx, dSetS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.edit_outlined, color: _blue, size: 22),
            SizedBox(width: 10),
            Text('Rename Organisation'),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl, autofocus: true,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                labelText: 'Organisation Name',
                prefixIcon: const Icon(Icons.apartment_rounded, size: 18, color: _navy),
                filled: true, fillColor: _pageBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 1.5)),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red[200]!)),
                child: Row(children: [Icon(Icons.error_outline, color: Colors.red[700], size: 15), const SizedBox(width: 8), Expanded(child: Text(error!, style: TextStyle(color: Colors.red[700], fontSize: 13)))]),
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dCtx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: saving ? null : () async {
                final newName = ctrl.text.trim();
                if (newName.isEmpty) { dSetS(() => error = 'Name is required'); return; }
                if (newName == currentName) { Navigator.pop(dCtx); return; }
                dSetS(() { saving = true; error = null; });
                final res = await FinanceAuthService.put('/api/finance/auth/rename-org', {'orgId': orgId, 'newOrgName': newName});
                if (!mounted) return;
                if (res['success'] == true) {
                  final updatedOrgs = (res['data']?['organizations'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
                  await FinanceSecureStorage.saveOrganizations(updatedOrgs);
                  setState(() { _organizations = updatedOrgs; if (orgId == _orgId) _orgName = newName; });
                  setS(() {});
                  if (dCtx.mounted) Navigator.pop(dCtx);
                  _showSuccess('Organisation renamed successfully');
                } else {
                  dSetS(() { saving = false; error = res['message'] ?? 'Failed to rename'; });
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: _white),
              child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _white)) : const Text('Rename'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Leave Org Dialog (3-step confirmation) ────────────────────────────────
  void _showLeaveOrgDialog({
    required String orgId,
    required String orgName,
    required void Function(void Function()) setS,
    required BuildContext ctx,
  }) async {
    // Step 1
    final step1 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [Icon(Icons.warning_amber_rounded, color: _orange), SizedBox(width: 10), Text('Leave Organisation')]),
        content: Text('You are about to leave "$orgName".\n\nYou will lose all access to this organisation. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: _orange, foregroundColor: _white), child: const Text('Continue')),
        ],
      ),
    );
    if (step1 != true || !mounted) return;

    // Step 2
    final step2 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [Icon(Icons.warning_amber_rounded, color: _red), SizedBox(width: 10), Text('Are you sure?')]),
        content: RichText(
          text: TextSpan(style: const TextStyle(fontSize: 14, color: _textPrimary, height: 1.5), children: [
            const TextSpan(text: 'Leaving '),
            TextSpan(text: orgName, style: const TextStyle(fontWeight: FontWeight.bold, color: _red)),
            const TextSpan(text: ' will permanently revoke your access.\n\nThis action cannot be undone.'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: _white), child: const Text('Yes, Leave')),
        ],
      ),
    );
    if (step2 != true || !mounted) return;

    // Step 3 — type org name to confirm
    final confirmCtrl = TextEditingController();
    bool confirmed = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (dCtx, dSetS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(children: [Icon(Icons.lock_outline_rounded, color: _red), SizedBox(width: 10), Text('Final Confirmation')]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _red.withOpacity(0.06), borderRadius: BorderRadius.circular(8), border: Border.all(color: _red.withOpacity(0.2))),
              child: Row(children: [const Icon(Icons.info_outline, color: _red, size: 14), const SizedBox(width: 8), Expanded(child: Text('Type the organisation name below to confirm leaving.', style: const TextStyle(fontSize: 13, color: _red)))]),
            ),
            const SizedBox(height: 14),
            Text('Type: "$orgName"', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navyDark)),
            const SizedBox(height: 8),
            TextField(
              controller: confirmCtrl, autofocus: true,
              onChanged: (_) => dSetS(() {}),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: orgName,
                filled: true, fillColor: _pageBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _red, width: 1.5)),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: confirmCtrl.text.trim() == orgName ? () { confirmed = true; Navigator.pop(dCtx); } : null,
              style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: _white, disabledBackgroundColor: _red.withOpacity(0.3)),
              child: const Text('Leave Organisation'),
            ),
          ],
        ),
      ),
    );

    if (!confirmed || !mounted) return;

    // Call API
    final res = await FinanceAuthService.delete('/api/finance/auth/leave-org', body: {'orgId': orgId});
    if (!mounted) return;
    if (res['success'] == true) {
      final updatedOrgs = (res['data']?['organizations'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await FinanceSecureStorage.saveOrganizations(updatedOrgs);
      setState(() => _organizations = updatedOrgs);
      setS(() {});
      if (ctx.mounted) Navigator.pop(ctx);
      _showSuccess('You have left "$orgName"');
    } else {
      _showError(res['message'] ?? 'Failed to leave organisation');
    }
  }

  // ── Create Org ────────────────────────────────────────────────────────────
  Widget _buildCreateOrgSection() {
    return StatefulBuilder(builder: (ctx, setS) {
      final orgCtrl  = TextEditingController();
      bool  creating = false;
      String? error;
      return StatefulBuilder(builder: (ctx2, setS2) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _infoBadge('You will become the Owner of this new organisation. You can switch between orgs from the sidebar.', _navy),
          const SizedBox(height: 16),
          const Text('Organisation Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _navy)),
          const SizedBox(height: 8),
          TextField(
            controller: orgCtrl, autofocus: true,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: 'e.g. Abra Logistics Pvt Ltd',
              prefixIcon: const Icon(Icons.apartment_rounded, size: 18, color: _navy),
              filled: true, fillColor: _pageBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 1.5)),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red[200]!)),
              child: Row(children: [Icon(Icons.error_outline, color: Colors.red[700], size: 15), const SizedBox(width: 8), Expanded(child: Text(error!, style: TextStyle(color: Colors.red[700], fontSize: 13)))]),
            ),
          ],
          const SizedBox(height: 20),
          _primaryBtn(
            label: creating ? 'Creating...' : 'Create Organisation',
            icon: Icons.add_rounded, color: _navy, loading: creating,
            onPressed: () async {
              final name = orgCtrl.text.trim();
              if (name.isEmpty) { setS2(() => error = 'Organisation name is required'); return; }
              setS2(() { creating = true; error = null; });
              final res = await FinanceAuthService.post('/api/finance/auth/create-org', {'orgName': name});
              if (!mounted) return;
              if (res['success'] == true) {
                final data = res['data'] as Map<String, dynamic>;
                final orgs = (data['organizations'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
                await FinanceSecureStorage.saveOrganizations(orgs);
                setState(() => _organizations = orgs);
                if (ctx.mounted) Navigator.pop(ctx);
                _showSuccess(res['message'] ?? 'Organisation created!');
              } else {
                setS2(() { creating = false; error = res['message'] ?? 'Failed to create'; });
              }
            },
          ),
        ]);
      });
    });
  }

  // ── Delete Account ────────────────────────────────────────────────────────
  Widget _buildDeleteAccountSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _red.withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: _red.withOpacity(0.2))),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, color: _red, size: 16),
          SizedBox(width: 10),
          Expanded(child: Text(
            'Deleting your account is permanent. Your login will be blocked immediately and all access will be revoked. There is no way to recover it.',
            style: TextStyle(fontSize: 13, color: _red, height: 1.5),
          )),
        ]),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _deleteAccount,
          icon: const Icon(Icons.delete_forever_rounded, size: 18, color: _red),
          label: const Text('Delete My Account', style: TextStyle(fontWeight: FontWeight.w700, color: _red, fontSize: 15)),
          style: OutlinedButton.styleFrom(foregroundColor: _red, side: const BorderSide(color: _red, width: 1.5), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        ),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BRANCH HELPERS (kept from original)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _showAddEditBranchDialog({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final nameCtrl    = TextEditingController(text: existing?['branchName'] ?? '');
    final cityCtrl    = TextEditingController(text: existing?['city']       ?? '');
    final addressCtrl = TextEditingController(text: existing?['address']    ?? '');
    final phoneCtrl   = TextEditingController(text: existing?['phone']      ?? '');
    final emailCtrl   = TextEditingController(text: existing?['email']      ?? '');
    final gstinCtrl   = TextEditingController(text: existing?['gstin']      ?? '');
    final formKey     = GlobalKey<FormState>();
    bool saving       = false;
    String? error;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 460,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_navyDark, _navy], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                ),
                child: Row(children: [
                  Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.account_tree_rounded, color: _white, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(isEdit ? 'Edit Branch' : 'Add New Branch', style: const TextStyle(color: _white, fontSize: 17, fontWeight: FontWeight.bold))),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white70, size: 20), onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: formKey,
                    child: Column(children: [
                      if (error != null) ...[
                        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _red.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: _red.withOpacity(0.3))), child: Row(children: [const Icon(Icons.error_outline, color: _red, size: 16), const SizedBox(width: 8), Expanded(child: Text(error!, style: const TextStyle(color: _red, fontSize: 13)))])),
                        const SizedBox(height: 14),
                      ],
                      _branchField(nameCtrl, 'Branch Name *', Icons.store_outlined, required: true),
                      const SizedBox(height: 12),
                      _branchField(cityCtrl, 'City', Icons.location_city_outlined),
                      const SizedBox(height: 12),
                      _branchField(addressCtrl, 'Address', Icons.location_on_outlined, maxLines: 2),
                      const SizedBox(height: 12),
                      _branchField(phoneCtrl, 'Phone', Icons.phone_outlined),
                      const SizedBox(height: 12),
                      _branchField(emailCtrl, 'Email', Icons.email_outlined),
                      const SizedBox(height: 12),
                      _branchField(gstinCtrl, 'GSTIN', Icons.receipt_outlined),
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Cancel'))),
                        const SizedBox(width: 12),
                        Expanded(child: ElevatedButton(
                          onPressed: saving ? null : () async {
                            if (!formKey.currentState!.validate()) return;
                            setS(() { saving = true; error = null; });
                            try {
                              final body = {'branchName': nameCtrl.text.trim(), 'city': cityCtrl.text.trim(), 'address': addressCtrl.text.trim(), 'phone': phoneCtrl.text.trim(), 'email': emailCtrl.text.trim(), 'gstin': gstinCtrl.text.trim()};
                              Map<String, dynamic> res;
                              if (isEdit) { res = await FinanceAuthService.put('/api/finance/branches/${existing!['branchId']}', body); }
                              else { res = await FinanceAuthService.post('/api/finance/branches', body); }
                              if (res['success'] == true) { if (ctx.mounted) Navigator.pop(ctx); await _loadBranches(); if (mounted) _showSuccess(isEdit ? 'Branch updated' : 'Branch created'); }
                              else { setS(() { error = res['message'] ?? 'Failed'; saving = false; }); }
                            } catch (e) { setS(() { error = 'Error: $e'; saving = false; }); }
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: _white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(isEdit ? 'Save Changes' : 'Create Branch'),
                        )),
                      ]),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _branchField(TextEditingController ctrl, String label, IconData icon, {bool required = false, int maxLines = 1}) {
    return TextFormField(
      controller: ctrl, maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: _navy),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
    );
  }

  Future<void> _deleteBranch(Map<String, dynamic> branch) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [Icon(Icons.delete_outline, color: _red), SizedBox(width: 10), Text('Delete Branch')]),
        content: Text('Delete "${branch['branchName']}"? All data tagged to this branch will remain.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: _white), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final res = await FinanceAuthService.delete('/api/finance/branches/${branch['branchId']}');
      if (res['success'] == true) { await _loadBranches(); _showSuccess('Branch deleted'); }
      else { _showError(res['message'] ?? 'Failed'); }
    } catch (e) { _showError('Error: $e'); }
  }

  // ── Delete Account ────────────────────────────────────────────────────────
  Future<void> _deleteAccount() async {
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [Icon(Icons.warning_amber_rounded, color: _red), SizedBox(width: 10), Text('Delete Account')]),
        content: const Text('This will permanently delete your account. You will lose access to all your data. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: _white), child: const Text('Continue')),
        ],
      ),
    );
    if (confirm1 != true || !mounted) return;

    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [Icon(Icons.delete_forever_rounded, color: _red), SizedBox(width: 10), Text('Are you absolutely sure?')]),
        content: RichText(
          text: TextSpan(style: const TextStyle(fontSize: 14, color: _textPrimary, height: 1.5), children: [
            const TextSpan(text: 'You are about to permanently delete the account for\n'),
            TextSpan(text: _email, style: const TextStyle(fontWeight: FontWeight.bold, color: _red)),
            const TextSpan(text: '\n\nThis cannot be recovered.'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: _white), child: const Text('Yes, Delete My Account')),
        ],
      ),
    );
    if (confirm2 != true || !mounted) return;

    final res = await FinanceAuthService.delete('/api/finance/auth/delete-account');
    if (!mounted) return;
    if (res['success'] == true) {
      await FinanceSecureStorage.clearSession();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => AccountDeletedScreen()), (_) => false);
    } else {
      _showError(res['message'] ?? 'Failed to delete account. Please try again.');
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [Icon(Icons.logout, color: _navy), SizedBox(width: 10), Text('Sign Out')]),
        content: const Text('Are you sure you want to sign out of the Finance Module?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: _white), child: const Text('Sign Out')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await FinanceSecureStorage.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const FinanceWelcomeScreen()), (_) => false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED SMALL WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLogoPreview({required bool hasPending, required bool hasLogo, String? fullUrl}) {
    if (hasPending) {
      if (kIsWeb && _pendingLogoBytes != null) return Image.memory(_pendingLogoBytes!, fit: BoxFit.contain, width: double.infinity, height: 150);
      if (_pendingLogoFile != null) return Image.file(_pendingLogoFile!, fit: BoxFit.contain, width: double.infinity, height: 150);
    }
    if (hasLogo && fullUrl != null) {
      return Image.network(fullUrl, fit: BoxFit.contain, width: double.infinity, height: 150,
          errorBuilder: (_, __, ___) => _logoPlaceholder(),
          loadingBuilder: (_, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(color: _blue)));
    }
    return _logoPlaceholder();
  }

  Widget _logoPlaceholder() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.image_outlined, size: 40, color: Colors.grey[400]),
    const SizedBox(height: 8),
    Text('No logo uploaded yet', style: TextStyle(fontSize: 13, color: _textMuted)),
    const SizedBox(height: 4),
    Text('Will appear on PDFs & emails', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
  ]);

  Widget _buildSigPreview({required bool hasPending, required bool hasSig, String? fullUrl}) {
    if (hasPending) {
      if (kIsWeb && _pendingSigBytes != null) return Image.memory(_pendingSigBytes!, fit: BoxFit.contain, width: double.infinity, height: 120);
      if (_pendingSigFile != null) return Image.file(_pendingSigFile!, fit: BoxFit.contain, width: double.infinity, height: 120);
    }
    if (hasSig && fullUrl != null) {
      return Image.network(fullUrl, fit: BoxFit.contain, width: double.infinity, height: 120,
          errorBuilder: (_, __, ___) => _sigPlaceholder(),
          loadingBuilder: (_, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(color: _purple)));
    }
    return _sigPlaceholder();
  }

  Widget _sigPlaceholder() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.draw_outlined, size: 36, color: Colors.grey[400]),
    const SizedBox(height: 8),
    Text('No signature uploaded yet', style: TextStyle(fontSize: 13, color: _textMuted)),
  ]);

  Widget _primaryBtn({required String label, IconData? icon, required Color color, bool loading = false, required VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _white))
            : (icon != null ? Icon(icon, size: 17) : const SizedBox.shrink()),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color, foregroundColor: _white,
          disabledBackgroundColor: color.withOpacity(0.5),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _infoBadge(String text, Color color) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.15))),
    child: Row(children: [
      Icon(Icons.info_outline, size: 15, color: color.withOpacity(0.9)),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: _textSecondary))),
    ]),
  );

  Widget _successBadge(String text) => Container(
    width: double.infinity, padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFBBF7D0))),
    child: Row(children: [
      const Icon(Icons.check_circle, color: Color(0xFF059669), size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w600, fontSize: 13))),
    ]),
  );

  Widget _resultBadge(String text, bool success) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: success ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: success ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
    ),
    child: Row(children: [
      Icon(success ? Icons.check_circle_outline : Icons.error_outline, color: success ? const Color(0xFF059669) : const Color(0xFFDC2626), size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: success ? const Color(0xFF065F46) : const Color(0xFF991B1B)))),
    ]),
  );

  Widget _formField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    String? Function(String?)? validator,
    String? hint,  // ✅ NEW: Optional hint text
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 15),
      validator: validator,
      decoration: _fieldDeco(label, icon, hint: hint),  // ✅ Pass hint to decoration
    );
  }

  Widget _pwField({required TextEditingController ctrl, required String label, required bool obscure, required VoidCallback onToggle, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl, obscureText: obscure,
      style: const TextStyle(fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(fontSize: 14, color: _textSecondary),
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: _navy),
        suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey[400], size: 18), onPressed: onToggle),
        filled: true, fillColor: _pageBg, contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.red.shade300)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.red.shade300, width: 1.5)),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, {int maxLines = 1}) => TextField(
    controller: ctrl, maxLines: maxLines,
    style: const TextStyle(fontSize: 15, color: _textPrimary),
    decoration: _fieldDeco(label, icon),
  );

  InputDecoration _fieldDeco(String label, IconData icon, {String? hint}) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 14, color: _textSecondary),
    hintText: hint,  // ✅ NEW: Add hint text support
    hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),  // ✅ Style for hint
    prefixIcon: Icon(icon, size: 18, color: _navy),
    filled: true,
    fillColor: _pageBg,
    contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 1.5)),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SETTING CARD WIDGET
// ═══════════════════════════════════════════════════════════════════════════════
class _SettingCard extends StatelessWidget {
  final _SettingItem item;
  final VoidCallback onTap;
  const _SettingCard({required this.item, required this.onTap});

  static const Map<String, List<Color>> _gradients = {
    'personal':        [Color(0xFF3D8EFF), Color(0xFF1A3A6B)],
    'password':        [Color(0xFF1A3A6B), Color(0xFF0D1B3E)],
    'org_details':     [Color(0xFF2463AE), Color(0xFF0D1B3E)],
    'org_logo':        [Color(0xFF3D8EFF), Color(0xFF2463AE)],
    'banking':         [Color(0xFF0D1B3E), Color(0xFF2463AE)],
    'signature':       [Color(0xFF1A3A6B), Color(0xFF3D8EFF)],
    'email':           [Color(0xFF2463AE), Color(0xFF3D8EFF)],
    'whatsapp':        [Color(0xFF25D366), Color(0xFF128C7E)],
    'payment_gateway': [Color(0xFF0D1B3E), Color(0xFF3D8EFF)],
    'branches':        [Color(0xFF1A3A6B), Color(0xFF2463AE)],
    'organisations':   [Color(0xFF2463AE), Color(0xFF1A3A6B)],
    'create_org':      [Color(0xFF3D8EFF), Color(0xFF0D1B3E)],
    'delete_account':  [Color(0xFFB71C1C), Color(0xFF0D1B3E)],
  };

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[item.id] ??
        [const Color(0xFF2463AE), const Color(0xFF0D1B3E)];
    final isDestructive = item.id == 'delete_account';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDestructive
                ? const Color(0xFFB71C1C).withOpacity(0.4)
                : const Color(0xFF2463AE).withOpacity(0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: colors[1].withOpacity(0.10),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon container with gradient background
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                item.icon,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDestructive
                      ? const Color(0xFFB71C1C)
                      : const Color(0xFF0D1B3E),
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROFILE MODAL WRAPPER
// ═══════════════════════════════════════════════════════════════════════════════
class _ProfileModal extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  const _ProfileModal({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final dialogW = screenW > 640 ? 560.0 : screenW * 0.92;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: dialogW,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 30, offset: const Offset(0, 10))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_navyDark, _navy], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, color: _white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(color: _white, fontSize: 17, fontWeight: FontWeight.bold))),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),
          // Scrollable body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: child,
            ),
          ),
        ]),
      ),
    );
  }
}

// ── _SectionLabel helper ──────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _navyDark, letterSpacing: 0.3));
  }
}