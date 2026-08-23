import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/services/chat_history_service.dart';
import 'package:private_agent/widgets/app_drawer.dart';

ChatSession _session(String id, {String title = '', DateTime? at}) {
  return ChatSession(
    id: id,
    title: title,
    timestamp: at ?? DateTime.now(),
    messages: const [],
  );
}

/// Pumps the drawer already open, so the tests exercise the same tree the user
/// sees. `loadSessions`/`deleteSession` are injected because the real ones read
/// the app documents directory, which does not exist under `flutter test`.
Widget _wrap({
  required List<ChatSession> sessions,
  String currentSessionId = 'none',
  void Function(ChatSession)? onOpenSession,
  void Function(String)? onSessionDeleted,
  VoidCallback? onNewChat,
  Future<void> Function(String)? deleteSession,
}) {
  return MaterialApp(
    home: Scaffold(
      drawer: AppDrawer(
        isDark: true,
        currentSessionId: currentSessionId,
        onNewChat: onNewChat ?? () {},
        onOpenSession: onOpenSession ?? (_) {},
        onSessionDeleted: onSessionDeleted ?? (_) {},
        onOpenTaskHistory: () {},
        onOpenSettings: () {},
        loadSessions: () async => sessions,
        deleteSession: deleteSession ?? (_) async {},
      ),
      body: const SizedBox(),
    ),
  );
}

Future<void> _open(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('groups sessions by calendar-day distance', (tester) async {
    final now = DateTime.now();
    await _open(
      tester,
      _wrap(
        sessions: [
          _session('a', title: 'Today chat', at: now),
          _session('b',
              title: 'Yesterday chat',
              at: DateTime(now.year, now.month, now.day - 1, 9)),
          _session('c',
              title: 'Old chat',
              at: DateTime(now.year, now.month, now.day - 40, 9)),
        ],
      ),
    );

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Older'), findsOneWidget);
    expect(find.text('Today chat'), findsOneWidget);
  });

  testWidgets('an empty title still renders a readable row', (tester) async {
    // The old drawer printed session.title straight through, so a chat whose
    // first message never produced a title showed a blank line.
    await _open(tester, _wrap(sessions: [_session('a')]));
    expect(find.text('Untitled chat'), findsOneWidget);
  });

  testWidgets('shows the empty state when there is no history',
      (tester) async {
    await _open(tester, _wrap(sessions: const []));
    expect(find.byKey(AppDrawer.sessionListKey), findsNothing);
    expect(find.textContaining('No chats yet'), findsOneWidget);
  });

  testWidgets('tapping a session closes the drawer and reports it',
      (tester) async {
    ChatSession? opened;
    await _open(
      tester,
      _wrap(
        sessions: [_session('a', title: 'Pick me')],
        onOpenSession: (s) => opened = s,
      ),
    );

    await tester.tap(find.text('Pick me'));
    await tester.pumpAndSettle();

    expect(opened?.id, 'a');
    expect(tester.state<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen,
        isFalse);
  });

  testWidgets('delete asks first and cancelling changes nothing',
      (tester) async {
    var deleted = 0;
    await _open(
      tester,
      _wrap(
        sessions: [_session('a', title: 'Keep me')],
        deleteSession: (_) async => deleted++,
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Delete chat?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(deleted, 0);
    expect(find.text('Keep me'), findsOneWidget);
  });

  testWidgets('confirming delete removes the row and notifies the host',
      (tester) async {
    final sessions = [_session('a', title: 'Bin me')];
    String? notified;

    await _open(
      tester,
      _wrap(
        sessions: sessions,
        onSessionDeleted: (id) => notified = id,
        deleteSession: (id) async => sessions.removeWhere((s) => s.id == id),
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(notified, 'a');
    // The list is re-read after the delete, so the row is gone without the
    // host having to rebuild the drawer.
    expect(find.text('Bin me'), findsNothing);
  });

  testWidgets('new chat closes the drawer', (tester) async {
    var taps = 0;
    await _open(
      tester,
      _wrap(sessions: const [], onNewChat: () => taps++),
    );

    await tester.tap(find.text('New chat'));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(tester.state<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen,
        isFalse);
  });
}
