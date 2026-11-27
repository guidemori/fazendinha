part of 'main.dart';

enum _FarmShortcut { warehouse, store, friends, ranking, notices }

String _cropSprite(CropType crop, int stage) =>
    'assets/images/farm_sprites/crops/${crop.name}_$stage.webp';

String _farmIcon(String name) => 'assets/images/farm_sprites/icons/$name.webp';

class _CropArtwork extends StatelessWidget {
  const _CropArtwork({required this.type, this.quantity});

  final CropType type;
  final int? quantity;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 38,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(_cropSprite(type, GameConstants.cropStageCount),
              excludeFromSemantics: true),
          if (quantity case final count?)
            Positioned(
              right: 0,
              bottom: 0,
              child: Text('$count',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
}
