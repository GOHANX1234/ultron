import 'package:flutter/material.dart';

import '../services/chat_history_service.dart';

/// The left-hand navigation drawer: brand, "new chat", the saved sessions
/// grouped by age, and the two secondary destinations.
///
/// This owns its own session loading. The previous version was a method on
/// `HomeScreen` that called `ChatHistoryService.loadSessions()` inline in a
/// `FutureBuilder`, so every `HomeScreen.setState` — one per streamed token —
/// constructed a fresh Future and re-read the file. Here the read happens when
/// the drawer is mounted, which (because Flutter's DrawerController does not
/// build its child while the drawer is closed) means once per open, plus once
/// more whenever something actually changes the list.
class AppDrawer extends StatefulWidget {
  const AppDrawer({
    super.key,
    required this.isDark,
    required this.currentSessionId,
    required this.onNewChat,
    required this.onOpenSession,
    required this.onSessionDeleted,
    required this.onOpenTaskHistory,
    required this.onOpenSettings,
    this.loadSessions = ChatHistoryService.loadSessions,
    this.deleteSession = ChatHistoryService.deleteSession,
  });

  final bool isDark;

  /// Marks one row as the session being viewed.
  final String currentSessionId;

  final VoidCallback onNewChat;
  final ValueChanged<ChatSession> onOpenSession;

  /// Fired after the session is already off disk, so the host can start a new
  /// chat if the one it was showing is the one that went away.
  final ValueChanged<String> onSessionDeleted;

  final VoidCallback onOpenTaskHistory;
  final VoidCallback onOpenSettings;

  /// Seams for tests: the real ones hit the app documents directory, which is
  /// not available under `flutter test`. Production code never passes these.
  final Future<List<ChatSession>> Function() loadSessions;
  final Future<void> Function(String id) deleteSession;

  static const double width = 320;

  static const double _radius = 28;
  static const double _rowRadius = 14;
  static const Color _accent = Color(0xFF6366F1);
  static const Color _accentAlt = Color(0xFF0EA5E9);

  /// Lets a test address the scrollable list without depending on row content.
  static const Key sessionListKey = Key('app-drawer-sessions');

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  late Future<List<ChatSession>> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = widget.loadSessions();
  }

  void _reload() {
    setState(() {
      _sessions = widget.loadSessions();
    });
  }

  /// Closes the drawer first, then runs [action] — so the caller never has to
  /// remember the pop, and the navigation animation does not fight the drawer's.
  void _dismissThen(VoidCallback action) {
    Navigator.pop(context);
    action();
  }

  Future<void> _deleteSession(ChatSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete chat?'),
        content: Text(
          '"${_titleOf(session)}" will be removed from history. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.deleteSession(session.id);
    widget.onSessionDeleted(session.id);
    if (mounted) _reload();
  }

  static String _titleOf(ChatSession session) =>
      session.title.trim().isEmpty ? 'Untitled chat' : session.title.trim();

  /// Calendar-day distance, so "Yesterday" means yesterday rather than
  /// "between 24 and 48 hours ago".
  static String _groupLabel(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final days = today.difference(day).inDays;

    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return 'Previous 7 days';
    if (days < 30) return 'Previous 30 days';
    return 'Older';
  }

  /// Time of day for today's chats, a short date for anything older. Both come
  /// from MaterialLocalizations, so they follow the device locale and its
  /// 12h/24h preference instead of a hard-coded format.
  String _timestampLabel(BuildContext context, DateTime timestamp) {
    final local = timestamp.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final isToday =
        local.year == now.year && local.month == now.month && local.day == now.day;

    if (isToday) {
      return localizations.formatTimeOfDay(
        TimeOfDay.fromDateTime(local),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
    }
    return localizations.formatShortDate(local);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return Drawer(
      width: AppDrawer.width,
      backgroundColor: isDark ? const Color(0xFF0B1120) : Colors.white,
      // Only the trailing corners are rounded: the leading edge is flush with
      // the screen, so rounding it would show the scrim through the gap.
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(AppDrawer._radius),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, isDark),
            _buildNewChatButton(context, isDark),
            _buildSectionLabel(isDark),
            Expanded(child: _buildSessionList(context, isDark)),
            _buildFooter(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppDrawer._accent.withValues(alpha: 0.32),
                  blurRadius: 12,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/app-logo.png',
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                // Decode near the drawn size instead of holding the full 512px
                // bitmap for a 38dp slot.
                cacheWidth: 152,
                cacheHeight: 152,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ultron-3',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Automation agent',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF64748B)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          _DrawerIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            isDark: isDark,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildNewChatButton(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        // The shadow lives on an outer Container because Ink cannot draw one,
        // and the gradient lives on Ink so the splash paints above it.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppDrawer._accent.withValues(alpha: isDark ? 0.34 : 0.28),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppDrawer._accent, AppDrawer._accentAlt],
              ),
            ),
            child: InkWell(
              onTap: () => _dismissThen(widget.onNewChat),
              child: const SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'New chat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'CHATS',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: isDark
                ? const Color(0xFF818CF8)
                : AppDrawer._accent.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionList(BuildContext context, bool isDark) {
    return FutureBuilder<List<ChatSession>>(
      future: _sessions,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final sessions = [...?snapshot.data]
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        if (sessions.isEmpty) return _buildEmptyState(isDark);

        // Flattened ahead of the builder so a group header can be emitted
        // whenever the calendar bucket changes. Session counts are small; the
        // list is a handful of rows, not a feed.
        final rows = <Widget>[];
        String? bucket;
        for (final session in sessions) {
          final label = _groupLabel(session.timestamp.toLocal());
          if (label != bucket) {
            rows.add(_buildGroupHeader(label, isDark, first: bucket == null));
            bucket = label;
          }
          rows.add(_buildSessionTile(context, session, isDark));
        }

        return ListView.builder(
          key: AppDrawer.sessionListKey,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          physics: const BouncingScrollPhysics(),
          itemCount: rows.length,
          itemBuilder: (context, index) => rows[index],
        );
      },
    );
  }

  Widget _buildGroupHeader(String label, bool isDark, {required bool first}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(10, first ? 2 : 14, 10, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    final muted = isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 34, color: muted),
            const SizedBox(height: 12),
            Text(
              'No chats yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Conversations you have will be saved here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, height: 1.4, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionTile(
    BuildContext context,
    ChatSession session,
    bool isDark,
  ) {
    final selected = session.id == widget.currentSessionId;
    final radius = BorderRadius.circular(AppDrawer._rowRadius);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? AppDrawer._accent.withValues(alpha: isDark ? 0.18 : 0.10)
            : Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _dismissThen(() => widget.onOpenSession(session)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? AppDrawer._accent.withValues(alpha: 0.38)
                    : Colors.transparent,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.chat_bubble_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: selected
                      ? AppDrawer._accent
                      : (isDark
                          ? const Color(0xFF64748B)
                          : const Color(0xFF94A3B8)),
                ),
                const SizedBox(width: 10),
                Expanded(child: _buildSessionText(context, session, isDark, selected)),
                _DrawerIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete chat',
                  isDark: isDark,
                  size: 32,
                  iconSize: 16,
                  tinted: false,
                  danger: true,
                  onPressed: () => _deleteSession(session),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionText(
    BuildContext context,
    ChatSession session,
    bool isDark,
    bool selected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _titleOf(session),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected
                ? (isDark ? Colors.white : const Color(0xFF0F172A))
                : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _timestampLabel(context, session.timestamp),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Column(
        children: [
          Divider(
            height: 1,
            thickness: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 8),
          _DrawerRow(
            icon: Icons.history_rounded,
            label: 'Task history',
            isDark: isDark,
            onTap: () => _dismissThen(widget.onOpenTaskHistory),
          ),
          _DrawerRow(
            icon: Icons.settings_rounded,
            label: 'Settings',
            isDark: isDark,
            onTap: () => _dismissThen(widget.onOpenSettings),
          ),
        ],
      ),
    );
  }
}

/// A square icon button. The tint is the Material's own colour so the splash is
/// clipped to the rounded shape rather than painting square behind it.
class _DrawerIconButton extends StatelessWidget {
  const _DrawerIconButton({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onPressed,
    this.size = 38,
    this.iconSize = 20,
    this.tinted = true,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  /// Whether to fill the button, or leave it flat for use inside a row that is
  /// already tinted.
  final bool tinted;

  final bool danger;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size / 3);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: tinted
            ? (isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.04))
            : Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: iconSize,
              color: danger
                  ? Colors.red.shade400.withValues(alpha: 0.85)
                  : (isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF475569)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A secondary destination in the footer, shaped like a session row so the two
/// halves of the drawer share one visual language.
class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppDrawer._rowRadius);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFFCBD5E1)
                      : const Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
