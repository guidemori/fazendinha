import 'package:fazendinhaidle/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('recalcula o tamanho do banner com até três retentativas',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const channel = MethodChannel('plugins.flutter.io/google_mobile_ads');
    final messenger = tester.binding.defaultBinaryMessenger;
    var queries = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'AdSize#getAnchoredAdaptiveBannerAdSize');
      queries++;
      if (queries.isOdd) throw PlatformException(code: 'size-unavailable');
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(FazendinhaApp(player: Player.initial()));
    await tester.pump();
    expect(queries, 1);

    for (final (index, seconds) in [30, 60, 120].indexed) {
      await tester.pump(Duration(seconds: seconds - 1));
      expect(queries, index + 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(queries, index + 2);
    }

    await tester.pump(const Duration(minutes: 5));
    expect(queries, 4);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
