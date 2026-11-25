import 'package:fazendinhaidle/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('abre a seleção de cultura por toque em paisagem',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(FazendinhaApp(player: Player.initial()));
    await tester.pumpAndSettle();

    final plots = find.byType(PlotWidget);
    expect(plots, findsNWidgets(4));
    await tester.tap(plots.first);
    await tester.pumpAndSettle();
    expect(find.byType(CropSelectorSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('restaura cultivo e upgrades e contabiliza o crescimento offline', () {
    final start = DateTime.utc(2026, 1, 1);
    final player = Player.initial()..coins = 1000;
    expect(player.buyPlot(), isTrue);
    expect(player.buyUpgrade(UpgradeType.sellBoost), isTrue);
    final crop = Crops.of(CropType.alface);
    expect(player.plant(player.plots.first, crop, start), isTrue);

    final restored = Player.fromMap(player.toMap());
    expect(restored.plotCount, 5);
    expect(restored.sellBoostLevel, 1);
    expect(restored.harvest(restored.plots.first, start), 0);
    final ready = start.add(crop.growTime);
    expect(restored.harvest(restored.plots.first, ready),
        restored.effectiveSellValue(crop));
    expect(restored.plots.first.isEmpty, isTrue);
  });
}
