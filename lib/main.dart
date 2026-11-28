// ============================================================
// 🌱 LITTLE FARM IDLE — FASE 2 + RODADA ANDROID (arquivo único)
// ------------------------------------------------------------
// Cole este conteúdo como: lib/main.dart
// (substitui toda a estrutura de pastas lib/core, lib/models, lib/ui)
//
// Fase 2: expansão de canteiros + melhorias temporárias
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
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dairy_cow_art.dart';
import 'rewarded_upgrade_ad.dart';
import 'social_farm.dart';
import 'visit_rewards.dart';

part 'farm_art.dart';

/// Liga o AdMob apenas em builds Android reais (não na web), usando os IDs
/// de teste do Google. Nos testes, rode com --dart-define=ENABLE_TEST_ADS=false
/// para evitar a MissingPluginException do plugin de anúncios.
bool get _useTestAds =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    const bool.fromEnvironment('ENABLE_TEST_ADS', defaultValue: true);

String? get _rewardedUpgradeUnit {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  const configured = String.fromEnvironment('LITTLE_FARM_REWARDED_AD_UNIT_ID');
  if (configured.isNotEmpty) return configured;
  return _useTestAds ? 'ca-app-pub-3940256099942544/5224354917' : null;
}

bool get _simulateUpgradeAd =>
    kIsWeb && const bool.fromEnvironment('WEEDS_PREVIEW');

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
  static const double newPlotGrowthFactor = 1.75;
  static const int maxPlots = 16;

  /// Intervalo de salvamento automático (segundos).
  static const int autoSaveSeconds = 30;

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
      (row - col) * isoTileHalfWidth,
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
    required int sellValue,
    required this.growTime,
    required this.unlockLevel,
  }) : _baseSellValue = sellValue;

  final CropType type;
  final int seedCost;
  final int _baseSellValue;
  final Duration growTime;
  final int unlockLevel;

  int get sellValue {
    final hours = growTime.inMilliseconds / Duration.millisecondsPerHour;
    final baseProfit = _baseSellValue - seedCost;
    return _baseSellValue + (baseProfit * .03 * hours).round();
  }

  static const maxHarvestWindow = Duration(hours: 48);
  static const harvestWindowMultiplier = 48;

  Duration get harvestWindow {
    final proportional = growTime * harvestWindowMultiplier;
    return proportional > maxHarvestWindow ? maxHarvestWindow : proportional;
  }

  String get emoji => type.emoji;
  String get label => type.label;
}

/// Repositório estático com os dados das 8 culturas.
class Crops {
  static Crop of(CropType type) => switch (type) {
        CropType.alface => const Crop(
            type: CropType.alface,
            seedCost: 5,
            sellValue: 8,
            growTime: Duration(seconds: 30),
            unlockLevel: 1,
          ),
        CropType.cenoura => const Crop(
            type: CropType.cenoura,
            seedCost: 25,
            sellValue: 40,
            growTime: Duration(minutes: 2),
            unlockLevel: 2,
          ),
        CropType.milho => const Crop(
            type: CropType.milho,
            seedCost: 120,
            sellValue: 190,
            growTime: Duration(minutes: 20),
            unlockLevel: 3,
          ),
        CropType.tomate => const Crop(
            type: CropType.tomate,
            seedCost: 200,
            sellValue: 320,
            growTime: Duration(minutes: 35),
            unlockLevel: 4,
          ),
        CropType.morango => const Crop(
            type: CropType.morango,
            seedCost: 350,
            sellValue: 550,
            growTime: Duration(minutes: 55),
            unlockLevel: 5,
          ),
        CropType.abobora => const Crop(
            type: CropType.abobora,
            seedCost: 600,
            sellValue: 1260,
            growTime: Duration(hours: 3),
            unlockLevel: 6,
          ),
        CropType.cafe => const Crop(
            type: CropType.cafe,
            seedCost: 1000,
            sellValue: 2100,
            growTime: Duration(hours: 5),
            unlockLevel: 7,
          ),
        CropType.cana => const Crop(
            type: CropType.cana,
            seedCost: 1800,
            sellValue: 3560,
            growTime: Duration(hours: 8),
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
  int _harvestsUntilWeeds = _newWeedInterval();
  int _weedDecayMillis = 0;

  static final _weedRandom = math.Random();
  static int _newWeedInterval() => 15 + _weedRandom.nextInt(16);

  bool get hasWeeds => _harvestsUntilWeeds == 0;

  void recordHarvest() {
    if (!hasWeeds) _harvestsUntilWeeds--;
  }

  void removeWeeds(DateTime now) {
    final at = plantedAt;
    final duration = growDuration;
    if (at != null && duration != null) {
      final remaining = at.add(duration).difference(now).inMilliseconds;
      if (remaining > 0) {
        final growingTime = math.min(remaining, duration.inMilliseconds);
        growDuration = duration - Duration(milliseconds: growingTime ~/ 5);
      } else {
        _weedDecayMillis += (-remaining + 1) ~/ 2;
      }
    }
    _harvestsUntilWeeds = _newWeedInterval();
  }

  static const wateringDuration = Duration(seconds: 3);
  static const plantingDuration = Duration(seconds: 2);

  bool isWatering(DateTime now) => wateredAt?.isAfter(now) ?? false;
  bool isWet(DateTime now) => wateredAt != null && !isWatering(now);
  bool isPlanting(DateTime now) => plantedAt?.isAfter(now) ?? false;

  double health(DateTime now) {
    final type = plantedCrop;
    final at = plantedAt;
    final duration = growDuration;
    if (type == null || at == null || duration == null) return 0;

    final elapsed =
        math.max(0, now.difference(at.add(duration)).inMilliseconds);
    final window = Crops.of(type).harvestWindow;
    final decay = elapsed * (hasWeeds ? 1.5 : 1) + _weedDecayMillis;
    return (1 - decay / window.inMilliseconds).clamp(0.0, 1.0);
  }

  DateTime spoilAt() {
    final window = Crops.of(plantedCrop!).harvestWindow.inMilliseconds;
    final remaining = window - _weedDecayMillis;
    final adjusted = hasWeeds ? (remaining * 2 / 3).ceil() : remaining;
    return plantedAt!.add(growDuration!).add(Duration(milliseconds: adjusted));
  }

  bool isDead(DateTime now) => isPlanted && health(now) <= 0;

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
    _weedDecayMillis = 0;
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
        'harvestsUntilWeeds': _harvestsUntilWeeds,
        'weedDecayMillis': _weedDecayMillis,
        'wateredAt': wateredAt?.toIso8601String(),
        'plantedCrop': plantedCrop?.name,
        'plantedAt': plantedAt?.toIso8601String(),
        'growDurationSeconds': growDuration?.inSeconds,
        'growDurationMilliseconds': growDuration?.inMilliseconds,
      };

  factory Plot.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String? ?? 'plot_0';
    final plot = Plot(id: id)..tilled = map['tilled'] != false;

    final weedCycles = map['harvestsUntilWeeds'];
    if (weedCycles is int && weedCycles >= 0 && weedCycles <= 30) {
      plot._harvestsUntilWeeds = weedCycles;
    }

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
    final weedDecay = map['weedDecayMillis'];
    if (weedDecay is int && weedDecay > 0) plot._weedDecayMillis = weedDecay;
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
        UpgradeType.sellBoost => '+20% na venda das culturas',
        UpgradeType.seedDiscount => '−15% no preço das sementes',
        UpgradeType.growSpeed => '−10% no crescimento dos novos plantios',
      };

  Duration get duration => Duration(minutes: this == growSpeed ? 30 : 15);
}

// ------------------------------------------------------------
// [models/player.dart]  Estado central do jogador
// ------------------------------------------------------------
typedef _FarmNotice = ({String message, DateTime at});

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
  final Map<UpgradeType, DateTime> upgradeEndsAt = {};

  Duration upgradeRemaining(UpgradeType type, DateTime now) {
    final remaining = upgradeEndsAt[type]?.difference(now) ?? Duration.zero;
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  bool grantUpgrade(UpgradeType type, DateTime now) {
    if (upgradeRemaining(type, now) > Duration.zero) return false;
    upgradeEndsAt[type] = now.add(type.duration);
    return true;
  }

  final Map<CropType, int> basket = {};
  final Map<CropType, int> seeds = {};
  static const fertilizerCost = 50;
  int fertilizer = 0;
  static const weedControlCost = 30;
  int weedControl = 0;
  int appliedDailyLoginCoins = 0;
  int appliedDailyLoginSeeds = 0;

  static const cowCost = 2000;
  static const milkSaleValue = 40;
  static const milkCycle = Duration(hours: 8);
  static const bottlesPerCycle = 6;
  static const milkXpPerCycle = 48;
  static const cowFeedCost = 30;
  int cowFeed = 0;
  static const guardDogCost = 1000;
  static const guardDogLifetime = Duration(days: 30);
  DateTime? guardDogOwnedUntil;

  bool get hasGuardDogHouse => guardDogOwnedUntil != null;
  bool get hasGuardDog => ownsGuardDog(DateTime.now());
  bool ownsGuardDog(DateTime now) => guardDogOwnedUntil?.isAfter(now) ?? false;
  static const guardDogFoodCost = 15;
  Duration guardDogMealTime = const Duration(hours: 12);
  final List<_FarmNotice> notices = [];

  void addNotice(String message, DateTime at) {
    if (notices.lastOrNull?.message == message) return;
    notices.add((message: message, at: at));
    if (notices.length > 50) notices.removeAt(0);
  }

  int guardDogFood = 0;
  DateTime? guardDogFedUntil;

  bool isGuardDogFed(DateTime now) =>
      ownsGuardDog(now) && (guardDogFedUntil?.isAfter(now) ?? false);

  bool buyGuardDogFood({int quantity = 1}) {
    if (quantity < 1 || quantity > coins ~/ guardDogFoodCost) return false;
    coins -= guardDogFoodCost * quantity;
    guardDogFood += quantity;
    return true;
  }

  bool feedGuardDog(DateTime now, {DateTime? serverDeadline}) {
    if (!ownsGuardDog(now) || guardDogFood == 0 || isGuardDogFed(now))
      return false;
    guardDogFood--;
    guardDogFedUntil = serverDeadline ?? now.add(guardDogMealTime);
    return true;
  }

  bool buyGuardDog(DateTime now) {
    if (ownsGuardDog(now) || coins < guardDogCost) return false;
    coins -= guardDogCost;
    guardDogOwnedUntil = now.add(guardDogLifetime);
    guardDogFedUntil = null;
    return true;
  }

  static const waterCycle = Duration(hours: 4);
  static const feedCycle = Duration(hours: 12);

  Duration milkProductionTime = milkCycle;
  Duration waterRefillTime = waterCycle;
  Duration feedRefillTime = feedCycle;

  DateTime? milkReadyAt;
  DateTime? _milkPausedAt;
  DateTime? cowWaterUntil;
  DateTime? cowFeedUntil;
  int milk = 0;

  bool get hasCow => milkReadyAt != null;

  bool buyCow(DateTime now) {
    if (hasCow || coins < cowCost) return false;
    coins -= cowCost;
    milkReadyAt = now.add(milkProductionTime);
    _milkPausedAt = now;
    return true;
  }

  bool hasCowWater(DateTime now) => cowWaterUntil?.isAfter(now) ?? false;
  bool hasCowFeed(DateTime now) => cowFeedUntil?.isAfter(now) ?? false;

  DateTime _productionTime(DateTime now) {
    final pausedAt = _milkPausedAt;
    if (pausedAt != null) return pausedAt.isBefore(now) ? pausedAt : now;
    var time = now;
    for (final limit in [cowWaterUntil, cowFeedUntil]) {
      if (limit != null && limit.isBefore(time)) time = limit;
    }
    return time;
  }

  Duration? milkRemaining(DateTime now) =>
      milkReadyAt?.difference(_productionTime(now));

  double troughLevel(DateTime now, {required bool water}) {
    final deadline = water ? cowWaterUntil : cowFeedUntil;
    final capacity = water ? waterRefillTime : feedRefillTime;
    return ((deadline?.difference(now).inMicroseconds ?? 0) /
            capacity.inMicroseconds)
        .clamp(0.0, 1.0);
  }

  double milkProgress(DateTime now) {
    final remaining = milkRemaining(now) ?? milkProductionTime;
    return (1 - remaining.inMicroseconds / milkProductionTime.inMicroseconds)
        .clamp(0.0, 1.0);
  }

  bool buyCowFeed({int quantity = 1}) {
    if (quantity < 1 || quantity > coins ~/ cowFeedCost) return false;
    coins -= cowFeedCost * quantity;
    cowFeed += quantity;
    return true;
  }

  bool refillTrough(DateTime now, {required bool water}) {
    final readyAt = milkReadyAt;
    if (readyAt == null || (!water && cowFeed == 0)) return false;
    _milkPausedAt = _productionTime(now);
    if (water) {
      cowWaterUntil = now.add(waterRefillTime);
    } else {
      cowFeed--;
      cowFeedUntil = now.add(feedRefillTime);
    }
    if (hasCowWater(now) && hasCowFeed(now)) {
      milkReadyAt = readyAt.add(now.difference(_milkPausedAt!));
      _milkPausedAt = null;
    }
    return true;
  }

  bool collectMilk(DateTime now) {
    final remaining = milkRemaining(now);
    if (remaining == null || remaining > Duration.zero) return false;
    milk += bottlesPerCycle;
    xp += milkXpPerCycle;
    milkReadyAt = now.add(milkProductionTime);
    _milkPausedAt = hasCowWater(now) && hasCowFeed(now) ? null : now;
    return true;
  }

  int sellOneMilk() {
    if (milk == 0) return 0;
    milk--;
    coins += milkSaleValue;
    return milkSaleValue;
  }

  int get currentLevelXp => xp - xpThresholds[level - 1];
  int? get levelXpGoal {
    final next = nextLevelXp;
    return next == null ? null : next - xpThresholds[level - 1];
  }

  void applyVisitRewards(VisitSnapshot snapshot) {
    if (snapshot.coinsPaid > appliedDailyLoginCoins) {
      coins += snapshot.coinsPaid - appliedDailyLoginCoins;
      appliedDailyLoginCoins = snapshot.coinsPaid;
    }
    if (snapshot.seedsPaid > appliedDailyLoginSeeds) {
      final amount = snapshot.seedsPaid - appliedDailyLoginSeeds;
      seeds.update(CropType.alface, (stock) => stock + amount,
          ifAbsent: () => amount);
      appliedDailyLoginSeeds = snapshot.seedsPaid;
    }
  }

  bool buySeed(CropType type, {int quantity = 1}) {
    if (!isUnlocked(type)) return false;
    final cost = effectiveSeedCost(Crops.of(type));
    if (quantity <= 0 || quantity > coins ~/ cost) return false;
    coins -= cost * quantity;
    seeds.update(type, (amount) => amount + quantity, ifAbsent: () => quantity);
    return true;
  }

  bool buyFertilizer() {
    if (coins < fertilizerCost) return false;
    coins -= fertilizerCost;
    fertilizer++;
    return true;
  }

  bool buyWeedControl() {
    if (coins < weedControlCost) return false;
    coins -= weedControlCost;
    weedControl++;
    return true;
  }

  bool applyWeedControl(Plot plot, DateTime now) {
    if (weedControl <= 0 || !plot.hasWeeds) return false;
    plot.removeWeeds(now);
    weedControl--;
    return true;
  }

  bool fertilize(Plot plot, DateTime now) {
    // Só fertiliza cultura em crescimento: ignora canteiro vazio, planta já
    // madura (pronta para colher ou morta) e plantio ainda em andamento.
    if (!plot.isPlanted || plot.isReady(now) || plot.isDead(now)) {
      return false;
    }
    final plantedAt = plot.plantedAt;
    final duration = plot.growDuration;
    if (fertilizer <= 0 ||
        plantedAt == null ||
        duration == null ||
        now.isBefore(plantedAt)) {
      return false;
    }

    final remaining = plantedAt.add(duration).difference(now);
    final reduction = remaining.inMilliseconds ~/ 4;
    if (reduction <= 0) return false;

    plot.growDuration = duration - Duration(milliseconds: reduction);
    fertilizer--;
    return true;
  }

  int sellCrop(CropType type, {int? quantity}) {
    final stock = basket[type] ?? 0;
    final amount = quantity ?? stock;
    if (amount <= 0 || amount > stock) return 0;
    if (amount == stock) {
      basket.remove(type);
    } else {
      basket[type] = stock - amount;
    }
    final proceeds = amount * effectiveSellValue(Crops.of(type));
    coins += proceeds;
    return proceeds;
  }

  int get basketCount =>
      basket.values.fold(milk, (total, amount) => total + amount);
  int get basketValue => basket.entries.fold(
        milk * milkSaleValue,
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

  int _effectiveUpgradeLevel(UpgradeType type, DateTime now) {
    final legacyLevel = switch (type) {
      UpgradeType.sellBoost => sellBoostLevel,
      UpgradeType.seedDiscount => seedDiscountLevel,
      UpgradeType.growSpeed => growSpeedLevel,
    };
    return legacyLevel + (upgradeRemaining(type, now) > Duration.zero ? 1 : 0);
  }

  int effectiveSeedCost(Crop crop, {DateTime? now}) => (crop.seedCost *
          math.pow(
              .85,
              _effectiveUpgradeLevel(
                UpgradeType.seedDiscount,
                now ?? DateTime.now(),
              )))
      .round()
      .clamp(1, crop.seedCost);

  int effectiveSellValue(Crop crop, {DateTime? now}) => (crop.sellValue *
          math.pow(
              1.20,
              _effectiveUpgradeLevel(
                UpgradeType.sellBoost,
                now ?? DateTime.now(),
              )))
      .round();

  Duration effectiveGrowTime(Crop crop, {DateTime? now}) => Duration(
        milliseconds: (crop.growTime.inMilliseconds *
                math.pow(
                    .90,
                    _effectiveUpgradeLevel(
                      UpgradeType.growSpeed,
                      now ?? DateTime.now(),
                    )))
            .round(),
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

  bool plant(Plot plot, Crop crop, DateTime now, {bool prepared = false}) {
    if (plot.isPlanted || !plot.tilled || !plot.isWet(now)) return false;
    final stock = seeds[crop.type] ?? 0;
    if (!isUnlocked(crop.type) || stock == 0) return false;
    if (stock == 1) {
      seeds.remove(crop.type);
    } else {
      seeds[crop.type] = stock - 1;
    }
    plot.plantedCrop = crop.type;
    plot.plantedAt = prepared ? now : now.add(Plot.plantingDuration);
    final duration = effectiveGrowTime(crop, now: now);
    plot.growDuration = plot.hasWeeds ? duration + duration ~/ 4 : duration;
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
    plot.recordHarvest();
    return reward;
  }

  int sellBasket() {
    final proceeds = basketValue;
    coins += proceeds;
    basket.clear();
    milk = 0;
    return proceeds;
  }

  Map<String, dynamic> toMap() => {
        'fertilizer': fertilizer,
        'weedControl': weedControl,
        'milkCycleHours': milkCycle.inHours,
        'milkReadyAt': milkReadyAt?.toIso8601String(),
        'milkPausedAt': _milkPausedAt?.toIso8601String(),
        'cowWaterUntil': cowWaterUntil?.toIso8601String(),
        'cowFeedUntil': cowFeedUntil?.toIso8601String(),
        'milk': milk,
        'cowFeed': cowFeed,
        'guardDogOwnedUntil': guardDogOwnedUntil?.toIso8601String(),
        'guardDogFood': guardDogFood,
        'notices': [
          for (final notice in notices)
            {'message': notice.message, 'at': notice.at.toIso8601String()},
        ],
        'guardDogFedUntil': guardDogFedUntil?.toIso8601String(),
        'basket': basket.map((type, amount) => MapEntry(type.name, amount)),
        'seeds': seeds.map((type, amount) => MapEntry(type.name, amount)),
        'appliedDailyLoginCoins': appliedDailyLoginCoins,
        'appliedDailyLoginSeeds': appliedDailyLoginSeeds,
        'coins': coins,
        'xp': xp,
        'plotCount': plotCount,
        'plots': plots.map((p) => p.toMap()).toList(),
        'sellBoostLevel': sellBoostLevel,
        'seedDiscountLevel': seedDiscountLevel,
        'growSpeedLevel': growSpeedLevel,
        'upgradeEndsAt': {
          for (final entry in upgradeEndsAt.entries)
            entry.key.name: entry.value.toIso8601String(),
        },
      };

  factory Player.fromMap(Map<String, dynamic> map, {bool dairyTest = false}) {
    final plotCount = map['plotCount'] as int? ?? GameConstants.startingPlots;
    final player = Player.initial(plotCount: plotCount);
    player.coins = map['coins'] as int? ?? GameConstants.startingCoins;
    player.xp = map['xp'] as int? ?? 0;
    player.sellBoostLevel = map['sellBoostLevel'] as int? ?? 0;
    player.seedDiscountLevel = map['seedDiscountLevel'] as int? ?? 0;
    player.growSpeedLevel = map['growSpeedLevel'] as int? ?? 0;
    if (map['upgradeEndsAt'] case final Map activeUpgrades) {
      for (final type in UpgradeType.values) {
        final stamp = activeUpgrades[type.name];
        if (stamp is! String) continue;
        if (DateTime.tryParse(stamp) case final DateTime end) {
          player.upgradeEndsAt[type] = end;
        }
      }
    }

    final fertilizer = map['fertilizer'];
    if (fertilizer is int && fertilizer > 0) player.fertilizer = fertilizer;
    final weedControl = map['weedControl'];
    if (weedControl is int && weedControl > 0) player.weedControl = weedControl;
    DateTime? readDate(String key) {
      final value = map[key];
      return value is String ? DateTime.tryParse(value) : null;
    }

    player.milkReadyAt = readDate('milkReadyAt');
    player.cowWaterUntil = readDate('cowWaterUntil');
    player.cowFeedUntil = readDate('cowFeedUntil');
    player._milkPausedAt = readDate('milkPausedAt');
    if (player.hasCow &&
        player._milkPausedAt == null &&
        (player.cowWaterUntil == null || player.cowFeedUntil == null)) {
      player._milkPausedAt = DateTime.now();
    }
    if (player.hasCow && map['milkCycleHours'] == null && !dairyTest) {
      final now = DateTime.now();
      final productionTime = player._productionTime(now);
      final remaining = player.milkReadyAt!.difference(productionTime);
      if (remaining > Duration.zero) {
        const legacyCycle = Duration(minutes: 30);
        final fraction = (remaining.inMicroseconds / legacyCycle.inMicroseconds)
            .clamp(0.0, 1.0);
        player.milkReadyAt = productionTime.add(
          Duration(microseconds: (milkCycle.inMicroseconds * fraction).round()),
        );
      }
    }
    player.guardDogOwnedUntil = readDate('guardDogOwnedUntil') ??
        (map['hasGuardDog'] == true
            ? DateTime.now().add(guardDogLifetime)
            : null);
    if (map['notices'] case final List savedNotices) {
      for (final entry in savedNotices) {
        if (entry is! Map) continue;
        final message = entry['message'];
        final stamp = entry['at'];
        if (message is! String || stamp is! String) continue;
        if (DateTime.tryParse(stamp) case final DateTime at) {
          player.addNotice(message, at);
        }
      }
    }
    final savedDogFood = map['guardDogFood'];
    if (savedDogFood is int && savedDogFood > 0)
      player.guardDogFood = savedDogFood;
    player.guardDogFedUntil = readDate('guardDogFedUntil');
    final savedFeed = map['cowFeed'];
    if (savedFeed is int && savedFeed > 0) player.cowFeed = savedFeed;
    final milk = map['milk'];
    if (milk is int && milk > 0) player.milk = milk;
    final legacyDays = (map['appliedServerVisitRewards'] as int? ??
            map['claimedVisitDays'] as int? ??
            0)
        .clamp(0, VisitRewardsApi.dayLimit);
    final legacySeeds = legacyDays * (legacyDays + 1) ~/ 2;
    player.appliedDailyLoginCoins =
        map['appliedDailyLoginCoins'] as int? ?? legacySeeds * 12;
    player.appliedDailyLoginSeeds =
        map['appliedDailyLoginSeeds'] as int? ?? legacySeeds;
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

    final colors = wet
        ? const [Color(0xff71513a), Color(0xff443224)]
        : stage > 0
            ? const [Color(0xff8e653f), Color(0xff563a25)]
            : tilled
                ? const [Color(0xffa37a51), Color(0xff65462e)]
                : const [Color(0xffaa8c5e), Color(0xff775b3d)];
    canvas.drawRect(
      rect,
      Paint()..color = colors.last,
    );

    final w = size.width;
    final h = size.height;
    final mound = Path()
      ..moveTo(w * .025, h * .50)
      ..quadraticBezierTo(w * .24, h * .24, w * .50, h * .02)
      ..quadraticBezierTo(w * .76, h * .19, w * .975, h * .50)
      ..quadraticBezierTo(w * .74, h * .68, w * .50, h * .82)
      ..quadraticBezierTo(w * .26, h * .70, w * .025, h * .50)
      ..close();
    final crown = Color.lerp(
      colors.first,
      const Color(0xffd2a677),
      wet ? .24 : .39,
    )!;
    canvas.drawPath(
      mound,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.25, -.23),
          radius: .67,
          colors: [crown, colors.first, colors.last],
          stops: const [0, .52, 1],
        ).createShader(rect),
    );

    final random = math.Random(47);
    final grain = Paint();
    for (var i = 0; i < 155; i++) {
      final center = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final radius = (.26 + random.nextDouble() * .9) * size.width / 76;
      final clod = Rect.fromCenter(
        center: center,
        width: radius * 2.8,
        height: radius * 1.45,
      );
      canvas.drawOval(clod, grain..color = const Color(0x542e1b11));
      canvas.drawOval(
        clod.shift(Offset(-radius * .24, -radius * .4)),
        grain..color = wet ? const Color(0x537e6041) : const Color(0x62d2a171),
      );
    }

    if (tilled) {
      // Broken indentations and loose clods give the bed irregular relief.
      for (var row = 0; row < 3; row++) {
        for (var section = 0; section < 6; section++) {
          final t = section / 6;
          final from = Offset(
            size.width * (.20 + row * .14 + t * .30),
            size.height * (.47 - row * .145 + t * .30),
          );
          final span = size.width * (.019 + random.nextDouble() * .031);
          canvas.drawLine(
            from,
            from + Offset(span, span * .45 + random.nextDouble() - .5),
            grain
              ..color = const Color(0x5239281c)
              ..strokeWidth = size.width * .015
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .024
        ..color = ready ? const Color(0xffc49a48) : const Color(0xff554029),
    );
  }

  @override
  bool shouldRepaint(PlotPainter oldDelegate) =>
      stage != oldDelegate.stage ||
      ready != oldDelegate.ready ||
      tilled != oldDelegate.tilled ||
      wet != oldDelegate.wet;
}

/// Canteiro individual renderizado como losango isométrico.
class PlotWidget extends StatelessWidget {
  const PlotWidget({
    super.key,
    required this.plot,
    required this.onTap,
    this.onPressStart,
    this.onPressEnd,
  });

  final Plot plot;
  final VoidCallback onTap;
  final VoidCallback? onPressStart;
  final VoidCallback? onPressEnd;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dead = plot.isDead(now);
    final stage = dead || plot.isPlanting(now) ? 0 : plot.stage(now);
    final ready = stage == GameConstants.cropStageCount;
    final artworkStage = dead ? GameConstants.cropStageCount : stage;
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
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: CustomPaint(
              painter: PlotPainter(
                stage: stage,
                ready: ready,
                tilled: plot.tilled,
                wet: plot.isWet(now),
              ),
            ),
          ),
          if (plot.hasWeeds)
            Positioned.fill(
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final height = constraints.maxHeight;
                    return Stack(
                      children: [
                        for (final (x, y) in [
                          (.22, .38),
                          (.60, .36),
                          (.38, .61)
                        ])
                          Positioned(
                            left: width * x,
                            top: height * y,
                            child: Image.asset(
                              _farmIcon('sprout'),
                              width: height * .3,
                              height: height * .3,
                              excludeFromSemantics: true,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          if (artworkStage > 0)
            IgnorePointer(
                child: CustomPaint(painter: _CropContactShadow(artworkStage))),
          if (plot.plantedCrop case final type? when artworkStage > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: LayoutBuilder(builder: (context, constraints) {
                  // The artwork changes in stages, but its size follows
                  // the same progress as the harvest countdown.
                  final size =
                      constraints.maxHeight * (.55 + plot.progress(now) * .60);
                  final buried = type == CropType.cenoura &&
                      artworkStage == GameConstants.cropStageCount;
                  final image = Image.asset(
                    _cropSprite(type, artworkStage),
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                  );
                  final sprite = dead ? _WiltedCrop(child: image) : image;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        left: (constraints.maxWidth - size) / 2,
                        bottom: constraints.maxHeight *
                                (type == CropType.alface ? .34 : .43) -
                            (buried ? 0 : size / 16),
                        width: size,
                        height: buried ? size * .64 : size,
                        child: buried
                            ? ClipRect(
                                child: OverflowBox(
                                  alignment: Alignment.topCenter,
                                  minHeight: size,
                                  maxHeight: size,
                                  child: sprite,
                                ),
                              )
                            : sprite,
                      ),
                    ],
                  );
                }),
              ),
            ),
          if (artworkStage > 0)
            IgnorePointer(
              child: CustomPaint(
                painter: _CropSoilRim(
                  artworkStage,
                  inset: plot.plantedCrop == CropType.alface,
                ),
              ),
            ),
          ClipPath(
            clipper: const IsoDiamondClipper(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onTapDown: onPressStart == null ? null : (_) => onPressStart!(),
              onTapUp: onPressEnd == null ? null : (_) => onPressEnd!(),
              onTapCancel: onPressEnd,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _WiltedCrop extends StatelessWidget {
  const _WiltedCrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: .40,
      alignment: Alignment.bottomCenter,
      child: Transform.scale(
        alignment: Alignment.bottomCenter,
        scaleY: .55,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            .22,
            .61,
            .08,
            0,
            16,
            .15,
            .44,
            .06,
            0,
            10,
            .08,
            .25,
            .04,
            0,
            5,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: child,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// [ui/widgets/new_plot_tile.dart]  Losango do canteiro expansível
// ------------------------------------------------------------

/// Área bloqueada que mostra o custo do próximo canteiro.
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
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: CustomPaint(
            painter: NewPlotPainter(enabled: enabled),
            child: Center(
              child: FractionallySizedBox(
                // Keep the full emblem inside the inset diamond, even
                // when the price grows or text scaling is enabled.
                widthFactor: .40,
                heightFactor: .43,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded,
                          size: 10,
                          color: enabled
                              ? const Color(0xffffd883)
                              : const Color(0xffe3dbbe)),
                      const SizedBox(height: 1),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(_farmIcon('coin'),
                              width: 8, height: 8, excludeFromSemantics: true),
                          const SizedBox(width: 2),
                          Text('$cost',
                              style: const TextStyle(
                                color: Color(0xfffff4d5),
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                                height: 1,
                              )),
                        ],
                      ),
                    ],
                  ),
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
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: enabled
              ? const [Color(0xff708544), Color(0xff344527)]
              : const [Color(0xff566346), Color(0xff2c3929)],
        ).createShader(rect),
    );

    final random = math.Random(19);
    final fleck = Paint()..color = const Color(0x32e4d6a0);
    for (var i = 0; i < 65; i++) {
      canvas.drawOval(
        Rect.fromLTWH(
            random.nextDouble() * size.width,
            random.nextDouble() * size.height,
            size.width * .023,
            size.height * .025),
        fleck,
      );
    }

    final inner = isoDiamondPath(Size(size.width * .88, size.height * .80))
        .shift(Offset(size.width * .06, size.height * .10));
    canvas.drawPath(
      inner,
      Paint()
        ..color = enabled ? const Color(0xaff2cb73) : const Color(0x70c5c199)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .012,
    );
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.width * 0.035)
        ..color = enabled ? const Color(0xff394223) : const Color(0xff32392a),
    );
  }

  @override
  bool shouldRepaint(NewPlotPainter oldDelegate) =>
      enabled != oldDelegate.enabled;
}

// ------------------------------------------------------------
// [ui/widgets/crop_selector_sheet.dart]  Seletor de culturas
// ------------------------------------------------------------
class CropSelectorSheet extends StatefulWidget {
  const CropSelectorSheet({
    super.key,
    required this.player,
    required this.onSelected,
    required this.onBuyFertilizer,
    required this.onBuyWeedControl,
    required this.onBuyCow,
    required this.onBuyCowFeed,
    required this.onBuyGuardDog,
    required this.onBuyGuardDogFood,
    this.startOnAnimals = false,
    required this.onOpenWarehouse,
  });

  final Player player;
  final void Function(CropType, int quantity) onSelected;
  final VoidCallback onBuyFertilizer;
  final VoidCallback onBuyWeedControl;
  final VoidCallback onBuyCow;
  final ValueChanged<int> onBuyCowFeed;
  final VoidCallback onBuyGuardDog;
  final ValueChanged<int> onBuyGuardDogFood;
  final bool startOnAnimals;
  final Future<void> Function() onOpenWarehouse;

  @override
  State<CropSelectorSheet> createState() => _CropSelectorSheetState();
}

enum _AnimalFeed { cow, dog }

class _CropSelectorSheetState extends State<CropSelectorSheet> {
  late bool _showAnimals = widget.startOnAnimals;
  CropType? _selected;
  _AnimalFeed? _selectedFeed;
  int _quantity = 1;
  Player get player => widget.player;

  Future<void> _showInsufficientCoins(int cost) async {
    final hasGoods = player.basketValue > 0;
    final openWarehouse = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const _FarmMenuTitle('Moedas insuficientes', 'coin'),
        content: Text(
          'Faltam ${cost - player.coins} moedas.'
          '${hasGoods ? '\nVenda as mercadorias do Armazém para conseguir moedas.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          if (hasGoods)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abrir Armazém'),
            ),
        ],
      ),
    );
    if (!mounted || openWarehouse != true) return;
    await widget.onOpenWarehouse();
    if (mounted) setState(() {});
  }

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

  Widget _bulkPurchase(int cost, ValueChanged<int> onBuy) {
    final maxQuantity = player.coins ~/ cost;
    final quantity = math.min(_quantity, maxQuantity);
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          IconButton(
            tooltip: 'Diminuir quantidade',
            onPressed: quantity <= 1
                ? null
                : () => setState(() => _quantity = quantity - 1),
            icon: const Icon(Icons.remove),
          ),
          Text('$quantity / $maxQuantity'),
          IconButton(
            tooltip: 'Aumentar quantidade',
            onPressed: quantity >= maxQuantity
                ? null
                : () => setState(() => _quantity = quantity + 1),
            icon: const Icon(Icons.add),
          ),
          FilledButton(
            onPressed: () {
              onBuy(quantity);
              setState(() => _quantity = 1);
            },
            child: Text('Comprar por ${cost * quantity} moedas'),
          ),
        ],
      ),
    );
  }

  Widget _feedItem(
    _AnimalFeed item, {
    required Widget artwork,
    required String title,
    required int stock,
    required int cost,
    required ValueChanged<int> onBuy,
  }) {
    final canAfford = player.coins >= cost;
    return Column(
      children: [
        ListTile(
          leading: artwork,
          title: Text(title),
          subtitle: Text('🪙 $cost por porção · Estoque: $stock'),
          trailing: const Icon(Icons.chevron_right, color: Colors.green),
          onTap: () {
            if (!canAfford) {
              _showInsufficientCoins(cost);
              return;
            }
            setState(() {
              _selectedFeed = item;
              _quantity = 1;
            });
          },
        ),
        if (_selectedFeed == item && canAfford) _bulkPurchase(cost, onBuy),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: _FarmMenuTitle('Loja da fazenda', 'store'),
                ),
                Text('Saldo: ${player.coins} moedas'),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Fechar loja',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Cultivo')),
                ButtonSegment(value: true, label: Text('Animais')),
              ],
              selected: {_showAnimals},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => setState(() {
                _showAnimals = selection.single;
                _selected = null;
                _selectedFeed = null;
                _quantity = 1;
              }),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (!_showAnimals) ...[
                    ListTile(
                      dense: true,
                      leading: Image.asset(_farmIcon(_FarmTool.fertilizer.name),
                          width: 32, height: 32, excludeFromSemantics: true),
                      title: const Text('Adubo'),
                      subtitle: Text(
                          '−25% do tempo restante · Estoque: ${player.fertilizer}'),
                      trailing: FilledButton.tonal(
                        onPressed: player.coins >= Player.fertilizerCost
                            ? widget.onBuyFertilizer
                            : () =>
                                _showInsufficientCoins(Player.fertilizerCost),
                        child: const Text(
                            'Comprar · ${Player.fertilizerCost} moedas'),
                      ),
                    ),
                    ListTile(
                      dense: true,
                      leading: const _WeedControlIcon(size: 32),
                      title: const Text('Defensivo'),
                      subtitle:
                          Text('Remove mato · Estoque: ${player.weedControl}'),
                      trailing: FilledButton.tonal(
                        onPressed: player.coins >= Player.weedControlCost
                            ? widget.onBuyWeedControl
                            : () =>
                                _showInsufficientCoins(Player.weedControlCost),
                        child: const Text(
                            'Comprar · ${Player.weedControlCost} moedas'),
                      ),
                    ),
                  ],
                  if (_showAnimals)
                    ListTile(
                      leading: Image.asset(_farmIcon('cow'),
                          width: 48, height: 40, excludeFromSemantics: true),
                      title: const Text('Vaca leiteira'),
                      subtitle: Text(player.hasCow
                          ? 'No pasto da fazenda'
                          : 'Limite de uma · ${Player.bottlesPerCycle} garrafas a cada ${_formatDuration(player.milkProductionTime)}'),
                      trailing: FilledButton.tonal(
                        onPressed: player.hasCow
                            ? null
                            : player.coins >= Player.cowCost
                                ? widget.onBuyCow
                                : () => _showInsufficientCoins(Player.cowCost),
                        child: Text(player.hasCow
                            ? 'Comprada'
                            : 'Comprar · 2.000 moedas'),
                      ),
                    ),
                  if (_showAnimals)
                    _feedItem(
                      _AnimalFeed.cow,
                      artwork: const _CowFeedIcon(),
                      title: 'Ração para vaca',
                      stock: player.cowFeed,
                      cost: Player.cowFeedCost,
                      onBuy: widget.onBuyCowFeed,
                    ),
                  if (_showAnimals)
                    ListTile(
                      leading: Image.asset(_farmIcon('guard_dog'),
                          width: 44, height: 40, excludeFromSemantics: true),
                      title: const Text('Cachorro guarda'),
                      subtitle: const Text(
                          'Patrulha os canteiros · Validade: 30 dias'),
                      trailing: FilledButton.tonal(
                        onPressed: player.hasGuardDog
                            ? null
                            : player.coins >= Player.guardDogCost
                                ? widget.onBuyGuardDog
                                : () =>
                                    _showInsufficientCoins(Player.guardDogCost),
                        child: Text(player.hasGuardDog
                            ? 'Comprado'
                            : 'Comprar · 1.000 moedas'),
                      ),
                    ),
                  if (_showAnimals)
                    _feedItem(
                      _AnimalFeed.dog,
                      artwork: const _GuardDogFoodIcon(),
                      title: 'Ração para cachorro',
                      stock: player.guardDogFood,
                      cost: Player.guardDogFoodCost,
                      onBuy: widget.onBuyGuardDogFood,
                    ),
                  ...List<Widget>.generate(
                    _showAnimals ? 0 : CropType.values.length,
                    (index) {
                      final type = CropType.values[index];
                      final crop = Crops.of(type);
                      final unlocked = player.isUnlocked(type);
                      final cost = player.effectiveSeedCost(crop);
                      final sell = player.effectiveSellValue(crop);
                      final canAfford = player.coins >= cost;
                      final isNew = player.isNewlyUnlocked(type);

                      return Column(children: [
                        ListTile(
                          leading: Opacity(
                            opacity: unlocked ? 1.0 : 0.4,
                            child: _CropArtwork(type: type),
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
                              ? const Icon(Icons.chevron_right,
                                  color: Colors.green)
                              : const Icon(Icons.lock_outline,
                                  color: Colors.grey),
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
                              _showInsufficientCoins(cost);
                              return;
                            }
                            setState(() {
                              _selected = type;
                              _quantity = 1;
                            });
                          },
                        ),
                        if (_selected == type && unlocked && canAfford)
                          _bulkPurchase(cost,
                              (quantity) => widget.onSelected(type, quantity)),
                      ]);
                    },
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

// ------------------------------------------------------------
// [ui/widgets/upgrade_sheet.dart]  Modal de upgrades
// ------------------------------------------------------------
class UpgradeSheet extends StatefulWidget {
  const UpgradeSheet({
    super.key,
    required this.player,
    required this.requestReward,
    required this.onGranted,
    this.isPreview = false,
  });

  final Player player;
  final Future<bool> Function()? requestReward;
  final VoidCallback onGranted;
  final bool isPreview;

  @override
  State<UpgradeSheet> createState() => _UpgradeSheetState();
}

class _UpgradeSheetState extends State<UpgradeSheet> {
  late final Timer _tick;
  UpgradeType? _pending;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _watch(UpgradeType type) async {
    final request = widget.requestReward;
    if (request == null || _pending != null) return;
    setState(() {
      _pending = type;
      _feedback = null;
    });
    final earned = await request();
    if (earned && widget.player.grantUpgrade(type, DateTime.now())) {
      widget.onGranted();
    }
    if (!mounted) return;
    setState(() {
      _pending = null;
      _feedback =
          earned ? null : 'A recompensa não foi liberada. Tente novamente.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: _FarmMenuTitle('Melhorias da fazenda', 'upgrades'),
                ),
                IconButton(
                  tooltip: 'Fechar melhorias',
                  onPressed:
                      _pending == null ? () => Navigator.pop(context) : null,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (widget.requestReward == null)
              const Text('Anúncios recompensados indisponíveis nesta versão.'),
            if (_feedback case final feedback?) Text(feedback),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  for (final type in UpgradeType.values)
                    _tile(type, widget.player.upgradeRemaining(type, now)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(UpgradeType type, Duration remaining) {
    final active = remaining > Duration.zero;
    final time = _HomeScreenState._formatDuration(remaining);
    return Card(
      child: ListTile(
        leading: Text(type.emoji, style: const TextStyle(fontSize: 26)),
        title: Text(type.label),
        subtitle: Text('${type.description} · ${type.duration.inMinutes} min'
            '${active ? '\nAtiva por mais $time' : ''}'),
        trailing: FilledButton(
          onPressed: active || _pending != null || widget.requestReward == null
              ? null
              : () => _watch(type),
          child: Text(active
              ? 'Ativa'
              : _pending == type
                  ? 'Carregando…'
                  : widget.isPreview
                      ? 'Simular anúncio'
                      : 'Assistir anúncio'),
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
    this.visitsApi,
    this.socialClient,
    this.onVisitRewards,
  });

  final Player player;
  final VoidCallback? onShouldSave;
  final VisitRewardsApi? visitsApi;
  final SupabaseClient? socialClient;
  final Future<void> Function(VisitSnapshot)? onVisitRewards;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _FarmTool { hoe, seed, water, fertilizer, weedControl, harvest }

typedef _FarmAction = ({Plot plot, _FarmTool tool, Object id, int xp});

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  _FarmTool _tool = _FarmTool.harvest;
  final _actions = <_FarmAction>[];
  Plot? _plantingPlot;
  Timer? _plantHold;
  Plot? _focusedPlot;
  String? _plotHint;
  Timer? _expansionNoticeTimer;
  CropType? _seed;

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
    unawaited(_renewGuard());
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
    if (_plantingPlot case final plot?
        when state != AppLifecycleState.resumed) {
      _endPlanting(plot);
    }
    if (state == AppLifecycleState.resumed) {
      // Ao retomar, re-renderiza com DateTime.now(): o tempo offline é
      // contabilizado e as plantações não ficam congeladas.
      unawaited(_renewGuard());
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _plantHold?.cancel();
    _bannerRetryTimer?.cancel();
    _expansionNoticeTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _showFarmMessage(String message) {
    widget.player.addNotice(message, DateTime.now());
    widget.onShouldSave?.call();
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

  void _inspectPlot(Plot? plot) {
    if (identical(_focusedPlot, plot) && _plotHint == null) return;
    setState(() {
      _focusedPlot = plot;
      _plotHint = null;
    });
  }

  void _beginPlanting(Plot plot) {
    final player = widget.player;
    final selected = _seed;
    if (selected == null ||
        _plantingPlot != null ||
        !plot.isEmpty ||
        !plot.tilled ||
        !plot.isWet(DateTime.now()) ||
        (player.seeds[selected] ?? 0) <= 0 ||
        !player.isUnlocked(selected)) return;

    final seed = Crops.of(selected);
    setState(() {
      _focusedPlot = _plantingPlot = plot;
      _plotHint = null;
    });
    _plantHold = Timer(Plot.plantingDuration, () {
      if (!mounted || !identical(_plantingPlot, plot)) return;
      _plantHold = null;
      final planted = player.plant(plot, seed, DateTime.now(), prepared: true);
      if (planted) widget.onShouldSave?.call();
      setState(() {
        _plantingPlot = null;
        if (planted) {
          _actions.add((plot: plot, tool: _FarmTool.seed, id: Object(), xp: 0));
        }
        _plotHint = planted
            ? null
            : 'Plantio não concluído. Confira o solo e as sementes.';
      });
    });
  }

  void _endPlanting(Plot plot) {
    if (!identical(_plantingPlot, plot)) return;
    _plantHold?.cancel();
    _plantHold = null;
    setState(() => _plantingPlot = null);
  }

  void _selectTool(_FarmTool tool) {
    _plantHold?.cancel();
    _plantHold = null;
    setState(() {
      _tool = tool;
      _actions.clear();
      _plantingPlot = null;
      _focusedPlot = null;
      _plotHint = null;
    });
  }

  void _handlePlotTap(Plot plot) {
    final player = widget.player;
    final now = DateTime.now();
    final previousXp = player.xp;
    String? hint;
    final changed = switch (_tool) {
      _FarmTool.hoe => plot.hoe(now),
      _FarmTool.water => plot.water(now),
      _FarmTool.fertilizer => player.fertilize(plot, now),
      _FarmTool.weedControl => player.applyWeedControl(plot, now),
      _FarmTool.seed => false,
      _FarmTool.harvest => player.harvest(plot, now) > 0,
    };
    if (_tool == _FarmTool.seed &&
        plot.isEmpty &&
        plot.tilled &&
        plot.isWet(now)) {
      _showSeeds(plot);
      return;
    }
    if (!changed && _tool == _FarmTool.fertilizer) {
      hint = player.fertilizer == 0
          ? 'Sem fertilizante · abra a Loja'
          : 'Aplique em uma cultura em crescimento';
    }
    if (_tool == _FarmTool.weedControl) {
      hint = changed
          ? 'Mato removido'
          : widget.player.weedControl == 0
              ? 'Sem defensivo · abra a Loja'
              : 'Este canteiro está sem mato';
    }
    if (changed) widget.onShouldSave?.call();
    setState(() {
      if (changed) {
        _actions.add((
          plot: plot,
          tool: _tool,
          id: Object(),
          xp: player.xp - previousXp,
        ));
      }
      _focusedPlot = plot;
      _plotHint = hint;
    });
  }

  Future<void> _showFarmDialog(
      String title, Widget Function(StateSetter) content) {
    return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: _FarmMenuTitle(
              title,
              switch (title) {
                'Armazém' => 'warehouse',
                'Sementes guardadas' => 'seed',
                'Cocho e bebedouro' => 'trough',
                'Amigos' => 'friends',
                'Ranking' => 'ranking',
                _ => 'notices',
              }),
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

  Future<void> _showWarehouse() {
    final player = widget.player;
    CropType? selected;
    var quantity = 1;
    return _showFarmDialog(
      'Armazém',
      (update) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (player.seeds.isNotEmpty ||
              player.fertilizer > 0 ||
              player.weedControl > 0) ...[
            const ListTile(title: Text('Estoque de plantio')),
            for (final entry in player.seeds.entries)
              _warehouseSupply(
                title: 'Semente de ${entry.key.label}',
                quantity: entry.value,
                artwork: _CropArtwork(type: entry.key),
                onUse: () {
                  _seed = entry.key;
                  _selectTool(_FarmTool.seed);
                },
              ),
            if (player.fertilizer > 0)
              _warehouseSupply(
                title: 'Adubo',
                quantity: player.fertilizer,
                artwork: _farmToolArtwork(_FarmTool.fertilizer, 32),
                onUse: () => _selectTool(_FarmTool.fertilizer),
              ),
            if (player.weedControl > 0)
              _warehouseSupply(
                title: 'Defensivo',
                quantity: player.weedControl,
                artwork: const _WeedControlIcon(size: 32),
                onUse: () => _selectTool(_FarmTool.weedControl),
              ),
            const Divider(),
            const ListTile(title: Text('Colheita para venda')),
          ],
          if (player.guardDogFood > 0)
            ListTile(
              leading: const _GuardDogFoodIcon(),
              title: const Text('Ração para cachorro'),
              subtitle: Text('Estoque: ${player.guardDogFood}'),
              trailing: TextButton(
                onPressed:
                    player.hasGuardDog && !player.isGuardDogFed(DateTime.now())
                        ? () {
                            Navigator.of(context, rootNavigator: true).pop();
                            unawaited(_feedGuardDog());
                          }
                        : null,
                child: const Text('Usar'),
              ),
            ),
          if (player.cowFeed > 0)
            ListTile(
              leading: const _CowFeedIcon(),
              title: const Text('Ração para vaca'),
              subtitle: Text(
                'Estoque: ${player.cowFeed}'
                '${player.hasCow ? '' : ' · Disponível após comprar a vaca'}',
              ),
              trailing: TextButton(
                onPressed: player.hasCow
                    ? () {
                        if (_feedCow()) update(() {});
                      }
                    : null,
                child: const Text('Usar'),
              ),
            ),
          if (player.basketCount == 0)
            const Text('A produção ainda está vazia.'),
          if (player.milk > 0)
            ListTile(
              leading: Image.asset(
                _farmIcon('milk_bottle'),
                width: 36,
                height: 36,
                excludeFromSemantics: true,
              ),
              title: const Text('Leite'),
              subtitle: Text('Quantidade: ${player.milk}'),
              trailing: TextButton(
                onPressed: () {
                  if (player.sellOneMilk() > 0) {
                    _farmChanged();
                    update(() {});
                  }
                },
                child: const Text('Vender 1 por ${Player.milkSaleValue}'),
              ),
            ),
          for (final entry in player.basket.entries) ...[
            ListTile(
              leading: _CropArtwork(type: entry.key),
              title: Text(entry.key.label),
              subtitle: Text('Quantidade: ${entry.value}'),
              trailing: TextButton(
                onPressed: () => update(() {
                  selected = entry.key;
                  quantity = 1;
                }),
                child: const Text('Vender'),
              ),
            ),
            if (selected == entry.key)
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Diminuir quantidade para vender',
                    onPressed:
                        quantity > 1 ? () => update(() => quantity--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$quantity / ${entry.value}'),
                  IconButton(
                    tooltip: 'Aumentar quantidade para vender',
                    onPressed: quantity < entry.value
                        ? () => update(() => quantity++)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (player.sellCrop(entry.key, quantity: quantity) > 0) {
                        _farmChanged();
                        update(() {
                          selected = null;
                          quantity = 1;
                        });
                      }
                    },
                    child: Text(
                      'Vender por ${quantity * player.effectiveSellValue(Crops.of(entry.key))}',
                    ),
                  ),
                ],
              ),
          ],
          if (player.basketCount > 0)
            FilledButton(
              onPressed: () {
                player.sellBasket();
                _farmChanged();
                update(() {
                  selected = null;
                  quantity = 1;
                });
              },
              child: Text('Vender tudo por ${player.basketValue}'),
            ),
        ],
      ),
    );
  }

  Widget _warehouseSupply({
    required String title,
    required int quantity,
    required Widget artwork,
    required VoidCallback onUse,
  }) {
    return ListTile(
      leading: artwork,
      title: Text(title),
      subtitle: Text('Estoque: $quantity'),
      trailing: TextButton(
        onPressed: () {
          Navigator.of(context, rootNavigator: true).pop();
          onUse();
        },
        child: const Text('Usar'),
      ),
    );
  }

  void _showVisits() {
    showDialog<void>(
      context: context,
      builder: (context) => _VisitRewardsDialog(
        api: widget.visitsApi,
        onConfirmed: (snapshot) async {
          final save = widget.onVisitRewards;
          if (save == null) return;
          final pending = save(snapshot);
          if (mounted) setState(() {});
          await pending;
        },
      ),
    );
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

  void _showSeeds(Plot plot) {
    final player = widget.player;
    _showFarmDialog(
      'Sementes guardadas',
      (update) => player.seeds.isEmpty
          ? const Text(
              'Compre sementes na Loja ou resgate uma recompensa de visita.')
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in player.seeds.entries)
                  Tooltip(
                    message: '${entry.key.label} · ${entry.value} sementes',
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _seed = entry.key;
                        setState(() {
                          _focusedPlot = plot;
                          _plotHint = plot.isWet(DateTime.now())
                              ? 'Segure para plantar ${entry.key.label}'
                              : null;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CropArtwork(type: entry.key, quantity: entry.value),
                          Text(entry.key.label,
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  void _showShop() => _openFarmShop();

  void _openFarmShop({bool animals = false}) {
    _showFarmSheet(
      builder: (context) => StatefulBuilder(
        builder: (context, update) => CropSelectorSheet(
          player: widget.player,
          onOpenWarehouse: _showWarehouse,
          startOnAnimals: animals,
          onBuyGuardDogFood: (quantity) {
            if (widget.player.buyGuardDogFood(quantity: quantity)) {
              _farmChanged();
              update(() {});
            }
          },
          onBuyGuardDog: () {
            if (widget.player.buyGuardDog(DateTime.now())) {
              _farmChanged();
              unawaited(_renewGuard());
              update(() {});
            }
          },
          onBuyCowFeed: (quantity) {
            if (widget.player.buyCowFeed(quantity: quantity)) {
              _farmChanged();
              update(() {});
            }
          },
          onSelected: (seed, quantity) {
            if (widget.player.buySeed(seed, quantity: quantity)) {
              _farmChanged();
              update(() {});
            }
          },
          onBuyCow: () {
            if (widget.player.buyCow(DateTime.now())) {
              _farmChanged();
              update(() {});
            }
          },
          onBuyWeedControl: () {
            if (widget.player.buyWeedControl()) {
              _farmChanged();
              update(() {});
            }
          },
          onBuyFertilizer: () {
            if (widget.player.buyFertilizer()) {
              _farmChanged();
              update(() {});
            }
          },
        ),
      ),
    );
  }

  void _showNotices() {
    final client = widget.socialClient;
    showDialog<void>(
      context: context,
      builder: (context) => _FarmNoticesDialog(
        notices: List.of(widget.player.notices),
        client: client?.auth.currentSession == null ? null : client,
      ),
    );
  }

  void _showUpgrades() {
    final unit = _rewardedUpgradeUnit;
    _showFarmSheet(
      builder: (context) => UpgradeSheet(
        player: widget.player,
        isPreview: _simulateUpgradeAd,
        requestReward: _simulateUpgradeAd
            ? () async => true
            : unit == null
                ? null
                : () => showRewardedUpgradeAd(unit),
        onGranted: () {
          widget.onShouldSave?.call();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Future<void> _renewGuard() async {
    final client = widget.socialClient;
    if (!widget.player.hasGuardDog || client?.auth.currentSession == null)
      return;
    try {
      await updateSocialGuard(client!,
          feed: false, ownedUntil: widget.player.guardDogOwnedUntil!);
    } catch (error) {
      debugPrint('Não foi possível renovar a guarda: ${error.runtimeType}');
    }
  }

  bool _feedingGuard = false;

  Future<bool> _feedGuardDog() async {
    final player = widget.player;
    if (_feedingGuard ||
        !player.hasGuardDog ||
        player.guardDogFood == 0 ||
        player.isGuardDogFed(DateTime.now())) return false;
    _feedingGuard = true;
    try {
      final client = widget.socialClient;
      final deadline = client?.auth.currentSession == null
          ? null
          : await updateSocialGuard(client!,
              feed: true, ownedUntil: player.guardDogOwnedUntil!);
      final fed = player.feedGuardDog(DateTime.now(), serverDeadline: deadline);
      if (fed && mounted) _farmChanged();
      return fed;
    } catch (error) {
      if (mounted)
        _showFarmMessage('Não foi possível alimentar. Tente novamente.');
      return false;
    } finally {
      _feedingGuard = false;
    }
  }

  void _guardHouseTapped() {
    final player = widget.player;
    if (!player.hasGuardDog) {
      _openFarmShop(animals: true);
    } else if (player.isGuardDogFed(DateTime.now())) {
      _showFarmMessage('O cachorro está alimentado.');
    } else if (player.guardDogFood == 0) {
      _openFarmShop(animals: true);
    } else {
      unawaited(_feedGuardDog());
    }
  }

  bool _feedCow() {
    if (!widget.player.refillTrough(DateTime.now(), water: false)) {
      return false;
    }
    _farmChanged();
    return true;
  }

  void _showCowCare() {
    final player = widget.player;
    _showFarmDialog(
      'Cocho e bebedouro',
      (update) {
        final now = DateTime.now();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (water, label, until) in [
              (true, 'Água', player.cowWaterUntil),
              (false, 'Ração', player.cowFeedUntil),
            ])
              ListTile(
                leading:
                    water ? const Icon(Icons.water_drop) : const _CowFeedIcon(),
                title: Text(label),
                subtitle: Text(until != null && until.isAfter(now)
                    ? 'Dura mais ${_formatDuration(until.difference(now))}'
                    : 'Vazio'),
                trailing: TextButton(
                  onPressed: () {
                    if (water) {
                      Navigator.of(context, rootNavigator: true).pop();
                      _selectTool(_FarmTool.water);
                    } else if (player.cowFeed == 0) {
                      Navigator.of(context, rootNavigator: true).pop();
                      _openFarmShop(animals: true);
                    } else if (_feedCow()) {
                      update(() {});
                    }
                  },
                  child: Text(water
                      ? 'Usar regador'
                      : player.cowFeed == 0
                          ? 'Comprar ração'
                          : 'Abastecer ração (${player.cowFeed})'),
                ),
              ),
          ],
        );
      },
    );
  }

  void _buyNewPlot() {
    final player = widget.player;
    if (!player.canBuyMorePlots) {
      _showFarmMessage('Fazenda no limite máximo de canteiros!');
    } else if (player.buyPlot()) {
      _expansionNoticeTimer?.cancel();
      _expansionNoticeTimer = null;
      _farmChanged();
    } else {
      _expansionNoticeTimer?.cancel();
      setState(() {
        _focusedPlot = null;
        _plotHint = null;
        _expansionNoticeTimer = Timer(const Duration(seconds: 4), () {
          setState(() => _expansionNoticeTimer = null);
        });
      });
    }
  }

  Widget _toolButton(_FarmTool tool, String label, {VoidCallback? onPressed}) {
    final active = _tool == tool;
    return IconButton(
      isSelected: active,
      tooltip: label,
      style: IconButton.styleFrom(
        backgroundColor: active ? const Color(0x99e5bc5c) : null,
        minimumSize: const Size(50, 50),
        padding: const EdgeInsets.all(6),
      ),
      onPressed: onPressed ?? () => _selectTool(tool),
      icon: _farmToolArtwork(tool, 38),
    );
  }

  Widget _shortcut(String label, _FarmShortcut illustration, String description,
      VoidCallback onTap) {
    return Tooltip(
      message: description,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width < 540 ? 44 : 52,
            height: 58,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 34,
                  child: Image.asset(_farmIcon(illustration.name),
                      excludeFromSemantics: true),
                ),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Colors.black, blurRadius: 5),
                        Shadow(color: Colors.black, offset: Offset(0, 1))
                      ],
                    )),
              ],
            ),
          ),
        ),
      ),
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
            tool: _tool,
            actions: _actions,
            onActionEnd: (id) {
              if (mounted) {
                setState(
                    () => _actions.removeWhere((action) => action.id == id));
              }
            },
            onPlotTap: _handlePlotTap,
            onBuyPlot: _buyNewPlot,
            onCowCare: _showCowCare,
            onGuardHouse: _guardHouseTapped,
            onFeedCow: () {
              if (!_feedCow()) _showCowCare();
            },
            onRefillCowWater: () {
              if (player.refillTrough(DateTime.now(), water: true))
                _farmChanged();
            },
            onPastureTap: () {
              if (player.collectMilk(DateTime.now())) _farmChanged();
            },
            showExpansionNotice: _expansionNoticeTimer != null,
            focusedPlot: _focusedPlot,
            plotHint: _plotHint,
            plantingPlot: _plantingPlot,
            onPressStart: _tool == _FarmTool.seed ? _beginPlanting : null,
            onPressEnd: _tool == _FarmTool.seed ? _endPlanting : null,
            onInspect: _tool == _FarmTool.harvest ? _inspectPlot : null,
          ),
          SafeArea(
            minimum: const EdgeInsets.all(8),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: _FarmPanel(
                      translucent: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _FarmProfileAvatar(client: widget.socialClient),
                          _LevelStatus(player: player),
                          Tooltip(
                            message: 'Moedas disponíveis',
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Image.asset(_farmIcon('coin'),
                                  width: 21,
                                  height: 21,
                                  excludeFromSemantics: true),
                              Text(' ${player.coins}'),
                            ]),
                          ),
                          if (MediaQuery.sizeOf(context).width >= 610) ...[
                            const SizedBox(width: 12),
                            Tooltip(
                              message: 'Canteiros cultiváveis',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(_farmIcon('sprout'),
                                      width: 20,
                                      height: 20,
                                      excludeFromSemantics: true),
                                  Text(' ${player.plots.length}'),
                                ],
                              ),
                            ),
                          ],
                        ],
                      )),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: EdgeInsets.only(
                        top: MediaQuery.sizeOf(context).width < 700 ? 46 : 0),
                    child: _FarmPanel(
                      translucent: true,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        children: [
                          _shortcut('Armazém', _FarmShortcut.warehouse,
                              'Armazém ${player.basketCount}', _showWarehouse),
                          _shortcut('Loja', _FarmShortcut.store,
                              'Comprar sementes e fertilizantes', _showShop),
                          _shortcut('Amigos', _FarmShortcut.friends,
                              'Visitar fazendas de amigos', () {
                            if (widget.socialClient case final client?) {
                              showSocialFarm(context, client,
                                  guardOwnedUntil: player.guardDogOwnedUntil);
                            } else {
                              _showFarmDialog(
                                  'Amigos',
                                  (_) => const Text(
                                      'O modo social está indisponível nesta versão.'));
                            }
                          }),
                          _shortcut(
                              'Ranking',
                              _FarmShortcut.ranking,
                              'Classificação das fazendas',
                              () => _showFarmDialog(
                                  'Ranking',
                                  (_) => const Text(
                                      'A classificação online ainda não está disponível.'))),
                          _shortcut('Check-in', _FarmShortcut.check_in,
                              'Recompensa diária', _showVisits),
                          _shortcut('Melhorias', _FarmShortcut.upgrades,
                              'Melhorias da fazenda', _showUpgrades),
                          _shortcut('Avisos', _FarmShortcut.notices,
                              'Notificações da fazenda', _showNotices),
                        ],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _FarmPanel(
                      translucent: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _toolButton(_FarmTool.hoe, 'Enxada'),
                          _toolButton(_FarmTool.seed, 'Sementes',
                              onPressed: () {
                            _seed = null;
                            _selectTool(_FarmTool.seed);
                          }),
                          _toolButton(_FarmTool.water, 'Regar'),
                          _toolButton(_FarmTool.fertilizer,
                              'Adubo · ${player.fertilizer}'),
                          _toolButton(_FarmTool.weedControl,
                              'Defensivo · ${player.weedControl}'),
                          _toolButton(_FarmTool.harvest,
                              player.hasCow ? 'Colher e alimentar' : 'Colher'),
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

class _VisitRewardsDialog extends StatefulWidget {
  const _VisitRewardsDialog({required this.api, required this.onConfirmed});

  final VisitRewardsApi? api;
  final Future<void> Function(VisitSnapshot) onConfirmed;

  @override
  State<_VisitRewardsDialog> createState() => _VisitRewardsDialogState();
}

class _VisitRewardsDialogState extends State<_VisitRewardsDialog> {
  VisitSnapshot? _snapshot;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final api = widget.api;
    if (api != null) unawaited(_send(api.visit));
  }

  Future<void> _send(Future<VisitSnapshot> Function() request) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final confirmed = await request();
      if (!mounted) return;
      await widget.onConfirmed(confirmed);
      if (mounted) setState(() => _snapshot = confirmed);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<VisitSnapshot> _claim(VisitRewardsApi api, String date) async {
    try {
      return await api.claim(date);
    } on VisitClaimUnavailable {
      return api.visit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    final snapshot = _snapshot;
    final Widget content;
    if (api == null) {
      content = const Text('Serviço de visitas indisponível nesta versão.');
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_failed)
            const Text(
                'Não foi possível confirmar o progresso. Tente novamente.'),
          if (snapshot != null) ...[
            LinearProgressIndicator(
              value: snapshot.rewardDay / VisitRewardsApi.dayLimit,
            ),
            Text('Sequência: ${snapshot.streak} dia(s) consecutivo(s)'),
            for (final (index, reward) in snapshot.rewards.indexed)
              ListTile(
                title: Text(index == VisitRewardsApi.dayLimit - 1
                    ? 'Dia ${index + 1} · Marco da semana'
                    : 'Dia ${index + 1}'),
                subtitle: Text(
                    '${reward.coins} moedas · ${reward.seeds} sementes de alface'),
                trailing: index + 1 == snapshot.rewardDay
                    ? TextButton(
                        onPressed: !_busy && !_failed && snapshot.claimable
                            ? () => _send(() => _claim(api, snapshot.date))
                            : null,
                        child: Text(snapshot.claimedToday
                            ? 'Resgatado hoje'
                            : 'Resgatar'),
                      )
                    : null,
              ),
          ],
        ],
      );
    }
    return AlertDialog(
      title: const _FarmMenuTitle('Check-in', 'check_in'),
      content:
          SizedBox(width: 480, child: SingleChildScrollView(child: content)),
      actions: [
        if (api != null)
          TextButton(
            onPressed: _busy ? null : () => _send(api.visit),
            child: const Text('Atualizar'),
          ),
        if (api != null &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android)
          TextButton(
            onPressed: () => const MethodChannel(
              'little_farm/daily_login_reminder',
            ).invokeMethod<void>('enable', true),
            child: const Text('Configurar lembrete'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _FarmMenuTitle extends StatelessWidget {
  const _FarmMenuTitle(this.title, this.artwork);

  final String title;
  final String artwork;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(_farmIcon(artwork),
            width: 36, height: 36, excludeFromSemantics: true),
        const SizedBox(width: 8),
        Flexible(
          child: Text(title,
              style: const TextStyle(
                color: Color(0xffffecc0),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              )),
        ),
      ],
    );
  }
}

class _FarmNoticesDialog extends StatefulWidget {
  const _FarmNoticesDialog({required this.notices, required this.client});

  final List<_FarmNotice> notices;
  final SupabaseClient? client;

  @override
  State<_FarmNoticesDialog> createState() => _FarmNoticesDialogState();
}

class _FarmNoticesDialogState extends State<_FarmNoticesDialog> {
  late final Future<List<_FarmNotice>> _remote = _loadSocialNotices();

  Future<List<_FarmNotice>> _loadSocialNotices() async {
    final client = widget.client;
    if (client == null) return [];
    final rows = await client.rpc('farm_social_notices') as List;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        if (DateTime.tryParse(row['created_at'] as String)
            case final DateTime at)
          (
            message: row['guarded'] == true
                ? 'O cachorro impediu ${row['visitor_name']} de roubar a colheita.'
                : '${row['visitor_name']} roubou uma unidade de ${row['crop']} da sua fazenda.',
            at: at,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const _FarmMenuTitle('Avisos', 'notices'),
        content: SizedBox(
          width: 420,
          height: 260,
          child: FutureBuilder<List<_FarmNotice>>(
            future: _remote,
            builder: (context, snapshot) {
              final notices = [...widget.notices, ...?snapshot.data]
                ..sort((a, b) => b.at.compareTo(a.at));
              final localizations = MaterialLocalizations.of(context);
              return ListView(
                children: [
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const LinearProgressIndicator(),
                  if (snapshot.hasError)
                    const ListTile(title: Text('Avisos online indisponíveis.')),
                  if (notices.isEmpty &&
                      snapshot.connectionState == ConnectionState.done &&
                      !snapshot.hasError)
                    const ListTile(title: Text('Você ainda não tem avisos.')),
                  for (final notice in notices)
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: Text(notice.message),
                      subtitle: Text(
                        '${localizations.formatCompactDate(notice.at.toLocal())}'
                        ' · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(notice.at.toLocal()))}',
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      );
}

class _FarmPanel extends StatelessWidget {
  const _FarmPanel({required this.child, this.translucent = false});

  final bool translucent;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const foreground = Color(0xfffff5d8);
    return Material(
      color: translucent ? const Color(0x9e15281d) : const Color(0xf0223528),
      elevation: translucent ? 0 : 3,
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

class _FarmProfileAvatar extends StatelessWidget {
  const _FarmProfileAvatar({required this.client});

  final SupabaseClient? client;

  @override
  Widget build(BuildContext context) {
    final auth = client?.auth;
    return StreamBuilder<AuthState>(
      stream: auth?.onAuthStateChange,
      builder: (context, _) {
        final metadata = auth?.currentUser?.userMetadata;
        final fallback = const Icon(
          Icons.person_rounded,
          color: Color(0xffe2ead1),
          size: 22,
        );
        final rawPhoto = metadata?['avatar_url'] ?? metadata?['picture'];
        final photo = rawPhoto is String ? Uri.tryParse(rawPhoto) : null;
        final hasPhoto =
            photo != null && photo.scheme == 'https' && photo.host.isNotEmpty;
        return Tooltip(
          message: 'Foto do jogador',
          child: CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xff456d42),
            child: hasPhoto
                ? ClipOval(
                    child: Image.network(
                      photo.toString(),
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (_, __, ___) => fallback,
                    ),
                  )
                : fallback,
          ),
        );
      },
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
      width: MediaQuery.sizeOf(context).width < 540 ? 107 : 146,
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
            _XpProgressBar(
              level: player.level,
              progress: player.levelProgress,
              animate: !MediaQuery.disableAnimationsOf(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _XpProgressBar extends StatefulWidget {
  const _XpProgressBar({
    required this.level,
    required this.progress,
    required this.animate,
  });

  final int level;
  final double progress;
  final bool animate;

  @override
  State<_XpProgressBar> createState() => _XpProgressBarState();
}

class _XpProgressBarState extends State<_XpProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: 1,
  );
  late double _start = widget.progress;

  double _progressTo(double target) =>
      _start +
      (target - _start) * Curves.easeOutCubic.transform(_animation.value);

  @override
  void didUpdateWidget(_XpProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animate) {
      _animation.value = 1;
      return;
    }
    if (widget.progress == oldWidget.progress &&
        widget.level == oldWidget.level) {
      return;
    }
    _start =
        widget.level == oldWidget.level ? _progressTo(oldWidget.progress) : 0;
    _animation.forward(from: 0);
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final pulse =
            _animation.isAnimating ? math.sin(math.pi * _animation.value) : 0.0;
        return Transform.scale(
          scaleY: 1 + .28 * pulse,
          child: LinearProgressIndicator(
            value: _progressTo(widget.progress),
            semanticsLabel: 'Progresso do nível',
            minHeight: 5,
            borderRadius: BorderRadius.circular(4),
            color: Color.lerp(
              const Color(0xfff9cf72),
              const Color(0xffffedab),
              pulse,
            ),
            backgroundColor: const Color(0xff52604c),
          ),
        );
      },
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
class _FarmScene extends StatefulWidget {
  const _FarmScene({
    required this.player,
    required this.tool,
    required this.actions,
    required this.onActionEnd,
    required this.onPlotTap,
    required this.onBuyPlot,
    required this.onPastureTap,
    required this.onCowCare,
    required this.onGuardHouse,
    required this.onFeedCow,
    required this.onRefillCowWater,
    required this.showExpansionNotice,
    required this.focusedPlot,
    required this.plotHint,
    this.plantingPlot,
    this.onPressStart,
    this.onPressEnd,
    this.onInspect,
  });

  final Player player;
  final _FarmTool tool;
  final List<_FarmAction> actions;
  final ValueChanged<Object> onActionEnd;
  final void Function(Plot plot) onPlotTap;
  final VoidCallback onBuyPlot;
  final VoidCallback onPastureTap;
  final VoidCallback onCowCare;
  final VoidCallback onGuardHouse;
  final VoidCallback onFeedCow;
  final VoidCallback onRefillCowWater;
  final bool showExpansionNotice;
  final Plot? focusedPlot;
  final String? plotHint;
  final Plot? plantingPlot;
  final ValueChanged<Plot>? onPressStart;
  final ValueChanged<Plot>? onPressEnd;
  final ValueChanged<Plot?>? onInspect;

  @override
  State<_FarmScene> createState() => _FarmSceneState();
}

class _FarmSceneState extends State<_FarmScene> {
  final _pointer = ValueNotifier<Offset?>(null);
  final _draggedPlots = <Plot>{};
  Offset? _lastDragPoint;

  void _endDrag() {
    _lastDragPoint = null;
    _draggedPlots.clear();
  }

  @override
  void dispose() {
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget;
    final player = scene.player;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final farmScale = math.max(w / 1672, h / 941);
        final farmWidth = 1672 * farmScale;
        final farmHeight = 941 * farmScale;
        final pasture = Offset(
            w - farmWidth * .09, (h - farmHeight) / 2 + farmHeight * .58);
        final cowWidth = farmWidth * .11;
        final dairyPanelWidth = math.min(w, math.max(148.0, cowWidth * 1.6));
        final tileCount =
            player.plots.length + (player.canBuyMorePlots ? 1 : 0);

        // Reserve the full strip from the start, so expanding never moves
        // the existing beds. The first row is on the creek side.
        final origin = Offset(w * .23, h * .35);
        final last =
            GameConstants.plotCenterForIndex(GameConstants.maxPlots - 1);
        final stripWidth = last.dx + GameConstants.isoTileHalfWidth * 2;
        final stripHeight = last.dy + GameConstants.isoTileHalfHeight;
        final scale = math.min(
          math.min(
            w * .53 / stripWidth,
            h * .195 / (GameConstants.isoTileHalfWidth * 2),
          ),
          math.max(1.0, h - origin.dy - 62) / stripHeight,
        );

        final tileW = GameConstants.isoTileHalfWidth * 2 * scale;
        final tileH = GameConstants.isoTileHalfHeight * 2 * scale;

        double leftFor(int i) =>
            origin.dx +
            GameConstants.plotCenterForIndex(i).dx * scale -
            tileW / 2;

        double topFor(int i) =>
            origin.dy +
            GameConstants.plotCenterForIndex(i).dy * scale -
            tileH / 2;

        final patrolOffset = Offset(tileW * .90, -tileH * .75);
        final patrolLength =
            (player.plots.length - 1) ~/ GameConstants.gridColumns;
        final patrolEnd = GameConstants.plotCenterForIndex(
              patrolLength * GameConstants.gridColumns,
            ) *
            scale;
        final dogFed = player.isGuardDogFed(DateTime.now());

        final effects = [
          for (final action in scene.actions)
            if (player.plots.indexOf(action.plot) case final int i when i >= 0)
              (action, Offset(leftFor(i) + tileW / 2, topFor(i) + tileH / 2)),
        ];

        final focus = player.plots
            .indexWhere((plot) => identical(plot, scene.focusedPlot));
        Plot? plotAt(Offset position, {double edgeTolerance = 0}) {
          Plot? closestPlot;
          // Convert the perpendicular screen distance into diamond coordinates.
          var nearest =
              1 + edgeTolerance * (Offset(2 / tileW, 2 / tileH)).distance;
          for (var i = player.plots.length - 1; i >= 0; i--) {
            final dx = (position.dx - leftFor(i) - tileW / 2).abs();
            final dy = (position.dy - topFor(i) - tileH / 2).abs();
            final distance = dx / (tileW / 2) + dy / (tileH / 2);
            if (distance > nearest ||
                (closestPlot != null && distance == nearest)) {
              continue;
            }
            nearest = distance;
            closestPlot = player.plots[i];
          }
          return closestPlot;
        }

        void inspectAt(Offset position) =>
            scene.onInspect?.call(plotAt(position));

        final acceptsEdgeTap =
            scene.tool == _FarmTool.hoe || scene.tool == _FarmTool.water;

        final acceptsDrag = acceptsEdgeTap || scene.tool == _FarmTool.harvest;

        void dragThrough(Offset position) {
          final from = _lastDragPoint ?? position;
          final steps = math.max(1, ((position - from).distance / 4).ceil());
          _lastDragPoint = position;
          for (var i = 0; i <= steps; i++) {
            final point = Offset.lerp(from, position, i / steps)!;
            final plot = plotAt(point);
            if (plot != null && _draggedPlots.add(plot)) scene.onPlotTap(plot);
          }
        }

        return MouseRegion(
          cursor: SystemMouseCursors.none,
          onEnter: (event) => _pointer.value = event.localPosition,
          onHover: (event) {
            _pointer.value = event.localPosition;
            if (scene.onInspect != null) inspectAt(event.localPosition);
          },
          onExit: (_) {
            if (!mounted) return;
            _pointer.value = null;
            scene.onInspect?.call(null);
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerMove: scene.onInspect == null
                ? null
                : (event) => inspectAt(event.localPosition),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onPanStart: acceptsDrag
                  ? (event) {
                      _endDrag();
                      dragThrough(event.localPosition);
                    }
                  : null,
              onPanUpdate: acceptsDrag
                  ? (event) => dragThrough(event.localPosition)
                  : null,
              onPanEnd: acceptsDrag ? (_) => _endDrag() : null,
              onPanCancel: acceptsDrag ? _endDrag : null,
              child: ColoredBox(
                color: const Color(0xFF253F29),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ExcludeSemantics(
                      child: Image.asset('assets/images/farm.webp',
                          fit: BoxFit.cover, alignment: Alignment.centerRight),
                    ),
                    if (acceptsEdgeTap)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        excludeFromSemantics: true,
                        onTapUp: (details) {
                          final plot =
                              plotAt(details.localPosition, edgeTolerance: 2);
                          if (plot != null) scene.onPlotTap(plot);
                        },
                      ),
                    for (final (water, x, y, angle) in [
                      (false, .824, .497, -.22),
                      (true, .888, .415, 0.0),
                    ])
                      Positioned(
                        left: w - farmWidth * (1 - x) - cowWidth * .25,
                        top: (h - farmHeight) / 2 +
                            farmHeight * y -
                            cowWidth * .28,
                        width: cowWidth * (water ? .50 : .56),
                        height: cowWidth * 2 / 3,
                        child: Transform.rotate(
                          angle: angle,
                          alignment: water
                              ? Alignment.center
                              : const Alignment(-.107, 0),
                          child: Tooltip(
                            message: water ? 'Bebedouro' : 'Cocho de ração',
                            child: GestureDetector(
                              onTap: player.hasCow
                                  ? water && scene.tool == _FarmTool.water
                                      ? scene.onRefillCowWater
                                      : !water &&
                                              scene.tool == _FarmTool.harvest
                                          ? scene.onFeedCow
                                          : scene.onCowCare
                                  : null,
                              child: _TroughArtwork(
                                spriteWidth: cowWidth,
                                water: water,
                                full: water
                                    ? player.hasCowWater(DateTime.now())
                                    : player.hasCowFeed(DateTime.now()),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (player.hasCow)
                      Positioned.fill(
                        child: _DairyPasture(
                          player: player,
                          cowWidth: cowWidth,
                          panelWidth: dairyPanelWidth,
                          home: Offset(
                            (pasture.dx - cowWidth * .2).clamp(
                                dairyPanelWidth / 2, w - dairyPanelWidth / 2),
                            pasture.dy - cowWidth * .46 + cowWidth / 3,
                          ),
                          feed: Offset(w - farmWidth * .176,
                              (h - farmHeight) / 2 + farmHeight * .497),
                          water: Offset(w - farmWidth * .112,
                              (h - farmHeight) / 2 + farmHeight * .415),
                          onTap: scene.onPastureTap,
                        ),
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
                          onTap: () => scene.onPlotTap(player.plots[i]),
                          onPressStart: scene.onPressStart == null
                              ? null
                              : () => scene.onPressStart!(player.plots[i]),
                          onPressEnd: scene.onPressEnd == null
                              ? null
                              : () => scene.onPressEnd!(player.plots[i]),
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
                          onTap: scene.onBuyPlot,
                        ),
                      ),
                    if (player.hasGuardDogHouse)
                      Positioned(
                        left: (w - farmWidth * .476 - tileW * .48)
                            .clamp(4.0, math.max(4.0, w - 110)),
                        top: ((h - farmHeight) / 2 +
                                farmHeight * .258 -
                                tileW * .48)
                            .clamp(4.0, math.max(4.0, h - 110)),
                        child: Tooltip(
                          message: dogFed || !player.hasGuardDog
                              ? 'Casinha do cachorro'
                              : 'Cachorro dormindo · toque para alimentar',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: scene.onGuardHouse,
                            child: Image.asset(
                              _farmIcon(player.hasGuardDog && !dogFed
                                  ? 'doghouse_sleeping'
                                  : 'doghouse'),
                              width: (tileW * .90).clamp(48.0, 108.0),
                              height: (tileW * .90).clamp(48.0, 108.0),
                              semanticLabel: 'Casinha do cachorro',
                            ),
                          ),
                        ),
                      ),
                    if (dogFed)
                      Positioned.fill(
                        child: _GuardPatrol(
                          start: origin + patrolOffset + patrolEnd * .35,
                          end: origin +
                              patrolOffset +
                              patrolEnd +
                              Offset(tileW * .28, tileH * .28),
                          size: (tileW * .88).clamp(44.0, 100.0),
                        ),
                      ),
                    if (scene.showExpansionNotice &&
                        player.canBuyMorePlots &&
                        player.coins < player.nextPlotCost)
                      Positioned(
                        width: math.min(184.0, w - 8),
                        left: (leftFor(player.plots.length) +
                                tileW / 2 -
                                math.min(184.0, w - 8) / 2)
                            .clamp(4.0, math.max(4.0, w - 188)),
                        bottom: h - topFor(player.plots.length) + 6,
                        child: IgnorePointer(
                          child: Semantics(
                            liveRegion: true,
                            child: _FarmPanel(
                              translucent: true,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 7),
                                child: Text(
                                  'Moedas insuficientes\n'
                                  'Faltam ${player.nextPlotCost - player.coins} moedas.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (focus >= 0)
                      Positioned(
                        width: 192,
                        left: (leftFor(focus) + tileW / 2 - 96)
                            .clamp(4.0, math.max(4.0, w - 196)),
                        top: player.plots[focus].hasWeeds
                            ? null
                            : math.max(52.0, topFor(focus) - 68),
                        bottom: player.plots[focus].hasWeeds
                            ? h - topFor(focus) + 6
                            : null,
                        child: IgnorePointer(
                          child: _PlotNotice(
                              plot: player.plots[focus],
                              hasWeedControl: player.weedControl > 0,
                              hint: scene.plotHint,
                              planting: identical(
                                  player.plots[focus], scene.plantingPlot)),
                        ),
                      ),
                    for (final (action, center) in effects)
                      Positioned(
                        key: ObjectKey(action.id),
                        left: center.dx - 30,
                        top: center.dy - 41,
                        child: IgnorePointer(
                          child: _FarmActionEffect(
                            tool: action.tool,
                            xp: action.xp,
                            onEnd: () => scene.onActionEnd(action.id),
                          ),
                        ),
                      ),
                    IgnorePointer(
                      child: ValueListenableBuilder<Offset?>(
                        valueListenable: _pointer,
                        builder: (context, pointer, _) => Stack(
                          children: [
                            if (pointer != null &&
                                effects.every((effect) =>
                                    (pointer - effect.$2).distance > tileW / 2))
                              Positioned(
                                left: pointer.dx - 5,
                                top: pointer.dy - 6,
                                child: _farmToolArtwork(scene.tool, 36),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GuardPatrol extends StatefulWidget {
  const _GuardPatrol(
      {required this.start, required this.end, required this.size});

  final Offset start;
  final Offset end;
  final double size;

  @override
  State<_GuardPatrol> createState() => _GuardPatrolState();
}

class _GuardPatrolState extends State<_GuardPatrol>
    with SingleTickerProviderStateMixin {
  late final AnimationController _patrol = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 11),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _patrol.reset();
    } else if (!_patrol.isAnimating) {
      _patrol.repeat();
    }
  }

  @override
  void dispose() {
    _patrol.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _patrol,
          builder: (context, _) {
            final phase = _patrol.value;
            final towardsEnd = phase < .5;
            final position = Offset.lerp(
                widget.start, widget.end, 1 - (phase * 2 - 1).abs())!;
            final step = (phase * 64).floor() % 4;
            return Stack(
              children: [
                Positioned(
                  left: position.dx - widget.size / 2,
                  top: position.dy - widget.size / 2,
                  child: Transform.flip(
                    flipX: towardsEnd,
                    child: Image.asset(
                      _farmIcon('guard_dog_step_$step'),
                      key: const ValueKey('guard-dog-patrol'),
                      width: widget.size,
                      height: widget.size,
                      semanticLabel: 'Cachorro guarda',
                      gaplessPlayback: true,
                      frameBuilder: (context, child, frame, _) => frame == null
                          ? Image.asset(_farmIcon('guard_dog'),
                              width: widget.size, height: widget.size)
                          : child,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _GuardDogFoodIcon extends StatelessWidget {
  const _GuardDogFoodIcon();

  @override
  Widget build(BuildContext context) => Image.asset(
        _farmIcon('guard_dog_food'),
        width: 36,
        height: 36,
        excludeFromSemantics: true,
      );
}

class _CowFeedIcon extends StatelessWidget {
  const _CowFeedIcon();

  @override
  Widget build(BuildContext context) => Image.asset(
        _farmIcon('cow_feed'),
        width: 36,
        height: 36,
        excludeFromSemantics: true,
      );
}

class _TroughArtwork extends StatelessWidget {
  const _TroughArtwork({
    required this.spriteWidth,
    required this.water,
    required this.full,
  });

  final double spriteWidth;
  final bool water;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final artwork = OverflowBox(
      alignment: water ? Alignment.centerRight : Alignment.centerLeft,
      minWidth: spriteWidth,
      maxWidth: spriteWidth,
      child: Image.asset(
        _farmIcon(full ? 'trough' : 'trough_empty'),
        width: spriteWidth,
        excludeFromSemantics: true,
      ),
    );
    return water
        ? ClipPath(clipper: const _BasinClipper(), child: artwork)
        : ClipPath(clipper: const _FeedTroughClipper(), child: artwork);
  }
}

class _FeedTroughClipper extends CustomClipper<Path> {
  const _FeedTroughClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width * .88, 0)
    // Follow the timber rim where the two objects meet in the sprite.
    ..lineTo(size.width * .88, size.height * .39)
    ..lineTo(size.width * .96, size.height * .46)
    ..lineTo(size.width * .98, size.height * .66)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_FeedTroughClipper oldClipper) => false;
}

class _BasinClipper extends CustomClipper<Path> {
  const _BasinClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height * .66)
    ..lineTo(size.width * .18, size.height * .66)
    ..lineTo(size.width * .085, size.height * .45)
    ..lineTo(0, size.height * .43)
    ..close();

  @override
  bool shouldReclip(_BasinClipper oldClipper) => false;
}

class _DairyPasture extends StatefulWidget {
  const _DairyPasture({
    required this.player,
    required this.cowWidth,
    required this.panelWidth,
    required this.home,
    required this.feed,
    required this.water,
    required this.onTap,
  });

  final Player player;
  final double cowWidth;
  final double panelWidth;
  final Offset home;
  final Offset feed;
  final Offset water;
  final VoidCallback onTap;

  @override
  State<_DairyPasture> createState() => _DairyPastureState();
}

class _DairyPastureState extends State<_DairyPasture>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  bool _statusPinned = false;
  late final _roam = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _roam.reset();
    } else if (!_roam.isAnimating) {
      _roam.repeat();
    }
  }

  @override
  void dispose() {
    _roam.dispose();
    super.dispose();
  }

  Widget _movingCow({required bool hasWater, required bool hasFeed}) {
    final size = widget.cowWidth;
    final home = widget.home;
    final graze = home + Offset(-size * .29, size * .10);
    final feed = hasFeed ? widget.feed + Offset(size * .30, size * .13) : graze;
    final water =
        hasWater ? widget.water + Offset(size * .30, size * .07) : home;
    final route = [
      home,
      graze,
      graze,
      feed,
      feed,
      water,
      water,
      home,
    ];
    return AnimatedBuilder(
      animation: _roam,
      builder: (context, _) {
        final phase = math.min(_roam.value * (route.length - 1), 6.999);
        final step = phase.floor();
        final progress = phase - step;
        final from = route[step];
        final to = route[step + 1];
        final walking = from != to;
        final facingRight = walking && to.dx > from.dx;
        final bending = !walking && (step == 1 || step == 3 || step == 5);
        final position =
            Offset.lerp(from, to, Curves.easeInOut.transform(progress))!;
        final motion = math.sin(progress * math.pi * 8);
        return Positioned(
          left: position.dx - size / 2,
          top: position.dy - size / 3 + (walking ? motion * size * .014 : 0),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              key: const ValueKey('dairy-cow'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _statusPinned = !_statusPinned),
              child: Transform.flip(
                flipX: facingRight,
                child: DairyCowArt(
                  asset: _farmIcon('cow'),
                  width: size,
                  stride: walking ? progress * math.pi * 8 : null,
                  headDip: bending
                      ? math.sin(progress * math.pi) * (.85 + .15 * motion)
                      : 0,
                  tailSwing: math.sin(_roam.value * math.pi * 24),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final now = DateTime.now();
    final remaining = player.milkRemaining(now)!;
    final hasWater = player.hasCowWater(now);
    final hasFeed = player.hasCowFeed(now);
    final needsSupplies = player.hasCow && (!hasWater || !hasFeed);
    final ready = remaining <= Duration.zero;
    final milkStatus = ready
        ? '${Player.bottlesPerCycle} garrafas · +${Player.milkXpPerCycle} XP'
        : needsSupplies
            ? 'Pausado'
            : _HomeScreenState._formatDuration(remaining);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _movingCow(hasWater: hasWater, hasFeed: hasFeed),
        if (_hovered || _statusPinned)
          Positioned(
            left: widget.home.dx - widget.panelWidth / 2,
            top: widget.home.dy + widget.cowWidth / 3,
            width: widget.panelWidth,
            child: IgnorePointer(
              ignoring: !ready,
              child: Center(
                child: _FarmPanel(
                  translucent: true,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Column(
                        children: [
                          _DairyMeter(
                            label: 'Água',
                            value: player.troughLevel(now, water: true),
                            color: const Color(0xFF8CD9FF),
                          ),
                          _DairyMeter(
                            label: 'Ração',
                            value: player.troughLevel(now, water: false),
                            color: const Color(0xFFFFCF74),
                          ),
                          _DairyMeter(
                            label: 'Produção de leite',
                            value: player.milkProgress(now),
                            color: const Color(0xFFF4F1D9),
                            status: milkStatus,
                          ),
                          if (ready)
                            TextButton(
                              onPressed: widget.onTap,
                              child: const Text('Ordenhar'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DairyMeter extends StatelessWidget {
  const _DairyMeter({
    required this.label,
    required this.value,
    required this.color,
    this.status,
  });

  final String label;
  final double value;
  final Color color;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final percent = '${(value * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                  child: Text(label, style: const TextStyle(fontSize: 10))),
              Text(percent, style: const TextStyle(fontSize: 10)),
            ],
          ),
          LinearProgressIndicator(
            value: value,
            color: color,
            backgroundColor: Colors.white24,
            minHeight: 4,
            borderRadius: BorderRadius.circular(4),
            semanticsLabel: label,
            semanticsValue: percent,
          ),
          if (status case final status?)
            Text(status, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class _PlotNotice extends StatelessWidget {
  const _PlotNotice({
    required this.plot,
    required this.hint,
    required this.planting,
    required this.hasWeedControl,
  });

  final bool planting;
  final bool hasWeedControl;

  final Plot plot;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final String label;
    double? progress;
    String? details;
    if (planting) {
      label = 'Plantando semente…';
    } else if (hint != null) {
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
      final ready = plot.isReady(now);
      final crop = Crops.of(plot.plantedCrop!);
      label = ready
          ? '${crop.label} pronta para colher'
          : '${crop.label} crescendo';
      if (ready) {
        final remaining = plot.spoilAt().difference(now);
        final seconds = (remaining.inMilliseconds / 1000).ceil();
        final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
        final remainder = (seconds % 60).toString().padLeft(2, '0');
        details =
            'Saúde $health/100\nApodrece em ${seconds ~/ 3600}:$minutes:$remainder';
      } else {
        final remaining = _HomeScreenState._formatDuration(end.difference(now));
        details = 'Saúde $health/100 · Colheita em $remaining';
      }
      progress = plot.progress(now);
    } else if (!plot.tilled) {
      label = 'Use a enxada para preparar';
    } else {
      label = plot.isWet(now)
          ? 'Terra úmida · pronta para plantar'
          : 'Use o regador para umedecer a terra antes de plantar';
    }
    return _FarmPanel(
      translucent: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12)),
            if (details != null)
              Text(details,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11)),
            if (plot.hasWeeds)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xff604718),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      plot.isReady(now)
                          ? 'Mato · Saúde cai 50% mais rápido'
                          : plot.isPlanted && !plot.isDead(now)
                              ? 'Mato · +25% no tempo de maturação'
                              : 'Mato no canteiro',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xffffe2a4),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      hasWeedControl
                          ? 'Use o defensivo do Armazém.'
                          : 'Compre defensivo na Loja.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xfffff5d8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            if (planting) ...[
              const SizedBox(height: 5),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Plot.plantingDuration,
                builder: (context, value, child) => LinearProgressIndicator(
                    value: value, minHeight: 6, color: const Color(0xffffd55c)),
              ),
            ],
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
  if (_useTestAds || _rewardedUpgradeUnit != null) {
    try {
      await MobileAds.instance.initialize();
    } catch (error) {
      debugPrint('Falha ao inicializar anúncios de teste: $error');
    }
  }
  if (kIsWeb && const bool.fromEnvironment('DAIRY_PREVIEW')) {
    final player = Player.initial()
      ..coins += Player.cowCost + Player.cowFeedCost * 3
      ..milkProductionTime = const Duration(seconds: 40)
      ..waterRefillTime = const Duration(seconds: 20)
      ..feedRefillTime = const Duration(seconds: 60)
      ..buyCow(DateTime.now());
    if (const bool.fromEnvironment('GUARD_PREVIEW')) {
      player.guardDogMealTime = const Duration(seconds: 45);
      if (Uri.base.queryParameters['comprar-cachorro'] == '1') {
        player.coins += Player.guardDogCost;
      } else {
        player.guardDogOwnedUntil = DateTime.now().add(Player.guardDogLifetime);
      }
    }
    if (const bool.fromEnvironment('WEEDS_PREVIEW')) {
      final now = DateTime.now();
      player.weedControl += 2;
      player.plots[0]
        .._harvestsUntilWeeds = 0
        ..plantedCrop = CropType.tomate
        ..plantedAt = now.subtract(const Duration(minutes: 2))
        ..growDuration = const Duration(minutes: 5);
      player.plots[1]
        .._harvestsUntilWeeds = 0
        ..plantedCrop = CropType.cenoura
        ..plantedAt = now.subtract(const Duration(minutes: 3))
        ..growDuration = const Duration(minutes: 2, seconds: 30);
    }
    runApp(FazendinhaApp(player: player));
    return;
  }

  await Hive.initFlutter();
  final dairyTest = kIsWeb &&
      (Uri.base.path.endsWith('/teste.html') ||
          Uri.base.queryParameters['teste-vaca'] == '1');
  final box = await Hive.openBox(dairyTest
      ? '${GameConstants.hiveBoxName}_dairy_test'
      : GameConstants.hiveBoxName);

  final player = await _loadOrCreate(box, dairyTest: dairyTest);
  final visitsApi = await _configureVisits(box);
  final socialClient = await configureSocialFarm();
  runApp(FazendinhaApp(
    player: player,
    box: box,
    visitsApi: visitsApi,
    socialClient: socialClient,
  ));
}

Future<VisitRewardsApi?> _configureVisits(Box box) async {
  final url = const String.fromEnvironment('VISIT_REWARDS_URL').trim();
  if (url.isEmpty) return null;
  final base = Uri.tryParse(url);
  final loopback = base != null &&
      const ['localhost', '127.0.0.1', '::1'].contains(base.host);
  if (base == null ||
      base.host.isEmpty ||
      base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment ||
      (base.scheme != 'https' && !(loopback && base.scheme == 'http'))) {
    debugPrint('VISIT_REWARDS_URL inválida.');
    return null;
  }
  const keyName = 'visitInstallationKey';
  try {
    final saved = box.get(keyName);
    if (saved is String) return VisitRewardsApi(base, saved);
    final key = VisitRewardsApi.newInstallationKey();
    await box.put(keyName, key);
    await box.flush();
    return VisitRewardsApi(base, key);
  } catch (error) {
    debugPrint('Não foi possível preparar o serviço de visitas: $error');
    return null;
  }
}

Future<Player> _loadOrCreate(Box box, {required bool dairyTest}) async {
  final saved = box.get(GameConstants.playerKey);
  final player = saved is Map
      ? Player.fromMap(Map<String, dynamic>.from(saved), dairyTest: dairyTest)
      : Player.initial();
  if (dairyTest) {
    player.milkProductionTime = const Duration(seconds: 40);
    player.waterRefillTime = const Duration(seconds: 20);
    player.feedRefillTime = const Duration(seconds: 60);
    if (!player.hasCow) {
      final balance = player.coins;
      player.coins = Player.cowCost;
      player.buyCow(DateTime.now());
      player.coins = balance;
      await box.put(GameConstants.playerKey, player.toMap());
      await box.flush();
    }
  }
  if (saved is! Map) {
    await box.put(GameConstants.playerKey, player.toMap());
    await box.flush();
  }
  return player;
}

class FazendinhaApp extends StatefulWidget {
  const FazendinhaApp({
    super.key,
    required this.player,
    this.box,
    this.visitsApi,
    this.socialClient,
  });

  final Player player;
  final Box? box;
  final VisitRewardsApi? visitsApi;
  final SupabaseClient? socialClient;

  @override
  State<FazendinhaApp> createState() => _FazendinhaAppState();
}

class _FazendinhaAppState extends State<FazendinhaApp>
    with WidgetsBindingObserver {
  Timer? _saveTimer;
  Future<void> _saveQueue = Future.value();
  bool _syncingDailyLogin = false;

  Future<void> _syncDailyLogin() async {
    final api = widget.visitsApi;
    if (api == null || _syncingDailyLogin) return;
    _syncingDailyLogin = true;
    try {
      final snapshot = await api.visit();
      if (mounted) {
        final saved = _applyVisitRewards(snapshot);
        setState(() {});
        await saved;
      }
    } catch (error) {
      debugPrint('Login diário indisponível: $error');
    } finally {
      _syncingDailyLogin = false;
    }
  }

  Future<void> _enableDailyReminder() async {
    if (widget.visitsApi == null ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      await const MethodChannel('little_farm/daily_login_reminder')
          .invokeMethod<void>('enable');
    } on PlatformException catch (error) {
      debugPrint('Não foi possível agendar o lembrete diário: ${error.code}');
    } on MissingPluginException {
      // O agendamento é nativo.
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_enableDailyReminder());
      unawaited(_syncDailyLogin());
    });
    _saveTimer = Timer.periodic(
      const Duration(seconds: GameConstants.autoSaveSeconds),
      (_) => _save(),
    );
  }

  Future<void> _persistPlayer() {
    final box = widget.box;
    if (box == null) return Future.value();
    final write = _saveQueue.then((_) async {
      await box.put(GameConstants.playerKey, widget.player.toMap());
      await box.flush();
    });
    _saveQueue =
        write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return write;
  }

  Future<void> _save() async {
    try {
      await _persistPlayer();
    } catch (error) {
      debugPrint('Falha ao salvar o progresso: $error');
    }
  }

  Future<void> _applyVisitRewards(VisitSnapshot snapshot) {
    widget.player.applyVisitRewards(snapshot);
    return _persistPlayer();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    widget.visitsApi?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_enableDailyReminder());
      unawaited(_syncDailyLogin());
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
        colorScheme: const ColorScheme.dark(
          primary: Color(0xfff6d487),
          onPrimary: Color(0xff2c2415),
          primaryContainer: Color(0xff50401f),
          onPrimaryContainer: Color(0xffffe6ac),
          secondary: Color(0xffc6d9a6),
          onSecondary: Color(0xff26331f),
          secondaryContainer: Color(0xff445337),
          onSecondaryContainer: Color(0xffecf6d5),
          surface: Color(0xff23382b),
          onSurface: Color(0xfffff0d0),
          onSurfaceVariant: Color(0xffded8bb),
          surfaceContainerLow: Color(0xff293e30),
          surfaceContainer: Color(0xff2b4132),
          surfaceContainerHigh: Color(0xff344a37),
          surfaceContainerHighest: Color(0xff40543e),
          outline: Color(0xffb99a60),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xff23382b),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xffac8951)),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xff23382b),
          modalBackgroundColor: Color(0xff23382b),
          surfaceTintColor: Colors.transparent,
        ),
        listTileTheme: ListTileThemeData(
          tileColor: const Color(0xff304637),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xff6d6748)),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xff344a37),
          contentTextStyle: TextStyle(color: Color(0xfffff0d0)),
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(
        player: widget.player,
        onShouldSave: _save,
        visitsApi: widget.visitsApi,
        socialClient: widget.socialClient,
        onVisitRewards: _applyVisitRewards,
      ),
    );
  }
}
