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
      center: Offset(size.width / 2, size.height * .57),
      width: size.width * (.16 + stage * .06),
      height: size.height * (.10 + stage * .023),
    );
    canvas.drawOval(
      shadow,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xd82a2116), Color(0x00262317)],
          stops: [.24, 1],
        ).createShader(shadow),
    );
  }

  @override
  bool shouldRepaint(_CropContactShadow oldDelegate) =>
      stage != oldDelegate.stage;
}

class _CropSoilRim extends CustomPainter {
  const _CropSoilRim(this.stage);

  final int stage;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .59);
    final clod = Paint();
    final scale = size.width / 76;
    for (var i = -2; i <= 2; i++) {
      final x = i * (1.1 + stage * .42) * scale;
      final y = (1 - i.abs() * .42) * scale;
      final rect = Rect.fromCenter(
        center: center + Offset(x, y),
        width: (2.5 + stage * .28) * scale,
        height: (1.5 + stage * .2) * scale,
      );
      canvas.drawOval(rect, clod..color = const Color(0xff563a25));
      canvas.drawOval(
        rect.deflate(.42 * scale).shift(Offset(0, -.28 * scale)),
        clod..color = const Color(0xff87613f),
      );
    }
  }

  @override
  bool shouldRepaint(_CropSoilRim oldDelegate) => stage != oldDelegate.stage;
}
