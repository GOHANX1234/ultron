import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/widgets/floating_nav_bar.dart';

void noop() {}
void noop2() {}

Widget _wrap({bool busy = false, VoidCallback? onNewChat}) {
  return MaterialApp(
    home: Scaffold(
      drawer: const Drawer(child: SizedBox()),
      // A Column, so the bar takes its intrinsic height the way it does on the
      // real screen. Straight in `body` it would be stretched to fill the
      // viewport, which is not the geometry being asserted below.
      body: Column(
        children: [
          FloatingNavBar(
            isDark: true,
            busy: busy,
            onNewChat: onNewChat ?? noop,
            onSettings: noop2,
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('brand stays optically centred despite uneven actions',
      (tester) async {
    await tester.pumpWidget(_wrap());

    // Measured against the bar's own card, not the viewport: that is the actual
    // invariant, and it does not assume anything about the test surface size or
    // the card's margins. It measures the whole brand row rather than the
    // wordmark, whose centre sits ~19px right of the row's because of the logo.
    final card = tester.getRect(find.byType(BackdropFilter));
    final brand = tester.getRect(find.byKey(FloatingNavBar.brandKey));

    // One action on the left, two on the right: a Row of Spacers would push the
    // brand left of centre, which is the layout bug this widget exists to fix.
    expect(brand.center.dx, closeTo(card.center.dx, 1.0));

    // ...and it must genuinely sit between the two action clusters, not merely
    // measure centred while overlapping them.
    expect(brand.left,
        greaterThan(tester.getRect(find.byIcon(Icons.menu_rounded)).right));
    expect(brand.right,
        lessThan(tester.getRect(find.byIcon(Icons.add_comment_outlined)).left));
  });

  testWidgets('renders without raising', (tester) async {
    // Split out of the centring test so a failure here points at the render
    // pass (the asset, the blur, an overflow) rather than at the layout maths.
    await tester.pumpWidget(_wrap());
    expect(tester.takeException(), isNull);
  });

  testWidgets('new chat is inert while busy', (tester) async {
    var taps = 0;
    void onTap() => taps++;

    await tester.pumpWidget(_wrap(busy: true, onNewChat: onTap));
    await tester.tap(find.byIcon(Icons.add_comment_outlined));
    await tester.pump();
    expect(taps, 0);

    await tester.pumpWidget(_wrap(busy: false, onNewChat: onTap));
    await tester.tap(find.byIcon(Icons.add_comment_outlined));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('menu action opens the enclosing drawer', (tester) async {
    await tester.pumpWidget(_wrap());
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
    expect(scaffold.isDrawerOpen, isFalse);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    expect(scaffold.isDrawerOpen, isTrue);
  });

  test('equal field values compare equal so setState can skip the subtree', () {
    // Element.updateChild short-circuits when the new widget == the old one.
    // That is the whole reason this widget is not a method on HomeScreen: the
    // chat screen calls setState for every streamed token.
    const a = FloatingNavBar(
      isDark: true,
      busy: false,
      onNewChat: noop,
      onSettings: noop2,
    );
    const b = FloatingNavBar(
      isDark: true,
      busy: false,
      onNewChat: noop,
      onSettings: noop2,
    );
    const busyOne = FloatingNavBar(
      isDark: true,
      busy: true,
      onNewChat: noop,
      onSettings: noop2,
    );

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
    expect(a, isNot(equals(busyOne)));
  });
}
