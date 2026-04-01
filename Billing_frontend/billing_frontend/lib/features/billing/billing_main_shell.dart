import 'package:flutter/material.dart';
import '../../core/finance_secure_storage.dart';
import '../finance_welcome_screen.dart';
import 'pages/home_billing.dart';
import 'pages/items_billing.dart';
import 'pages/invoices_list_page.dart';
import 'pages/payments_received_page.dart';
import 'pages/customers_list_page.dart';
import 'pages/recurring_invoices_list_page.dart';
import 'pages/new_recurring_invoice.dart';
import 'pages/banking_page.dart';
import 'pages/new_expenses.dart';
import 'pages/expenses_list_page.dart';
import 'pages/vendors_list_page.dart';
import 'pages/quotes_list_page.dart';
import 'pages/sales_orders_list_page.dart';
import 'pages/recurring_expenses_list_page.dart';
import 'pages/delivery_challans_list_page.dart';
import 'pages/credit_notes_list_page.dart';
import 'pages/purchase_orders_list_page.dart';
import 'pages/bill_list_page.dart';
import 'pages/recurring_bills_list_page.dart';
import 'pages/payment_made_list_page.dart';
import 'pages/vendor_credits_list_page.dart';
import 'pages/manual_journals_list_page.dart';
import 'rate_card_list.dart';
import 'pages/chart_of_accounts_list_page.dart';
import 'pages/budgets_list_page.dart';
import '../erp/erp_users_management_screen.dart';
import '../../data/services/finance_auth_service.dart';
import '../../core/services/api_service.dart';
import 'pages/finance_profile_page.dart';
import 'pages/currency_adjustments_list_page.dart';
import 'pages/projects_list_page.dart';
import 'pages/timesheets_list_page.dart';
import 'pages/reports_list_page.dart';

// TMS Screens
import '../TMS/raise_ticket.dart';
import '../TMS/my_tickets.dart';
import '../TMS/all_tickets.dart';
import '../TMS/closed_tickets.dart';

// ─── COLORS ───────────────────────────────────────────────────────────────────
const _kNavyDark   = Color(0xFF0F172A);
const _kNavy       = Color(0xFF1E3A5F);
const _kBlueAccent = Color(0xFF2563EB);
const _kWhite      = Color(0xFFFFFFFF);
const _kPageBg     = Color(0xFFF8FAFC);
// ──────────────────────────────────────────────────────────────────────────────

// ─── PERMISSION → SIDEBAR ROUTE MAP ──────────────────────────────────────────
// Maps each permission key from billing_users.permissions to sidebar routes.
// If a user has can_access:true for a key, the corresponding route is shown.
const Map<String, List<String>> _kPermissionRouteMap = {
  // Items
  'items':              ['items'],
  // Sales sub-items
  'invoices':           ['sales/invoices'],
  'credit_notes':       ['sales/credit_notes'],
  'payments_received':  ['sales/payments_received'],
  'quotes':             ['sales/quotes'],
  'sales_orders':       ['sales/orders'],
  'delivery_challans':  ['sales/delivery_challans'],
  'customers':          ['sales/customers'],
  'recurring_invoices': ['sales/recurring_invoices'],
  // Purchases sub-items
  'expenses':           ['purchases/expenses'],
  'bills':              ['purchases/bills'],
  'purchase_orders':    ['purchases/orders'],
  'vendor_credits':     ['purchases/vendor_credits'],
  'payments_made':      ['purchases/payments_made'],
  'vendors':            ['purchases/vendors'],
  'recurring_expenses': ['purchases/recurring_expenses'],
  'recurring_bills':    ['purchases/recurring_bills'],
  // Accountant
  'manual_journals':        ['accountant/manual_journals'],
  'currency_adjustments':   ['accountant/currency_adjustments'],
  'chart_of_accounts':      ['accountant/chart_of_accounts'],
  'budgets':                ['accountant/budgets'],
  // Top-level
  'banking':            ['banking'],
  'reports':            ['reports'],
  'rate_cards':         ['rate_cards'],
  'role_access_control':['role_access_control'],
  // Time Tracking
  'projects':           ['time_tracking/projects'],
  'timesheets':         ['time_tracking/timesheet'],
  // TMS — always visible to all users
  'raise_ticket':       ['tms/raise_ticket'],
  'my_tickets':         ['tms/my_tickets'],
  'all_tickets':        ['tms/all_tickets'],
  'closed_tickets':     ['tms/closed_tickets'],
};
// ──────────────────────────────────────────────────────────────────────────────

class BillingMainShell extends StatefulWidget {
  const BillingMainShell({Key? key}) : super(key: key);

  @override
  State<BillingMainShell> createState() => _BillingMainShellState();
}

class _BillingMainShellState extends State<BillingMainShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int    _selectedIndex    = 0;
  bool   _isSidebarExpanded = true;
  String _currentPageTitle  = 'Dashboard';

  // ── Session data loaded from FinanceSecureStorage ───────────────────────────
  String                      _userRole      = '';
  String                      _name          = '';
  String                      _orgId         = '';
  String                      _orgName       = '';
  String?                     _orgLogoUrl; 
  Map<String, dynamic>        _permissions   = {};
  List<Map<String, dynamic>>  _organizations = [];
  bool                        _sessionLoaded = false;

  // Track which sections are expanded
  final Map<String, bool> _expandedSections = {
    'tms':          false,
    'accountant':   false,
    'time_tracking':false,
    'purchases':    false,
    'sales':        false,
  };

  // ── FULL menu definition (all items) ────────────────────────────────────────
  final List<NavigationItem> _allMenuItems = [
    NavigationItem(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: 'Dashboard',
      route: 'home',
    ),
    NavigationItem(
      icon: Icons.confirmation_number_outlined,
      selectedIcon: Icons.confirmation_number,
      label: 'TMS',
      route: 'tms',
      isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Raise a Ticket',  route: 'tms/raise_ticket',  icon: Icons.add_circle_outline),
        SubNavigationItem(label: 'My Tickets',       route: 'tms/my_tickets',    icon: Icons.assignment_outlined),
        SubNavigationItem(label: 'All Tickets',      route: 'tms/all_tickets',   icon: Icons.list_alt_outlined),
        SubNavigationItem(label: 'Closed Tickets',   route: 'tms/closed_tickets',icon: Icons.archive_outlined),
      ],
    ),
    NavigationItem(
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
      label: 'Items',
      route: 'items',
    ),
    NavigationItem(
      icon: Icons.shopping_cart_outlined,
      selectedIcon: Icons.shopping_cart,
      label: 'Sales',
      route: 'sales',
      isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Customers',           route: 'sales/customers',         icon: Icons.people_outline),
        SubNavigationItem(label: 'Invoices',            route: 'sales/invoices',          icon: Icons.receipt_long_outlined),
        SubNavigationItem(label: 'Recurring Invoices',  route: 'sales/recurring_invoices',icon: Icons.repeat_outlined),
        SubNavigationItem(label: 'Payments Received',   route: 'sales/payments_received', icon: Icons.payment_outlined),
        SubNavigationItem(label: 'Credit Notes',        route: 'sales/credit_notes',      icon: Icons.note_outlined),
        SubNavigationItem(label: 'Quotes',              route: 'sales/quotes',            icon: Icons.request_quote_outlined),
        SubNavigationItem(label: 'Sales Orders',        route: 'sales/orders',            icon: Icons.shopping_bag_outlined),
        SubNavigationItem(label: 'Delivery Challans',   route: 'sales/delivery_challans', icon: Icons.local_shipping_outlined),
      ],
    ),
    NavigationItem(
      icon: Icons.shopping_bag_outlined,
      selectedIcon: Icons.shopping_bag,
      label: 'Purchases',
      route: 'purchases',
      isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Vendors',             route: 'purchases/vendors',           icon: Icons.store_outlined),
        SubNavigationItem(label: 'Expenses',            route: 'purchases/expenses',          icon: Icons.money_off_outlined),
        SubNavigationItem(label: 'Recurring Expenses',  route: 'purchases/recurring_expenses',icon: Icons.repeat_outlined),
        SubNavigationItem(label: 'Purchase Orders',     route: 'purchases/orders',            icon: Icons.shopping_cart_outlined),
        SubNavigationItem(label: 'Bills',               route: 'purchases/bills',             icon: Icons.description_outlined),
        SubNavigationItem(label: 'Recurring Bills',     route: 'purchases/recurring_bills',   icon: Icons.repeat_outlined),
        SubNavigationItem(label: 'Payments Made',       route: 'purchases/payments_made',     icon: Icons.payment_outlined),
        SubNavigationItem(label: 'Vendor Credits',      route: 'purchases/vendor_credits',    icon: Icons.credit_card_outlined),
      ],
    ),
    NavigationItem(
      icon: Icons.access_time_outlined,
      selectedIcon: Icons.access_time,
      label: 'Time Tracking',
      route: 'time_tracking',
      isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Projects',  route: 'time_tracking/projects',  icon: Icons.folder_outlined),
        SubNavigationItem(label: 'Timesheet', route: 'time_tracking/timesheet', icon: Icons.schedule_outlined),
      ],
    ),
    NavigationItem(
      icon: Icons.credit_card_outlined,
      selectedIcon: Icons.credit_card,
      label: 'Rate Cards',
      route: 'rate_cards',
    ),
    NavigationItem(
      icon: Icons.account_balance_outlined,
      selectedIcon: Icons.account_balance,
      label: 'Banking',
      route: 'banking',
    ),
    NavigationItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: 'Accountant',
      route: 'accountant',
      isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Manual Journals',      route: 'accountant/manual_journals',      icon: Icons.book_outlined),
        SubNavigationItem(label: 'Currency Adjustments', route: 'accountant/currency_adjustments', icon: Icons.currency_exchange_outlined),
        SubNavigationItem(label: 'Chart of Accounts',    route: 'accountant/chart_of_accounts',    icon: Icons.account_tree_outlined),
        SubNavigationItem(label: 'Budgets',              route: 'accountant/budgets',              icon: Icons.account_balance_wallet_outlined),
      ],
    ),
    NavigationItem(
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      label: 'Reports',
      route: 'reports',
    ),
    // NavigationItem(
    //   icon: Icons.folder_outlined,
    //   selectedIcon: Icons.folder,
    //   label: 'Documents',
    //   route: 'documents',
    // ),
    NavigationItem(
      icon: Icons.admin_panel_settings_outlined,
      selectedIcon: Icons.admin_panel_settings,
      label: 'Role Access Control',
      route: 'role_access_control',
    ),
    NavigationItem(
      icon: Icons.person_pin_outlined,
      selectedIcon: Icons.person_pin,
      label: 'My Profile',
      route: 'my_profile',
    ),
  ];

  // ── Filtered menu items (computed after session loads) ──────────────────────
  List<NavigationItem> get _visibleMenuItems {
    // Owner / Admin see everything
    final isAdmin = _userRole == 'owner' || _userRole == 'admin';
    if (isAdmin) return _allMenuItems;

    // Dashboard is always visible
    // TMS is always visible to all users
    // Everything else is filtered by permissions
    return _allMenuItems
        .map((item) {
          // Dashboard — always show
          if (item.route == 'home') return item;

          // TMS — always show (all sub-items)
          if (item.route == 'tms') return item;

          // My Profile — always visible to all users
          if (item.route == 'my_profile') return item;

          // Non-expandable top-level items
          if (!item.isExpandable) {
            if (_canAccessRoute(item.route)) return item;
            return null;
          }

          // Expandable sections — filter sub-items
          final visibleSubs = (item.subItems ?? [])
              .where((sub) => _canAccessRoute(sub.route))
              .toList();

          if (visibleSubs.isEmpty) return null;

          return NavigationItem(
            icon:         item.icon,
            selectedIcon: item.selectedIcon,
            label:        item.label,
            route:        item.route,
            isExpandable: item.isExpandable,
            subItems:     visibleSubs,
          );
        })
        .whereType<NavigationItem>()
        .toList();
  }

  /// Returns true if the user has can_access:true for the given sidebar route.
  bool _canAccessRoute(String route) {
    for (final entry in _kPermissionRouteMap.entries) {
      if (entry.value.contains(route)) {
        final perm = _permissions[entry.key];
        if (perm is Map) {
          final ca = perm['can_access'];
          if (ca == true || ca == 1 || ca == 'true') return true;
        }
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  // ── Load session data from secure storage ───────────────────────────────────
  Future<void> _loadSession() async {
    final role       = await FinanceSecureStorage.getRole()       ?? '';
    final name       = await FinanceSecureStorage.getName()       ?? '';
    final orgId      = await FinanceSecureStorage.getOrgId()      ?? '';
    final orgName    = await FinanceSecureStorage.getOrgName()    ?? '';
    final orgLogoUrl = await FinanceSecureStorage.getOrgLogoUrl();     // ✅ NEW
    final perms      = await FinanceSecureStorage.getPermissions();
    final orgs       = await FinanceSecureStorage.getOrganizations();
 
    if (mounted) {
      setState(() {
        _userRole      = role;
        _name          = name;
        _orgId         = orgId;
        _orgName       = orgName;
        _orgLogoUrl    = orgLogoUrl;   // ✅ NEW
        _permissions   = perms;
        _organizations = orgs;
        _sessionLoaded = true;
      });
      debugPrint('✅ BillingMainShell session loaded');
      debugPrint('   role: $_userRole');
      debugPrint('   orgId: $_orgId  orgName: $_orgName');
      debugPrint('   orgLogoUrl: ${_orgLogoUrl ?? 'none'}');
      debugPrint('   permissions: ${_permissions.keys.toList()}');
      debugPrint('   organizations count: ${_organizations.length}');
    }
  }

  // ── Org switcher ─────────────────────────────────────────────────────────────
void _showOrgSwitcher(BuildContext context) {
  if (_organizations.length <= 1) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You only belong to one organization.'),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }
 
  // CENTER OVERLAY CARD (not bottom sheet)
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.5),
    barrierDismissible: true,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: _OrgSwitcherCard(
        organizations:   _organizations,
        currentOrgId:    _orgId,
        onOrgSelected:   _switchOrg,
      ),
    ),
  );
}

Future<void> _switchOrg(String orgId, String orgName) async {
    if (orgId == _orgId) {
      Navigator.pop(context); // close switcher
      return;
    }
 
    // ── Step 1: close org switcher dialog ──
    Navigator.pop(context);

    // ── Step 1b: pop ALL pushed pages back to the shell root ──
    // This ensures no stale list pages (invoices, customers, etc.) remain
    // on the navigator stack showing org1 data after the switch.
    Navigator.of(context).popUntil((route) => route.isFirst);
 
    // ── Step 2: show full-screen loading ──
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF2563EB)),
                const SizedBox(height: 16),
                Text(
                  'Switching to $orgName...',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1E3A5F),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
 
    try {
      // ── Step 3: call backend — get new token for new org ──
      final result = await FinanceAuthService.selectOrg(orgId);
 
      if (!mounted) return;
 
      if (result['success'] == true) {

        // ── Step 4a: CRITICAL — bust the ApiService token cache immediately ──
        // Without this, all API calls for the next 50 min use the old org's token.
        ApiService().clearTokenCache();

        // ── Step 4: CRITICAL — reset ALL page state BEFORE reloading session ──
        // This forces every page widget to unmount and rebuild from scratch.
        if (mounted) {
          setState(() {
            _selectedIndex    = -1;   // show loading spinner in content area
            _currentPageTitle = 'Dashboard';
            // Collapse all sidebar sections so no stale expanded state
            _expandedSections.updateAll((key, _) => false);
            // Clear org-scoped vars immediately so no old data leaks into UI
            _orgId         = orgId;
            _orgName       = orgName;
            _orgLogoUrl    = null;     // ✅ clear logo until reloaded
            _permissions   = {};
          });
        }
 
        // ── Step 5: reload session — new token + orgId now in storage ──
        await _loadSession();
 
        // ── Step 6: wait a frame so widget tree rebuilds cleanly ──
        await Future.delayed(const Duration(milliseconds: 300));
 
        // ── Step 7: dismiss loading dialog ──
        if (mounted) Navigator.pop(context);
 
        // ── Step 8: show Dashboard with new org's ValueKey ──
        if (mounted) {
          setState(() {
            _selectedIndex = 0;
          });
        }
 
        // ── Step 9: success snackbar ──
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text('Switched to $orgName'),
              ]),
              backgroundColor: const Color(0xFF2563EB),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // ── Failure ──
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to switch organisation'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error switching organisation: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }
  // ── Page content ─────────────────────────────────────────────────────────────
Widget _getSelectedPage() {
  if (_selectedIndex == -1) {
    return Container(
      color: _kPageBg,
      child: const Center(
        child: CircularProgressIndicator(color: Color(0xFF2563EB)),
      ),
    );
  }

  switch (_selectedIndex) {
    case 0:
      return HomeBilling(key: ValueKey('home_$_orgId'));
    case 1:
      return _buildPlaceholderPage('TMS');
    case 2:
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() { _selectedIndex = 0; _currentPageTitle = 'Dashboard'; });
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ItemsBilling()),
          ).then((_) { if (mounted) setState(() { _selectedIndex = 0; _currentPageTitle = 'Dashboard'; }); });
        }
      });
      return HomeBilling(key: ValueKey('home_$_orgId'));
    case 3:
      return _buildPlaceholderPage('Sales');
    case 4:
      return _buildPlaceholderPage('Purchases');
    case 5:
      return _buildPlaceholderPage('Time Tracking');
    case 6:
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() { _selectedIndex = 0; _currentPageTitle = 'Dashboard'; });
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => RateCardListScreen()),
          ).then((_) { if (mounted) setState(() { _selectedIndex = 0; _currentPageTitle = 'Dashboard'; }); });
        }
      });
      return HomeBilling(key: ValueKey('home_$_orgId'));
    case 7:
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() { _selectedIndex = 0; _currentPageTitle = 'Dashboard'; });
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => BankingDashboardPage()),
          ).then((_) { if (mounted) setState(() { _selectedIndex = 0; _currentPageTitle = 'Dashboard'; }); });
        }
      });
      return HomeBilling(key: ValueKey('home_$_orgId'));
    case 8:
      return _buildPlaceholderPage('Accountant');
    case 9:
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() { _selectedIndex = 0; _currentPageTitle = 'Dashboard'; });
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ReportsListPage()),
          ).then((_) { if (mounted) setState(() { _selectedIndex = 0; _currentPageTitle = 'Dashboard'; }); });
        }
      });
      return HomeBilling(key: ValueKey('home_$_orgId'));
    case 10:
      return _buildPlaceholderPage('Documents');
    case 11:
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() { _selectedIndex = 0; _currentPageTitle = 'Dashboard'; });
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const FinanceERPUsersScreen()),
          ).then((_) { if (mounted) setState(() { _selectedIndex = 0; _currentPageTitle = 'Dashboard'; }); });
        }
      });
      return HomeBilling(key: ValueKey('home_$_orgId'));
    case 12:
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() { _selectedIndex = 0; _currentPageTitle = 'Dashboard'; });
          _openProfile();
        }
      });
      return HomeBilling(key: ValueKey('home_$_orgId'));
    default:
      return HomeBilling(key: ValueKey('home_$_orgId'));
  }
}

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FinanceProfilePage()),
    ).then((_) => _loadSession());
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(children: [
          Icon(Icons.logout, color: Color(0xFF1E3A5F)),
          SizedBox(width: 10),
          Text('Sign Out'),
        ]),
        content: const Text('Are you sure you want to sign out of the Finance Module?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await FinanceSecureStorage.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const FinanceWelcomeScreen()),
      (route) => false,
    );
  }

  Widget _buildPlaceholderPage(String title) {
    return Container(
      color: _kPageBg,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.construction, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('$title Page', style: TextStyle(fontSize: 24, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text('Coming Soon', style: TextStyle(fontSize: 16, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_sessionLoaded) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF2563EB)),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile    = screenWidth < 1024;

    return Scaffold(
      key: _scaffoldKey,
      drawer: isMobile ? _buildDrawer() : null,
      body: Row(
        children: [
          // ── Sidebar (desktop) ────────────────────────────────────────────────
          if (!isMobile)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _isSidebarExpanded ? 240 : 70,
              child: _buildSidebarContent(isDrawer: false),
            ),

          // ── Main content ─────────────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                _buildTopBar(isMobile),
                Expanded(
                  child: Container(
                    color: _kPageBg,
                    child: _getSelectedPage(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────────
  Widget _buildTopBar(bool isMobile) {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [_kNavyDark, _kNavy],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu, color: _kWhite),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              tooltip: 'Open Menu',
            ),
          const SizedBox(width: 8),
          // Page title
          Expanded(
            child: Text(
              _currentPageTitle,
              style: const TextStyle(
                color: _kWhite,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // ── Org switcher chip (top bar) ────────────────────────────────────
          if (_orgName.isNotEmpty)
            GestureDetector(
              onTap: () => _showOrgSwitcher(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.business, color: _kWhite, size: 14),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        _orgName,
                        style: const TextStyle(
                          color: _kWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_organizations.length > 1) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.swap_horiz, color: _kWhite, size: 14),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _openProfile,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: _kBlueAccent,
              child: Text(
                _name.isNotEmpty ? _name[0].toUpperCase() : 'U',
                style: const TextStyle(
                    color: _kWhite, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.logout, color: _kWhite),
            onPressed: _logout,
            tooltip: 'Sign Out',
          ),
        ],
      ),
    );
  }

  // ── Sidebar content (shared between desktop sidebar and drawer) ───────────────
  Widget _buildSidebarContent({required bool isDrawer}) {
    final showFull = isDrawer || _isSidebarExpanded;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kNavyDark, _kNavy],
        ),
      ),
      child: Column(
        children: [
          // ── Header with org switcher ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Finance Module title row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _kBlueAccent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: _kWhite,
                        size: 20,
                      ),
                    ),
                    if (showFull) ...[
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Finance Module',
                          style: TextStyle(
                            color: _kWhite,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],

                  ],
                ),

                // ── Org switcher row (sidebar) ──────────────────────────────
                if (showFull && _orgName.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _showOrgSwitcher(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.business,
                              color: _kWhite, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _orgName,
                                  style: const TextStyle(
                                    color: _kWhite,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  _userRole.toUpperCase(),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.55),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_organizations.length > 1)
                            const Icon(Icons.unfold_more,
                                color: _kWhite, size: 14),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Menu items ──────────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: _buildMenuWidgets(showFull: showFull, isDrawer: isDrawer),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build menu widgets from filtered items ───────────────────────────────────
  List<Widget> _buildMenuWidgets({required bool showFull, required bool isDrawer}) {
    final items   = _visibleMenuItems;
    final widgets = <Widget>[];

    for (int i = 0; i < items.length; i++) {
      final item       = items[i];
      final isSelected = _selectedIndex == i;
      final isExpanded = _expandedSections[item.route] ?? false;

      widgets.add(
        _SidebarItem(
          item:       item,
          index:      i,
          isSelected: isSelected,
          isExpanded: isExpanded,
          showFull:   showFull,
          onTap: () {
            if (item.isExpandable) {
              setState(() {
                _expandedSections[item.route] = !isExpanded;
              });
            } else {
              // Route-based navigation for special top-level pages
              if (item.route == 'role_access_control') {
                if (isDrawer) Navigator.pop(context);
                _navigateToSubPage(item.route, item.label);
              } else {
                setState(() {
                  _selectedIndex    = i;
                  _currentPageTitle = item.label;
                });
                if (isDrawer) Navigator.pop(context);
              }
            }
          },
        ),
      );

      // Sub-items
      if (item.isExpandable && isExpanded && showFull) {
        for (final sub in item.subItems ?? []) {
          widgets.add(
            _SubSidebarItem(
              subItem: sub,
              onTap: () {
                setState(() => _currentPageTitle = sub.label);
                if (isDrawer) Navigator.pop(context);
                _navigateToSubPage(sub.route, sub.label);
              },
            ),
          );
        }
      }
    }
    return widgets;
  }

  // ── Sub-page navigation ──────────────────────────────────────────────────────
  void _navigateToSubPage(String route, String label) {
    void _push(Widget page) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => page))
          .then((_) {
        if (mounted) {
          setState(() {
            _selectedIndex    = 0;
            _currentPageTitle = 'Dashboard';
          });
        }
      });
    }

    switch (route) {
      case 'tms/raise_ticket':
        _push(const RaiseTicketScreen());
        break;
      case 'tms/my_tickets':
        _push(const MyTicketsScreen());
        break;
      case 'tms/all_tickets':
        _push(const AllTicketsScreen());
        break;
      case 'tms/closed_tickets':
        _push(const ClosedTicketsScreen());
        break;
      case 'sales/customers':
        _push(const CustomersListPage());
        break;
      case 'sales/invoices':
        _push(const InvoicesListPage());
        break;
      case 'sales/recurring_invoices':
        _push(const RecurringInvoicesListPage());
        break;
      case 'sales/payments_received':
        _push(const PaymentsReceivedPage());
        break;
      case 'sales/credit_notes':
        _push(const CreditNotesListPage());
        break;
      case 'sales/quotes':
        _push(const QuotesListPage());
        break;
      case 'sales/orders':
        _push(const SalesOrdersListPage());
        break;
      case 'sales/delivery_challans':
        _push(const DeliveryChallansListPage());
        break;
      case 'purchases/vendors':
        _push(const VendorsListPage());
        break;
      case 'purchases/expenses':
        _push(const ExpensesListPage());
        break;
      case 'purchases/recurring_expenses':
        _push(const RecurringExpensesListPage());
        break;
      case 'purchases/orders':
        _push(const PurchaseOrdersListPage());
        break;
      case 'purchases/bills':
        _push(const BillListPage());
        break;
      case 'purchases/recurring_bills':
        _push(RecurringBillsListPage());
        break;
      case 'purchases/payments_made':
        _push(const PaymentMadeListPage());
        break;
      case 'purchases/vendor_credits':
        _push(const VendorCreditsListPage());
        break;
      case 'accountant/manual_journals':
        _push(const ManualJournalsListPage());
        break;
      case 'accountant/currency_adjustments':
        _push(const CurrencyAdjustmentsListPage());
        break;
      case 'accountant/chart_of_accounts':
        _push(const ChartOfAccountsListPage());
        break;
      case 'accountant/budgets':
        _push(const BudgetsListPage());
        break;
      case 'time_tracking/projects':
        _push(const ProjectsListPage());
        break;
      case 'time_tracking/timesheet':
        _push(const TimesheetsListPage());
        break;
      case 'role_access_control':
        _push(const FinanceERPUsersScreen());
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label — Coming Soon'),
            duration: const Duration(seconds: 1),
            backgroundColor: _kBlueAccent,
          ),
        );
    }
  }

  // ── Drawer (mobile) ──────────────────────────────────────────────────────────
  Widget _buildDrawer() {
    return Drawer(child: _buildSidebarContent(isDrawer: true));
  }
}

// ─── ORG SWITCHER BOTTOM SHEET ────────────────────────────────────────────────
class _OrgSwitcherCard extends StatelessWidget {
  final List<Map<String, dynamic>> organizations;
  final String currentOrgId;
  final Future<void> Function(String orgId, String orgName) onOrgSelected;
 
  const _OrgSwitcherCard({
    required this.organizations,
    required this.currentOrgId,
    required this.onOrgSelected,
  });
 
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E3A5F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.swap_horiz_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Switch Organisation',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text('Select the organisation to work in',
                          style: TextStyle(
                              color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
 
          // ── Org list ────────────────────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: organizations.map((org) {
                  final orgId   = org['orgId']?.toString()   ?? '';
                  final orgName = org['orgName']?.toString() ?? '';
                  final role    = org['role']?.toString()    ?? '';
                  final isCurrent = orgId == currentOrgId;
 
                  return GestureDetector(
                    onTap: () => onOrgSelected(orgId, orgName),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? const Color(0xFF2563EB).withOpacity(0.06)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isCurrent
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFE2E8F0),
                          width: isCurrent ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Org avatar
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                orgName.isNotEmpty
                                    ? orgName[0].toUpperCase()
                                    : 'O',
                                style: TextStyle(
                                  color: isCurrent
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  orgName,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isCurrent
                                        ? const Color(0xFF2563EB)
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? const Color(0xFF2563EB).withOpacity(0.1)
                                        : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    role.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: isCurrent
                                          ? const Color(0xFF2563EB)
                                          : const Color(0xFF64748B),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_rounded,
                                      color: Color(0xFF2563EB), size: 14),
                                  SizedBox(width: 4),
                                  Text('Active',
                                      style: TextStyle(
                                          color: Color(0xFF2563EB),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            )
                          else
                            const Icon(Icons.chevron_right_rounded,
                                color: Color(0xFFCBD5E1), size: 20),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── SIDEBAR ITEM WIDGET ──────────────────────────────────────────────────────
class _SidebarItem extends StatelessWidget {
  final NavigationItem item;
  final int            index;
  final bool           isSelected;
  final bool           isExpanded;
  final bool           showFull;
  final VoidCallback   onTap;

  const _SidebarItem({
    required this.item,
    required this.index,
    required this.isSelected,
    required this.isExpanded,
    required this.showFull,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? _kBlueAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Icon(
              isSelected ? item.selectedIcon : item.icon,
              color: _kWhite,
              size: 22,
            ),
            if (showFull) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: _kWhite,
                    fontSize: 15,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              if (item.isExpandable)
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: _kWhite,
                  size: 18,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── SUB SIDEBAR ITEM WIDGET ──────────────────────────────────────────────────
class _SubSidebarItem extends StatelessWidget {
  final SubNavigationItem subItem;
  final VoidCallback      onTap;

  const _SubSidebarItem({required this.subItem, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 22, right: 10, top: 1, bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            if (subItem.icon != null)
              Icon(subItem.icon, color: _kWhite, size: 17)
            else
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: _kWhite,
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                subItem.label,
                style: const TextStyle(
                  color: _kWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── DATA MODELS ─────────────────────────────────────────────────────────────
class NavigationItem {
  final IconData           icon;
  final IconData           selectedIcon;
  final String             label;
  final String             route;
  final bool               isExpandable;
  final List<SubNavigationItem>? subItems;

  NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
    this.isExpandable = false,
    this.subItems,
  });
}

class SubNavigationItem {
  final String   label;
  final String   route;
  final IconData? icon;

  SubNavigationItem({
    required this.label,
    required this.route,
    this.icon,
  });
}