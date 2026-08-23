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
  testWidgets('brand is centred in the gap between the action clusters',
      (tester) async {
    await tester.pumpWidget(_wrap());

    // The bar has one action on the left and two on the right, so a
    // card-centred brand reads as pushed right. The invariant is that the
    // brand is centred in the free space *between* the clusters: equal gaps to
    // the menu button on its left and the new-chat button on its right.
    final brand = tester.getRect(find.byKey(FloatingNavBar.brandKey));
    final menu = tester.getRect(find.byIcon(Icons.menu_rounded));
    final newChat = tester.getRect(find.byIcon(Icons.add_comment_outlined));

    expect(brand.center.dx, closeTo((menu.right + newChat.left) / 2, 1.0));

    // ...and it must genuinely sit between them, not merely measure centred
    // while overlapping.
    expect(brand.left, greaterThan(menu.right));
    expect(brand.right, lessThan(newChat.left));

    // The shift is leftward of the card's own centre, which is the point of it.
    final card = tester.getRect(find.byType(BackdropFilter));
    expect(brand.center.dx, lessThan(card.center.dx));
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
