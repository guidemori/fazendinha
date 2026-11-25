import 'crop.dart';

/// Um canteiro individual da fazenda. Pode estar vazio ou com uma cultura
/// plantada. O cálculo de "pronto para colher" entra na Fase 1 (game loop).
class Plot {
  Plot({required this.id});

  final String id;
  CropType? plantedCrop;
  DateTime? plantedAt;

  bool get isEmpty => plantedCrop == null;
  bool get isPlanted => plantedCrop != null;
}