import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';

/// One permission, argued rather than announced.
///
/// The shape of the row is the argument: what it is, why the app needs it in
/// mechanical terms, and — set apart behind a rule — what the user actually
/// loses by refusing. A permission screen is the moment an automation app is
/// most likely to be uninstalled, so the honest cost of "no" is printed next to
/// every request instead of an "ACTION NEEDED" badge nagging for a "yes".
///
/// There is deliberately no icon. Six rounded-square glyphs down the left edge
/// added nothing a reader could use and made every item look equally important.
class PermissionItem extends StatelessWidget {
  const PermissionItem({
    super.key,
    required this.name,
    required this.why,
    required this.consequence,
    required this.granted,
    required this.onGrant,
    this.grantLabel = 'Grant',
  });

  final String name;

  /// Plain-language mechanism. Not marketing: what is read, and what is done
  /// with it.
  final String why;

  /// What stops working if this is refused. Rendered behind a rule, without
  /// alarm colour.
  final String consequence;

  final bool granted;
  final VoidCallback onGrant;
  final String grantLabel;

  static Key grantKey(String name) => Key('grant-$name');
  static Key grantedKey(String name) => Key('granted-$name');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x2,
        vertical: Space.x2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3, right: Space.x2),
                  child: Text(name, style: AppType.bodyStrong),
                ),
              ),
              granted ? _grantedMark() : _grantButton(),
            ],
          ),
          const SizedBox(height: Space.x1),
          Text(why, style: AppType.body),
          const SizedBox(height: Space.x1 + Space.half),
          Container(
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Brand.line, width: 2)),
            ),
            padding: const EdgeInsets.only(left: Space.x1 + Space.half),
            child: Text(consequence, style: AppType.caption),
          ),
        ],
      ),
    );
  }

  Widget _grantedMark() {
    return Padding(
      key: grantedKey(name),
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Brand.signal,
              borderRadius: Corner.markR,
            ),
          ),
          const SizedBox(width: Space.x1),
          Text(
            'GRANTED',
            style: AppType.eyebrow.copyWith(color: Brand.signal),
          ),
        ],
      ),
    );
  }

  /// A compact outline, not a filled accent: granting is the user's decision to
  /// make, and one screen should have exactly one primary action — here that is
  /// "Continue", not six competing Grant buttons.
  Widget _grantButton() {
    return Material(
      key: grantKey(name),
      color: Brand.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: Corner.tickR,
        side: BorderSide(color: Brand.lineStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onGrant,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x2 - Space.half,
            vertical: Space.x1,
          ),
          child: Text(grantLabel, style: AppType.label),
        ),
      ),
    );
  }
}
