// ============================================================
// 🌱 LITTLE FARM IDLE — FASE 2 + RODADA ANDROID (arquivo único)
// ------------------------------------------------------------
// Cole este conteúdo como: lib/main.dart
// (substitui toda a estrutura de pastas lib/core, lib/models, lib/ui)
//
// Fase 2: expansão de canteiros + upgrades permanentes
// (venda melhor, semente barata, crescimento rápido) e destaque
// visual "Novo!" para culturas recém-desbloqueadas.
//
// Rodada Android (aparelho físico):
// • Nome de exibição: Little Farm
// • AdMob de teste somente no Android (banner + app id de teste do Google)
// • Tempo offline: crescimento pelo relógio real (DateTime.now)
// • Persistência: aguarda put + flush a cada gravação
// • Orientação travada em paisagem
// ============================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Liga o AdMob apenas em builds Android reais (não na web), usando os IDs
/// de teste do Google. Nos testes, rode com --dart-define=ENABLE_TEST_ADS=false
/// para evitar a MissingPluginException do plugin de anúncios.
bool get _useTestAds =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    const bool.fromEnvironment('ENABLE_TEST_ADS', defaultValue: true);

// ------------------------------------------------------------
// [core/game_constants.dart]  Constantes centrais do jogo
// ------------------------------------------------------------
class GameConstants {
  static const String hiveBoxName = 'fazendinha_idle_box';
  static const String playerKey = 'player';

  /// Moedas iniciais: 15 = 3 sementes de alface (5 cada).
  static const int startingCoins = 15;
  static const int startingPlots = 4;

  /// Curva de custo dos canteiros: custo = base x fator^quantidade.
  static const double newPlotBaseCost = 100.0;
  static const double newPlotGrowthFactor = 1.5;
  static const int maxPlots = 12;

  /// Intervalo de salvamento automático (segundos).
  static const int autoSaveSeconds = 30;

  /// Nível máximo de cada upgrade.
  static const int maxUpgradeLevel = 10;

  /// Geometria do losango isométrico.
  ///
  /// [isoTileHalfWidth] é a metade da largura do losango; [isoTileHalfHeight]
  /// é a metade da altura. A tela translada o "chão" para o centro e desenha
  /// os losangos a partir de [plotCenterForIndex].
  static const double isoTileHalfWidth = 56.0;
  static const double isoTileHalfHeight = 28.0;

  /// Número de colunas da grade de canteiros.
  static const int gridColumns = 2;

  /// Quantidade de estágios visuais de crescimento (broto → pronto).
  static const int cropStageCount = 4;

  /// Centro do losango do canteiro [index] no espaço do chão isométrico.
  ///
  /// O eixo X cresce para a direita; o Y cresce para baixo. Canteiros
  /// vizinhos compartilham bordas nos pontos médios dos losangos, o que
  /// permite tocar inclusive nas bordas sem ambiguidade.
  static Offset plotCenterForIndex(int index) {
    final col = index % gridColumns;
    final row = index ~/ gridColumns;
    return Offset(
      (col - row) * isoTileHalfWidth,
      (col + row) * isoTileHalfHeight,
    );
  }
}

// ------------------------------------------------------------
// [models/crop.dart]  Tipos de cultura + dados de cada uma
// ------------------------------------------------------------
enum CropType {
  alface,
  cenoura,
  milho,
  tomate,
  morango,
  abobora,
  cafe,
  cana;

  String get label => switch (this) {
        CropType.alface => 'Alface',
        CropType.cenoura => 'Cenoura',
        CropType.milho => 'Milho',
        CropType.tomate => 'Tomate',
        CropType.morango => 'Morango',
        CropType.abobora => 'Abóbora',
        CropType.cafe => 'Café',
        CropType.cana => 'Cana-de-açúcar',
      };

  String get emoji => switch (this) {
        CropType.alface => '🥬',
        CropType.cenoura => '🥕',
        CropType.milho => '🌽',
        CropType.tomate => '🍅',
        CropType.morango => '🍓',
        CropType.abobora => '🎃',
        CropType.cafe => '☕',
        CropType.cana => '🎋',
      };
}

class Crop {
  const Crop({
    required this.type,
    required this.seedCost,
    required this.sellValue,
    required this.growTime,
    required this.unlockLevel,
  });

  final CropType type;
  final int seedCost;
  final int sellValue;
  final Duration growTime;
  final int unlockLevel;

  String get emoji => type.emoji;
  String get label => type.label;
}

/// Repositório estático com os dados das 8 culturas.
class Crops {
  static Crop of(CropType type) => switch (type) {
        CropType.alface => const Crop(
            type: CropType.alface,
            seedCost: 5,
            sellValue: 12,
            growTime: Duration(seconds: 30),
            unlockLevel: 1,
          ),
        CropType.cenoura => const Crop(
            type: CropType.cenoura,
            seedCost: 25,
            sellValue: 70,
            growTime: Duration(minutes: 2),
            unlockLevel: 2,
          ),
        CropType.milho => const Crop(
            type: CropType.milho,
            seedCost: 120,
            sellValue: 350,
            growTime: Duration(minutes: 10),
            unlockLevel: 3,
          ),
        CropType.tomate => const Crop(
            type: CropType.tomate,
            seedCost: 200,
            sellValue: 550,
            growTime: Duration(minutes: 15),
            unlockLevel: 4,
          ),
        CropType.morango => const Crop(
            type: CropType.morango,
            seedCost: 350,
            sellValue: 900,
            growTime: Duration(minutes: 20),
            unlockLevel: 5,
          ),
        CropType.abobora => const Crop(
            type: CropType.abobora,
            seedCost: 600,
            sellValue: 1500,
            growTime: Duration(minutes: 30),
            unlockLevel: 6,
          ),
        CropType.cafe => const Crop(
            type: CropType.cafe,
            seedCost: 1000,
            sellValue: 2500,
            growTime: Duration(minutes: 45),
            unlockLevel: 7,
          ),
        CropType.cana => const Crop(
            type: CropType.cana,
            seedCost: 1800,
            sellValue: 4500,
            growTime: Duration(hours: 1),
            unlockLevel: 8,
          ),
      };
}

// ------------------------------------------------------------
// [models/plot.dart]  Um canteiro individual da fazenda
// ------------------------------------------------------------
class Plot {
  Plot({required this.id});

  final String id;
  CropType? plantedCrop;
  DateTime? plantedAt;
  Duration? growDuration;
  bool tilled = true;
  DateTime? wateredAt;

  static const wateringDuration = Duration(seconds: 3);
  static const plantingDuration = Duration(seconds: 2);
  static const harvestWindow = Duration(hours: 48);

  bool isWatering(DateTime now) => wateredAt?.isAfter(now) ?? false;
  bool isWet(DateTime now) => wateredAt != null && !isWatering(now);
  bool isPlanting(DateTime now) => plantedAt?.isAfter(now) ?? false;

  double health(DateTime now) {
    final at = plantedAt;
    final duration = growDuration;
    if (at == null || duration == null) return 0;
    final elapsed = now.difference(at.add(duration)).inMilliseconds;
    return (1 - elapsed / harvestWindow.inMilliseconds).clamp(0.0, 1.0);
  }

  bool isDead(DateTime now) => isPlanted && health(now) == 0;

  bool water(DateTime now) {
    if (!tilled || isPlanted || wateredAt != null) return false;
    wateredAt = now.add(wateringDuration);
    return true;
  }

  bool hoe(DateTime now) {
    if (isPlanted && !isDead(now)) return false;
    if (tilled && isEmpty) return false;
    clear();
    tilled = true;
    return true;
  }

  void clear() {
    plantedCrop = null;
    plantedAt = null;
    growDuration = null;
    wateredAt = null;
    tilled = false;
  }

  bool get isEmpty => plantedCrop == null;
  bool get isPlanted => plantedCrop != null;

  bool isReady(DateTime now) {
    final crop = plantedCrop;
    final at = plantedAt;
    final duration = growDuration;
    if (crop == null || at == null || duration == null) return false;
    return !now.isBefore(at.add(duration)) && !isDead(now);
  }

  double progress(DateTime now) {
    final at = plantedAt;
    final duration = growDuration;
    if (at == null || duration == null || duration.inMilliseconds == 0) {
      return 0;
    }
    final elapsed = now.difference(at).inMilliseconds;
    return (elapsed / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Estágio visual de crescimento, de 1 (broto) a
  /// [GameConstants.cropStageCount] (maduro/pronto).
  ///
  /// Canteiro vazio retorna 0; cultura pronta para colher retorna o estágio
  /// máximo. O seletor e o widget do terreno usam esse valor para trocar a
  /// arte sem recriar o progresso.
  int stage(DateTime now) {
    if (isEmpty) return 0;
    if (isReady(now)) return GameConstants.cropStageCount;
    // O crescimento percorre só os estágios 1..3 (broto → quase pronta).
    // O 4º fica reservado para a colheita: aos 23 de 30 s a alface ainda
    // aparece em crescimento, e só fica "pronta" quando isReady for true.
    final scaled = progress(now) * (GameConstants.cropStageCount - 1);
    return scaled.ceil().clamp(1, GameConstants.cropStageCount - 1);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'tilled': tilled,
        'wateredAt': wateredAt?.toIso8601String(),
        'plantedCrop': plantedCrop?.name,
        'plantedAt': plantedAt?.toIso8601String(),
        'growDurationSeconds': growDuration?.inSeconds,
        'growDurationMilliseconds': growDuration?.inMilliseconds,
      };

  factory Plot.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String? ?? 'plot_0';
    final plot = Plot(id: id)..tilled = map['tilled'] != false;

    final wet = map['wateredAt'];
    plot.wateredAt = wet is String ? DateTime.tryParse(wet) : null;
    final cropName = map['plantedCrop'] as String?;
    if (cropName == null) return plot; // Já está vazio.

    final plantedAtStr = map['plantedAt'] as String?;
    if (plantedAtStr == null) {
      // Cultura plantada sem data de plantio: save inconsistente. Descarta o
      // plantio (opção A) para o canteiro não ficar preso em "crescendo".
      return plot;
    }

    plot.plantedCrop = CropType.values.firstWhere((c) => c.name == cropName);
    plot.plantedAt = DateTime.parse(plantedAtStr);
    final milliseconds = map['growDurationMilliseconds'];
    final seconds = map['growDurationSeconds'];

    if (milliseconds is int) {
      plot.growDuration = Duration(milliseconds: milliseconds);
    } else if (seconds is int) {
      plot.growDuration = Duration(seconds: seconds);
    } else {
      plot.growDuration = Crops.of(plot.plantedCrop!).growTime;
    }

    return plot;
  }
}

// ------------------------------------------------------------
// [models/upgrade.dart]  Tipos de upgrade permanente
// ------------------------------------------------------------
enum UpgradeType {
  sellBoost,
  seedDiscount,
  growSpeed;

  String get label => switch (this) {
        UpgradeType.sellBoost => 'Venda Melhor',
        UpgradeType.seedDiscount => 'Semente Barata',
        UpgradeType.growSpeed => 'Crescimento Rápido',
      };

  String get emoji => switch (this) {
        UpgradeType.sellBoost => '💰',
        UpgradeType.seedDiscount => '🪙',
        UpgradeType.growSpeed => '⏱️',
      };

  String get description => switch (this) {
        UpgradeType.sellBoost => '+20% de venda por nível',
        UpgradeType.seedDiscount => '−15% no custo da semente por nível',
        UpgradeType.growSpeed => '−10% no tempo de crescimento por nível',
      };
}

// ------------------------------------------------------------
// [models/player.dart]  Estado central do jogador
// ------------------------------------------------------------
class Player {
  Player({
    required this.coins,
    required this.plotCount,
    required this.plots,
    this.xp = 0,
    this.sellBoostLevel = 0,
    this.seedDiscountLevel = 0,
    this.growSpeedLevel = 0,
  });

  factory Player.initial({int plotCount = GameConstants.startingPlots}) {
    return Player(
      coins: GameConstants.startingCoins,
      plotCount: plotCount,
      plots: List.generate(plotCount, (i) => Plot(id: 'plot_$i')),
    );
  }

  /// Limiares de XP por nível, do 1 ao 8.
  static const xpThresholds = [0, 100, 300, 600, 1000, 1500, 2100, 2800];

  int coins;
  int xp;
  int plotCount;
  List<Plot> plots;
  int sellBoostLevel;
  int seedDiscountLevel;
  int growSpeedLevel;
  final Map<CropType, int> basket = {};
  final Map<CropType, int> seeds = {};
  static const visitDayLimit = 7;
  int visitDays = 0;
  int claimedVisitDays = 0;
  int? lastVisitDay;

  int get currentLevelXp => xp - xpThresholds[level - 1];
  int? get levelXpGoal {
    final next = nextLevelXp;
    return next == null ? null : next - xpThresholds[level - 1];
  }

  bool recordVisit(DateTime now) {
    final local = now.toLocal();
    final day = DateTime.utc(local.year, local.month, local.day)
        .difference(DateTime.utc(1970))
        .inDays;
    if (visitDays >= visitDayLimit || (lastVisitDay ?? -1) >= day) return false;
    lastVisitDay = day;
    visitDays++;
    return true;
  }

  static int visitCoins(int day) => 12 * day;

  bool claimVisitReward(int day) {
    if (day != claimedVisitDays + 1 || day > visitDays) return false;
    coins += visitCoins(day);
    seeds.update(CropType.alface, (amount) => amount + day,
        ifAbsent: () => day);
    claimedVisitDays = day;
    return true;
  }

  bool buySeed(CropType type) {
    if (!isUnlocked(type)) return false;
    final cost = effectiveSeedCost(Crops.of(type));
    if (coins < cost) return false;
    coins -= cost;
    seeds.update(type, (amount) => amount + 1, ifAbsent: () => 1);
    return true;
  }

  int sellCrop(CropType type) {
    final amount = basket.remove(type) ?? 0;
    final proceeds = amount * effectiveSellValue(Crops.of(type));
    coins += proceeds;
    return proceeds;
  }

  int get basketCount =>
      basket.values.fold(0, (total, amount) => total + amount);
  int get basketValue => basket.entries.fold(
        0,
        (total, entry) =>
            total + effectiveSellValue(Crops.of(entry.key)) * entry.value,
      );

  double get levelProgress {
    if (level == xpThresholds.length) return 1;
    final start = xpThresholds[level - 1];
    return (xp - start) / (xpThresholds[level] - start);
  }

  int? get nextLevelXp =>
      level < xpThresholds.length ? xpThresholds[level] : null;

  int get level {
    var lvl = 1;
    for (var i = 0; i < xpThresholds.length; i++) {
      if (xp >= xpThresholds[i]) lvl = i + 1;
    }
    return lvl;
  }

  bool isUnlocked(CropType type) => level >= Crops.of(type).unlockLevel;

  /// Cultura acaba de ser desbloqueada no nível atual (badge "Novo!").
  bool isNewlyUnlocked(CropType type) => level == Crops.of(type).unlockLevel;

  // Efeitos acumulativos (multiplicativos) dos upgrades.
  double get sellMultiplier => math.pow(1.20, sellBoostLevel).toDouble();
  double get seedCostMultiplier => math.pow(0.85, seedDiscountLevel).toDouble();
  double get growTimeMultiplier => math.pow(0.90, growSpeedLevel).toDouble();

  int effectiveSeedCost(Crop crop) =>
      (crop.seedCost * seedCostMultiplier).round();
  int effectiveSellValue(Crop crop) =>
      (crop.sellValue * sellMultiplier).round();
  Duration effectiveGrowTime(Crop crop) => Duration(
        milliseconds:
            (crop.growTime.inMilliseconds * growTimeMultiplier).round(),
      );

  int get nextPlotCost {
    final exponent = plotCount - GameConstants.startingPlots;
    return (GameConstants.newPlotBaseCost *
            math.pow(GameConstants.newPlotGrowthFactor, exponent))
        .round();
  }

  bool get canBuyMorePlots => plotCount < GameConstants.maxPlots;

  bool buyPlot() {
    if (!canBuyMorePlots) return false;
    final cost = nextPlotCost;
    if (coins < cost) return false;
    coins -= cost;
    plotCount++;
    plots.add(Plot(id: 'plot_${plotCount - 1}'));
    return true;
  }

  int upgradeLevel(UpgradeType type) => switch (type) {
        UpgradeType.sellBoost => sellBoostLevel,
        UpgradeType.seedDiscount => seedDiscountLevel,
        UpgradeType.growSpeed => growSpeedLevel,
      };

  int upgradeCost(UpgradeType type) {
    final currentLevel = upgradeLevel(type);
    final (base, factor) = switch (type) {
      UpgradeType.sellBoost => (100.0, 1.8),
      UpgradeType.seedDiscount => (80.0, 1.6),
      UpgradeType.growSpeed => (120.0, 1.7),
    };
    return (base * math.pow(factor, currentLevel)).round();
  }

  bool buyUpgrade(UpgradeType type) {
    if (upgradeLevel(type) >= GameConstants.maxUpgradeLevel) return false;
    final cost = upgradeCost(type);
    if (coins < cost) return false;
    coins -= cost;
    switch (type) {
      case UpgradeType.sellBoost:
        sellBoostLevel++;
      case UpgradeType.seedDiscount:
        seedDiscountLevel++;
      case UpgradeType.growSpeed:
        growSpeedLevel++;
    }
    return true;
  }

  bool plant(Plot plot, Crop crop, DateTime now) {
    if (plot.isPlanted || !plot.tilled || !plot.isWet(now)) return false;
    final stock = seeds[crop.type] ?? 0;
    if (!isUnlocked(crop.type) || stock == 0) return false;
    if (stock == 1) {
      seeds.remove(crop.type);
    } else {
      seeds[crop.type] = stock - 1;
    }
    plot.plantedCrop = crop.type;
    plot.plantedAt = now.add(Plot.plantingDuration);
    plot.growDuration = effectiveGrowTime(crop);
    plot.wateredAt = null;
    return true;
  }

  int harvest(Plot plot, DateTime now) {
    if (!plot.isPlanted || !plot.isReady(now)) return 0;
    final crop = Crops.of(plot.plantedCrop!);
    final reward = effectiveSellValue(crop);
    basket.update(crop.type, (amount) => amount + 1, ifAbsent: () => 1);
    xp += reward;
    plot.clear();
    return reward;
  }

  int sellBasket() {
    final proceeds = basketValue;
    coins += proceeds;
    basket.clear();
    return proceeds;
  }

  Map<String, dynamic> toMap() => {
        'basket': basket.map((type, amount) => MapEntry(type.name, amount)),
        'seeds': seeds.map((type, amount) => MapEntry(type.name, amount)),
        'visitDays': visitDays,
        'claimedVisitDays': claimedVisitDays,
        'lastVisitDay': lastVisitDay,
        'coins': coins,
        'xp': xp,
        'plotCount': plotCount,
        'plots': plots.map((p) => p.toMap()).toList(),
        'sellBoostLevel': sellBoostLevel,
        'seedDiscountLevel': seedDiscountLevel,
        'growSpeedLevel': growSpeedLevel,
      };

  factory Player.fromMap(Map<String, dynamic> map) {
    final plotCount = map['plotCount'] as int? ?? GameConstants.startingPlots;
    final player = Player.initial(plotCount: plotCount);
    player.coins = map['coins'] as int? ?? GameConstants.startingCoins;
    player.xp = map['xp'] as int? ?? 0;
    player.sellBoostLevel = map['sellBoostLevel'] as int? ?? 0;
    player.seedDiscountLevel = map['seedDiscountLevel'] as int? ?? 0;
    player.growSpeedLevel = map['growSpeedLevel'] as int? ?? 0;

    player.visitDays = (map['visitDays'] as int? ?? 0).clamp(0, visitDayLimit);
    player.claimedVisitDays =
        (map['claimedVisitDays'] as int? ?? 0).clamp(0, player.visitDays);
    player.lastVisitDay = map['lastVisitDay'] as int?;
    for (final (key, inventory) in [
      ('basket', player.basket),
      ('seeds', player.seeds)
    ]) {
      final raw = map[key];
      if (raw is Map) {
        for (final type in CropType.values) {
          final count = raw[type.name];
          if (count is int && count > 0) inventory[type] = count;
        }
      }
    }

    final rawPlots = map['plots'];
    if (rawPlots is List) {
      player.plots = rawPlots
          .map((p) => Plot.fromMap(Map<String, dynamic>.from(p as Map)))
          .toList();
    }
    if (player.plots.length != player.plotCount) {
      player.plotCount = player.plots.length;
    }
    return player;
  }
}

// ------------------------------------------------------------
// [ui/widgets/plot_widget.dart]  Canteiro isométrico (losango)
// ------------------------------------------------------------

/// Losango 2:1 compartilhado pelos canteiros e pelo botão de expansão.
Path isoDiamondPath(Size size) => Path()
  ..moveTo(size.width / 2, 0)
  ..lineTo(size.width, size.height / 2)
  ..lineTo(size.width / 2, size.height)
  ..lineTo(0, size.height / 2)
  ..close();

/// Recorta a pintura E o hit-test no formato de losango. Assim um toque na
/// borda compartilhada por dois canteiros seleciona apenas um deles.
class IsoDiamondClipper extends CustomClipper<Path> {
  const IsoDiamondClipper();

  @override
  Path getClip(Size size) => isoDiamondPath(size);

  @override
  bool shouldReclip(IsoDiamondClipper oldClipper) => false;
}

/// Pinta a terra arada e o cultivo conforme o estágio de crescimento
/// (0 = vazio; 1..3 = crescendo; [GameConstants.cropStageCount] = pronta).
class PlotPainter extends CustomPainter {
  PlotPainter(
      {required this.stage,
      required this.ready,
      required this.tilled,
      required this.wet});

  final int stage;
  final bool ready;
  final bool tilled;
  final bool wet;

  @override
  void paint(Canvas canvas, Size size) {
    final path = isoDiamondPath(size);
    final rect = Offset.zero & size;

    canvas.save();
    canvas.clipPath(path);

    // Terra: mais clara vazia; mais escura quando cultivada.
    final soil = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: wet
            ? const [Color(0xff744c36), Color(0xff3e382e)]
            : !tilled
                ? const [Color(0xFFAA9467), Color(0xFF7D6B49)]
                : stage == 0
                    ? const [Color(0xFFBC8A55), Color(0xFF7A4E2F)]
                    : const [Color(0xFF9C7040), Color(0xFF5C4026)],
      ).createShader(rect);
    canvas.drawRect(rect, soil);

    // Sulcos de plantio seguindo a diagonal maior do losango.
    final furrow = Paint()
      ..color = const Color(0xFF6B4A2C)
      ..strokeWidth = math.max(1.5, size.width * 0.03)
      ..strokeCap = StrokeCap.round;
    final ridge = Paint()
      ..color = const Color(0xFFCDA06A)
      ..strokeWidth = math.max(1.0, size.width * 0.012)
      ..strokeCap = StrokeCap.round;
    for (var r = 1; tilled && r < 4; r++) {
      final sx = size.width * (0.10 + r * 0.14);
      final sy = size.height * (0.74 - r * 0.16);
      final from = Offset(sx, sy);
      final to = Offset(
        sx + size.width * 0.38,
        sy + size.height * 0.38,
      );
      canvas.drawLine(from, to, furrow);
      canvas.drawLine(
        from + const Offset(0, -2),
        to + const Offset(0, -2),
        ridge,
      );
    }

    _paintCrop(canvas, size);
    canvas.restore();

    // Contorno: dourado quando pronto para colher.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ready ? size.width * 0.05 : size.width * 0.035
        ..color = ready ? const Color(0xFFFFD54F) : const Color(0xFF4A3A26),
    );
  }

  void _paintCrop(Canvas canvas, Size size) {
    if (stage == 0) return;
    final center = Offset(size.width / 2, size.height * 0.40);
    final baseR = size.width * (0.06 + stage * 0.035);
    final leafCount = 4 + stage * 2;
    final leaf = Paint()..color = _stageColor(stage);

    for (var i = 0; i < leafCount; i++) {
      final angle = (i / leafCount) * 2 * math.pi;
      final r = baseR * (i.isEven ? 1.05 : 0.78);
      final leafCenter = center +
          Offset(
            math.cos(angle) * r * 0.55,
            math.sin(angle) * r * 0.55,
          );
      canvas.drawCircle(leafCenter, r, leaf);
    }
    canvas.drawCircle(
      center,
      baseR * 0.62,
      Paint()..color = const Color(0xFFA5D65A),
    );

    // Brilho indicando pronta para colher.
    if (stage == GameConstants.cropStageCount) {
      canvas.drawCircle(
        center,
        baseR * 1.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFFF9C4),
      );
    }
  }

  Color _stageColor(int stage) => switch (stage) {
        1 => const Color(0xFF9CCC65),
        2 => const Color(0xFF74A93A),
        3 => const Color(0xFF52912E),
        _ => const Color(0xFF3E8E41),
      };

  @override
  bool shouldRepaint(PlotPainter oldDelegate) =>
      stage != oldDelegate.stage ||
      ready != oldDelegate.ready ||
      tilled != oldDelegate.tilled ||
      wet != oldDelegate.wet;
}

/// Canteiro individual renderizado como losango isométrico.
class PlotWidget extends StatelessWidget {
  const PlotWidget({super.key, required this.plot, required this.onTap});

  final Plot plot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dead = plot.isDead(now);
    final stage = dead || plot.isPlanting(now) ? 0 : plot.stage(now);
    final ready = stage == GameConstants.cropStageCount;
    final label = dead
        ? 'Planta morta'
        : plot.isEmpty
            ? (plot.isWet(now)
                ? 'Terra úmida'
                : plot.tilled
                    ? 'Terra seca'
                    : 'Terra para preparar')
            : ready
                ? '${plot.plantedCrop!.label} pronta para colher'
                : '${plot.plantedCrop!.label} crescendo';

    return Semantics(
      button: true,
      label: label,
      child: ClipPath(
        clipper: const IsoDiamondClipper(),
        clipBehavior: Clip.hardEdge,
        child: GestureDetector(
          onTap: onTap,
          child: CustomPaint(
            painter: PlotPainter(
                stage: stage,
                ready: ready,
                tilled: plot.tilled,
                wet: plot.isWet(now)),
            child: SizedBox.expand(
              child: dead
                  ? const Center(
                      child: Icon(Icons.eco, color: Color(0xff443426)))
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// [ui/widgets/new_plot_tile.dart]  Losango do canteiro expansível
// ------------------------------------------------------------

/// Losango tracejado que representa o próximo canteiro comprável.
class NewPlotTile extends StatelessWidget {
  const NewPlotTile({
    super.key,
    required this.cost,
    required this.enabled,
    required this.onTap,
  });

  final int cost;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Novo canteiro · $cost moedas',
      child: ClipPath(
        clipper: const IsoDiamondClipper(),
        clipBehavior: Clip.hardEdge,
        child: GestureDetector(
          onTap: onTap,
          child: CustomPaint(
            painter: NewPlotPainter(enabled: enabled),
            child: FractionallySizedBox(
              widthFactor: .72,
              heightFactor: .65,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Novo canteiro',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: enabled
                            ? const Color(0xFF2E4E1E)
                            : const Color(0xFF6E6E6E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '🪙 $cost',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: enabled
                            ? const Color(0xFF2E4E1E)
                            : const Color(0xFF6E6E6E),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NewPlotPainter extends CustomPainter {
  NewPlotPainter({required this.enabled});

  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final path = isoDiamondPath(size);
    final rect = Offset.zero & size;

    canvas.save();
    canvas.clipPath(path);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: enabled
              ? const [Color(0xFFB9D67E), Color(0xFF7EA652)]
              : const [Color(0xFF9C9C9C), Color(0xFF6E6E6E)],
        ).createShader(rect),
    );

    // Bordadura interna tracejada sugerindo o contorno do futuro canteiro.
    final inner = Path()
      ..moveTo(size.width / 2, size.height * 0.16)
      ..lineTo(size.width * 0.84, size.height / 2)
      ..lineTo(size.width / 2, size.height * 0.84)
      ..lineTo(size.width * 0.16, size.height / 2)
      ..close();
    canvas.drawPath(
      inner,
      Paint()
        ..color = enabled ? const Color(0xFF4E7A2A) : const Color(0xFF5A5A5A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.width * 0.03),
    );
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.width * 0.035)
        ..color = enabled ? const Color(0xFF3E5C2A) : const Color(0xFF555555),
    );
  }

  @override
  bool shouldRepaint(NewPlotPainter oldDelegate) =>
      enabled != oldDelegate.enabled;
}

// ------------------------------------------------------------
// [ui/widgets/crop_selector_sheet.dart]  Seletor de culturas
// ------------------------------------------------------------
class CropSelectorSheet extends StatelessWidget {
  const CropSelectorSheet({
    super.key,
    required this.player,
    required this.onSelected,
  });

  final Player player;
  final ValueChanged<CropType> onSelected;

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final minutes = d.inMinutes % 60;
      return '${d.inHours}h${minutes.toString().padLeft(2, '0')}min';
    }
    if (d.inMinutes > 0) {
      final seconds = d.inSeconds % 60;
      return '${d.inMinutes}min${seconds.toString().padLeft(2, '0')}s';
    }
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Loja de sementes',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: CropType.values.length,
                itemBuilder: (context, index) {
                  final type = CropType.values[index];
                  final crop = Crops.of(type);
                  final unlocked = player.isUnlocked(type);
                  final cost = player.effectiveSeedCost(crop);
                  final sell = player.effectiveSellValue(crop);
                  final canAfford = player.coins >= cost;
                  final isNew = player.isNewlyUnlocked(type);

                  return ListTile(
                    leading: Opacity(
                      opacity: unlocked ? 1.0 : 0.4,
                      child: Text(
                        crop.emoji,
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          crop.label,
                          style: unlocked
                              ? null
                              : const TextStyle(color: Colors.grey),
                        ),
                        if (isNew) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Novo!',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          unlocked
                              ? (canAfford
                                  ? 'Semente 🪙 $cost · Vende 🪙 $sell'
                                  : 'Semente 🪙 $cost · Faltam 🪙 ${cost - player.coins}')
                              : 'Requer nível ${crop.unlockLevel}',
                        ),
                        if (unlocked) ...[
                          const SizedBox(height: 2),
                          Text(
                            '⏱️ ${_formatDuration(player.effectiveGrowTime(crop))}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                    isThreeLine: unlocked,
                    trailing: unlocked
                        ? const Icon(Icons.chevron_right, color: Colors.green)
                        : const Icon(Icons.lock_outline, color: Colors.grey),
                    onTap: () {
                      if (!unlocked) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                'Requer nível ${crop.unlockLevel} para plantar ${crop.label}.',
                              ),
                            ),
                          );
                        return;
                      }
                      if (!canAfford) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(
                            content: Text(
                                'Moedas insuficientes! Faltam ${cost - player.coins}.'),
                          ));
                        return;
                      }
                      onSelected(type);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// [ui/widgets/upgrade_sheet.dart]  Modal de upgrades
// ------------------------------------------------------------
class UpgradeSheet extends StatelessWidget {
  const UpgradeSheet({
    super.key,
    required this.player,
    required this.onPurchased,
  });

  final Player player;
  final VoidCallback onPurchased;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '🛠️ Upgrades da fazenda',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final type in UpgradeType.values)
                    _UpgradeTile(
                      player: player,
                      type: type,
                      onPurchased: onPurchased,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpgradeTile extends StatelessWidget {
  const _UpgradeTile({
    required this.player,
    required this.type,
    required this.onPurchased,
  });

  final Player player;
  final UpgradeType type;
  final VoidCallback onPurchased;

  @override
  Widget build(BuildContext context) {
    final currentLevel = player.upgradeLevel(type);
    final maxed = currentLevel >= GameConstants.maxUpgradeLevel;
    final cost = player.upgradeCost(type);
    final canAfford = player.coins >= cost;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(type.emoji, style: const TextStyle(fontSize: 28)),
        title: Text(type.label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${type.description}\nNível $currentLevel/${GameConstants.maxUpgradeLevel}',
        ),
        isThreeLine: true,
        trailing: maxed
            ? const Text(
                'Máx',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              )
            : FilledButton(
                style: canAfford
                    ? null
                    : FilledButton.styleFrom(
                        backgroundColor: Colors.grey.shade400,
                        foregroundColor: Colors.white,
                      ),
                onPressed: () {
                  if (!canAfford) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            'Moedas insuficientes! Faltam 🪙 ${cost - player.coins}.',
                          ),
                        ),
                      );
                    return;
                  }
                  final ok = player.buyUpgrade(type);
                  if (ok) onPurchased();
                },
                child: Text('🪙 $cost'),
              ),
      ),
    );
  }
}

// ------------------------------------------------------------
// [ui/screens/home_screen.dart]  Tela principal da fazenda
// ------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.player,
    this.onShouldSave,
  });

  final Player player;
  final VoidCallback? onShouldSave;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _FarmTool { inspect, hoe, seed, water, harvest }

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  _FarmTool _tool = _FarmTool.inspect;
  Plot? _focusedPlot;
  String? _plotHint;
  CropType _seed = CropType.alface;

  /// Banner de teste do Google AdMob (Android).
  static const _bannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  static const _bannerRetryDelays = [
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(minutes: 2),
  ];

  Timer? _tick;
  BannerAd? _bannerAd;
  bool _bannerLoaded = false;
  Timer? _bannerRetryTimer;
  int _bannerRetryAttempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Atualiza as barras de progresso em tempo real.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (_useTestAds) _loadBanner();
  }

  void _loadBanner() {
    // O banner adaptativo ancorado precisa da largura real da tela, que só
    // existe após o primeiro layout. Leia no pós-frame e carregue o anúncio
    // em largura cheia no rodapé (canto inferior em paisagem).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_useTestAds) return;
      final media = MediaQuery.of(context);
      final width = (media.size.width - media.viewPadding.horizontal).floor();
      final AnchoredAdaptiveBannerAdSize? adSize;
      try {
        adSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
            width);
      } catch (error) {
        debugPrint('Falha ao calcular o tamanho do anúncio de teste: $error');
        _scheduleBannerRetry();
        return;
      }
      if (!mounted) return;
      if (adSize == null) {
        _scheduleBannerRetry();
        return;
      }

      final banner = BannerAd(
        adUnitId: _bannerAdUnitId,
        size: adSize,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted || !identical(_bannerAd, ad)) return;
            setState(() {
              _bannerLoaded = true;
              _bannerRetryAttempts = 0;
            });
          },
          onAdFailedToLoad: (ad, _) => _onBannerLoadFailure(ad),
        ),
      );
      _bannerAd = banner;
      try {
        await banner.load();
      } catch (error) {
        debugPrint('Falha ao carregar o anúncio de teste: $error');
        _onBannerLoadFailure(banner);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _onBannerLoadFailure(Ad ad) {
    if (!mounted || !identical(_bannerAd, ad)) return;
    setState(() {
      _bannerAd = null;
      _bannerLoaded = false;
    });
    unawaited(ad.dispose());
    _scheduleBannerRetry();
  }

  void _scheduleBannerRetry() {
    if (!mounted) return;
    _bannerRetryTimer?.cancel();
    if (_bannerRetryAttempts >= _bannerRetryDelays.length) return;
    final delay = _bannerRetryDelays[_bannerRetryAttempts++];
    _bannerRetryTimer = Timer(delay, () {
      _bannerRetryTimer = null;
      if (mounted) _loadBanner();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Ao retomar, re-renderiza com DateTime.now(): o tempo offline é
      // contabilizado e as plantações não ficam congeladas.
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _bannerRetryTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _showFarmMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 62),
        content: Text(message),
      ));
  }

  void _farmChanged() {
    widget.onShouldSave?.call();
    setState(() {});
  }

  void _handlePlotTap(Plot plot) {
    final player = widget.player;
    final now = DateTime.now();
    String? hint;
    final changed = switch (_tool) {
      _FarmTool.inspect => false,
      _FarmTool.hoe => plot.hoe(now),
      _FarmTool.water => plot.water(now),
      _FarmTool.seed => player.plant(plot, Crops.of(_seed), now),
      _FarmTool.harvest => player.harvest(plot, now) > 0,
    };
    if (!changed &&
        _tool == _FarmTool.seed &&
        plot.isEmpty &&
        plot.isWet(now) &&
        (player.seeds[_seed] ?? 0) == 0) {
      hint = 'Sem sementes de ${_seed.label} · abra a Loja';
    }
    if (changed) widget.onShouldSave?.call();
    setState(() {
      _focusedPlot = plot;
      _plotHint = hint;
    });
  }

  void _showFarmDialog(String title, Widget Function(StateSetter) content) {
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(title),
          content: SizedBox(
              width: 480, child: SingleChildScrollView(child: content(update))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'))
          ],
        ),
      ),
    );
  }

  void _showWarehouse() {
    final player = widget.player;
    _showFarmDialog(
        'Armazém',
        (update) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (player.basket.isEmpty)
                  const Text('A colheita ainda está vazia.'),
                for (final entry in player.basket.entries)
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(entry.key.label),
                    subtitle: Text('Quantidade: ${entry.value}'),
                    trailing: TextButton(
                      onPressed: () {
                        player.sellCrop(entry.key);
                        _farmChanged();
                        update(() {});
                      },
                      child: Text(
                          'Vender por ${entry.value * player.effectiveSellValue(Crops.of(entry.key))}'),
                    ),
                  ),
                if (player.basket.isNotEmpty)
                  FilledButton(
                    onPressed: () {
                      player.sellBasket();
                      _farmChanged();
                      update(() {});
                    },
                    child: Text('Vender tudo por ${player.basketValue}'),
                  ),
              ],
            ));
  }

  void _showVisits() {
    final player = widget.player;
    if (player.recordVisit(DateTime.now())) _farmChanged();
    _showFarmDialog(
        'Visitas de 7 dias',
        (update) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                    value: player.visitDays / Player.visitDayLimit),
                Text(
                    '${player.visitDays}/${Player.visitDayLimit} dias registrados'),
                for (var day = 1; day <= Player.visitDayLimit; day++)
                  ListTile(
                    title: Text('Dia $day'),
                    subtitle: Text(
                        '${Player.visitCoins(day)} moedas · $day sementes de alface'),
                    trailing: TextButton(
                      onPressed: day == player.claimedVisitDays + 1 &&
                              day <= player.visitDays
                          ? () {
                              if (player.claimVisitReward(day)) {
                                _farmChanged();
                                update(() {});
                              }
                            }
                          : null,
                      child: Text(day <= player.claimedVisitDays
                          ? 'Resgatado'
                          : day <= player.visitDays
                              ? 'Resgatar'
                              : 'Aguardando'),
                    ),
                  ),
              ],
            ));
  }

  static String _formatDuration(Duration d) {
    if (d.isNegative || d.inSeconds <= 0) return 'agora';
    if (d.inHours >= 1) {
      final minutes = d.inMinutes % 60;
      return minutes == 0
          ? '${d.inHours}h'
          : '${d.inHours}h${minutes.toString().padLeft(2, '0')}min';
    }
    if (d.inMinutes >= 1) {
      final seconds = d.inSeconds % 60;
      return seconds == 0
          ? '${d.inMinutes}min'
          : '${d.inMinutes}min${seconds.toString().padLeft(2, '0')}s';
    }
    return '${d.inSeconds}s';
  }

  void _showFarmSheet({required WidgetBuilder builder}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Builder(builder: builder),
        ),
      ),
    );
  }

  void _showSeeds() {
    final player = widget.player;
    _showFarmDialog(
        'Sementes guardadas',
        (_) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (player.seeds.isEmpty)
                  const Text(
                      'Compre sementes na Loja ou resgate uma recompensa de visita.'),
                for (final entry in player.seeds.entries)
                  ListTile(
                    title: Text(entry.key.label),
                    subtitle: Text('Quantidade: ${entry.value}'),
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _seed = entry.key;
                        _tool = _FarmTool.seed;
                        _plotHint = null;
                      });
                    },
                  ),
              ],
            ));
  }

  void _showShop() {
    _showFarmSheet(
      builder: (context) => CropSelectorSheet(
        player: widget.player,
        onSelected: (seed) {
          if (widget.player.buySeed(seed)) _farmChanged();
        },
      ),
    );
  }

  void _showUpgrades() {
    _showFarmSheet(
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => UpgradeSheet(
          player: widget.player,
          onPurchased: () {
            widget.onShouldSave?.call();
            setState(() {});
            setSheetState(() {});
          },
        ),
      ),
    );
  }

  void _buyNewPlot() {
    final player = widget.player;
    if (!player.canBuyMorePlots) {
      _showFarmMessage('Fazenda no limite máximo de canteiros!');
    } else if (player.buyPlot()) {
      _farmChanged();
    } else {
      final missing = player.nextPlotCost - player.coins;
      _showFarmMessage(
          'Moedas insuficientes! Faltam 🪙 $missing para o novo canteiro.');
    }
  }

  Widget _toolButton(_FarmTool tool, IconData icon, String label) {
    final active = _tool == tool;
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor:
            active ? const Color(0xff29351f) : const Color(0xfffff5d8),
        backgroundColor: active ? const Color(0xfff9cf72) : null,
      ),
      onPressed: () => setState(() => _tool = tool),
      icon: Icon(icon, size: 17),
      label: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _FarmScene(
            player: player,
            onPlotTap: _handlePlotTap,
            onBuyPlot: _buyNewPlot,
            focusedPlot: _focusedPlot,
            plotHint: _plotHint,
          ),
          SafeArea(
            minimum: const EdgeInsets.all(8),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: _FarmPanel(child: _LevelStatus(player: player)),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: _FarmPanel(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.monetization_on,
                            color: Color(0xffffd167), size: 17),
                        const SizedBox(width: 5),
                        Text('${player.coins}'),
                        TextButton(
                            onPressed: _showWarehouse,
                            child: Text('Armazém ${player.basketCount}')),
                        TextButton(
                            onPressed: _showShop, child: const Text('Loja')),
                        IconButton(
                          tooltip: 'Visitas de 7 dias',
                          icon: const Icon(Icons.card_giftcard, size: 20),
                          onPressed: _showVisits,
                        ),
                        IconButton(
                          icon: const Icon(Icons.trending_up, size: 20),
                          tooltip: 'Melhorias',
                          onPressed: _showUpgrades,
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _FarmPanel(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _toolButton(_FarmTool.inspect, Icons.touch_app,
                              'Inspecionar'),
                          _toolButton(_FarmTool.hoe, Icons.handyman, 'Enxada'),
                          TextButton.icon(
                            onPressed: _showSeeds,
                            icon: const Icon(Icons.eco, size: 17),
                            label: Text(_tool == _FarmTool.seed
                                ? '${_seed.label} · ${player.seeds[_seed] ?? 0}'
                                : 'Sementes'),
                          ),
                          _toolButton(
                              _FarmTool.water, Icons.water_drop, 'Regar'),
                          _toolButton(
                              _FarmTool.harvest, Icons.agriculture, 'Colher'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _bannerLoaded && _bannerAd != null
          ? SafeArea(
              top: false,
              child: SizedBox(
                height: _bannerAd!.size.height.toDouble(),
                child: Center(
                  child: SizedBox(
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _FarmPanel extends StatelessWidget {
  const _FarmPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const foreground = Color(0xfffff5d8);
    return Material(
      color: const Color(0xf0223528),
      elevation: 3,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: IconTheme(
          data: const IconThemeData(color: foreground),
          child: TextButtonTheme(
            data: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: foreground,
                disabledForegroundColor: const Color(0xffb9b7a4),
              ),
            ),
            child: DefaultTextStyle(
              style:
                  const TextStyle(color: foreground, fontFamily: 'FarmRoboto'),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelStatus extends StatelessWidget {
  const _LevelStatus({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final target = player.levelXpGoal;
    return SizedBox(
      width: 146,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text('Nível ${player.level}'),
                  const SizedBox(width: 12),
                  Text(target == null
                      ? 'Máx.'
                      : '${player.currentLevelXp}/$target XP'),
                ],
              ),
            ),
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: player.levelProgress,
              semanticsLabel: 'Progresso do nível',
              minHeight: 5,
              borderRadius: BorderRadius.circular(4),
              color: const Color(0xfff9cf72),
              backgroundColor: const Color(0xff52604c),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// [ui/widgets/farm_scene.dart]  Cena isométrica 2.5D da fazenda
// ------------------------------------------------------------

/// Compõe os canteiros em um terreno contínuo, usando a projeção isométrica
/// de [GameConstants.plotCenterForIndex]. A cena escala à largura da tela e
/// o toque é identificado pelo mesmo mapeamento, sem ambiguidade na borda
/// compartilhada (garantida pelo recorte de hit-test de cada canteiro).
class _FarmScene extends StatelessWidget {
  const _FarmScene({
    required this.player,
    required this.onPlotTap,
    required this.onBuyPlot,
    required this.focusedPlot,
    required this.plotHint,
  });

  final Player player;
  final void Function(Plot plot) onPlotTap;
  final VoidCallback onBuyPlot;
  final Plot? focusedPlot;
  final String? plotHint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final tileCount =
            player.plots.length + (player.canBuyMorePlots ? 1 : 0);

        // Caixa envolvente dos losangos, no espaço isométrico.
        var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0;
        for (var i = 0; i < tileCount; i++) {
          final c = GameConstants.plotCenterForIndex(i);
          minX = math.min(minX, c.dx);
          maxX = math.max(maxX, c.dx);
          minY = math.min(minY, c.dy);
          maxY = math.max(maxY, c.dy);
        }
        minX -= GameConstants.isoTileHalfWidth;
        maxX += GameConstants.isoTileHalfWidth;
        minY -= GameConstants.isoTileHalfHeight;
        maxY += GameConstants.isoTileHalfHeight;

        final contentW = math.max(1.0, maxX - minX);
        final contentH = math.max(1.0, maxY - minY);

        // Escala para caber com folga, preservando o aspecto 2:1 do losango.
        final scale = math.min(w * .46 / contentW, h * .48 / contentH);
        final isoCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
        final screenCenter = Offset(w * .41, h * .59);

        final tileW = GameConstants.isoTileHalfWidth * 2 * scale;
        final tileH = GameConstants.isoTileHalfHeight * 2 * scale;

        double leftFor(int i) {
          final c = GameConstants.plotCenterForIndex(i);
          return screenCenter.dx + (c.dx - isoCenter.dx) * scale - tileW / 2;
        }

        double topFor(int i) {
          final c = GameConstants.plotCenterForIndex(i);
          return screenCenter.dy + (c.dy - isoCenter.dy) * scale - tileH / 2;
        }

        final focus =
            player.plots.indexWhere((plot) => identical(plot, focusedPlot));
        return ColoredBox(
          color: const Color(0xFF253F29),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                child:
                    Image.asset('assets/images/farm.webp', fit: BoxFit.cover),
              ),
              // Índice crescente = mais perto do observador; desenhado por
              // último para dar a sobreposição frontal correta.
              for (var i = 0; i < player.plots.length; i++)
                Positioned(
                  left: leftFor(i),
                  top: topFor(i),
                  width: tileW,
                  height: tileH,
                  child: PlotWidget(
                    plot: player.plots[i],
                    onTap: () => onPlotTap(player.plots[i]),
                  ),
                ),
              if (player.canBuyMorePlots && tileCount > 0)
                Positioned(
                  left: leftFor(player.plots.length),
                  top: topFor(player.plots.length),
                  width: tileW,
                  height: tileH,
                  child: NewPlotTile(
                    cost: player.nextPlotCost,
                    enabled: player.coins >= player.nextPlotCost,
                    onTap: onBuyPlot,
                  ),
                ),
              if (focus >= 0)
                Positioned(
                  width: 192,
                  left: (leftFor(focus) + tileW / 2 - 96)
                      .clamp(4.0, math.max(4.0, w - 196)),
                  top: math.max(52.0, topFor(focus) - 68),
                  child: IgnorePointer(
                    child:
                        _PlotNotice(plot: player.plots[focus], hint: plotHint),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PlotNotice extends StatelessWidget {
  const _PlotNotice({required this.plot, required this.hint});

  final Plot plot;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final String label;
    double? progress;
    String? details;
    if (hint != null) {
      label = hint!;
    } else if (plot.isWatering(now) || plot.isPlanting(now)) {
      final watering = plot.isWatering(now);
      final end = watering ? plot.wateredAt! : plot.plantedAt!;
      final duration = watering ? Plot.wateringDuration : Plot.plantingDuration;
      label = watering ? 'Regando terra…' : 'Plantando semente…';
      progress =
          (1 - end.difference(now).inMilliseconds / duration.inMilliseconds)
              .clamp(0.0, 1.0);
    } else if (plot.isDead(now)) {
      label = 'Planta morta · limpe com a enxada';
    } else if (plot.isPlanted) {
      final health = (plot.health(now) * 100).ceil();
      final end = plot.plantedAt!.add(plot.growDuration!);
      final remaining = end.difference(now);
      label = plot.isReady(now)
          ? '${plot.plantedCrop!.label} pronta para colher'
          : '${plot.plantedCrop!.label} crescendo';
      details =
          'Saúde $health/100${remaining.isNegative ? '' : ' · ${_HomeScreenState._formatDuration(remaining)}'}';
      progress = plot.progress(now);
    } else if (!plot.tilled) {
      label = 'Use a enxada para preparar';
    } else {
      label = plot.isWet(now)
          ? 'Terra úmida · pronta para plantar'
          : 'Terra seca · regue antes de plantar';
    }
    return _FarmPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12)),
            if (details != null)
              Text(details, style: const TextStyle(fontSize: 11)),
            if (progress != null) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(value: progress, minHeight: 4),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// [main.dart]  Inicialização do app
// ------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Trava o app em paisagem (melhor aproveitamento da cena isométrica 2.5D).
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  // AdMob de teste — o App ID real entra no AndroidManifest.xml.
  // Inicializa somente no Android (não na web), usando os IDs de teste.
  if (_useTestAds) {
    try {
      await MobileAds.instance.initialize();
    } catch (error) {
      debugPrint('Falha ao inicializar anúncios de teste: $error');
    }
  }
  await Hive.initFlutter();
  final box = await Hive.openBox(GameConstants.hiveBoxName);

  final player = await _loadOrCreate(box);
  runApp(FazendinhaApp(player: player, box: box));
}

Future<Player> _loadOrCreate(Box box) async {
  final saved = box.get(GameConstants.playerKey);
  if (saved is Map) {
    return Player.fromMap(Map<String, dynamic>.from(saved));
  }
  final fresh = Player.initial(plotCount: GameConstants.startingPlots);
  await box.put(GameConstants.playerKey, fresh.toMap());
  await box.flush();
  return fresh;
}

class FazendinhaApp extends StatefulWidget {
  const FazendinhaApp({super.key, required this.player, this.box});

  final Player player;
  final Box? box;

  @override
  State<FazendinhaApp> createState() => _FazendinhaAppState();
}

class _FazendinhaAppState extends State<FazendinhaApp>
    with WidgetsBindingObserver {
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.player.recordVisit(DateTime.now())) unawaited(_save());
    _saveTimer = Timer.periodic(
      const Duration(seconds: GameConstants.autoSaveSeconds),
      (_) => _save(),
    );
  }

  Future<void> _save() async {
    final box = widget.box;
    if (box == null) return;
    try {
      // Aguarda a gravação antes do flush para não perder o progresso se o
      // app for encerrado logo após plantar/colher/comprar.
      await box.put(GameConstants.playerKey, widget.player.toMap());
      await box.flush();
    } catch (e) {
      // Falha de escrita não deve derrubar o app em segundo plano.
      debugPrint('Falha ao salvar o progresso: $e');
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.player.recordVisit(DateTime.now())) {
      setState(() {});
      unawaited(_save());
    }
    final isBackground = state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached;
    if (isBackground) {
      _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Little Farm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'FarmRoboto',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4CAF50)),
        useMaterial3: true,
      ),
      home: HomeScreen(
        player: widget.player,
        onShouldSave: _save,
      ),
    );
  }
}
