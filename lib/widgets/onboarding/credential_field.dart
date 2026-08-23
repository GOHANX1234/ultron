import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';

/// A single field in a credentials form.
///
/// Everything the user types here is machine data — a secret, a URL, a model id
/// — so the input is set in the mono face while its label and help stay in the
/// text face. That split is what makes the screen read as a credentials form
/// rather than a settings page with colourful chips, and it makes a mistyped
/// endpoint visible: in mono, `l` and `1` are not the same shape.
class CredentialField extends StatelessWidget {
  const CredentialField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.obscure = false,
    this.onToggleObscure,
    this.optional = false,
    this.hasError = false,
    this.keyboardType,
    this.actionLabel,
    this.onAction,
    this.trailingLink,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;

  /// One line under the field. Where the secret is kept, or what the value is
  /// for — the thing a user needs before they will paste a key in.
  final String? helper;

  final bool obscure;

  /// Non-null renders the reveal toggle. Callers own the flag so the state stays
  /// with the form.
  final VoidCallback? onToggleObscure;

  final bool optional;
  final bool hasError;
  final TextInputType? keyboardType;

  /// An in-field action, e.g. "Fetch" on the model field.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// A right-aligned link beside the label, e.g. provider key documentation.
  final Widget? trailingLink;

  static Key fieldKey(String label) => Key('field-$label');
  static Key toggleKey(String label) => Key('field-toggle-$label');
  static Key actionKey(String label) => Key('field-action-$label');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(), style: AppType.eyebrow),
            if (optional) ...[
              const SizedBox(width: Space.x1),
              Text(
                'OPTIONAL',
                style: AppType.eyebrow.copyWith(color: Brand.textTertiary),
              ),
            ],
            const Spacer(),
            if (trailingLink != null) trailingLink!,
          ],
        ),
        const SizedBox(height: Space.x1),
        Container(
          decoration: BoxDecoration(
            color: Brand.surfaceHigh,
            borderRadius: Corner.controlR,
            border: Border.all(color: hasError ? Brand.danger : Brand.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: fieldKey(label),
                  controller: controller,
                  obscureText: obscure,
                  obscuringCharacter: '•',
                  keyboardType: keyboardType,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(
                    fontFamily: AppType.mono,
                    fontSize: 13.5,
                    color: Brand.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Space.x2 - Space.half,
                      vertical: Space.x2 - Space.half,
                    ),
                    hintText: hint,
                    hintStyle: const TextStyle(
                      fontFamily: AppType.mono,
                      fontSize: 13.5,
                      color: Brand.textTertiary,
                    ),
                  ),
                ),
              ),
              if (onToggleObscure != null)
                IconButton(
                  key: toggleKey(label),
                  onPressed: onToggleObscure,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: Brand.textSecondary,
                  ),
                  tooltip: obscure ? 'Show' : 'Hide',
                ),
              if (actionLabel != null) ...[
                Container(width: 1, height: 24, color: Brand.line),
                InkWell(
                  key: actionKey(label),
                  onTap: onAction,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.x2 - Space.half,
                      vertical: Space.x2 - Space.half,
                    ),
                    child: Text(
                      actionLabel!,
                      style: AppType.label.copyWith(color: Brand.signal),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: Space.x1 - Space.half),
          Text(helper!, style: AppType.caption),
        ],
      ],
    );
  }
}
