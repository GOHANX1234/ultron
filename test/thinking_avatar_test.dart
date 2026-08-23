import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/widgets/thinking_avatar.dart';

void main() {
  testWidgets('thinking avatar renders the bundled animation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ThinkingAvatar())),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, ThinkingAvatar.assetPath);
    expect(image.gaplessPlayback, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('avatar asset is an animated WebP in the bundle', (tester) async {
    final bytes = await rootBundle.load(ThinkingAvatar.assetPath);
    final header = bytes.buffer.asUint8List(0, 16);

    // RIFF container with a WEBP fourcc, and an "ANIM"/"ANMF" chunk marking it
    // as animated rather than a single still frame.
    expect(String.fromCharCodes(header.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(header.sublist(8, 12)), 'WEBP');
    expect(String.fromCharCodes(header.sublist(12, 16)), 'VP8X');

    final all = bytes.buffer.asUint8List();
    expect(String.fromCharCodes(all.sublist(0, 64)), contains('ANIM'));
    expect(bytes.lengthInBytes, greaterThan(1024));
  });
}
