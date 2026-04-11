import 'package:flutter/material.dart';
import '../../core/finance_secure_storage.dart';
import '../../app/config/api_config.dart';
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
import 'pages/fixed_assets_list_page.dart';
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
import 'pages/eway_bill_list_page.dart';
import 'pages/payment_links_page.dart';
import 'pages/manual_journals_list_page.dart';
// import 'rate_card_list.dart'; // Rate cards disabled
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
import '../../../core/widgets/global_timer_bar.dart';

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
const Map<String, List<String>> _kPermissionRouteMap = {
  'items':              ['items'],
  'invoices':           ['sales/invoices'],
  'credit_notes':       ['sales/credit_notes'],
  'payments_received':  ['sales/payments_received'],
  'quotes':             ['sales/quotes'],
  'sales_orders':       ['sales/orders'],
  'delivery_challans':  ['sales/delivery_challans'],
  'customers':          ['sales/customers'],
  'recurring_invoices': ['sales/recurring_invoices'],
  'expenses':           ['purchases/expenses'],
  'assets':             ['purchases/assets'],
  'bills':              ['purchases/bills'],
  'purchase_orders':    ['purchases/orders'],
  'vendor_credits':     ['purchases/vendor_credits'],
  'eway_bills':         ['purchases/eway_bills'],
  'payment_links':      ['purchases/payment_links'],
  'payments_made':      ['purchases/payments_made'],
  'vendors':            ['purchases/vendors'],
  'recurring_expenses': ['purchases/recurring_expenses'],
  'recurring_bills':    ['purchases/recurring_bills'],
  'manual_journals':        ['accountant/manual_journals'],
  'currency_adjustments':   ['accountant/currency_adjustments'],
  'chart_of_accounts':      ['accountant/chart_of_accounts'],
  'budgets':                ['accountant/budgets'],
  'banking':            ['banking'],
  'reports':            ['reports'],
  // 'rate_cards':         ['rate_cards'], // Rate cards disabled
  'role_access_control':['role_access_control'],
  'projects':           ['time_tracking/projects'],
  'timesheets':         ['time_tracking/timesheet'],
  'raise_ticket':       ['tms/raise_ticket'],
  'my_tickets':         ['tms/my_tickets'],
  'all_tickets':        ['tms/all_tickets'],
  'closed_tickets':     ['tms/closed_tickets'],
};
// ──────────────────────────────────────────────────────────────────────────────

// ─── QUICK CREATE MENU DATA ───────────────────────────────────────────────────
class _QuickCreateSection {
  final String title;
  final IconData icon;
  final Color color;
  final List<_QuickCreateItem> items;
  const _QuickCreateSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });
}

class _QuickCreateItem {
  final String label;
  final IconData icon;
  final String route;
  final String pageTitle;
  // Permission key — null means always visible (admin check handles it)
  final String? permissionKey;
  const _QuickCreateItem({
    required this.label,
    required this.icon,
    required this.route,
    required this.pageTitle,
    this.permissionKey,
  });
}

const List<_QuickCreateSection> _kQuickCreateSections = [
  _QuickCreateSection(
    title: 'General',
    icon: Icons.settings_outlined,
    color: Color(0xFF64748B),
    items: [
      _QuickCreateItem(
        label: 'Add User',
        icon: Icons.person_add_outlined,
        route: 'role_access_control',
        pageTitle: 'Role Access Control',
        permissionKey: 'role_access_control',
      ),
    ],
  ),
  _QuickCreateSection(
    title: 'Sales',
    icon: Icons.shopping_cart_outlined,
    color: Color(0xFF2563EB),
    items: [
      _QuickCreateItem(label: 'Customer',           icon: Icons.people_outline,         route: 'sales/customers',          pageTitle: 'Customers',           permissionKey: 'customers'),
      _QuickCreateItem(label: 'Invoice',             icon: Icons.receipt_long_outlined,  route: 'sales/invoices',           pageTitle: 'Invoices',            permissionKey: 'invoices'),
      _QuickCreateItem(label: 'Recurring Invoice',   icon: Icons.repeat_outlined,        route: 'sales/recurring_invoices', pageTitle: 'Recurring Invoices',  permissionKey: 'recurring_invoices'),
      _QuickCreateItem(label: 'Payment Received',    icon: Icons.payment_outlined,       route: 'sales/payments_received',  pageTitle: 'Payments Received',   permissionKey: 'payments_received'),
      _QuickCreateItem(label: 'Credit Note',         icon: Icons.note_outlined,          route: 'sales/credit_notes',       pageTitle: 'Credit Notes',        permissionKey: 'credit_notes'),
      _QuickCreateItem(label: 'Quote',               icon: Icons.request_quote_outlined, route: 'sales/quotes',             pageTitle: 'Quotes',              permissionKey: 'quotes'),
      _QuickCreateItem(label: 'Sales Order',         icon: Icons.shopping_bag_outlined,  route: 'sales/orders',             pageTitle: 'Sales Orders',        permissionKey: 'sales_orders'),
      _QuickCreateItem(label: 'Delivery Challan',    icon: Icons.local_shipping_outlined,route: 'sales/delivery_challans',  pageTitle: 'Delivery Challans',   permissionKey: 'delivery_challans'),
    ],
  ),
  _QuickCreateSection(
    title: 'Purchases',
    icon: Icons.shopping_bag_outlined,
    color: Color(0xFF7C3AED),
    items: [
      _QuickCreateItem(label: 'Vendor',              icon: Icons.store_outlined,             route: 'purchases/vendors',           pageTitle: 'Vendors',           permissionKey: 'vendors'),
      _QuickCreateItem(label: 'Expense',             icon: Icons.money_off_outlined,         route: 'purchases/expenses',          pageTitle: 'Expenses',          permissionKey: 'expenses'),
      _QuickCreateItem(label: 'Bill',                icon: Icons.description_outlined,       route: 'purchases/bills',             pageTitle: 'Bills',             permissionKey: 'bills'),
      _QuickCreateItem(label: 'Purchase Order',      icon: Icons.shopping_cart_outlined,     route: 'purchases/orders',            pageTitle: 'Purchase Orders',   permissionKey: 'purchase_orders'),
      _QuickCreateItem(label: 'Vendor Credit',       icon: Icons.credit_card_outlined,       route: 'purchases/vendor_credits',    pageTitle: 'Vendor Credits',    permissionKey: 'vendor_credits'),
      _QuickCreateItem(label: 'E-Way Bill',          icon: Icons.receipt_outlined,           route: 'purchases/eway_bills',        pageTitle: 'E-Way Bills',       permissionKey: 'eway_bills'),
      _QuickCreateItem(label: 'Payment Link',        icon: Icons.link_outlined,              route: 'purchases/payment_links',     pageTitle: 'Payment Links',     permissionKey: 'payment_links'),
      _QuickCreateItem(label: 'Payment Made',        icon: Icons.payment_outlined,           route: 'purchases/payments_made',     pageTitle: 'Payments Made',     permissionKey: 'payments_made'),
    ],
  ),
  _QuickCreateSection(
    title: 'Accountant',
    icon: Icons.person_outline,
    color: Color(0xFF059669),
    items: [
      _QuickCreateItem(label: 'Manual Journal',      icon: Icons.book_outlined,              route: 'accountant/manual_journals',      pageTitle: 'Manual Journals',      permissionKey: 'manual_journals'),
      _QuickCreateItem(label: 'Currency Adjustment', icon: Icons.currency_exchange_outlined, route: 'accountant/currency_adjustments', pageTitle: 'Currency Adjustments', permissionKey: 'currency_adjustments'),
      _QuickCreateItem(label: 'Chart of Accounts',   icon: Icons.account_tree_outlined,      route: 'accountant/chart_of_accounts',    pageTitle: 'Chart of Accounts',    permissionKey: 'chart_of_accounts'),
      _QuickCreateItem(label: 'Budget',              icon: Icons.account_balance_wallet_outlined, route: 'accountant/budgets',          pageTitle: 'Budgets',              permissionKey: 'budgets'),
    ],
  ),
  _QuickCreateSection(
    title: 'Time Tracking',
    icon: Icons.access_time_outlined,
    color: Color(0xFFD97706),
    items: [
      _QuickCreateItem(label: 'Project',    icon: Icons.folder_outlined,   route: 'time_tracking/projects',  pageTitle: 'Projects',   permissionKey: 'projects'),
      _QuickCreateItem(label: 'Timesheet',  icon: Icons.schedule_outlined, route: 'time_tracking/timesheet', pageTitle: 'Timesheet',  permissionKey: 'timesheets'),
    ],
  ),
  _QuickCreateSection(
    title: 'TMS',
    icon: Icons.confirmation_number_outlined,
    color: Color(0xFFDC2626),
    items: [
      _QuickCreateItem(label: 'Raise Ticket',  icon: Icons.add_circle_outline,  route: 'tms/raise_ticket',   pageTitle: 'Raise a Ticket',  permissionKey: 'raise_ticket'),
      _QuickCreateItem(label: 'My Tickets',    icon: Icons.assignment_outlined, route: 'tms/my_tickets',     pageTitle: 'My Tickets',      permissionKey: 'my_tickets'),
      _QuickCreateItem(label: 'All Tickets',   icon: Icons.list_alt_outlined,   route: 'tms/all_tickets',    pageTitle: 'All Tickets',     permissionKey: 'all_tickets'),
      _QuickCreateItem(label: 'Closed Tickets',icon: Icons.archive_outlined,    route: 'tms/closed_tickets', pageTitle: 'Closed Tickets',  permissionKey: 'closed_tickets'),
    ],
  ),
];
// ──────────────────────────────────────────────────────────────────────────────

class BillingMainShell extends StatefulWidget {
  const BillingMainShell({Key? key}) : super(key: key);

  @override
  State<BillingMainShell> createState() => _BillingMainShellState();
}

class _BillingMainShellState extends State<BillingMainShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Key on the "+" button so we can get its position for the overlay
  final GlobalKey _quickCreateKey = GlobalKey();

  String _currentRoute      = 'home';
  String _currentPageTitle  = 'Dashboard';
  bool   _isSidebarExpanded = true;

  // ── Session data ─────────────────────────────────────────────────────────
  String                      _userRole      = '';
  String                      _name          = '';
  String                      _orgId         = '';
  String                      _orgName       = '';
  String?                     _orgLogoUrl;
  Map<String, dynamic>        _permissions   = {};
  List<Map<String, dynamic>>  _organizations = [];
  bool                        _sessionLoaded = false;

  String _token = '';

  final Map<String, bool> _expandedSections = {
    'tms':           false,
    'accountant':    false,
    'time_tracking': false,
    'purchases':     false,
    'sales':         false,
  };

  // ── Quick create overlay ──────────────────────────────────────────────────
  OverlayEntry? _quickCreateOverlay;
  bool          _quickCreateOpen = false;

  // ── FULL menu definition ─────────────────────────────────────────────────
  final List<NavigationItem> _allMenuItems = [
    NavigationItem(icon: Icons.dashboard_outlined,        selectedIcon: Icons.dashboard,        label: 'Dashboard',         route: 'home'),
    NavigationItem(icon: Icons.confirmation_number_outlined, selectedIcon: Icons.confirmation_number, label: 'TMS', route: 'tms', isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Raise a Ticket',  route: 'tms/raise_ticket',  icon: Icons.add_circle_outline),
        SubNavigationItem(label: 'My Tickets',       route: 'tms/my_tickets',    icon: Icons.assignment_outlined),
        SubNavigationItem(label: 'All Tickets',      route: 'tms/all_tickets',   icon: Icons.list_alt_outlined),
        SubNavigationItem(label: 'Closed Tickets',   route: 'tms/closed_tickets',icon: Icons.archive_outlined),
      ]),
    NavigationItem(icon: Icons.inventory_2_outlined,      selectedIcon: Icons.inventory_2,      label: 'Items',             route: 'items'),
    NavigationItem(icon: Icons.shopping_cart_outlined,    selectedIcon: Icons.shopping_cart,    label: 'Sales',             route: 'sales', isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Customers',           route: 'sales/customers',         icon: Icons.people_outline),
        SubNavigationItem(label: 'Invoices',            route: 'sales/invoices',          icon: Icons.receipt_long_outlined),
        SubNavigationItem(label: 'Recurring Invoices',  route: 'sales/recurring_invoices',icon: Icons.repeat_outlined),
        SubNavigationItem(label: 'Payments Received',   route: 'sales/payments_received', icon: Icons.payment_outlined),
        SubNavigationItem(label: 'Credit Notes',        route: 'sales/credit_notes',      icon: Icons.note_outlined),
        SubNavigationItem(label: 'Quotes',              route: 'sales/quotes',            icon: Icons.request_quote_outlined),
        SubNavigationItem(label: 'Sales Orders',        route: 'sales/orders',            icon: Icons.shopping_bag_outlined),
        SubNavigationItem(label: 'Delivery Challans',   route: 'sales/delivery_challans', icon: Icons.local_shipping_outlined),
      ]),
    NavigationItem(icon: Icons.shopping_bag_outlined,     selectedIcon: Icons.shopping_bag,     label: 'Purchases',         route: 'purchases', isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Vendors',             route: 'purchases/vendors',           icon: Icons.store_outlined),
        SubNavigationItem(label: 'Expenses',            route: 'purchases/expenses',          icon: Icons.money_off_outlined),
        SubNavigationItem(label: 'Fixed Assets',        route: 'purchases/assets',            icon: Icons.business_center_outlined),
        SubNavigationItem(label: 'Recurring Expenses',  route: 'purchases/recurring_expenses',icon: Icons.repeat_outlined),
        SubNavigationItem(label: 'Purchase Orders',     route: 'purchases/orders',            icon: Icons.shopping_cart_outlined),
        SubNavigationItem(label: 'Bills',               route: 'purchases/bills',             icon: Icons.description_outlined),
        SubNavigationItem(label: 'Recurring Bills',     route: 'purchases/recurring_bills',   icon: Icons.repeat_outlined),
        SubNavigationItem(label: 'Payments Made',       route: 'purchases/payments_made',     icon: Icons.payment_outlined),
        SubNavigationItem(label: 'Vendor Credits',      route: 'purchases/vendor_credits',    icon: Icons.credit_card_outlined),
        SubNavigationItem(label: 'E-Way Bills',         route: 'purchases/eway_bills',        icon: Icons.receipt_outlined),
        SubNavigationItem(label: 'Payment Links',       route: 'purchases/payment_links',     icon: Icons.link_outlined),
      ]),
    NavigationItem(icon: Icons.access_time_outlined,      selectedIcon: Icons.access_time,      label: 'Time Tracking',     route: 'time_tracking', isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Projects',  route: 'time_tracking/projects',  icon: Icons.folder_outlined),
        SubNavigationItem(label: 'Timesheet', route: 'time_tracking/timesheet', icon: Icons.schedule_outlined),
      ]),
    // NavigationItem(icon: Icons.credit_card_outlined, selectedIcon: Icons.credit_card, label: 'Rate Cards', route: 'rate_cards'), // Rate cards disabled
    NavigationItem(icon: Icons.account_balance_outlined,  selectedIcon: Icons.account_balance,  label: 'Banking',           route: 'banking'),
    NavigationItem(icon: Icons.person_outline,            selectedIcon: Icons.person,           label: 'Accountant',        route: 'accountant', isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Manual Journals',      route: 'accountant/manual_journals',      icon: Icons.book_outlined),
        SubNavigationItem(label: 'Currency Adjustments', route: 'accountant/currency_adjustments', icon: Icons.currency_exchange_outlined),
        SubNavigationItem(label: 'Chart of Accounts',    route: 'accountant/chart_of_accounts',    icon: Icons.account_tree_outlined),
        SubNavigationItem(label: 'Budgets',              route: 'accountant/budgets',              icon: Icons.account_balance_wallet_outlined),
      ]),
    NavigationItem(icon: Icons.bar_chart_outlined,        selectedIcon: Icons.bar_chart,        label: 'Reports',           route: 'reports'),
    NavigationItem(icon: Icons.admin_panel_settings_outlined, selectedIcon: Icons.admin_panel_settings, label: 'Role Access Control', route: 'role_access_control'),
    NavigationItem(icon: Icons.person_pin_outlined,       selectedIcon: Icons.person_pin,       label: 'My Profile',        route: 'my_profile'),
  ];

  List<NavigationItem> get _visibleMenuItems {
    final isAdmin = _userRole == 'owner' || _userRole == 'admin';
    if (isAdmin) return _allMenuItems;
    return _allMenuItems.map((item) {
      if (item.route == 'home') return item;
      if (item.route == 'my_profile') return item;
      if (!item.isExpandable) {
        if (_canAccessRoute(item.route)) return item;
        return null;
      }
      final visibleSubs = (item.subItems ?? []).where((sub) => _canAccessRoute(sub.route)).toList();
      if (visibleSubs.isEmpty) return null;
      return NavigationItem(icon: item.icon, selectedIcon: item.selectedIcon, label: item.label, route: item.route, isExpandable: item.isExpandable, subItems: visibleSubs);
    }).whereType<NavigationItem>().toList();
  }

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

  // ── Check if a quick-create item is accessible ────────────────────────────
  bool _canAccessQuickItem(_QuickCreateItem item) {
    final isAdmin = _userRole == 'owner' || _userRole == 'admin';
    if (isAdmin) return true;
    if (item.permissionKey == null) return true;
    return _canAccessRoute(item.route);
  }

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _closeQuickCreate();
    super.dispose();
  }

  Future<void> _loadSession() async {
    final role       = await FinanceSecureStorage.getRole()       ?? '';
    final name       = await FinanceSecureStorage.getName()       ?? '';
    final orgId      = await FinanceSecureStorage.getOrgId()      ?? '';
    final orgName    = await FinanceSecureStorage.getOrgName()    ?? '';
    final orgLogoUrl = await FinanceSecureStorage.getOrgLogoUrl();
    final perms      = await FinanceSecureStorage.getPermissions();
    final orgs       = await FinanceSecureStorage.getOrganizations();
    final token      = await FinanceSecureStorage.getToken() ?? '';

    if (mounted) {
      setState(() {
        _userRole      = role;
        _name          = name;
        _orgId         = orgId;
        _orgName       = orgName;
        _orgLogoUrl    = orgLogoUrl;
        _permissions   = perms;
        _organizations = orgs;
        _token         = token;
        _sessionLoaded = true;
      });
    }
  }

  // ── Org switcher ──────────────────────────────────────────────────────────
  void _showOrgSwitcher(BuildContext context) {
    if (_organizations.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You only belong to one organization.'), duration: Duration(seconds: 2)));
      return;
    }
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: _OrgSwitcherCard(organizations: _organizations, currentOrgId: _orgId, onOrgSelected: _switchOrg),
      ),
    );
  }

  Future<void> _switchOrg(String orgId, String orgName) async {
    if (orgId == _orgId) { Navigator.pop(context); return; }
    Navigator.pop(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    showDialog(
      context: context, barrierDismissible: false, barrierColor: Colors.black.withOpacity(0.4),
      builder: (_) => WillPopScope(onWillPop: () async => false,
        child: Center(child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: Color(0xFF2563EB)),
            const SizedBox(height: 16),
            Text('Switching to $orgName...', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1E3A5F))),
          ]),
        ))),
    );
    try {
      final result = await FinanceAuthService.selectOrg(orgId);
      if (!mounted) return;
      if (result['success'] == true) {
        ApiService().clearTokenCache();
        if (mounted) setState(() { _currentRoute = 'loading'; _currentPageTitle = 'Dashboard'; _expandedSections.updateAll((key, _) => false); _orgId = orgId; _orgName = orgName; _orgLogoUrl = null; _permissions = {}; });
        await _loadSession();
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) Navigator.pop(context);
        if (mounted) setState(() { _currentRoute = 'home'; _currentPageTitle = 'Dashboard'; });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 16), const SizedBox(width: 8), Text('Switched to $orgName')]),
          backgroundColor: const Color(0xFF2563EB), behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), duration: const Duration(seconds: 2)));
      } else {
        if (mounted) Navigator.pop(context);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Failed to switch organisation'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error switching organisation: $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
    }
  }

  // ── QUICK CREATE OVERLAY ──────────────────────────────────────────────────

  void _toggleQuickCreate() {
    if (_quickCreateOpen) {
      _closeQuickCreate();
    } else {
      _openQuickCreate();
    }
  }

  void _closeQuickCreate() {
    _quickCreateOverlay?.remove();
    _quickCreateOverlay = null;
    if (mounted) setState(() => _quickCreateOpen = false);
  }

  void _openQuickCreate() {
    setState(() => _quickCreateOpen = true);

    // Get position of the + button
    final RenderBox? buttonBox = _quickCreateKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox?;

    Offset buttonOffset = Offset.zero;
    Size   buttonSize   = Size.zero;

    if (buttonBox != null && overlayBox != null) {
      buttonOffset = buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox);
      buttonSize   = buttonBox.size;
    }

    final screenSize   = MediaQuery.of(context).size;
    final isMobile     = screenSize.width < 600;

    _quickCreateOverlay = OverlayEntry(
      builder: (ctx) => _QuickCreateOverlay(
        buttonOffset:  buttonOffset,
        buttonSize:    buttonSize,
        screenSize:    screenSize,
        isMobile:      isMobile,
        sections:      _kQuickCreateSections,
        canAccess:     _canAccessQuickItem,
        onItemTap:     (item) {
          _closeQuickCreate();
          _navigateInline(item.route, item.pageTitle);
        },
        onDismiss:     _closeQuickCreate,
      ),
    );

    Overlay.of(context).insert(_quickCreateOverlay!);
  }

  // ── Page routing ──────────────────────────────────────────────────────────
  Widget _getSelectedPage() {
    if (_currentRoute == 'loading') {
      return Container(color: _kPageBg, child: const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB))));
    }
    switch (_currentRoute) {
      case 'home':                           return HomeBilling(key: ValueKey('home_$_orgId'));
      case 'tms/raise_ticket':               return _EmbeddedPage(child: const RaiseTicketScreen());
      case 'tms/my_tickets':                 return _EmbeddedPage(child: const MyTicketsScreen());
      case 'tms/all_tickets':                return _EmbeddedPage(child: const AllTicketsScreen());
      case 'tms/closed_tickets':             return _EmbeddedPage(child: const ClosedTicketsScreen());
      case 'items':                          return _EmbeddedPage(child: const ItemsBilling());
      case 'sales/customers':                return _EmbeddedPage(child: const CustomersListPage());
      case 'sales/invoices':                 return _EmbeddedPage(child: const InvoicesListPage());
      case 'sales/recurring_invoices':       return _EmbeddedPage(child: const RecurringInvoicesListPage());
      case 'sales/payments_received':        return _EmbeddedPage(child: const PaymentsReceivedPage());
      case 'sales/credit_notes':             return _EmbeddedPage(child: const CreditNotesListPage());
      case 'sales/quotes':                   return _EmbeddedPage(child: const QuotesListPage());
      case 'sales/orders':                   return _EmbeddedPage(child: const SalesOrdersListPage());
      case 'sales/delivery_challans':        return _EmbeddedPage(child: const DeliveryChallansListPage());
      case 'purchases/vendors':              return _EmbeddedPage(child: const VendorsListPage());
      case 'purchases/expenses':             return _EmbeddedPage(child: const ExpensesListPage());
      case 'purchases/assets':               return _EmbeddedPage(child: FixedAssetsListPage(baseUrl: ApiConfig.baseUrl, token: _token));
      case 'purchases/recurring_expenses':   return _EmbeddedPage(child: const RecurringExpensesListPage());
      case 'purchases/orders':               return _EmbeddedPage(child: const PurchaseOrdersListPage());
      case 'purchases/bills':                return _EmbeddedPage(child: const BillListPage());
      case 'purchases/recurring_bills':      return _EmbeddedPage(child: RecurringBillsListPage());
      case 'purchases/payments_made':        return _EmbeddedPage(child: const PaymentMadeListPage());
      case 'purchases/vendor_credits':       return _EmbeddedPage(child: const VendorCreditsListPage());
      case 'purchases/eway_bills':           return _EmbeddedPage(child: const EWayBillListPage());
      case 'purchases/payment_links':        return _EmbeddedPage(child: const PaymentLinksListPage());
      case 'time_tracking/projects':         return _EmbeddedPage(child: const ProjectsListPage());
      case 'time_tracking/timesheet':        return _EmbeddedPage(child: const TimesheetsListPage());
      // case 'rate_cards': return _EmbeddedPage(child: RateCardListScreen()); // Rate cards disabled
      case 'banking':                        return _EmbeddedPage(child: BankingDashboardPage());
      case 'accountant/manual_journals':     return _EmbeddedPage(child: const ManualJournalsListPage());
      case 'accountant/currency_adjustments':return _EmbeddedPage(child: const CurrencyAdjustmentsListPage());
      case 'accountant/chart_of_accounts':   return _EmbeddedPage(child: const ChartOfAccountsListPage());
      case 'accountant/budgets':             return _EmbeddedPage(child: const BudgetsListPage());
      case 'reports':                        return _EmbeddedPage(child: const ReportsListPage());
      case 'role_access_control':            return _EmbeddedPage(child: const FinanceERPUsersScreen());
      default:                               return HomeBilling(key: ValueKey('home_$_orgId'));
    }
  }

  void _navigateInline(String route, String label) {
    setState(() { _currentRoute = route; _currentPageTitle = label; });
  }

  void _goToDashboard() {
    setState(() { _currentRoute = 'home'; _currentPageTitle = 'Dashboard'; });
  }

  void _openProfile() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceProfilePage())).then((_) {
      if (mounted) { setState(() { _currentRoute = 'home'; _currentPageTitle = 'Dashboard'; }); _loadSession(); }
    });
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(children: [Icon(Icons.logout, color: Color(0xFF1E3A5F)), SizedBox(width: 10), Text('Sign Out')]),
        content: const Text('Are you sure you want to sign out of the Abra Finance ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white),
            child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await FinanceSecureStorage.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const FinanceWelcomeScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_sessionLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF2563EB))));
    }
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile    = screenWidth < 1024;

    return PopScope(
      canPop: _currentRoute == 'home',
      onPopInvoked: (didPop) {
        if (!didPop && _currentRoute != 'home') _goToDashboard();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: isMobile ? _buildDrawer() : null,
        body: GlobalTimerBar(
          child: Row(children: [
            if (!isMobile)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isSidebarExpanded ? 240 : 70,
                child: _buildSidebarContent(isDrawer: false),
              ),
            Expanded(child: Column(children: [
              _buildTopBar(isMobile),
              Expanded(child: Container(color: _kPageBg, child: _getSelectedPage())),
            ])),
          ]),
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar(bool isMobile) {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [_kNavyDark, _kNavy]),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        if (isMobile)
          IconButton(icon: const Icon(Icons.menu, color: _kWhite), onPressed: () => _scaffoldKey.currentState?.openDrawer(), tooltip: 'Open Menu')
        else
          IconButton(
            icon: Icon(_isSidebarExpanded ? Icons.menu_open : Icons.menu, color: _kWhite),
            onPressed: () => setState(() => _isSidebarExpanded = !_isSidebarExpanded),
            tooltip: _isSidebarExpanded ? 'Collapse Sidebar' : 'Expand Sidebar'),
        if (_currentRoute != 'home') ...[
          const SizedBox(width: 4),
          IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: _kWhite, size: 18), onPressed: _goToDashboard, tooltip: 'Back to Dashboard'),
        ],
        const SizedBox(width: 4),
        Expanded(child: Text(_currentPageTitle, style: const TextStyle(color: _kWhite, fontSize: 18, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),

        // ── Org name chip ─────────────────────────────────────────────────
        if (_orgName.isNotEmpty)
          GestureDetector(
            onTap: () => _showOrgSwitcher(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.business, color: _kWhite, size: 14),
                const SizedBox(width: 5),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(_orgName, style: const TextStyle(color: _kWhite, fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                if (_organizations.length > 1) ...[const SizedBox(width: 3), const Icon(Icons.swap_horiz, color: _kWhite, size: 14)],
              ]),
            ),
          ),

        const SizedBox(width: 8),

        // ── "+" Quick Create button ───────────────────────────────────────
        _QuickCreateButton(
          globalKey:  _quickCreateKey,
          isOpen:     _quickCreateOpen,
          onPressed:  _toggleQuickCreate,
        ),

        const SizedBox(width: 6),

        // ── Profile avatar ────────────────────────────────────────────────
        GestureDetector(
          onTap: _openProfile,
          child: CircleAvatar(
            radius: 16,
            backgroundColor: _kBlueAccent,
            child: Text(_name.isNotEmpty ? _name[0].toUpperCase() : 'U',
                style: const TextStyle(color: _kWhite, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ),

        const SizedBox(width: 4),
        IconButton(icon: const Icon(Icons.logout, color: _kWhite), onPressed: _logout, tooltip: 'Sign Out'),
      ]),
    );
  }

  // ── Sidebar ───────────────────────────────────────────────────────────────
  Widget _buildSidebarContent({required bool isDrawer}) {
    final showFull = isDrawer || _isSidebarExpanded;
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_kNavyDark, _kNavy])),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _kBlueAccent, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.account_balance_wallet, color: _kWhite, size: 20)),
              if (showFull) ...[const SizedBox(width: 10), const Expanded(child: Text('Abra Finance', style: TextStyle(color: _kWhite, fontSize: 17, fontWeight: FontWeight.bold)))],
            ]),
            if (showFull && _orgName.isNotEmpty) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => _showOrgSwitcher(context),
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withOpacity(0.15))),
                  child: Row(children: [
                    const Icon(Icons.business, color: _kWhite, size: 14), const SizedBox(width: 6),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_orgName, style: const TextStyle(color: _kWhite, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      Text(_userRole.toUpperCase(), style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5)),
                    ])),
                    if (_organizations.length > 1) const Icon(Icons.unfold_more, color: _kWhite, size: 14),
                  ]),
                ),
              ),
            ],
          ]),
        ),
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: _buildMenuWidgets(showFull: showFull, isDrawer: isDrawer))),
      ]),
    );
  }

  List<Widget> _buildMenuWidgets({required bool showFull, required bool isDrawer}) {
    final items   = _visibleMenuItems;
    final widgets = <Widget>[];
    for (final item in items) {
      final isSelected = _currentRoute == item.route || (_currentRoute.startsWith('${item.route}/') && item.isExpandable);
      final isExpanded = _expandedSections[item.route] ?? false;
      widgets.add(_SidebarItem(
        item: item, isSelected: isSelected, isExpanded: isExpanded, showFull: showFull,
        onTap: () {
          if (item.isExpandable) { setState(() => _expandedSections[item.route] = !isExpanded); }
          else { if (isDrawer) Navigator.pop(context); _handleTopLevelNavigation(item.route, item.label); }
        },
      ));
      if (item.isExpandable && isExpanded && showFull) {
        for (final sub in item.subItems ?? []) {
          widgets.add(_SubSidebarItem(
            subItem: sub, isSelected: _currentRoute == sub.route,
            onTap: () { if (isDrawer) Navigator.pop(context); _navigateInline(sub.route, sub.label); },
          ));
        }
      }
    }
    return widgets;
  }

  void _handleTopLevelNavigation(String route, String label) {
    switch (route) {
      case 'home':       _goToDashboard(); break;
      case 'my_profile': _openProfile();   break;
      default:           _navigateInline(route, label);
    }
  }

  Widget _buildDrawer() => Drawer(child: _buildSidebarContent(isDrawer: true));
}

// =============================================================================
// QUICK CREATE BUTTON
// =============================================================================
class _QuickCreateButton extends StatelessWidget {
  final GlobalKey  globalKey;
  final bool       isOpen;
  final VoidCallback onPressed;

  const _QuickCreateButton({required this.globalKey, required this.isOpen, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: globalKey,
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isOpen ? _kBlueAccent : _kBlueAccent.withOpacity(0.85),
          borderRadius: BorderRadius.circular(8),
          boxShadow: isOpen ? [BoxShadow(color: _kBlueAccent.withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 2))] : [],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedRotation(
            turns: isOpen ? 0.125 : 0,  // 45 deg when open
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add, color: _kWhite, size: 18),
          ),
          const SizedBox(width: 4),
          const Text('New', style: TextStyle(color: _kWhite, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// =============================================================================
// QUICK CREATE OVERLAY
// =============================================================================
class _QuickCreateOverlay extends StatefulWidget {
  final Offset                               buttonOffset;
  final Size                                 buttonSize;
  final Size                                 screenSize;
  final bool                                 isMobile;
  final List<_QuickCreateSection>            sections;
  final bool Function(_QuickCreateItem)      canAccess;
  final void Function(_QuickCreateItem)      onItemTap;
  final VoidCallback                         onDismiss;

  const _QuickCreateOverlay({
    required this.buttonOffset,
    required this.buttonSize,
    required this.screenSize,
    required this.isMobile,
    required this.sections,
    required this.canAccess,
    required this.onItemTap,
    required this.onDismiss,
  });

  @override
  State<_QuickCreateOverlay> createState() => _QuickCreateOverlayState();
}

class _QuickCreateOverlayState extends State<_QuickCreateOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fadeAnim;
  late Animation<double>   _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _fadeAnim  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Filter sections to only show items the user can access
  List<_QuickCreateSection> get _filteredSections {
    return widget.sections.map((section) {
      final visibleItems = section.items.where(widget.canAccess).toList();
      if (visibleItems.isEmpty) return null;
      return _QuickCreateSection(title: section.title, icon: section.icon, color: section.color, items: visibleItems);
    }).whereType<_QuickCreateSection>().toList();
  }

  @override
  Widget build(BuildContext context) {
    // Dismiss on tap outside
    return Stack(children: [
      // Translucent barrier
      Positioned.fill(
        child: GestureDetector(
          onTap: widget.onDismiss,
          behavior: HitTestBehavior.opaque,
          child: Container(color: Colors.black.withOpacity(0.25)),
        ),
      ),

      // Card
      if (widget.isMobile)
        // Mobile: bottom sheet style
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)),
              child: _buildCard(isMobile: true),
            ),
          ),
        )
      else
        // Desktop: dropdown below "+" button
        _buildDesktopPositioned(),
    ]);
  }

  Widget _buildDesktopPositioned() {
    const cardWidth  = 760.0;
    const cardMaxH   = 480.0;

    // Calculate left position — align to right edge of button, clamp so card stays on screen
    double left = widget.buttonOffset.dx + widget.buttonSize.width - cardWidth;
    if (left < 8) left = 8;
    if (left + cardWidth > widget.screenSize.width - 8) left = widget.screenSize.width - cardWidth - 8;

    double top = widget.buttonOffset.dy + widget.buttonSize.height + 6;
    if (top + cardMaxH > widget.screenSize.height - 8) top = widget.buttonOffset.dy - cardMaxH - 6;

    return Positioned(
      left: left,
      top:  top,
      width: cardWidth,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale:     _scaleAnim,
          alignment: Alignment.topRight,
          child: _buildCard(isMobile: false),
        ),
      ),
    );
  }

  Widget _buildCard({required bool isMobile}) {
    final sections = _filteredSections;

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxHeight: isMobile ? widget.screenSize.height * 0.75 : 480),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: isMobile
              ? const BorderRadius.vertical(top: Radius.circular(20))
              : BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 8)),
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6,  offset: const Offset(0, 2)),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF1E3A5F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: _kBlueAccent, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.add, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Quick Create', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Select what you want to create or navigate to', style: TextStyle(color: Colors.white60, fontSize: 11)),
              ])),
              GestureDetector(
                onTap: widget.onDismiss,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ]),
          ),

          // Sections
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: isMobile
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: sections.map((s) => _buildSection(s, isMobile: true)).toList())
                  : _buildDesktopGrid(sections),
            ),
          ),
        ]),
      ),
    );
  }

  // Desktop: multi-column grid
  Widget _buildDesktopGrid(List<_QuickCreateSection> sections) {
    // Arrange sections in rows of 3
    final rows = <List<_QuickCreateSection>>[];
    for (int i = 0; i < sections.length; i += 3) {
      rows.add(sections.sublist(i, i + 3 > sections.length ? sections.length : i + 3));
    }
    return Column(children: rows.map((row) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: row.map((s) {
          return Expanded(child: Padding(
            padding: EdgeInsets.only(right: s == row.last ? 0 : 12),
            child: _buildSection(s, isMobile: false),
          ));
        }).toList()),
      );
    }).toList());
  }

  Widget _buildSection(_QuickCreateSection section, {required bool isMobile}) {
    if (isMobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Section header
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: section.color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
              child: Icon(section.icon, color: section.color, size: 14),
            ),
            const SizedBox(width: 8),
            Text(section.title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: section.color, letterSpacing: 0.5)),
          ]),
        ),
        // Items — mobile: horizontal scroll chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: section.items.map((item) => Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 12),
            child: _QuickCreateChip(item: item, color: section.color, onTap: () => widget.onItemTap(item)),
          )).toList()),
        ),
        const Divider(height: 4),
        const SizedBox(height: 8),
      ]);
    }

    // Desktop: vertical list per column
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Section header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: section.color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(section.icon, color: section.color, size: 14),
          const SizedBox(width: 7),
          Text(section.title.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: section.color, letterSpacing: 0.8)),
        ]),
      ),
      const SizedBox(height: 8),
      // Items
      ...section.items.map((item) => _QuickCreateListItem(item: item, color: section.color, onTap: () => widget.onItemTap(item))),
    ]);
  }
}

// ── Desktop list-style item ───────────────────────────────────────────────────
class _QuickCreateListItem extends StatefulWidget {
  final _QuickCreateItem item;
  final Color            color;
  final VoidCallback     onTap;
  const _QuickCreateListItem({required this.item, required this.color, required this.onTap});

  @override
  State<_QuickCreateListItem> createState() => _QuickCreateListItemState();
}

class _QuickCreateListItemState extends State<_QuickCreateListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered ? widget.color.withOpacity(0.07) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(children: [
            Icon(widget.item.icon, color: _hovered ? widget.color : const Color(0xFF64748B), size: 15),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.item.label,
                style: TextStyle(fontSize: 13, color: _hovered ? widget.color : const Color(0xFF1E293B), fontWeight: _hovered ? FontWeight.w600 : FontWeight.normal))),
            if (_hovered) Icon(Icons.arrow_forward_ios, color: widget.color, size: 11),
          ]),
        ),
      ),
    );
  }
}

// ── Mobile chip-style item ────────────────────────────────────────────────────
class _QuickCreateChip extends StatelessWidget {
  final _QuickCreateItem item;
  final Color            color;
  final VoidCallback     onTap;
  const _QuickCreateChip({required this.item, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(item.icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(item.label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// =============================================================================
// _EmbeddedPage
// =============================================================================
class _EmbeddedPage extends StatelessWidget {
  final Widget child;
  const _EmbeddedPage({required this.child});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        appBarTheme: Theme.of(context).appBarTheme.copyWith(toolbarHeight: 0, elevation: 0, shadowColor: Colors.transparent, surfaceTintColor: Colors.transparent),
      ),
      child: child,
    );
  }
}

// =============================================================================
// ORG SWITCHER CARD
// =============================================================================
class _OrgSwitcherCard extends StatelessWidget {
  final List<Map<String, dynamic>>                             organizations;
  final String                                                 currentOrgId;
  final Future<void> Function(String orgId, String orgName)   onOrgSelected;

  const _OrgSwitcherCard({required this.organizations, required this.currentOrgId, required this.onOrgSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 40, offset: const Offset(0, 16))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF1E3A5F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 20)),
            const SizedBox(width: 14),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Switch Organisation', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Select the organisation to work in', style: TextStyle(color: Colors.white60, fontSize: 12)),
            ])),
            IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ]),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: organizations.map((org) {
              final orgId     = org['orgId']?.toString()   ?? '';
              final orgName   = org['orgName']?.toString() ?? '';
              final role      = org['role']?.toString()    ?? '';
              final isCurrent = orgId == currentOrgId;
              return GestureDetector(
                onTap: () => onOrgSelected(orgId, orgName),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isCurrent ? const Color(0xFF2563EB).withOpacity(0.06) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isCurrent ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0), width: isCurrent ? 2 : 1),
                  ),
                  child: Row(children: [
                    Container(width: 46, height: 46,
                      decoration: BoxDecoration(color: isCurrent ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(12)),
                      child: Center(child: Text(orgName.isNotEmpty ? orgName[0].toUpperCase() : 'O',
                          style: TextStyle(color: isCurrent ? Colors.white : const Color(0xFF64748B), fontSize: 18, fontWeight: FontWeight.bold)))),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(orgName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isCurrent ? const Color(0xFF2563EB) : const Color(0xFF0F172A))),
                      const SizedBox(height: 4),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: isCurrent ? const Color(0xFF2563EB).withOpacity(0.1) : const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(6)),
                        child: Text(role.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isCurrent ? const Color(0xFF2563EB) : const Color(0xFF64748B), letterSpacing: 0.5))),
                    ])),
                    if (isCurrent)
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: const Color(0xFF2563EB).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB), size: 14), SizedBox(width: 4),
                          Text('Active', style: TextStyle(color: Color(0xFF2563EB), fontSize: 11, fontWeight: FontWeight.w600)),
                        ]))
                    else
                      const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 20),
                  ]),
                ),
              );
            }).toList()),
          ),
        ),
      ]),
    );
  }
}

// =============================================================================
// SIDEBAR ITEM
// =============================================================================
class _SidebarItem extends StatelessWidget {
  final NavigationItem item;
  final bool           isSelected;
  final bool           isExpanded;
  final bool           showFull;
  final VoidCallback   onTap;

  const _SidebarItem({required this.item, required this.isSelected, required this.isExpanded, required this.showFull, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(color: isSelected ? _kBlueAccent : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(children: [
          Icon(isSelected ? item.selectedIcon : item.icon, color: _kWhite, size: 22),
          if (showFull) ...[
            const SizedBox(width: 12),
            Expanded(child: Text(item.label, style: TextStyle(color: _kWhite, fontSize: 15, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400))),
            if (item.isExpandable) Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: _kWhite, size: 18),
          ],
        ]),
      ),
    );
  }
}

// =============================================================================
// SUB SIDEBAR ITEM
// =============================================================================
class _SubSidebarItem extends StatelessWidget {
  final SubNavigationItem subItem;
  final bool              isSelected;
  final VoidCallback      onTap;

  const _SubSidebarItem({required this.subItem, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 22, right: 10, top: 1, bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: isSelected ? Colors.white.withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          if (subItem.icon != null) Icon(subItem.icon, color: _kWhite, size: 17)
          else Container(width: 5, height: 5, decoration: const BoxDecoration(color: _kWhite, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(subItem.label, style: TextStyle(color: _kWhite, fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400))),
        ]),
      ),
    );
  }
}

// =============================================================================
// DATA MODELS
// =============================================================================
class NavigationItem {
  final IconData                 icon;
  final IconData                 selectedIcon;
  final String                   label;
  final String                   route;
  final bool                     isExpandable;
  final List<SubNavigationItem>? subItems;

  NavigationItem({required this.icon, required this.selectedIcon, required this.label, required this.route, this.isExpandable = false, this.subItems});
}

class SubNavigationItem {
  final String    label;
  final String    route;
  final IconData? icon;

  SubNavigationItem({required this.label, required this.route, this.icon});
}