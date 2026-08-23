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

  testWidgets('avatar asset is a real GIF in the bundle', (tester) async {
    final bytes = await rootBundle.load(ThinkingAvatar.assetPath);
    final header = bytes.buffer.asUint8List(0, 6);

    expect(String.fromCharCodes(header), anyOf('GIF89a', 'GIF87a'));
    expect(bytes.lengthInBytes, greaterThan(1024));
  });
}
