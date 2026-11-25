/// Tipos de cultura disponíveis, na ordem de desbloqueio (seção 3.2).
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

/// Dados completos de uma cultura (custo, venda, tempo e desbloqueio).
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