// ============================================================================
// FINANCE PROFILE PAGE — CHUNK 1 of 2
// Copy everything from here to the end of _sectionOrgLogo()
// ============================================================================
// File: lib/features/finance_auth/presentation/pages/finance_profile_page.dart
// ✅ UPDATED:
//   • Desktop layout fixed to proper 2-column split
//   • All font sizes increased by 1px
//   • Grey text replaced with black/near-black
//   • Section card icon colors set to _navy
// ============================================================================

import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/finance_secure_storage.dart';
import '../../../data/services/finance_auth_service.dart';
import '../../finance_welcome_screen.dart';
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

// ── Text colours (black-based, replacing greys) ───────────────────────────────
const Color _textPrimary   = Color(0xFF0F172A); // was navyDark / grey[900]
const Color _textSecondary = Color(0xFF1E293B); // was grey[700] / 64748B
const Color _textMuted     = Color(0xFF334155); // was grey[500] / 94A3B8

class FinanceProfilePage extends StatefulWidget {
  const FinanceProfilePage({Key? key}) : super(key: key);

  @override
  State<FinanceProfilePage> createState() => _FinanceProfilePageState();
}

class _FinanceProfilePageState extends State<FinanceProfilePage> {
  // ── Session data ─────────────────────────────────────────────────────────────
  String  _name          = '';
  String  _email         = '';
  String  _phone         = '';
  String  _role          = '';
  String  _orgId         = '';
  String  _orgName       = '';
  String? _orgLogoUrl;
  String? _createdBy;
  List<Map<String, dynamic>> _organizations = [];
  bool    _sessionLoaded = false;

  // ── Profile form ──────────────────────────────────────────────────────────────
  final _profileFormKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  bool _savingProfile = false;

  // ── Password form ─────────────────────────────────────────────────────────────
  final _pwFormKey     = GlobalKey<FormState>();
  final _currPwCtrl    = TextEditingController();
  final _newPwCtrl     = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  bool _savingPw       = false;
  bool _obscureCurr    = true;
  bool _obscureNew     = true;
  bool _obscureConfirm = true;

  // ── Logo upload state ─────────────────────────────────────────────────────────
  bool       _uploadingLogo   = false;
  bool       _deletingLogo    = false;
  Uint8List? _pendingLogoBytes;
  File?      _pendingLogoFile;
  String?    _pendingLogoName;

  // ── Create org ────────────────────────────────────────────────────────────────
  bool get _canCreateOrg => _role == 'owner' && (_createdBy == null || _createdBy!.isEmpty);

  // ── Org profile form ──────────────────────────────────────────────────────────
  final _gstCtrl        = TextEditingController();
  final _orgPhoneCtrl   = TextEditingController();
  final _whatsappCtrl   = TextEditingController();
  final _orgEmailCtrl   = TextEditingController();
  final _addressCtrl    = TextEditingController();
  bool _savingOrgProfile  = false;
  bool _loadingOrgProfile = false;

  // ── Banking details form ───────────────────────────────────────────────────────
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

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController();
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _loadSession();
    _loadOrgProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _currPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    _gstCtrl.dispose();
    _orgPhoneCtrl.dispose();
    _whatsappCtrl.dispose();
    _orgEmailCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  // ── Load session ──────────────────────────────────────────────────────────────
  Future<void> _loadSession() async {
    final name       = await FinanceSecureStorage.getName()       ?? '';
    final email      = await FinanceSecureStorage.getEmail()      ?? '';
    final phone      = await FinanceSecureStorage.getPhone()      ?? '';
    final role       = await FinanceSecureStorage.getRole()       ?? '';
    final orgId      = await FinanceSecureStorage.getOrgId()      ?? '';
    final orgNm      = await FinanceSecureStorage.getOrgName()    ?? '';
    final orgLogoUrl = await FinanceSecureStorage.getOrgLogoUrl();
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
        _organizations = orgs;
        _sessionLoaded = true;
        _nameCtrl.text  = name;
        _emailCtrl.text = email;
        _phoneCtrl.text = phone;
      });
    }
  }

  // ── Load / Save Org Profile ───────────────────────────────────────────────────
  Future<void> _loadOrgProfile() async {
    setState(() => _loadingOrgProfile = true);
    try {
      final res = await FinanceAuthService.get('/api/finance/auth/org-profile');
      if (res['success'] == true) {
        final d = res['data'] as Map<String, dynamic>? ?? {};
        if (mounted) {
          setState(() {
            _gstCtrl.text      = d['gstNumber']?.toString()      ?? '';
            _orgPhoneCtrl.text = d['phone']?.toString()          ?? '';
            _whatsappCtrl.text = d['whatsappNumber']?.toString() ?? '';
            _orgEmailCtrl.text = d['email']?.toString()          ?? '';
            _addressCtrl.text  = d['address']?.toString()        ?? '';
            _bankHolderCtrl.text = d['bankAccountHolder']?.toString()   ?? '';
            _bankNumberCtrl.text = d['bankAccountNumber']?.toString()   ?? '';
            _bankIfscCtrl.text   = d['bankIfscCode']?.toString()        ?? '';
            _bankNameCtrl.text   = d['bankName']?.toString()            ?? '';
            _upiCtrl.text        = d['upiId']?.toString()               ?? '';
            _otherPayCtrl.text   = d['otherPaymentOptions']?.toString() ?? '';
            _qrCodePath          = d['qrCodePath']?.toString();
            _orgDocuments        = List<Map<String, dynamic>>.from(
              (d['documents'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
            );
          });
        }
      }
    } catch (e) {
      debugPrint('❌ _loadOrgProfile error: $e');
    } finally {
      if (mounted) setState(() => _loadingOrgProfile = false);
    }
  }

  Future<void> _saveOrgProfile() async {
    setState(() => _savingOrgProfile = true);
    try {
      final res = await FinanceAuthService.put('/api/finance/auth/update-org-profile', {
        'gstNumber':      _gstCtrl.text.trim(),
        'phone':          _orgPhoneCtrl.text.trim(),
        'whatsappNumber': _whatsappCtrl.text.trim(),
        'email':          _orgEmailCtrl.text.trim(),
        'address':        _addressCtrl.text.trim(),
      });
      if (res['success'] == true) {
        _showSuccess('Organisation details saved successfully');
      } else {
        _showError(res['message'] ?? 'Failed to save organisation details');
      }
    } catch (e) {
      _showError('Error saving organisation details: $e');
    } finally {
      if (mounted) setState(() => _savingOrgProfile = false);
    }
  }

  // ── Initials ──────────────────────────────────────────────────────────────────
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

  // ── Resolve full logo URL ─────────────────────────────────────────────────────
  String? _fullLogoUrl(String? relative) {
    if (relative == null || relative.isEmpty) return null;
    if (relative.startsWith('http')) return relative;
    final base = FinanceApiConfig.baseUrl.replaceAll(RegExp(r'/$'), '');
    return '$base$relative';
  }

  // ── Update profile ────────────────────────────────────────────────────────────
  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    setState(() => _savingProfile = true);

    final res = await FinanceAuthService.put('/api/finance/auth/update-profile', {
      'name':  _nameCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
    });

    if (!mounted) return;
    setState(() => _savingProfile = false);

    if (res['success'] == true) {
      final user = (res['data'] as Map?)?['user'] as Map? ?? {};
      await FinanceSecureStorage.saveSession(
        token:      await FinanceSecureStorage.getToken()   ?? '',
        userId:     await FinanceSecureStorage.getUserId()  ?? '',
        name:       user['name']?.toString()  ?? _nameCtrl.text,
        email:      user['email']?.toString() ?? _emailCtrl.text,
        phone:      user['phone']?.toString() ?? _phoneCtrl.text,
        role:       _role,
        orgId:      _orgId,
        orgName:    _orgName,
        orgLogoUrl: _orgLogoUrl,
      );
      setState(() {
        _name  = user['name']?.toString()  ?? _nameCtrl.text;
        _email = user['email']?.toString() ?? _emailCtrl.text;
        _phone = user['phone']?.toString() ?? _phoneCtrl.text;
      });
      _showSuccess('Profile updated successfully');
    } else {
      _showError(res['message'] ?? 'Failed to update profile');
    }
  }

  // ── Change password ───────────────────────────────────────────────────────────
  Future<void> _changePassword() async {
    if (!_pwFormKey.currentState!.validate()) return;
    setState(() => _savingPw = true);

    final res = await FinanceAuthService.put('/api/finance/auth/change-password', {
      'currentPassword': _currPwCtrl.text,
      'newPassword':     _newPwCtrl.text,
    });

    if (!mounted) return;
    setState(() => _savingPw = false);

    if (res['success'] == true) {
      _currPwCtrl.clear();
      _newPwCtrl.clear();
      _confirmPwCtrl.clear();
      _showSuccess('Password changed successfully');
    } else {
      _showError(res['message'] ?? 'Failed to change password');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // LOGO UPLOAD METHODS
  // ══════════════════════════════════════════════════════════════════════════════

  Future<void> _pickLogo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source:    ImageSource.gallery,
        maxWidth:  1200,
        maxHeight: 600,
        imageQuality: 90,
      );
      if (picked == null) return;

      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _pendingLogoBytes = bytes;
          _pendingLogoFile  = null;
          _pendingLogoName  = picked.name;
        });
      } else {
        setState(() {
          _pendingLogoFile  = File(picked.path);
          _pendingLogoBytes = null;
          _pendingLogoName  = picked.name;
        });
      }
    } catch (e) {
      _showError('Could not pick image: $e');
    }
  }

  Future<void> _uploadLogo() async {
    if (_pendingLogoBytes == null && _pendingLogoFile == null) return;

    setState(() => _uploadingLogo = true);

    final res = await FinanceAuthService.uploadOrgLogo(
      imageFile:  _pendingLogoFile,
      imageBytes: _pendingLogoBytes,
      filename:   _pendingLogoName ?? 'logo.jpg',
    );

    if (!mounted) return;
    setState(() => _uploadingLogo = false);

    if (res['success'] == true) {
      final newUrl = res['data']?['logoUrl']?.toString();
      setState(() {
        _orgLogoUrl       = newUrl;
        _pendingLogoBytes = null;
        _pendingLogoFile  = null;
        _pendingLogoName  = null;
      });
      _showSuccess('Logo uploaded successfully! It will appear on invoices, quotes, and emails.');
    } else {
      _showError(res['message'] ?? 'Logo upload failed');
    }
  }

  Future<void> _deleteLogo() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.delete_outline, color: _red),
          SizedBox(width: 10),
          Text('Remove Logo'),
        ]),
        content: const Text('Remove the logo for this organisation? PDFs and emails will show the default logo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: _white),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _deletingLogo = true);
    final res = await FinanceAuthService.deleteOrgLogo();
    if (!mounted) return;
    setState(() {
      _deletingLogo = false;
      if (res['success'] == true) {
        _orgLogoUrl       = null;
        _pendingLogoBytes = null;
        _pendingLogoFile  = null;
        _pendingLogoName  = null;
      }
    });
    if (res['success'] == true) {
      _showSuccess('Logo removed');
    } else {
      _showError(res['message'] ?? 'Failed to remove logo');
    }
  }

  void _discardPending() {
    setState(() {
      _pendingLogoBytes = null;
      _pendingLogoFile  = null;
      _pendingLogoName  = null;
    });
  }

  // ── Create org dialog ─────────────────────────────────────────────────────────
  void _showCreateOrgDialog() {
    final orgCtrl  = TextEditingController();
    bool  creating = false;
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 420,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_navyDark, _navy],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft:  Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.business_rounded, color: _white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text('Create New Organisation',
                          style: TextStyle(color: _white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: _white),
                      onPressed: creating ? null : () => Navigator.pop(ctx),
                    ),
                  ]),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Organisation Name',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _navy)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: orgCtrl,
                        autofocus: true,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'e.g. Abra Logistics Pvt Ltd',
                          prefixIcon: const Icon(Icons.apartment_rounded, size: 18, color: _navy),
                          filled: true,
                          fillColor: _pageBg,
                          contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 1.5)),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(children: [
                            Icon(Icons.error_outline, color: Colors.red[700], size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(error!, style: TextStyle(color: Colors.red[700], fontSize: 14))),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        'You will become the Owner of this new organisation.',
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                // Footer
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: creating ? null : () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _textSecondary,
                          side: BorderSide(color: Colors.grey[300]!),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: creating
                            ? null
                            : () async {
                                final name = orgCtrl.text.trim();
                                if (name.isEmpty) {
                                  setS(() => error = 'Organisation name is required');
                                  return;
                                }
                                setS(() { creating = true; error = null; });

                                final res = await FinanceAuthService.post(
                                  '/api/finance/auth/create-org',
                                  {'orgName': name},
                                );

                                if (!mounted) return;

                                if (res['success'] == true) {
                                  final data = res['data'] as Map<String, dynamic>;
                                  final orgs = (data['organizations'] as List)
                                      .map((e) => Map<String, dynamic>.from(e as Map))
                                      .toList();
                                  await FinanceSecureStorage.saveOrganizations(orgs);
                                  setState(() => _organizations = orgs);
                                  Navigator.pop(ctx);
                                  _showSuccess(res['message'] ?? 'Organisation created!');
                                } else {
                                  setS(() {
                                    creating = false;
                                    error = res['message'] ?? 'Failed to create organisation';
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:         _navy,
                          foregroundColor:         _white,
                          disabledBackgroundColor: _navy.withOpacity(0.5),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: creating
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(color: _white, strokeWidth: 2))
                            : const Text('Create', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Logout ────────────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.logout, color: _navy),
          SizedBox(width: 10),
          Text('Sign Out'),
        ]),
        content: const Text('Are you sure you want to sign out of the Finance Module?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: _white),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await FinanceSecureStorage.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const FinanceWelcomeScreen()),
      (_) => false,
    );
  }

  // ── Snackbars ─────────────────────────────────────────────────────────────────
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
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (!_sessionLoaded) {
      return const Scaffold(
        backgroundColor: _pageBg,
        body: Center(child: CircularProgressIndicator(color: _blue)),
      );
    }

    return Scaffold(
      backgroundColor: _pageBg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: LayoutBuilder(builder: (_, c) {
              if (c.maxWidth >= 1100) return _buildDesktopLayout();
              if (c.maxWidth >= 700)  return _buildTabletLayout();
              return _buildMobileLayout();
            }),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────────
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
                  Row(children: [
                    _roleBadge(_role),
                    const SizedBox(width: 8),
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
                        Text(_orgName,
                            style: const TextStyle(color: _white, fontSize: 12, fontWeight: FontWeight.w500)),
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

  // ── Layouts ───────────────────────────────────────────────────────────────────

  // ✅ Desktop: 3-row grid layout
  // Row 1 → Personal Info        | Change Password
  // Row 2 → Organisation Logo    | Organisation Details
  // Row 3 → Banking Details      | My Organisations
  //                              | Create Org (below My Orgs, same column)
  Widget _buildDesktopLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Row 1: Personal Info + Change Password ──────────────────────────
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _sectionPersonalInfo()),
                const SizedBox(width: 20),
                Expanded(child: _sectionChangePassword()),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Row 2: Organisation Logo + Organisation Details ─────────────────
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _sectionOrgLogo()),
                const SizedBox(width: 20),
                Expanded(child: _sectionOrgDetails()),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Row 3: Banking Details (left) | My Orgs + Create Org (right) ────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left — Banking Details (takes full height naturally)
              Expanded(child: _sectionBanking()),
              const SizedBox(width: 20),
              // Right — My Organisations stacked with Create Org below
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionMyOrganisations(),
                    if (_canCreateOrg) ...[
                      const SizedBox(height: 16),
                      _sectionCreateOrg(),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _sectionPersonalInfo()),
          const SizedBox(width: 14),
          Expanded(child: Column(children: [
            _sectionOrgLogo(),
            const SizedBox(height: 14),
            _sectionOrgDetails(),
            const SizedBox(height: 14),
            _sectionBanking(),
            const SizedBox(height: 14),
            _sectionMyOrganisations(),
          ])),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _sectionChangePassword()),
          if (_canCreateOrg) ...[
            const SizedBox(width: 14),
            Expanded(child: _sectionCreateOrg()),
          ],
        ]),
      ]),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _sectionPersonalInfo(),
        const SizedBox(height: 14),
        _sectionOrgLogo(),
        const SizedBox(height: 14),
        _sectionOrgDetails(),
        const SizedBox(height: 14),
        _sectionBanking(),
        const SizedBox(height: 14),
        _sectionChangePassword(),
        const SizedBox(height: 14),
        _sectionMyOrganisations(),
        if (_canCreateOrg) ...[
          const SizedBox(height: 14),
          _sectionCreateOrg(),
        ],
        const SizedBox(height: 30),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // SECTION: Organisation Logo
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _sectionOrgLogo() {
    final hasPending = _pendingLogoBytes != null || _pendingLogoFile != null;
    final hasLogo    = _orgLogoUrl != null && _orgLogoUrl!.isNotEmpty;
    final fullUrl    = _fullLogoUrl(_orgLogoUrl);

    return _sectionCard(
      icon:      Icons.image_outlined,
      iconColor: _orange,
      title:     'Organisation Logo',
      subtitle:  'Used in PDFs, invoices, quotes & emails',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Current / Preview logo ──────────────────────────────────────────
          Center(
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 340, maxHeight: 160),
              decoration: BoxDecoration(
                color: _pageBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasPending ? _blue : const Color(0xFFDDE3EE),
                  width: hasPending ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: _buildLogoPreview(hasPending: hasPending, hasLogo: hasLogo, fullUrl: fullUrl),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Info badge ───────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _blue.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _blue.withOpacity(0.15)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 15, color: _blue.withOpacity(0.8)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Recommended: 300×120 px, PNG or JPEG, max 5 MB.\n'
                  'Different logos can be set per organisation.',
                  style: TextStyle(fontSize: 12, color: _textSecondary),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 16),

          // ── Action buttons ───────────────────────────────────────────────────
          if (hasPending) ...[
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _uploadingLogo ? null : _uploadLogo,
                  icon: _uploadingLogo
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _white))
                      : const Icon(Icons.cloud_upload_outlined, size: 17),
                  label: Text(_uploadingLogo ? 'Uploading...' : 'Upload Logo',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:         _blue,
                    foregroundColor:         _white,
                    disabledBackgroundColor: _blue.withOpacity(0.5),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _uploadingLogo ? null : _discardPending,
                icon: const Icon(Icons.close, size: 17),
                label: const Text('Discard', style: TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _textSecondary,
                  side: BorderSide(color: Colors.grey[300]!),
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ]),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pickLogo,
                icon: const Icon(Icons.upload_file_outlined, size: 17),
                label: Text(
                  hasLogo ? 'Change Logo' : 'Choose Logo',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: _white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            if (hasLogo) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _deletingLogo ? null : _deleteLogo,
                  icon: _deletingLogo
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.delete_outline, size: 17),
                  label: Text(_deletingLogo ? 'Removing...' : 'Remove Logo',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: BorderSide(color: _red.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildLogoPreview({
    required bool hasPending,
    required bool hasLogo,
    String? fullUrl,
  }) {
    if (hasPending) {
      if (kIsWeb && _pendingLogoBytes != null) {
        return Image.memory(
          _pendingLogoBytes!,
          fit: BoxFit.contain,
          width: double.infinity,
          height: 160,
        );
      } else if (_pendingLogoFile != null) {
        return Image.file(
          _pendingLogoFile!,
          fit: BoxFit.contain,
          width: double.infinity,
          height: 160,
        );
      }
    }

    if (hasLogo && fullUrl != null) {
      return Image.network(
        fullUrl,
        fit: BoxFit.contain,
        width: double.infinity,
        height: 160,
        errorBuilder: (_, __, ___) => _logoPlaceholder(),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator(color: _blue));
        },
      );
    }

    return _logoPlaceholder();
  }

  Widget _logoPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_outlined, size: 43, color: Colors.grey[400]),
        const SizedBox(height: 8),
        Text(
          'No logo uploaded yet',
          style: TextStyle(fontSize: 14, color: _textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          'Your logo will appear on PDFs & emails',
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
        ),
      ],
    );
  }

// ════════════════════════════════════════════════════════════════════════════
// END OF CHUNK 1
// Continue in chunk 2 from _sectionOrgDetails() onwards
// ════════════════════════════════════════════════════════════════════════════
// ════════════════════════════════════════════════════════════════════════════
// CHUNK 2 of 2 — paste below the last line of Chunk 1
// Starts at _sectionOrgDetails() and ends with the closing } of the class
// ════════════════════════════════════════════════════════════════════════════

  // ── Section: Organisation Details ────────────────────────────────────────────
  Widget _sectionOrgDetails() {
    return _sectionCard(
      icon:      Icons.business_outlined,
      iconColor: const Color(0xFF1E3A5F),
      title:     'Organisation Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loadingOrgProfile)
            const Center(child: CircularProgressIndicator())
          else ...[
            _formField(ctrl: _gstCtrl,      label: 'GST Number',      icon: Icons.receipt_long_outlined),
            const SizedBox(height: 12),
            _formField(ctrl: _orgPhoneCtrl, label: 'Phone',           icon: Icons.phone_outlined,    keyboard: TextInputType.phone),
            const SizedBox(height: 12),
            _formField(ctrl: _whatsappCtrl, label: 'WhatsApp Number', icon: Icons.chat_outlined,     keyboard: TextInputType.phone),
            const SizedBox(height: 12),
            _formField(ctrl: _orgEmailCtrl, label: 'Email',           icon: Icons.email_outlined,    keyboard: TextInputType.emailAddress),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressCtrl,
              maxLines: 3,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                labelText: 'Address',
                labelStyle: const TextStyle(fontSize: 14, color: _textSecondary),
                prefixIcon: const Icon(Icons.location_on_outlined, size: 18, color: _navy),
                filled: true, fillColor: _pageBg,
                contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 1.5)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _savingOrgProfile ? null : _saveOrgProfile,
                icon: _savingOrgProfile
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_savingOrgProfile ? 'Saving...' : 'Save Organisation Details'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Section: Personal Info ────────────────────────────────────────────────────
  Widget _sectionPersonalInfo() {
    return _sectionCard(
      icon:      Icons.person_outline_rounded,
      iconColor: _blue,
      title:     'Personal Information',
      child: Form(
        key: _profileFormKey,
        child: Column(children: [
          _formField(
            ctrl: _nameCtrl, label: 'Full Name',
            icon: Icons.person_outline_rounded,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
          ),
          const SizedBox(height: 14),
          _formField(
            ctrl: _phoneCtrl, label: 'Phone Number',
            icon: Icons.phone_outlined, keyboard: TextInputType.phone,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone is required' : null,
          ),
          const SizedBox(height: 14),
          _formField(
            ctrl: _emailCtrl, label: 'Email Address',
            icon: Icons.email_outlined, keyboard: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _savingProfile ? null : _saveProfile,
              icon: _savingProfile
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _white))
                  : const Icon(Icons.save_outlined, size: 17),
              label: Text(_savingProfile ? 'Saving...' : 'Save Changes',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor:         _blue,
                foregroundColor:         _white,
                disabledBackgroundColor: _blue.withOpacity(0.5),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Section: Change Password ──────────────────────────────────────────────────
  Widget _sectionChangePassword() {
    return _sectionCard(
      icon:      Icons.lock_outline_rounded,
      iconColor: _purple,
      title:     'Change Password',
      child: Form(
        key: _pwFormKey,
        child: Column(children: [
          _pwField(
            ctrl: _currPwCtrl, label: 'Current Password',
            obscure: _obscureCurr,
            onToggle: () => setState(() => _obscureCurr = !_obscureCurr),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          _pwField(
            ctrl: _newPwCtrl, label: 'New Password',
            obscure: _obscureNew,
            onToggle: () => setState(() => _obscureNew = !_obscureNew),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (v.length < 6) return 'Min 6 characters';
              return null;
            },
          ),
          const SizedBox(height: 14),
          _pwField(
            ctrl: _confirmPwCtrl, label: 'Confirm New Password',
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
            validator: (v) => v != _newPwCtrl.text ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _savingPw ? null : _changePassword,
              icon: _savingPw
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _white))
                  : const Icon(Icons.lock_reset_rounded, size: 17),
              label: Text(_savingPw ? 'Updating...' : 'Update Password',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor:         _purple,
                foregroundColor:         _white,
                disabledBackgroundColor: _purple.withOpacity(0.5),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Section: My Organisations ─────────────────────────────────────────────────
  Widget _sectionMyOrganisations() {
    return _sectionCard(
      icon:      Icons.business_rounded,
      iconColor: _green,
      title:     'My Organisations',
      subtitle:  '${_organizations.length} organisation${_organizations.length != 1 ? 's' : ''}',
      child: Column(
        children: _organizations.map((org) {
          final orgId    = org['orgId']?.toString()   ?? '';
          final orgName  = org['orgName']?.toString() ?? '';
          final role     = org['role']?.toString()    ?? '';
          final logoUrl  = org['logoUrl']?.toString();
          final isCurrent = orgId == _orgId;

          Color roleColor;
          switch (role) {
            case 'owner':      roleColor = _blue;   break;
            case 'admin':      roleColor = _purple; break;
            case 'accountant': roleColor = _green;  break;
            default:           roleColor = _orange;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isCurrent ? _blue.withOpacity(0.05) : _pageBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrent ? _blue : const Color(0xFFDDE3EE),
                width: isCurrent ? 1.5 : 1,
              ),
            ),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: isCurrent ? _blue : Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: (logoUrl != null && logoUrl.isNotEmpty)
                      ? Image.network(
                          _fullLogoUrl(logoUrl) ?? '',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.business_rounded,
                            color: isCurrent ? _white : Colors.grey[600],
                            size: 20,
                          ),
                        )
                      : Icon(
                          Icons.business_rounded,
                          color: isCurrent ? _white : Colors.grey[600],
                          size: 20,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(orgName,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: isCurrent ? _blue : _navyDark)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: roleColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(role.toUpperCase(),
                        style: TextStyle(
                            color: roleColor, fontSize: 11,
                            fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                ]),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Active',
                      style: TextStyle(color: _blue, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ]),
          );
        }).toList(),
      ),
    );
  }

  // ── Section: Create Another Org ───────────────────────────────────────────────
  Widget _sectionCreateOrg() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_navy.withOpacity(0.06), _blue.withOpacity(0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _navy.withOpacity(0.15)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_navy, _blue]),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: _navy.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: const Icon(Icons.add_business_rounded, color: _white, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Create Another Organisation',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navyDark)),
                SizedBox(height: 2),
                Text('Manage multiple businesses from one account',
                    style: TextStyle(fontSize: 13, color: _textSecondary)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          ...[
            'Separate books for each organisation',
            'Upload a different logo per organisation',
            'Switch instantly from the sidebar',
          ].map((point) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Container(width: 5, height: 5,
                  decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(point, style: const TextStyle(fontSize: 13, color: _textSecondary)),
            ]),
          )),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showCreateOrgDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create Organisation',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: _white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────────
  Widget _sectionCard({
    required IconData icon,
    required Color    iconColor,
    required String   title,
    String?           subtitle,
    required Widget   child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EEF4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.04),
              borderRadius: const BorderRadius.only(
                topLeft:  Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              border: Border(bottom: BorderSide(color: iconColor.withOpacity(0.12))),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                // ✅ icon color set to _navy
                child: Icon(icon, color: _navy, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navyDark)),
                  if (subtitle != null)
                    Text(subtitle, style: const TextStyle(fontSize: 13, color: _textSecondary)),
                ]),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(20), child: child),
        ],
      ),
    );
  }

  Widget _formField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 14, color: _textSecondary),
        prefixIcon: Icon(icon, size: 18, color: _navy),
        filled: true, fillColor: _pageBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 1.5)),
        errorBorder:   OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.red.shade300)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.red.shade300, width: 1.5)),
      ),
    );
  }

  Widget _pwField({
    required TextEditingController ctrl,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 14, color: _textSecondary),
        prefixIcon: Icon(Icons.lock_outline_rounded, size: 18, color: _navy),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: Colors.grey[400], size: 18),
          onPressed: onToggle,
        ),
        filled: true, fillColor: _pageBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 1.5)),
        errorBorder:   OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.red.shade300)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.red.shade300, width: 1.5)),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // SECTION: Banking Details
  // ══════════════════════════════════════════════════════════════════════════════

  Future<void> _saveBanking() async {
    setState(() => _savingBanking = true);
    try {
      final res = await FinanceAuthService.put('/api/finance/auth/update-org-profile', {
        'bankAccountHolder':   _bankHolderCtrl.text.trim(),
        'bankAccountNumber':   _bankNumberCtrl.text.trim(),
        'bankIfscCode':        _bankIfscCtrl.text.trim(),
        'bankName':            _bankNameCtrl.text.trim(),
        'upiId':               _upiCtrl.text.trim(),
        'otherPaymentOptions': _otherPayCtrl.text.trim(),
      });
      if (res['success'] == true) {
        _showSuccess('Banking details saved');
      } else {
        _showError(res['message'] ?? 'Failed to save banking details');
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _savingBanking = false);
    }
  }

  Future<void> _pickQrCode() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600, imageQuality: 90);
      if (picked == null) return;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        setState(() { _pendingQrBytes = bytes; _pendingQrFile = null; _pendingQrName = picked.name; });
      } else {
        setState(() { _pendingQrFile = File(picked.path); _pendingQrBytes = null; _pendingQrName = picked.name; });
      }
    } catch (e) { _showError('Could not pick image: $e'); }
  }

  Future<void> _uploadQrCode() async {
    if (_pendingQrBytes == null && _pendingQrFile == null) return;
    setState(() => _uploadingQr = true);
    try {
      final res = await FinanceAuthServiceExtra.uploadOrgQr(
        imageFile: _pendingQrFile, imageBytes: _pendingQrBytes, filename: _pendingQrName ?? 'qr.png');
      if (!mounted) return;
      if (res['success'] == true) {
        setState(() { _qrCodePath = res['data']?['qrCodePath']?.toString(); _pendingQrBytes = null; _pendingQrFile = null; _pendingQrName = null; });
        _showSuccess('QR code uploaded');
      } else { _showError(res['message'] ?? 'Upload failed'); }
    } catch (e) { _showError('Error: $e'); } finally { if (mounted) setState(() => _uploadingQr = false); }
  }

  Future<void> _uploadDocument(String label) async {
    if (label.trim().isEmpty) { _showError('Please enter a document label'); return; }
    try {
      final picker = FilePicker.platform;
      final result = await picker.pickFiles(withData: kIsWeb);
      if (result == null) return;
      setState(() => _uploadingDoc = true);
      final res = await FinanceAuthServiceExtra.uploadOrgDocument(
        docFile:  kIsWeb ? null : File(result.files.single.path!),
        docBytes: kIsWeb ? result.files.single.bytes : null,
        filename: result.files.single.name,
        label:    label.trim(),
      );
      if (!mounted) return;
      if (res['success'] == true) {
        final doc = res['data'] as Map<String, dynamic>;
        setState(() => _orgDocuments.add(doc));
        _showSuccess('Document uploaded');
      } else { _showError(res['message'] ?? 'Upload failed'); }
    } catch (e) { _showError('Error: $e'); } finally { if (mounted) setState(() => _uploadingDoc = false); }
  }

  Future<void> _deleteDocument(String docId) async {
    try {
      final res = await FinanceAuthServiceExtra.deleteOrgDocument(docId);
      if (res['success'] == true) {
        setState(() => _orgDocuments.removeWhere((d) => d['_id']?.toString() == docId));
        _showSuccess('Document deleted');
      } else { _showError(res['message'] ?? 'Delete failed'); }
    } catch (e) { _showError('Error: $e'); }
  }

  Widget _sectionBanking() {
    final hasQr = _qrCodePath != null && _qrCodePath!.isNotEmpty;
    final hasPendingQr = _pendingQrBytes != null || _pendingQrFile != null;
    final docLabelCtrl = TextEditingController();

    return _sectionCard(
      icon: Icons.account_balance_outlined,
      iconColor: _blue,
      title: 'Banking & Payment Details',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'These details appear in invoice PDFs and emails as payment instructions.',
          style: TextStyle(fontSize: 13, color: _textSecondary),
        ),
        const SizedBox(height: 16),
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

        // QR Code
        const Text('Payment QR Code',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _navyDark)),
        const SizedBox(height: 8),
        if (hasPendingQr) ...[
          Container(
            height: 120, width: 120,
            decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
            child: kIsWeb && _pendingQrBytes != null
                ? Image.memory(_pendingQrBytes!, fit: BoxFit.contain)
                : _pendingQrFile != null ? Image.file(_pendingQrFile!, fit: BoxFit.contain) : const SizedBox(),
          ),
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton.icon(
              onPressed: _uploadingQr ? null : _uploadQrCode,
              icon: _uploadingQr
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload, size: 16),
              label: Text(_uploadingQr ? 'Uploading...' : 'Upload QR'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _blue, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => setState(() { _pendingQrBytes = null; _pendingQrFile = null; _pendingQrName = null; }),
              child: const Text('Discard'),
            ),
          ]),
        ] else if (hasQr) ...[
          Row(children: [
            const Icon(Icons.check_circle, color: Color(0xFF27AE60), size: 18),
            const SizedBox(width: 6),
            const Text('QR code uploaded', style: TextStyle(fontSize: 14, color: Color(0xFF27AE60))),
            const Spacer(),
            TextButton.icon(onPressed: _pickQrCode, icon: const Icon(Icons.edit, size: 16), label: const Text('Change')),
          ]),
        ] else ...[
          OutlinedButton.icon(
            onPressed: _pickQrCode,
            icon: const Icon(Icons.qr_code_2, size: 18),
            label: const Text('Upload QR Code'),
            style: OutlinedButton.styleFrom(foregroundColor: _blue, side: const BorderSide(color: _blue)),
          ),
        ],
        const SizedBox(height: 16),

        // Save banking button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _savingBanking ? null : _saveBanking,
            icon: _savingBanking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(_savingBanking ? 'Saving...' : 'Save Banking Details'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy, foregroundColor: _white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Documents
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Documents',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _navyDark)),
          TextButton.icon(
            onPressed: _uploadingDoc ? null : () {
              showDialog(context: context, builder: (_) => AlertDialog(
                title: const Text('Add Document'),
                content: TextField(
                  controller: docLabelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Document Label (e.g. GST Certificate)',
                    border: OutlineInputBorder(),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: () { Navigator.pop(context); _uploadDocument(docLabelCtrl.text); },
                    child: const Text('Upload'),
                  ),
                ],
              ));
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Document'),
          ),
        ]),
        if (_orgDocuments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No documents uploaded yet.',
                style: TextStyle(fontSize: 13, color: _textMuted)),
          )
        else
          ...(_orgDocuments.map((doc) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined, color: Color(0xFF2563EB), size: 20),
            title: Text(doc['label']?.toString() ?? 'Document',
                style: const TextStyle(fontSize: 14, color: _textPrimary)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
              onPressed: () => _deleteDocument(doc['_id']?.toString() ?? ''),
            ),
          ))),
      ]),
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 14, color: _textSecondary),
    prefixIcon: Icon(icon, size: 18, color: _navy),
    filled: true, fillColor: _pageBg,
    contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
    border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 1.5)),
  );

  Widget _field(TextEditingController ctrl, String label, IconData icon, {int maxLines = 1}) =>
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 15, color: _textPrimary),
        decoration: _fieldDecoration(label, icon),
      );
}
// ════════════════════════════════════════════════════════════════════════════
// END OF CHUNK 2 — END OF FILE
// ════════════════════════════════════════════════════════════════════════════