/// Constantes centrais do jogo: moedas, canteiros iniciais e curvas de custo.
class GameConstants {
  static const String hiveBoxName = 'fazendinha_idle_box';

  /// Estado inicial do jogador.
  static const int startingCoins = 0;
  static const int startingPlots = 4;

  /// Curva de custo para novos canteiros: custo = base x fator^quantidade.
  static const double newPlotBaseCost = 100.0;
  static const double newPlotGrowthFactor = 1.5;

  /// Intervalo de salvamento automático (segundos).
  static const int autoSaveSeconds = 30;

  /// Moedas vendidas por cultura (ver seção 3.2 do projeto).
  static const int alfaceSeedCost = 5;
  static const int alfaceSellValue = 12;
  static const int alfaceGrowSeconds = 30;

  static const int cenouraSeedCost = 25;
  static const int cenouraSellValue = 70;
  static const int cenouraGrowSeconds = 120;
}