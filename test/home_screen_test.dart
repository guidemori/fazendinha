import 'package:fazendinhaidle/main.dart';
import 'package:flutter/material.dart';
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

  testWidgets('mostra o motivo de ações indisponíveis em paisagem',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final player = Player.initial()..coins = 0;
    final growingPlot = player.plots.last;
    growingPlot.plantedCrop = CropType.alface;
    growingPlot.plantedAt = DateTime.now();
    growingPlot.growDuration = const Duration(minutes: 10);

    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.tap(find.byType(PlotWidget).last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Alface crescendo · falta'), findsOneWidget);

    await tester.tap(find.byType(NewPlotTile));
    await tester.pumpAndSettle();
    expect(
        find.text('Moedas insuficientes! Faltam 🪙 100 para o novo canteiro.'),
        findsOneWidget);

    await tester.tap(find.byType(PlotWidget).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cenoura'));
    await tester.pumpAndSettle();
    expect(find.text('Requer nível 2 para plantar Cenoura.').hitTestable(),
        findsOneWidget);

    await tester.tap(find.text('Alface'));
    await tester.pumpAndSettle();
    expect(find.text('Moedas insuficientes! Faltam 🪙 5.').hitTestable(),
        findsOneWidget);
    expect(player.plots.first.isEmpty, isTrue);

    Navigator.of(tester.element(find.byType(CropSelectorSheet))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Upgrades'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '🪙 100'));
    await tester.pumpAndSettle();
    expect(find.text('Moedas insuficientes! Faltam 🪙 100.').hitTestable(),
        findsOneWidget);
    expect(player.coins, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('libera canteiro salvo sem data de plantio', () {
    final player = Player.initial();
    final saved = player.toMap();
    final plots = saved['plots'] as List<Map<String, dynamic>>;
    plots.first['plantedCrop'] = CropType.alface.name;
    plots.first.remove('plantedAt');

    final restored = Player.fromMap(saved);
    final plot = restored.plots.first;
    expect(plot.id, player.plots.first.id);
    expect(plot.isEmpty, isTrue);
    expect(restored.plant(plot, Crops.of(CropType.alface), DateTime.utc(2026)),
        isTrue);
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
