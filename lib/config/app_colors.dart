import 'package:flutter/material.dart';

/// Centralized color constants for Ultron-3.
/// All hex colors used in the app should reference these constants.
abstract class AppColors {
  // Indigo palette (primary brand)
  static const Color indigo600 = Color(0xFF4F46E5);
  static const Color indigo500 = Color(0xFF6366F1);
  static const Color indigo400 = Color(0xFF818CF8);

  // Sky/Cyan palette (secondary brand)
  static const Color sky500 = Color(0xFF0EA5E9);
  static const Color sky400 = Color(0xFF38BDF8);

  // Slate palette (backgrounds & text)
  static const Color slate950 = Color(0xFF0B0F19);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate850 = Color(0xFF111827);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate750 = Color(0xFF243049);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate50  = Color(0xFFF8FAFC);

  // Dark UI surfaces
  static const Color darkBg   = Color(0xFF090D16);
  static const Color darkCard = Color(0xFF151D30);
  static const Color darkChip = Color(0xFF1A2236);

  // Special
  static const Color telegramBlue = Color(0xFF0088CC);
  static const Color electricBlue = Color(0xFF0055FF);
  static const Color emerald500   = Color(0xFF10B981);
  static const Color amber500     = Color(0xFFF59E0B);
  static const Color violet500    = Color(0xFF8B5CF6);
}
