import 'dart:convert';

import 'package:fazendinhaidle/main.dart';
import 'package:fazendinhaidle/visit_rewards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

    await tester.tap(find.byTooltip('Regar'));
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
    await tester.tap(find.byTooltip('Sementes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alface'));
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();
    expect(find.text('Segure para plantar Alface'), findsOneWidget);
    expect(player.seeds[CropType.alface], 1);

    var hold = await tester.startGesture(tester.getCenter(tile));
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('Plantando semente…'), findsOneWidget);
    await hold.up();
    await tester.pump(Plot.plantingDuration);
    expect(plot.isEmpty, isTrue);
    expect(player.seeds[CropType.alface], 1);

    hold = await tester.startGesture(tester.getCenter(tile));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(Plot.plantingDuration);
    expect(plot.stage(DateTime.now()), 1);
    expect(player.seeds[CropType.alface], isNull);
    await hold.up();
    await tester.pump();

    await tester.tap(find.byTooltip('Colher'));
    await tester.pump();
    final center = tester.getCenter(tile);
    final inspection = await tester.startGesture(center - const Offset(48, 0));
    await inspection.moveTo(center);
    await inspection.moveBy(const Offset(2, 0));
    await tester.pump();
    expect(find.textContaining('Colheita em '), findsOneWidget);
    await inspection.up();
    expect(plot.isPlanted, isTrue);

    expect(player.coins, 10);

    plot.plantedAt = DateTime.now().subtract(const Duration(minutes: 1));
    await tester.tap(find.byTooltip('Colher'));
    await tester.tap(tile);
    await tester.pump();
    expect(find.text('12/100 XP'), findsOneWidget);
    expect(player.coins, 10);
    await tester.tap(find.byTooltip('Armazém 1'));
    await tester.pumpAndSettle();
    expect(find.text('Quantidade: 1'), findsOneWidget);
    await tester.tap(find.text('Vender por 12'));
    await tester.pumpAndSettle();
    expect(player.coins, 22);
    expect(player.basketCount, 0);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Enxada'));
    await tester.tap(tile);
    await tester.pump();
    expect(plot.tilled, isTrue);
    expect(plot.isWet(DateTime.now()), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('registra e resgata a visita usando a resposta do servidor',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final player = Player.initial();
    final calls = <String>[];
    final api = VisitRewardsApi(
      Uri.parse('https://visits.example/'),
      'test-key',
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer test-key');
        calls.add(request.url.path);
        if (request.url.path == '/v2/visits') {
          expect(request.body, isEmpty);
          return http.Response(jsonEncode(visitResponse(1, 0)), 200);
        }
        expect(jsonDecode(request.body), {'date': '2026-01-01'});
        return http.Response(jsonEncode(visitResponse(1, 1)), 200);
      }),
    );
    await tester.pumpWidget(FazendinhaApp(player: player, visitsApi: api));
    await tester.pumpAndSettle();
    expect(calls, ['/v2/visits']);
    await tester.tap(find.text('Avisos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login diário'));
    await tester.pumpAndSettle();
    expect(find.text('Sequência: 1 dia(s) consecutivo(s)'), findsOneWidget);
    await tester.tap(find.text('Resgatar'));
    await tester.pumpAndSettle();
    expect(find.text('Resgatado hoje'), findsOneWidget);
    expect(calls, ['/v2/visits', '/v2/visits', '/v2/claims']);
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

  test('reaplica resgates confirmados sem duplicar saldo ou estoque', () {
    final legacy = Player.initial().toMap()
      ..['coins'] = 27
      ..['seeds'] = {'alface': 1}
      ..['claimedVisitDays'] = 1;
    final player = Player.fromMap(legacy);
    expect(player.appliedDailyLoginSeeds, 0);
    expect(player.coins, 27);

    player.applyVisitRewards(VisitSnapshot.fromJson(visitResponse(2, 1)));
    final restored = Player.fromMap(player.toMap());
    restored.applyVisitRewards(VisitSnapshot.fromJson(visitResponse(2, 2)));
    restored.applyVisitRewards(VisitSnapshot.fromJson(visitResponse(2, 1)));
    restored.applyVisitRewards(VisitSnapshot.fromJson(visitResponse(2, 2)));
    expect(restored.appliedDailyLoginSeeds, 3);
    expect(restored.coins, 27 + 12 + 24);
    expect(restored.seeds[CropType.alface], 4);
  });

  test('restaura estoque, solo e progresso de XP com saves anteriores', () {
    final player = Player.initial()..xp = 140;
    final data = player.toMap()
      ..remove('seeds')
      ..remove('appliedServerVisitRewards');
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

Map<String, dynamic> visitResponse(int visited, int claimed) => {
      'event': 'daily-login-v2',
      'date': '2026-01-01',
      'streak': visited,
      'rewardDay': visited,
      'claimable': claimed < visited,
      'claimedToday': claimed == visited,
      'coinsPaid': 12 * claimed * (claimed + 1) ~/ 2,
      'seedsPaid': claimed * (claimed + 1) ~/ 2,
      'rewards': [
        for (var day = 1; day <= 7; day++) {'coins': day * 12, 'seeds': day},
      ],
    };
