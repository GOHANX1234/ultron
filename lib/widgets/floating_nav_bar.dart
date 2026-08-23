import 'dart:ui';

import 'package:flutter/material.dart';

/// The floating glass bar at the top of the chat screen.
///
/// This lives outside `HomeScreen` and overrides [operator ==] on purpose.
/// `HomeScreen` calls `setState` for every streamed token, and
/// `Element.updateChild` skips rebuilding a child whose new widget compares
/// equal to the old one — so as long as none of these fields change, the whole
/// bar (including its [BackdropFilter], the most expensive thing in the
/// subtree) is untouched while a reply streams in. All the callbacks are method
/// tear-offs on the state object, which Dart canonicalises per instance, so
/// they stay equal across rebuilds. Do not pass closures.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.isDark,
    required this.busy,
    required this.onNewChat,
    required this.onSettings,
  });

  final bool isDark;

  /// Disables "New chat" while a reply is generating. Passed as state rather
  /// than a nullable callback so the callback itself stays a stable tear-off.
  final bool busy;

  final VoidCallback onNewChat;
  final VoidCallback onSettings;

  /// Concentric geometry: an action's radius is the card's radius minus the
  /// inset, so every curve shares a centre with the card's.
  static const double _radius = 22;
  static const double _inset = 6;
  static const double _action = 44;
  static const double _actionRadius = _radius - _inset;

  static const Color _accent = Color(0xFF6366F1);

  /// Identifies the logo-plus-wordmark row. Tests assert on the centring of the
  /// whole row: the wordmark alone sits right of the logo, so its own centre is
  /// not the brand's centre.
  static const Key brandKey = Key('floating-nav-brand');

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RepaintBoundary(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.all(_inset),
                decoration: BoxDecoration(
                  // A gradient rather than a flat fill: glass reads as glass
                  // because the sheen falls off from the top-left.
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            Colors.white.withValues(alpha: 0.14),
                            Colors.white.withValues(alpha: 0.06),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.88),
                            Colors.white.withValues(alpha: 0.68),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(_radius),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.90),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.28)
                          : const Color(0x0C0F172A),
                      blurRadius: 18,
                      spreadRadius: -2,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                // Stack, not Row-with-Spacers: the previous layout had one
                // action on the left and two on the right, so a pair of
                // Spacers pushed the title off-centre by half an action.
                // Centring it independently keeps it optically centred however
                // many actions each side grows to.
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Centred in the space *between* the action clusters, not
                    // in the card: one action sits on the left and two on the
                    // right, so a card-centred brand reads as pushed right —
                    // the eye centres it against the visible gaps, not the
                    // card's midpoint. The insets are the cluster widths, so
                    // this stays correct if either side gains an action.
                    Padding(
                      padding: const EdgeInsets.only(
                        left: _action,
                        right: _action * 2 + _inset,
                      ),
                      child: const _NavBrand(key: FloatingNavBar.brandKey),
                    ),
                    Row(
                      children: [
                        _NavAction(
                          icon: Icons.menu_rounded,
                          tooltip: 'Menu',
                          isDark: isDark,
                          // Scaffold.of works here because the bar is built
                          // inside the Scaffold's body, which also means the
                          // caller does not have to thread a key through.
                          onPressed: () => Scaffold.of(context).openDrawer(),
                        ),
                        const Spacer(),
                        _NavAction(
                          icon: Icons.add_comment_outlined,
                          tooltip: 'New chat',
                          isDark: isDark,
                          onPressed: busy ? null : onNewChat,
                        ),
                        const SizedBox(width: _inset),
                        _NavAction(
                          icon: Icons.settings_rounded,
                          tooltip: 'Settings',
                          isDark: isDark,
                          onPressed: onSettings,
                        ),
                      ],
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

  @override
  bool operator ==(Object other) =>
      other is FloatingNavBar &&
      other.isDark == isDark &&
      other.busy == busy &&
      other.onNewChat == onNewChat &&
      other.onSettings == onSettings;

  @override
  int get hashCode => Object.hash(isDark, busy, onNewChat, onSettings);
}

/// Logo plus wordmark. Const so it is created once and never rebuilt.
class _NavBrand extends StatelessWidget {
  const _NavBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                color: FloatingNavBar._accent.withValues(alpha: 0.30),
                blurRadius: 8,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset(
              'assets/app-logo.png',
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              // The logo is drawn at 28dp from a 512px source; without an
              // explicit cache size the full-resolution bitmap is decoded and
              // held in memory.
              cacheWidth: 112,
              cacheHeight: 112,
            ),
          ),
        ),
        const SizedBox(width: 10),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF0EA5E9), Color(0xFF38BDF8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Ultron-3',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// One 44dp action. A null [onPressed] renders the disabled colours.
class _NavAction extends StatelessWidget {
  const _NavAction({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: Material(
        // The tint is the Material's own colour rather than a nested
        // decorated Container, so the ink splash is clipped to the same
        // rounded shape instead of overflowing a square.
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(FloatingNavBar._actionRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(FloatingNavBar._actionRadius),
          child: SizedBox(
            width: FloatingNavBar._action,
            height: FloatingNavBar._action,
            child: Icon(
              icon,
              size: 20,
              color: isDark
                  ? (enabled ? Colors.white : Colors.white30)
                  : (enabled ? const Color(0xFF1E293B) : Colors.black26),
            ),
          ),
        ),
      ),
    );
  }
}
