import 'package:flutter/material.dart';

import '../config/design_tokens.dart';

/// The two button styles in the system, and there are only two on purpose.
///
/// [PrimaryButton] is a solid accent fill with a black label — the one action
/// that moves the user forward on a screen. [SecondaryButton] is a hairline
/// outline with no fill. Anything that needs less weight than the outline is
/// body text with a link, not a third button. The pill-shaped glowing gradient
/// these replace made every action look primary, which is the same as having no
/// hierarchy at all.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
  });

  final String label;

  /// A null callback renders the disabled state. Kept as nullability rather
  /// than a separate `enabled` flag so it cannot disagree with itself.
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Shows a spinner in place of the icon and blocks input. The label stays put
  /// so the button does not change width mid-request.
  final bool busy;
  final bool expand;

  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    final button = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: enabled ? Brand.signal : Brand.surfaceHigh,
        borderRadius: Corner.controlR,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (busy) ...[
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Brand.textSecondary),
                    ),
                  ),
                  const SizedBox(width: Space.x1 + Space.half),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                      color: enabled ? Brand.onSignal : Brand.textTertiary,
                    ),
                  ),
                ),
                if (icon != null && !busy) ...[
                  Icon(
                    icon,
                    size: 17,
                    color: enabled ? Brand.onSignal : Brand.textTertiary,
                  ),
                  // No trailing gap: the label's own horizontal padding is the
                  // gap, and adding one here would push the pair off centre.
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// The outline style. Same metrics as [PrimaryButton] so the two sit level in a
/// footer row.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = enabled ? Brand.textPrimary : Brand.textTertiary;

    final button = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Corner.controlR,
          side: BorderSide(color: enabled ? Brand.lineStrong : Brand.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: PrimaryButton.height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: foreground),
                  const SizedBox(width: Space.x1),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
