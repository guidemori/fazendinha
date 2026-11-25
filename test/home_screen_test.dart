import 'package:fazendinhaidle/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rega, planta, colhe no armazém e vende em paisagem',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final player = Player.initial();
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pumpAndSettle();
    final tile = find.byType(PlotWidget).first;
    final plot = player.plots.first;
    await tester.tap(tile);
    await tester.pump();
    expect(find.text('Terra seca · regue antes de plantar'), findsOneWidget);

    await tester.tap(find.text('Regar'));
    await tester.tap(tile);
    await tester.pump();
    expect(find.text('Regando terra…'), findsOneWidget);
    plot.wateredAt = DateTime.now().subtract(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Terra úmida · pronta para plantar'), findsOneWidget);

    await tester.tap(find.text('Loja'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alface'));
    await tester.pumpAndSettle();
    expect(player.coins, 10);
    expect(player.seeds[CropType.alface], 1);
    await tester.tap(find.text('Sementes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alface'));
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();
    expect(find.text('Plantando semente…'), findsOneWidget);
    expect(player.seeds[CropType.alface], isNull);
    expect(player.coins, 10);

    plot.plantedAt = DateTime.now().subtract(const Duration(minutes: 1));
    await tester.tap(find.text('Colher'));
    await tester.tap(tile);
    await tester.pump();
    expect(find.text('12/100 XP'), findsOneWidget);
    expect(player.coins, 10);
    await tester.tap(find.text('Armazém 1'));
    await tester.pumpAndSettle();
    expect(find.text('Quantidade: 1'), findsOneWidget);
    await tester.tap(find.text('Vender por 12'));
    await tester.pumpAndSettle();
    expect(player.coins, 22);
    expect(player.basketCount, 0);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enxada'));
    await tester.tap(tile);
    await tester.pump();
    expect(plot.tilled, isTrue);
    expect(plot.isWet(DateTime.now()), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('permite resgatar a primeira visita no aparelho', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final player = Player.initial();
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Visitas de 7 dias'));
    await tester.pumpAndSettle();
    expect(find.text('1/7 dias registrados'), findsOneWidget);
    await tester.tap(find.text('Resgatar'));
    await tester.pumpAndSettle();
    expect(find.text('Resgatado'), findsOneWidget);
    expect(player.coins, 27);
    expect(player.seeds[CropType.alface], 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('rega persiste, e a enxada libera semente morta após prazo offline', () {
    final start = DateTime.utc(2026, 1, 1);
    final player = Player.initial();
    final crop = Crops.of(CropType.alface);
    final plot = player.plots.first;
    expect(player.buySeed(crop.type), isTrue);
    expect(player.plant(plot, crop, start), isFalse);
    expect(plot.water(start), isTrue);
    final restored = Player.fromMap(player.toMap());
    final wetPlot = restored.plots.first;
    expect(wetPlot.isWatering(start), isTrue);
    final wetAt = start.add(Plot.wateringDuration);
    expect(restored.plant(wetPlot, crop, wetAt), isTrue);
    final readyAt = wetAt.add(Plot.plantingDuration).add(crop.growTime);
    expect(wetPlot.isReady(readyAt), isTrue);
    expect(wetPlot.hoe(readyAt), isFalse);
    final expiry = readyAt.add(crop.harvestWindow);
    expect(wetPlot.isDead(expiry), isTrue);
    expect(restored.harvest(wetPlot, expiry), 0);
    expect(wetPlot.hoe(expiry), isTrue);
    expect(wetPlot.isEmpty, isTrue);
    expect(wetPlot.isWet(expiry), isFalse);
  });

  test('a saúde cai mais devagar em culturas com maturação mais longa', () {
    final start = DateTime.utc(2026, 1, 1);
    var previousWindow = Duration.zero;

    for (final type in CropType.values) {
      final crop = Crops.of(type);
      final effectiveDuration = crop.growTime ~/ 2;
      final matureAt = start.add(effectiveDuration);
      final plot = Plot(id: type.name)
        ..plantedCrop = type
        ..plantedAt = start
        ..growDuration = effectiveDuration;
      final restored = Plot.fromMap(plot.toMap());

      expect(crop.harvestWindow, greaterThan(previousWindow));
      expect(crop.harvestWindow, lessThanOrEqualTo(const Duration(hours: 48)));
      expect(restored.health(start), 1);
      expect(restored.health(matureAt), 1);
      expect(restored.health(matureAt.add(crop.harvestWindow ~/ 2)), .5);
      final expiresAt = matureAt.add(crop.harvestWindow);
      expect(restored.isReady(expiresAt.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(restored.isDead(expiresAt), isTrue);
      previousWindow = crop.harvestWindow;
    }

    const slowCrop = Crop(
      type: CropType.cana,
      seedCost: 1,
      sellValue: 1,
      growTime: Duration(hours: 2),
      unlockLevel: 1,
    );
    expect(slowCrop.harvestWindow, const Duration(hours: 48));
  });

  test('fertilizante reduz o tempo restante e persiste o consumo', () {
    final start = DateTime.utc(2026, 1, 1);
    final player = Player.initial();
    final plot = player.plots.first;
    final crop = Crops.of(CropType.alface);
    expect(player.buyFertilizer(), isTrue);
    expect(player.buySeed(crop.type), isTrue);
    expect(player.coins, 2);
    expect(player.fertilize(plot, start), isFalse);
    expect(plot.water(start), isTrue);
    final planting = start.add(Plot.wateringDuration);
    expect(player.plant(plot, crop, planting), isTrue);
    expect(player.fertilize(plot, planting), isFalse);

    final now = plot.plantedAt!.add(const Duration(seconds: 10));
    expect(player.fertilize(plot, now), isTrue);
    final restored = Player.fromMap(player.toMap());
    final restoredPlot = restored.plots.first;
    expect(restored.fertilizer, 0);
    expect(restoredPlot.growDuration, const Duration(seconds: 25));
    final ready = restoredPlot.plantedAt!.add(const Duration(seconds: 25));
    expect(restoredPlot.isReady(ready), isTrue);
    expect(restored.buyFertilizer(), isFalse);

    restored.fertilizer = 1;
    expect(restored.fertilize(restoredPlot, ready), isFalse);
    expect(restored.fertilizer, 1);
  });

  test('recompensas crescem e cada data e resgate contam uma vez', () {
    final first = DateTime(2026, 1, 1, 10);
    final player = Player.initial();
    expect(player.recordVisit(first), isTrue);
    expect(player.claimVisitReward(1), isTrue);
    expect(player.claimVisitReward(1), isFalse);
    expect(player.recordVisit(first.add(const Duration(hours: 2))), isFalse);
    final restored = Player.fromMap(player.toMap());
    expect(restored.recordVisit(first), isFalse);
    expect(restored.recordVisit(first.add(const Duration(days: 1))), isTrue);
    expect(restored.claimVisitReward(2), isTrue);
    expect(restored.coins, 15 + 12 + 24);
    expect(restored.seeds[CropType.alface], 3);
  });

  test('visita exige outra data e intervalo de 23 horas após restaurar', () {
    final first = DateTime(2026, 1, 1, 23);
    final player = Player.initial();
    expect(player.recordVisit(first), isTrue);

    final restored = Player.fromMap(player.toMap());
    expect(restored.recordVisit(first.add(const Duration(hours: 1))), isFalse);
    expect(
        restored.recordVisit(first.subtract(const Duration(days: 1))), isFalse);
    final next = first.add(Player.minVisitGap);
    expect(restored.recordVisit(next), isTrue);
    expect(restored.visitDays, 2);

    final legacy = Player.fromMap(player.toMap()..remove('lastVisitAbsolute'));
    expect(legacy.recordVisit(first), isFalse);
    expect(legacy.recordVisit(first.add(const Duration(hours: 1))), isTrue);
    expect(legacy.lastVisitAbsolute, isNotNull);
  });

  test('restaura estoque, solo e progresso de XP com saves anteriores', () {
    final player = Player.initial()..xp = 140;
    final data = player.toMap()
      ..remove('seeds')
      ..remove('visitDays');
    final plots = data['plots'] as List<Map<String, dynamic>>;
    plots.first
      ..remove('wateredAt')
      ..['plantedCrop'] = CropType.alface.name
      ..remove('plantedAt');
    final restored = Player.fromMap(data);
    expect(restored.plots.first.isEmpty, isTrue);
    expect(restored.plots.first.isWet(DateTime.now()), isFalse);
    expect(restored.seeds, isEmpty);
    expect(restored.currentLevelXp, 40);
    expect(restored.levelXpGoal, 200);
    expect(restored.levelProgress, .2);
  });
}
