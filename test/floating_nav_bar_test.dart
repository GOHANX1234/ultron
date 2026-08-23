import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/widgets/floating_nav_bar.dart';

void noop() {}
void noop2() {}

Widget _wrap({bool busy = false, VoidCallback? onNewChat}) {
  return MaterialApp(
    home: Scaffold(
      drawer: const Drawer(child: SizedBox()),
      body: FloatingNavBar(
        isDark: true,
        busy: busy,
        onNewChat: onNewChat ?? noop,
        onSettings: noop2,
      ),
    ),
  );
}

void main() {
  testWidgets('brand stays optically centred despite uneven actions',
      (tester) async {
    await tester.pumpWidget(_wrap());

    final width = tester.getSize(find.byType(MaterialApp)).width;
    final brandCentre = tester.getCenter(find.text('Ultron-3')).dx;

    // One action on the left, two on the right: a Row of Spacers would push the
    // brand left of centre, which is the layout bug this widget exists to fix.
    expect(brandCentre, closeTo(width / 2, 1.0));
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
