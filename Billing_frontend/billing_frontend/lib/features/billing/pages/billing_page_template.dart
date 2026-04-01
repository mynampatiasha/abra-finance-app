import 'package:flutter/material.dart';

class BillingPageTemplate extends StatefulWidget {
  final String title;
  final Widget content;
  final List<Widget>? actions;
  final bool showNewButton;
  final VoidCallback? onNewPressed;

  const BillingPageTemplate({
    Key? key,
    required this.title,
    required this.content,
    this.actions,
    this.showNewButton = true,
    this.onNewPressed,
  }) : super(key: key);

  @override
  State<BillingPageTemplate> createState() => _BillingPageTemplateState();
}

class _BillingPageTemplateState extends State<BillingPageTemplate> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Upper bar with title and actions
        Container(
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey[300]!, width: 1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                // Title with dropdown arrow
                Row(
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey[600],
                      size: 20,
                    ),
                  ],
                ),
                
                const Spacer(),
                
                // Action buttons
                if (widget.actions != null) ...widget.actions!,
                
                // New button
                if (widget.showNewButton) ...[
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: widget.onNewPressed ?? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Create New ${widget.title}'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3498DB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
                
                // More options button
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    // Show more options menu
                    _showMoreOptionsMenu(context);
                  },
                  icon: Icon(
                    Icons.more_horiz,
                    color: Colors.grey[600],
                  ),
                  tooltip: 'More options',
                ),
              ],
            ),
          ),
        ),
        
        // Main content area
        Expanded(
          child: Container(
            color: Colors.grey[50],
            child: widget.content,
          ),
        ),
      ],
    );
  }

  void _showMoreOptionsMenu(BuildContext context) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 200,
        60,
        20,
        0,
      ),
      items: [
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.import_export, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              const Text('Import'),
            ],
          ),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Import functionality')),
            );
          },
        ),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.file_download, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              const Text('Export'),
            ],
          ),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Export functionality')),
            );
          },
        ),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.settings, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              const Text('Settings'),
            ],
          ),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Settings functionality')),
            );
          },
        ),
      ],
    );
  }
}
