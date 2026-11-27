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

class _CropContactShadow extends CustomPainter {
  const _CropContactShadow(this.stage);

  final int stage;

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * .50),
      width: size.width * (.09 + stage * .055),
      height: size.height * (.07 + stage * .022),
    );
    canvas.drawOval(
      shadow,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xaa262317), Color(0x00262317)],
          stops: [.24, 1],
        ).createShader(shadow),
    );
  }

  @override
  bool shouldRepaint(_CropContactShadow oldDelegate) =>
      stage != oldDelegate.stage;
}
