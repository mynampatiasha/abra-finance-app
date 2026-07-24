import 'package:flutter/material.dart';

const kNavyDark = Color(0xFF0F172A);
const kNavy = Color(0xFF1E3A5F);
const kBlueAccent = Color(0xFF2563EB);
const kWhite = Color(0xFFFFFFFF);
const kPageBg = Color(0xFFF8FAFC);

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBack;

  /// Optional: called AFTER pop, use to reset shell state to Dashboard.
  /// In BillingMainShell pass: onBack: () => setState(() { _selectedIndex = 0; _currentPageTitle = 'Dashboard'; })
  final VoidCallback? onBack;

  const AppTopBar({
    Key? key,
    required this.title,
    this.actions,
    this.showBack = true,
    this.onBack,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // ── backgroundColor = kNavyDark (matches gradient start color).
      // This means:
      //   • Embedded mode  → toolbarHeight collapses to 0 via Theme override,
      //                       so this color is hidden — nothing visible at all.
      //   • Standalone screen → kNavyDark sits behind the flexibleSpace gradient
      //                         seamlessly — no double color, no gap.
      backgroundColor: kNavyDark,

      // ── flexibleSpace renders the gradient only when height > 1.
      // When _EmbeddedPage collapses toolbarHeight → 0, maxHeight ≤ 1
      // and SizedBox.shrink() is returned — zero paint, zero bar.
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight <= 1) return const SizedBox.shrink();
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [kNavyDark, kNavy],
              ),
            ),
          );
        },
      ),

      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Row(
        children: [
          if (showBack)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: kWhite),
              tooltip: 'Back',
              onPressed: () {
                Navigator.of(context).pop(); // ✅ pop the current page
                onBack?.call(); // ✅ reset shell to Dashboard
              },
            ),
          if (showBack) const SizedBox(width: 4),
          Text(
            title,
            style: const TextStyle(
              color: kWhite,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: actions,
    );
  }
}
