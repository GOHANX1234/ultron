import 'package:flutter/material.dart';

import '../config/design_tokens.dart';

/// The Ultron mark: a screen, its element rows, and one of them selected.
///
/// It is drawn rather than illustrated, and it is drawn from the product's
/// actual mechanism — the agent reads the on-screen element tree and acts on one
/// element at a time. That is the whole brief for a mark here: something that
/// says *automation and control* to someone who has never opened the app, and
/// that survives being 20dp tall in a header. The sparkle it replaces said
/// "generative AI" and nothing about this app.
class UltronMark extends StatelessWidget {
  const UltronMark({super.key, this.size = 28, this.accent = Brand.signal});

  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MarkPainter(accent: accent, outline: Brand.textPrimary),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.accent, required this.outline});

  final Color accent;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is expressed as a fraction of the box, so the mark is
    // resolution-independent and can be asked for at any size.
    final u = size.width / 28;
    final stroke = 1.6 * u;

    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        stroke / 2 + 3.5 * u,
        stroke / 2,
        size.width - stroke - 7 * u,
        size.height - stroke,
      ),
      Radius.circular(4.5 * u),
    );

    canvas.drawRRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = outline,
    );

    // Three element rows. The middle one is the selected target, so it is
    // filled with the accent and runs wider than the rows around it: the mark
    // reads as "this row, out of the ones on screen".
    final rows = <_Row>[
      _Row(top: 7.5 * u, width: 8 * u, accent: false),
      _Row(top: 12.5 * u, width: 13 * u, accent: true),
      _Row(top: 17.5 * u, width: 6 * u, accent: false),
    ];

    for (final row in rows) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(7.5 * u, row.top, row.width, 3 * u),
          Radius.circular(1.5 * u),
        ),
        Paint()
          ..color = row.accent ? accent : outline.withValues(alpha: 0.45)
          ..style = PaintingStyle.fill,
      );
    }

    // The tap: a small accent square hanging off the selected row, past the
    // frame edge, which is what stops the mark from reading as a list icon.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(21 * u, 11 * u, 6 * u, 6 * u),
        Radius.circular(2 * u),
      ),
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.outline != outline;
}

class _Row {
  const _Row({required this.top, required this.width, required this.accent});
  final double top;
  final double width;
  final bool accent;
}

/// Mark plus wordmark. The "3" is set in the data face inside an accent tile —
/// the version is machine information, not part of the name.
class UltronWordmark extends StatelessWidget {
  const UltronWordmark({super.key, this.markSize = 24});

  final double markSize;

  static const Key wordKey = Key('ultron-wordmark-text');

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UltronMark(size: markSize),
        const SizedBox(width: Space.x1),
        const Text(
          'ULTRON',
          key: wordKey,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
            color: Brand.textPrimary,
          ),
        ),
        const SizedBox(width: Space.half + 2),
        Container(
          width: 17,
          height: 17,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Brand.signal,
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          child: const Text(
            '3',
            style: TextStyle(
              fontFamily: AppType.mono,
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w700,
              color: Brand.onSignal,
            ),
          ),
        ),
      ],
    );
  }
}
