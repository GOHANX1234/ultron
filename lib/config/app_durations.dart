/// Centralized animation and timing constants for Ultron-3.
abstract class AppDurations {
  // UI Animations
  static const Duration fast      = Duration(milliseconds: 150);
  static const Duration normal    = Duration(milliseconds: 300);
  static const Duration slow      = Duration(milliseconds: 500);
  static const Duration pageTurn  = Duration(milliseconds: 400);
  static const Duration liquidLoop = Duration(seconds: 12);

  // Task Execution Delays
  static const Duration defaultStep = Duration(milliseconds: 1200);
  static const Duration appOpen     = Duration(milliseconds: 3000);
  static const Duration typeText    = Duration(milliseconds: 2000);
  static const Duration click       = Duration(milliseconds: 1500);
  static const Duration scroll      = Duration(milliseconds: 1000);
  static const Duration waitAction  = Duration(seconds: 1);
  static const Duration taskDone    = Duration(seconds: 4);
  static const Duration parseRetry  = Duration(seconds: 2);
  static const Duration stuckTask   = Duration(seconds: 3);

  // Timeouts
  static const Duration nativeCall  = Duration(seconds: 3);
  static const Duration taskTimeout = Duration(seconds: 90);
}
