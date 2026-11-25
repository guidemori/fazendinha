import 'package:fazendinhaidle/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('planta direto e completa o ciclo de colher, vender e preparar',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final player = Player.initial();
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pumpAndSettle();

    final plots = find.byType(PlotWidget);
    expect(plots, findsNWidgets(4));
    await tester.tap(find.text('Alface'));
    await tester.pumpAndSettle();
    expect(find.byType(CropSelectorSheet), findsOneWidget);
    await tester.tap(find.text('Alface').last);
    await tester.pumpAndSettle();
    await tester.tap(plots.first);
    await tester.pump();
    await tester.tap(plots.at(1));
    await tester.pump();
    expect(find.byType(CropSelectorSheet), findsNothing);
    expect(player.coins, 5);
    final first = player.plots.first;
    first.plantedAt = DateTime.now().subtract(const Duration(minutes: 1));
    await tester.tap(find.text('Colher'));
    await tester.tap(plots.first);
    await tester.pump();
    expect(player.basketCount, 1);
    expect(player.coins, 5);
    expect(find.text('12/100 XP'), findsOneWidget);
    expect(first.tilled, isFalse);

    await tester.tap(find.text('Vender 1'));
    await tester.pump();
    expect(player.basketCount, 0);
    expect(player.coins, 17);

    await tester.tap(find.text('Preparar'));
    await tester.tap(plots.first);
    await tester.pump();
    expect(first.tilled, isTrue);
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

    await tester.tap(find.text('Alface'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cenoura'));
    await tester.pumpAndSettle();
    expect(find.text('Requer nível 2 para plantar Cenoura.').hitTestable(),
        findsOneWidget);

    Navigator.of(tester.element(find.byType(CropSelectorSheet))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PlotWidget).first);
    await tester.pumpAndSettle();
    expect(find.text('Moedas insuficientes! Faltam 5.'), findsOneWidget);
    expect(player.plots.first.isEmpty, isTrue);

    await tester.tap(find.byTooltip('Melhorias'));
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
    final plot = restored.plots.first;
    expect(plot.isEmpty, isTrue);
    expect(plot.tilled, isFalse);
    expect(restored.plant(plot, crop, ready), isFalse);
    expect(restored.basketCount, 1);
    expect(restored.levelProgress, closeTo(.14, .01));
    final reloaded = Player.fromMap(restored.toMap());
    expect(reloaded.plots.first.tilled, isFalse);
    final coins = reloaded.coins;
    expect(reloaded.sellBasket(), reloaded.effectiveSellValue(crop));
    expect(reloaded.coins, coins + reloaded.effectiveSellValue(crop));
    expect(reloaded.basketCount, 0);
  });
}
