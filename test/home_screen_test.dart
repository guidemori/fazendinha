import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:fazendinhaidle/main.dart';
import 'package:fazendinhaidle/visit_rewards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('preço de venda inclui bônus de 3% do lucro por hora de maturação', () {
    final saleValues = CropType.values.map((type) => Crops.of(type).sellValue);
    expect(saleValues, [8, 40, 191, 322, 556, 1319, 2265, 3982]);
  });

  for (final type in CropType.values) {
    testWidgets('adubo acelera o visual de ${type.label} durante o crescimento',
        (tester) async {
      final player = Player.initial()..fertilizer = 1;
      final duration = Crops.of(type).growTime;
      final plot = player.plots.first
        ..plantedCrop = type
        ..plantedAt = DateTime.now().subtract(duration ~/ 8)
        ..growDuration = duration;
      await tester.pumpWidget(FazendinhaApp(player: player));
      await tester.pumpAndSettle();

      final tile = find.byType(PlotWidget).first;
      final cropImage = find.descendant(of: tile, matching: find.byType(Image));
      final originalAsset = tester.widget<Image>(cropImage).image;
      final originalWidth = tester.getSize(cropImage).width;
      await tester.tap(find.byTooltip('Adubo · 1'));
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(player.fertilizer, 0);
      expect(plot.growDuration!, lessThan(duration));
      expect(tester.widget<Image>(cropImage).image, originalAsset);
      expect(tester.getSize(cropImage).width, greaterThan(originalWidth));

      plot.plantedAt = DateTime.now().subtract(plot.growDuration!);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(plot.stage(DateTime.now()), GameConstants.cropStageCount);
      final matureAsset = tester.widget<Image>(cropImage).image as AssetImage;
      expect(matureAsset.assetName, endsWith('/${type.name}_4.webp'));
      expect(find.text('${type.label} pronta para colher'), findsOneWidget);
    });
  }

  testWidgets('compra adubo direto na loja e atualiza o estoque',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 360);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final player = Player.initial()..coins = 65;
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pumpAndSettle();
    final toolbarAdubo = find.descendant(
      of: find.byTooltip('Adubo · 0'),
      matching: find.byType(Image),
    );
    final toolbarAsset = tester.widget<Image>(toolbarAdubo).image;
    await tester.tap(find.text('Loja'));
    await tester.pumpAndSettle();

    expect(find.text('Adubo'), findsOneWidget);
    final shopAdubo = find.ancestor(
      of: find.text('Adubo'),
      matching: find.byType(ListTile),
    );
    expect((tester.widget<ListTile>(shopAdubo).leading! as Image).image,
        toolbarAsset);
    final buy = find.text('Comprar · 50 moedas');
    await tester.tap(buy);
    await tester.pumpAndSettle();
    expect(player.fertilizer, 1);
    expect(player.coins, 15);
    expect(find.textContaining('Estoque: 1'), findsOneWidget);

    await tester.tap(buy);
    await tester.pumpAndSettle();
    expect(find.text('Moedas insuficientes'), findsOneWidget);
    expect(player.fertilizer, 1);
  });

  testWidgets('enxada e regador aceitam toques nas bordas do canteiro',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 360);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final player = Player.initial();
    for (final plot in player.plots) {
      plot.tilled = false;
    }
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pumpAndSettle();
    final tile = tester.getRect(find.byType(PlotWidget).first);
    final plot = player.plots.first;
    final topEdge = Offset(tile.center.dx, tile.top);
    await tester.tap(find.byTooltip('Enxada'));
    await tester.pump();
    await tester.tapAt(topEdge - const Offset(0, 6));
    expect(plot.tilled, isFalse);
    await tester.tapAt(topEdge - const Offset(0, 1));
    await tester.pump();
    expect(plot.tilled, isTrue);
    expect(player.plots.skip(1).every((plot) => !plot.tilled), isTrue);

    await tester.tap(find.byTooltip('Regar'));
    await tester.pump();
    final diagonal =
        Offset(tile.left + tile.width / 4, tile.top + tile.height / 4 - 1);
    await tester.tapAt(diagonal);
    await tester.pump();
    expect(plot.wateredAt, isNotNull);
    expect(
        player.plots.skip(1).every((plot) => plot.wateredAt == null), isTrue);
  });

  testWidgets('pede a enxada antes de escolher a semente após colher',
      (tester) async {
    final player = Player.initial()..seeds[CropType.alface] = 1;
    final plot = player.plots.first
      ..plantedCrop = CropType.alface
      ..plantedAt = DateTime.now().subtract(const Duration(seconds: 31))
      ..growDuration = const Duration(seconds: 30);
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pumpAndSettle();

    final tile = find.byType(PlotWidget).first;
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(plot.isEmpty, isTrue);
    expect(plot.tilled, isFalse);
    await tester.tap(find.byTooltip('Sementes'));
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Use a enxada para preparar'), findsOneWidget);
    expect(find.text('Sementes guardadas'), findsNothing);

    await tester.tap(find.byTooltip('Enxada'));
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(plot.tilled, isTrue);
    await tester.tap(find.byTooltip('Sementes'));
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Use o regador para umedecer a terra antes de plantar'),
        findsOneWidget);
    expect(find.text('Sementes guardadas'), findsNothing);

    await tester.tap(find.byTooltip('Regar'));
    await tester.tap(tile);
    await tester.pump();
    plot.wateredAt = DateTime.now().subtract(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Sementes'));
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Sementes guardadas'), findsOneWidget);
  });

  testWidgets('abre a seleção no próximo canteiro se a semente acabar',
      (tester) async {
    final player = Player.initial()
      ..xp = 350
      ..seeds[CropType.alface] = 1
      ..seeds[CropType.cenoura] = 1
      ..seeds[CropType.milho] = 1;
    for (final plot in player.plots.take(2)) {
      plot.wateredAt = DateTime.now();
    }
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sementes'));
    await tester.pumpAndSettle();
    final tiles = find.byType(PlotWidget);
    await tester.tap(tiles.at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alface'));
    await tester.pumpAndSettle();

    final held = await tester.startGesture(tester.getCenter(tiles.at(0)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(Plot.plantingDuration);
    await held.up();
    await tester.pump();
    expect(player.plots.first.plantedCrop, CropType.alface);
    expect(player.seeds.containsKey(CropType.alface), isFalse);

    await tester.tap(tiles.at(1));
    await tester.pumpAndSettle();
    expect(find.text('Sementes guardadas'), findsOneWidget);
    expect(find.text('Cenoura'), findsOneWidget);
    expect(find.text('Milho'), findsOneWidget);
    await tester.tap(find.text('Cenoura'));
    await tester.pumpAndSettle();
    expect(find.text('Segure para plantar Cenoura'), findsOneWidget);
    await tester.tap(tiles.at(1));
    await tester.pumpAndSettle();
    expect(find.text('Sementes guardadas'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('arrastar aplica a ferramenta nos canteiros do percurso',
      (tester) async {
    final player = Player.initial();
    final first = player.plots[0]..tilled = false;
    final second = player.plots[1]..tilled = false;
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pumpAndSettle();
    final tiles = find.byType(PlotWidget);
    final start = tester.getCenter(tiles.at(0));
    final end = tester.getCenter(tiles.at(1));

    Future<void> drag(String tool) async {
      await tester.tap(find.byTooltip(tool));
      await tester.pump();
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(end);
      await gesture.moveTo(start);
      await gesture.up();
      await tester.pump();
    }

    await drag('Enxada');
    expect(first.tilled && second.tilled, isTrue);
    await drag('Regar');
    expect(first.wateredAt, isNotNull);
    expect(second.wateredAt, isNotNull);

    for (final plot in [first, second]) {
      plot.plantedCrop = CropType.alface;
      plot.plantedAt = DateTime.now().subtract(const Duration(minutes: 1));
      plot.growDuration = Crops.of(CropType.alface).growTime;
    }
    await drag('Colher');
    expect(player.basket[CropType.alface], 2);
    expect(player.xp, 16);
    expect(find.text('+8 XP'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
    expect(find.text('Use o regador para umedecer a terra antes de plantar'),
        findsOneWidget);

    await tester.tap(find.byTooltip('Regar'));
    await tester.tap(tile);
    await tester.pump();
    expect(find.text('Regando terra…'), findsOneWidget);
    plot.wateredAt = DateTime.now().subtract(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Terra úmida · pronta para plantar'), findsOneWidget);

    await tester.tap(find.text('Loja'));
    await tester.pumpAndSettle();
    final lettuce = find.text('Alface');
    await tester.scrollUntilVisible(lettuce, 60,
        scrollable: find.descendant(
          of: find.byType(CropSelectorSheet),
          matching: find.byType(Scrollable),
        ));
    await tester.tap(lettuce);
    await tester.pumpAndSettle();
    final purchase = find.text('Comprar por 5 moedas');
    await tester.ensureVisible(purchase);
    await tester.pumpAndSettle();
    await tester.tap(purchase);
    await tester.pumpAndSettle();
    expect(find.text('Loja da fazenda'), findsOneWidget);
    await tester.tap(find.byTooltip('Fechar loja'));
    await tester.pumpAndSettle();
    expect(player.coins, 10);
    expect(player.seeds[CropType.alface], 1);
    await tester.tap(find.byTooltip('Sementes'));
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Sementes guardadas'), findsOneWidget);
    await tester.tap(find.text('Alface'));
    await tester.pumpAndSettle();
    expect(find.text('Segure para plantar Alface'), findsOneWidget);
    expect(player.seeds[CropType.alface], 1);

    var hold = await tester.startGesture(tester.getCenter(tile));
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('Plantando semente…'), findsOneWidget);
    await hold.up();
    await tester.pump(Plot.plantingDuration);
    expect(plot.isEmpty, isTrue);
    expect(player.seeds[CropType.alface], 1);
    await tester.tap(find.text('Alface'));
    await tester.pumpAndSettle();

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
    final inspection =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await inspection.addPointer(location: center - const Offset(48, 0));
    await inspection.moveTo(center);
    await tester.pump();
    expect(find.textContaining('Colheita em '), findsOneWidget);
    await inspection.removePointer();
    expect(plot.isPlanted, isTrue);

    expect(player.coins, 10);

    plot.plantedAt = DateTime.now().subtract(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 1));
    final readyCenter = tester.getCenter(tile);
    final readyInspection =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await readyInspection.addPointer(
        location: readyCenter - const Offset(48, 0));
    await readyInspection.moveTo(readyCenter);
    await tester.pump();
    expect(find.textContaining('Apodrece em '), findsOneWidget);
    await readyInspection.removePointer();
    await tester.tap(find.byTooltip('Colher'));
    await tester.tap(tile);
    await tester.pump();
    final progressBar = find.byWidgetPredicate((widget) =>
        widget is LinearProgressIndicator &&
        widget.semanticsLabel == 'Progresso do nível');
    double progress() =>
        tester.widget<LinearProgressIndicator>(progressBar).value!;
    expect(progress(), 0);
    expect(find.text('+8 XP'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    expect(progress(), greaterThan(0));
    expect(progress(), lessThan(.08));
    expect(tester.widget<LinearProgressIndicator>(progressBar).color,
        isNot(const Color(0xfff9cf72)));
    await tester.pump(const Duration(milliseconds: 350));
    expect(progress(), closeTo(.08, .0001));
    expect(tester.widget<LinearProgressIndicator>(progressBar).color,
        const Color(0xfff9cf72));
    expect(find.text('8/100 XP'), findsOneWidget);
    expect(player.coins, 10);
    await tester.tap(find.byTooltip('Armazém 1'));
    await tester.pumpAndSettle();
    expect(find.text('Quantidade: 1'), findsOneWidget);
    await tester.tap(find.text('Vender'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vender por 8'));
    await tester.pumpAndSettle();
    expect(player.coins, 18);
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

  testWidgets(
      'a faixa de canteiros avança em direção à barra sem mudar os primeiros',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 360);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final player = Player.initial(plotCount: GameConstants.maxPlots - 1);
    player.coins = 100000;
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pumpAndSettle();

    final plots = find.byType(PlotWidget);
    final first = tester.getCenter(plots.first);
    final expansion = find.byType(NewPlotTile);
    final pending = tester.getRect(expansion);
    expect(first.dx, lessThan(tester.view.physicalSize.width * .3));
    expect(pending.center.dx, greaterThan(first.dx));
    expect(pending.center.dy, greaterThan(first.dy));
    expect(pending.bottom,
        lessThan(tester.getTopLeft(find.byTooltip('Colher')).dy));

    await tester.tap(expansion);
    await tester.pump();
    expect(tester.getCenter(plots.first), first);
    expect(tester.getRect(plots.last), pending);
    expect(expansion, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('vende parte de uma cultura e depois vende o restante',
      (tester) async {
    final player = Player.initial()..basket[CropType.cenoura] = 3;
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.tap(find.text('Armazém'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vender'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aumentar quantidade para vender'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vender por 80'));
    await tester.pumpAndSettle();
    expect(player.basket[CropType.cenoura], 1);
    expect(player.coins, 95);
    await tester.tap(find.text('Vender tudo por 40'));
    await tester.pumpAndSettle();
    expect(player.basket, isEmpty);
    expect(player.coins, 135);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mostra a falta de moedas acima do canteiro bloqueado',
      (tester) async {
    final player = Player.initial()..coins = 53;
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pumpAndSettle();

    final tile = find.byType(NewPlotTile);
    await tester.tap(tile);
    await tester.pump();

    final notice = find.text('Moedas insuficientes\nFaltam 47 moedas.');
    expect(notice, findsOneWidget);
    expect(tester.getCenter(notice).dx, closeTo(tester.getCenter(tile).dx, 1));
    expect(
        tester.getBottomLeft(notice).dy, lessThan(tester.getTopLeft(tile).dy));
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    expect(notice, findsNothing);
  });

  test('produção de leite pausa sem insumos e retoma após o save', () {
    final start = DateTime.utc(2026);
    final player = Player.initial()
      ..coins = 2000
      ..cowFeed = 1;
    expect(player.buyCow(start), isTrue);
    expect(player.milkRemaining(start.add(const Duration(hours: 5))),
        Player.milkCycle);
    expect(player.refillTrough(start, water: true), isTrue);
    final fed = start.add(const Duration(hours: 1, minutes: 50));
    expect(player.milkProgress(fed), 0);
    expect(player.refillTrough(fed, water: false), isTrue);
    expect(player.milkRemaining(fed), Player.milkCycle);
    expect(player.milkProgress(fed.add(const Duration(minutes: 1))),
        greaterThan(0));
    final restored = Player.fromMap(player.toMap());
    final later = start.add(const Duration(hours: 5));
    const remaining = Duration(hours: 5, minutes: 50);
    expect(restored.troughLevel(later, water: true), 0);
    expect(restored.troughLevel(later, water: false), closeTo(53 / 72, .001));
    expect(restored.milkRemaining(later), remaining);
    expect(restored.collectMilk(later), isFalse);
    expect(restored.refillTrough(later, water: true), isTrue);
    expect(restored.milkRemaining(later), remaining);
    final refill = later.add(const Duration(hours: 4));
    expect(restored.refillTrough(refill, water: true), isTrue);
    final ready = later.add(remaining);
    expect(restored.milkProgress(ready), 1);
    expect(restored.collectMilk(ready), isTrue);
    expect(restored.milk, 6);
    expect(restored.milkProgress(ready), 0);
  });

  testWidgets('compra a vaca, coleta leite no pasto e vende no armazém',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final player = Player.initial()
      ..coins = Player.cowCost + Player.cowFeedCost * 2;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: FazendinhaApp(player: player),
    ));
    await tester.pumpAndSettle();

    expect(player.hasCow, isFalse);
    expect(find.text('Comprar vaca'), findsNothing);
    await tester.tap(find.text('Loja'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Animais'));
    await tester.pumpAndSettle();
    expect(find.text('Vaca leiteira'), findsOneWidget);
    await tester.ensureVisible(find.text('Comprar · 2.000 moedas'));
    await tester.tap(find.text('Comprar · 2.000 moedas'));
    await tester.pumpAndSettle();
    expect(player.hasCow, isTrue);
    expect(find.text('Comprada'), findsOneWidget);
    expect(player.coins, Player.cowFeedCost * 2);
    await tester.tap(find.text('Ração para vaca'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aumentar quantidade'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.text('Comprar por 60 moedas'));
    await tester.pumpAndSettle();
    expect(player.cowFeed, 2);
    expect(player.coins, 0);
    player.coins = Player.cowCost;
    expect(player.buyCow(DateTime.now()), isFalse);
    expect(player.coins, Player.cowCost);
    player.coins = 0;
    await tester.tap(find.byTooltip('Fechar loja'));
    await tester.pumpAndSettle();

    expect(find.text('Pausado'), findsNothing);
    await tester.tap(find.byTooltip('Regar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bebedouro'));
    await tester.pumpAndSettle();
    expect(player.hasCowWater(DateTime.now()), isTrue);
    await tester.tap(find.text('Armazém'));
    await tester.pumpAndSettle();
    final feedRow = find.ancestor(
      of: find.text('Ração para vaca'),
      matching: find.byType(ListTile),
    );
    await tester.tap(find.descendant(of: feedRow, matching: find.text('Usar')));
    await tester.pumpAndSettle();
    expect(player.cowFeed, 1);
    expect(player.hasCowFeed(DateTime.now()), isTrue);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Colher e alimentar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cocho de ração'));
    await tester.pumpAndSettle();
    expect(player.cowFeed, 0);

    expect(player.collectMilk(DateTime.now()), isFalse);
    player.milkReadyAt = DateTime.now().subtract(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('dairy-cow')));
    await tester.pump();
    expect(player.milk, 0);
    final xpBeforeMilking = player.xp;
    expect(find.text('6 garrafas · +48 XP'), findsOneWidget);
    await tester.tap(find.text('Ordenhar'));
    await tester.pump();
    expect(player.milk, 6);
    expect(player.xp, xpBeforeMilking + Player.milkXpPerCycle);
    expect(player.collectMilk(DateTime.now()), isFalse);
    expect(player.xp, xpBeforeMilking + Player.milkXpPerCycle);
    final restored = Player.fromMap(player.toMap());
    expect(restored.hasCow, isTrue);
    expect(restored.milk, 6);
    expect(restored.milkReadyAt, player.milkReadyAt);

    await tester.tap(find.text('Armazém'));
    await tester.pumpAndSettle();
    expect(find.text('Leite'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName.endsWith('/milk_bottle.webp')),
      findsOneWidget,
    );
    await tester.tap(find.text('Vender tudo por 240'));
    await tester.pumpAndSettle();
    expect(player.milk, 0);
    expect(player.coins, 240);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('cada cachorro custa mil moedas e expira 30 dias após a compra', () {
    final now = DateTime.utc(2026, 11, 28);
    final player = Player.initial()..coins = 999;
    expect(player.buyGuardDog(now), isFalse);
    expect(player.hasGuardDogHouse, isFalse);
    player.coins = 2000;
    expect(player.buyGuardDog(now), isTrue);
    expect(player.coins, 1000);
    expect(player.buyGuardDog(now), isFalse);

    final restored = Player.fromMap(player.toMap());
    final expiration = now.add(const Duration(days: 30));
    expect(restored.guardDogOwnedUntil, expiration);
    expect(restored.ownsGuardDog(expiration), isFalse);
    expect(restored.hasGuardDogHouse, isTrue);
    expect(restored.buyGuardDog(expiration), isTrue);
    expect(restored.coins, 0);
  });

  testWidgets('compra ração, acorda o cachorro e volta a dormir com fome',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final player = Player.initial()
      ..coins += Player.guardDogCost + Player.guardDogFoodCost
      ..buyGuardDog(DateTime.now());
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pumpAndSettle();
    final sleeping = find.byTooltip('Cachorro dormindo · toque para alimentar');
    final patrolling = find.byKey(const ValueKey('guard-dog-patrol'));
    expect(sleeping, findsOneWidget);
    expect(patrolling, findsNothing);

    await tester.tap(sleeping);
    await tester.pumpAndSettle();
    final feedItem = find.text('Ração para cachorro');
    await tester.scrollUntilVisible(
      feedItem,
      70,
      scrollable: find.descendant(
          of: find.byType(CropSelectorSheet),
          matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    await tester.tap(feedItem);
    await tester.pumpAndSettle();
    final more = find.byTooltip('Aumentar quantidade');
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.text('Comprar por 30 moedas'));
    await tester.pumpAndSettle();
    expect(player.guardDogFood, 2);
    expect(player.coins, 0);
    await tester.tap(find.byTooltip('Fechar loja'));
    await tester.pumpAndSettle();

    final beforeMeal = DateTime.now();
    await tester.tap(sleeping);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(player.guardDogFood, 1);
    expect(player.guardDogFedUntil!.difference(beforeMeal).inHours, 12);
    expect(Player.fromMap(player.toMap()).guardDogFedUntil,
        player.guardDogFedUntil);
    expect(patrolling, findsOneWidget);
    expect(
      tester.getCenter(patrolling).dx,
      greaterThan(tester.getCenter(find.byType(PlotWidget).first).dx),
    );

    player.guardDogFedUntil = DateTime.now();
    await tester.pump(const Duration(seconds: 1));
    expect(sleeping, findsOneWidget);
    expect(patrolling, findsNothing);
    player.guardDogOwnedUntil = DateTime.now();
    await tester.pump(const Duration(seconds: 1));
    expect(sleeping, findsNothing);
    expect(find.byTooltip('Casinha do cachorro'), findsOneWidget);
    expect(player.hasGuardDog, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a vaca caminha e mostra o status ao passar o mouse ou tocar',
      (tester) async {
    final player = Player.initial()..coins = Player.cowCost;
    player.buyCow(DateTime.now());
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pump();
    final cow = find.byKey(const ValueKey('dairy-cow'));
    final milkBar = find.text('Produção de leite');
    final start = tester.getCenter(cow);
    expect(milkBar, findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: start);
    await tester.pump();
    expect(milkBar, findsOneWidget);
    await mouse.moveTo(const Offset(50, 50));
    await tester.pump();
    expect(milkBar, findsNothing);
    await mouse.removePointer();

    await tester.tap(cow);
    await tester.pump();
    final barStart = tester.getCenter(milkBar);
    expect(find.text('Água'), findsOneWidget);
    expect(find.text('Ração'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getCenter(cow).dx, lessThan(start.dx));
    expect(tester.getCenter(milkBar), barStart);
    await tester.tap(cow);
    await tester.pump();
    expect(milkBar, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('armazém mostra sementes, adubo e defensivo separados da venda',
      (tester) async {
    final player = Player.initial()
      ..seeds[CropType.alface] = 3
      ..fertilizer = 2
      ..weedControl = 1
      ..basket[CropType.alface] = 1;
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.tap(find.text('Armazém'));
    await tester.pumpAndSettle();

    expect(find.text('Estoque de plantio'), findsOneWidget);
    expect(find.text('Semente de Alface'), findsOneWidget);
    expect(find.text('Adubo'), findsOneWidget);
    expect(find.text('Defensivo'), findsOneWidget);
    expect(find.text('Usar'), findsNWidgets(3));
    expect(find.text('Colheita para venda'), findsOneWidget);
    expect(find.text('Vender tudo por 8'), findsOneWidget);
  });

  test('o preço do canteiro sobe a cada desbloqueio', () {
    final player = Player.initial()..coins = 581;
    for (final cost in [100, 175, 306]) {
      expect(player.nextPlotCost, cost);
      expect(player.buyPlot(), isTrue);
    }
    expect(player.coins, 0);
    expect(player.nextPlotCost, 536);
  });

  testWidgets('compra em lote é limitada pelo saldo e mantém a loja aberta',
      (tester) async {
    final player = Player.initial()..coins = 25;
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.tap(find.text('Loja'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alface'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Aumentar quantidade'));
      await tester.pumpAndSettle();
    }
    expect(find.text('5 / 5'), findsOneWidget);
    final plus =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add));
    expect(plus.onPressed, isNull);
    await tester.tap(find.text('Comprar por 25 moedas'));
    await tester.pumpAndSettle();
    expect(player.coins, 0);
    expect(player.seeds[CropType.alface], 5);
    expect(find.text('Loja da fazenda'), findsOneWidget);
    expect(find.text('Saldo: 0 moedas'), findsOneWidget);
    player.basket[CropType.alface] = 2;
    await tester.tap(find.text('Alface'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Venda as mercadorias do Armazém'), findsOneWidget);
    await tester.tap(find.text('Abrir Armazém'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vender tudo por 16'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(find.text('Saldo: 16 moedas'), findsOneWidget);

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
    await tester.tap(find.text('Check-in'));
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

  testWidgets('avisos guardam mensagens e os atalhos ficam na barra',
      (tester) async {
    final player = Player.initial()
      ..addNotice('Aviso de teste', DateTime(2026, 11, 28, 10));
    await tester
        .pumpWidget(FazendinhaApp(player: Player.fromMap(player.toMap())));
    await tester.pumpAndSettle();
    expect(find.text('Check-in'), findsOneWidget);
    expect(find.text('Melhorias'), findsOneWidget);

    await tester.tap(find.text('Avisos'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('Aviso de teste')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Check-in')),
        findsNothing);
    expect(find.descendant(of: dialog, matching: find.text('Melhorias')),
        findsNothing);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Melhorias'));
    await tester.pumpAndSettle();
    expect(find.text('Melhorias da fazenda'), findsOneWidget);
  });

  testWidgets('ressincroniza o login na virada do dia sem resgatar sozinho',
      (tester) async {
    final player = Player.initial();
    final calls = <String>[];
    final api = VisitRewardsApi(
      Uri.parse('https://visits.example/farm'),
      'test-key',
      client: MockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path == '/farm/v2/claims') {
          expect(jsonDecode(request.body), {'date': '2026-01-01'});
          return http.Response('{}', 409);
        }
        final afterMidnight = calls.contains('/farm/v2/claims');
        final snapshot = visitResponse(afterMidnight ? 2 : 1, 0);
        if (afterMidnight) snapshot['date'] = '2026-01-02';
        return http.Response(jsonEncode(snapshot), 200);
      }),
    );
    await tester.pumpWidget(FazendinhaApp(player: player, visitsApi: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check-in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resgatar'));
    await tester.pumpAndSettle();

    expect(calls, [
      '/farm/v2/visits',
      '/farm/v2/visits',
      '/farm/v2/claims',
      '/farm/v2/visits',
    ]);
    expect(find.text('Sequência: 2 dia(s) consecutivo(s)'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Resgatar'))
            .onPressed,
        isNotNull);
    expect(player.coins, Player.initial().coins);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cultura morta mantém a própria imagem em versão murcha',
      (tester) async {
    final player = Player.initial();
    player.plots.first
      ..plantedCrop = CropType.tomate
      ..growDuration = const Duration(minutes: 35)
      ..plantedAt = DateTime.now().subtract(const Duration(days: 2));
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pumpAndSettle();

    final tile = find.byType(PlotWidget).first;
    final filtered = find.descendant(
      of: tile,
      matching: find.byType(ColorFiltered),
    );
    expect(filtered, findsOneWidget);
    final sprite = tester.widget<Image>(
      find.descendant(of: filtered, matching: find.byType(Image)),
    );
    expect((sprite.image as AssetImage).assetName, endsWith('/tomate_4.webp'));
    expect(find.descendant(of: tile, matching: find.byIcon(Icons.eco)),
        findsNothing);
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

      expect(
          crop.harvestWindow,
          previousWindow == Crop.maxHarvestWindow
              ? Crop.maxHarvestWindow
              : greaterThan(previousWindow));
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

  testWidgets('o status identifica a penalidade do mato em cada fase',
      (tester) async {
    final player = Player.initial()..coins = 40;
    final data = player.plots.first.toMap()..['harvestsUntilWeeds'] = 0;
    final plot = Plot.fromMap(data)
      ..plantedCrop = CropType.alface
      ..plantedAt = DateTime.now()
      ..growDuration = const Duration(milliseconds: 37500);
    player.plots[0] = plot;
    await tester.pumpWidget(FazendinhaApp(player: player));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PlotWidget).first);
    await tester.pump();
    expect(find.text('Mato · +25% no tempo de maturação'), findsOneWidget);
    expect(find.textContaining('Saúde 100/100'), findsOneWidget);
    expect(find.text('Compre defensivo na Loja.'), findsOneWidget);

    await tester.tap(find.text('Loja'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comprar · 30 moedas'));
    await tester.pumpAndSettle();
    expect(player.weedControl, 1);
    await tester.tap(find.byTooltip('Fechar loja'));
    await tester.pumpAndSettle();

    plot.plantedAt = DateTime.now().subtract(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Mato · Saúde cai 50% mais rápido'), findsOneWidget);
    expect(find.text('Use o defensivo do Armazém.'), findsOneWidget);

    await tester.tap(find.text('Armazém'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PlotWidget).first);
    await tester.pump();
    expect(find.text('Mato removido'), findsOneWidget);
    expect(player.weedControl, 0);
    expect(plot.hasWeeds, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('mato persiste, atrasa a maturação e só reduz saúde após amadurecer',
      () {
    final start = DateTime.utc(2026, 1, 1);
    final crop = Crops.of(CropType.alface);
    final player = Player.initial()..coins = 40;
    final freshPlot = player.plots.first.toMap();
    expect(freshPlot['harvestsUntilWeeds'], inInclusiveRange(15, 30));
    final plot = Plot.fromMap(freshPlot..['harvestsUntilWeeds'] = 1)
      ..plantedCrop = crop.type
      ..plantedAt = start.subtract(crop.growTime)
      ..growDuration = crop.growTime;
    player.plots[0] = plot;

    expect(player.harvest(plot, start), greaterThan(0));
    expect(plot.hasWeeds, isTrue);
    final restored = Player.fromMap(player.toMap());
    final infested = restored.plots.first;
    expect(infested.hasWeeds, isTrue);
    expect(infested.hoe(start), isTrue);
    expect(infested.hasWeeds, isTrue);
    expect(restored.buySeed(crop.type), isTrue);
    expect(restored.buyWeedControl(), isTrue);
    expect(restored.coins, 5);
    infested.wateredAt = start;
    expect(restored.plant(infested, crop, start, prepared: true), isTrue);
    expect(infested.growDuration, const Duration(milliseconds: 37500));
    final mature = start.add(infested.growDuration!);
    expect(infested.health(start), 1);
    expect(infested.health(mature.subtract(const Duration(seconds: 1))), 1);
    expect(infested.health(mature), 1);
    expect(infested.spoilAt(), mature.add(const Duration(minutes: 16)));

    final treatment = mature.add(const Duration(minutes: 4));
    expect(infested.health(treatment), .75);
    expect(restored.applyWeedControl(infested, treatment), isTrue);
    expect(infested.hasWeeds, isFalse);
    expect(restored.weedControl, 0);
    expect(infested.health(treatment), .75);
    expect(infested.spoilAt(), mature.add(const Duration(minutes: 22)));
    expect(infested.toMap()['harvestsUntilWeeds'], inInclusiveRange(15, 30));
    expect(Plot.fromMap(infested.toMap()).health(treatment), .75);
  });

  test('fertilizante reduz o tempo restante e persiste o consumo', () {
    final start = DateTime.utc(2026, 1, 1);
    final player = Player.initial()..coins = 57;
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
      ..remove('appliedDailyLoginCoins')
      ..remove('appliedDailyLoginSeeds')
      ..['coins'] = 27
      ..['seeds'] = {'alface': 1}
      ..['claimedVisitDays'] = 1;
    final player = Player.fromMap(legacy);
    expect(player.appliedDailyLoginCoins, 12);
    expect(player.appliedDailyLoginSeeds, 1);

    player.applyVisitRewards(VisitSnapshot.fromJson(visitResponse(2, 1)));
    expect(player.coins, 27);
    expect(player.seeds[CropType.alface], 1);

    final restored = Player.fromMap(player.toMap());
    restored.applyVisitRewards(VisitSnapshot.fromJson(visitResponse(2, 2)));
    restored.applyVisitRewards(VisitSnapshot.fromJson(visitResponse(2, 1)));
    restored.applyVisitRewards(VisitSnapshot.fromJson(visitResponse(2, 2)));
    expect(restored.appliedDailyLoginSeeds, 3);
    expect(restored.coins, 27 + 24);
    expect(restored.seeds[CropType.alface], 3);
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
