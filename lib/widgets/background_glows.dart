import 'package:flutter/material.dart';

/// Ambient background glow effect used throughout the app.
/// Renders two radial gradient orbs that adapt to dark/light mode.
class BackgroundGlows extends StatelessWidget {
  const BackgroundGlows({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned.fill(
      child: Stack(
        children: [
          // Top-left indigo glow
          Positioned(
            top: -150,
            left: -50,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    isDark
                        ? const Color(0xFF6366F1).withValues(alpha: 0.24)
                        : const Color(0xFF4F46E5).withValues(alpha: 0.12),
                    isDark
                        ? const Color(0xFF6366F1).withValues(alpha: 0)
                        : const Color(0xFF4F46E5).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          // Bottom-right cyan glow
          Positioned(
            bottom: 50,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    isDark
                        ? const Color(0xFF38BDF8).withValues(alpha: 0.18)
                        : const Color(0xFF0EA5E9).withValues(alpha: 0.09),
                    isDark
                        ? const Color(0xFF38BDF8).withValues(alpha: 0)
                        : const Color(0xFF0EA5E9).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
