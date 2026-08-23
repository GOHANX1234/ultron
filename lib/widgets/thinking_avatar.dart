import 'package:flutter/material.dart';

/// Animated avatar shown while the assistant is generating a response.
///
/// The GIF loops on its own; the widget only exists while a request is in
/// flight, so mounting it starts the animation from the first frame.
class ThinkingAvatar extends StatelessWidget {
  /// Asset path of the looping avatar animation.
  static const String assetPath = 'assets/bloub-default-cycle.gif';

  /// Warm the image cache so the first frame appears without a flash.
  static Future<void> precache(BuildContext context) {
    return precacheImage(const AssetImage(assetPath), context);
  }

  final double size;

  const ThinkingAvatar({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.35 : 0.22),
              blurRadius: size * 0.45,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            assetPath,
            width: size,
            height: size,
            fit: BoxFit.cover,
            // Keep the previous frame on screen instead of flashing empty
            // space while the next one decodes.
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
            errorBuilder: (context, error, stackTrace) => Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF6366F1),
              ),
              child: SizedBox(
                width: size * 0.4,
                height: size * 0.4,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
