import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/models/chat_message.dart';
import 'package:private_agent/widgets/message_bubble.dart';

Widget _wrap(ChatMessage message, {bool use24h = false}) {
  return MaterialApp(
    home: Scaffold(
      // Copy the ambient MediaQuery rather than building a bare MediaQueryData:
      // MessageBubble sizes itself from MediaQuery.sizeOf, which would be
      // Size.zero and overflow.
      body: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: use24h),
          child: MessageBubble(message: message),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('timestamp is rendered in the device local zone', (tester) async {
    // A UTC timestamp, as ChatMessage.fromJson would produce for history that
    // was persisted from a UTC DateTime.
    final utc = DateTime.utc(2026, 1, 2, 22, 15);
    final expected = TimeOfDay.fromDateTime(utc.toLocal());

    await tester.pumpWidget(
      _wrap(
        ChatMessage(role: 'user', content: 'hello', timestamp: utc),
        use24h: true,
      ),
    );

    final hh = expected.hour.toString().padLeft(2, '0');
    final mm = expected.minute.toString().padLeft(2, '0');
    expect(find.text('$hh:$mm'), findsOneWidget);
  });

  testWidgets('timestamp honours the 12-hour device preference',
      (tester) async {
    final ts = DateTime(2026, 1, 2, 14, 5);

    await tester.pumpWidget(
      _wrap(
        ChatMessage(role: 'user', content: 'hello', timestamp: ts),
        use24h: false,
      ),
    );

    expect(find.textContaining('2:05'), findsOneWidget);
    expect(find.text('14:05'), findsNothing);
  });

  testWidgets('fromJson normalises a UTC timestamp to local', (tester) async {
    final utc = DateTime.utc(2026, 1, 2, 22, 15);
    final restored = ChatMessage.fromJson({
      'role': 'assistant',
      'content': 'hi',
      'timestamp': utc.toIso8601String(),
      'actionResult': null,
    });

    expect(restored.timestamp.isUtc, isFalse);
    expect(restored.timestamp, equals(utc.toLocal()));
  });
}
