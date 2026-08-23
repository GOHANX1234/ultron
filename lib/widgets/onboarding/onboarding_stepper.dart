import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';

/// A real three-step stepper: numbered tiles, connectors that fill in behind
/// you, and a label on the step you are actually on.
///
/// It replaces a floating "Step 2 of 3" pill and a row of glowing tab chips.
/// Two things that fixes: the pill told you where you were without telling you
/// what was left, and the chips looked equally tappable in both directions when
/// only backwards navigation is allowed. Here a tile is tappable exactly when
/// it is behind you, and a completed step is marked with a check rather than
/// with a colour change you have to learn.
///
/// Only the current step is labelled. Three labels fit on a 360dp screen at the
/// default text size and stop fitting at the first accessibility step up, so the
/// label travels with the position instead.
class OnboardingStepper extends StatelessWidget {
  const OnboardingStepper({
    super.key,
    required this.labels,
    required this.current,
    required this.onSelect,
  });

  final List<String> labels;
  final int current;

  /// Called with the index of a step the user is allowed to return to. Steps at
  /// or beyond [current] never call it.
  final ValueChanged<int> onSelect;

  static Key tileKey(int index) => Key('onboarding-step-$index');

  static const double _tile = 26;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    for (var i = 0; i < labels.length; i++) {
      if (i > 0) {
        children.add(
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: Space.x1),
              color: i <= current ? Brand.signal : Brand.line,
            ),
          ),
        );
      }
      children.add(_tileFor(i));
    }

    return Semantics(
      container: true,
      label: 'Step ${current + 1} of ${labels.length}, ${labels[current]}',
      child: ExcludeSemantics(child: Row(children: children)),
    );
  }

  Widget _tileFor(int index) {
    final done = index < current;
    final isCurrent = index == current;

    final Color fill;
    final Color border;
    final Color foreground;
    if (isCurrent) {
      fill = Brand.signal;
      border = Brand.signal;
      foreground = Brand.onSignal;
    } else if (done) {
      fill = Colors.transparent;
      border = Brand.signal;
      foreground = Brand.signal;
    } else {
      fill = Colors.transparent;
      border = Brand.line;
      foreground = Brand.textTertiary;
    }

    final tile = Container(
      key: tileKey(index),
      width: _tile,
      height: _tile,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: Corner.tickR,
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 15, color: Brand.signal)
          : Text(
              // Zero-padded, in the data face: the step number is an index, not
              // a headline.
              '0${index + 1}',
              style: AppType.dataSmall.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
    );

    return InkWell(
      onTap: done ? () => onSelect(index) : null,
      borderRadius: Corner.tickR,
      child: Row(
        children: [
          tile,
          if (isCurrent) ...[
            const SizedBox(width: Space.x1),
            Text(
              labels[index].toUpperCase(),
              style: AppType.eyebrow.copyWith(color: Brand.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}
