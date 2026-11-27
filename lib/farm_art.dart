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
  const _CropSoilRim(this.stage, {required this.inset});

  final int stage;
  final bool inset;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * (inset ? .64 : .59));
    final clod = Paint();
    final scale = size.width / 76;
    for (var i = -2; i <= 2; i++) {
      final x = i * (1.1 + stage * (inset ? .65 : .42)) * scale;
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
  bool shouldRepaint(_CropSoilRim oldDelegate) =>
      stage != oldDelegate.stage || inset != oldDelegate.inset;
}

class _FarmActionEffect extends StatelessWidget {
  const _FarmActionEffect({super.key, required this.tool, required this.onEnd});

  final VoidCallback onEnd;

  final _FarmTool tool;

  @override
  Widget build(BuildContext context) {
    final water = tool == _FarmTool.water;
    final fertilizer = tool == _FarmTool.fertilizer;
    final harvest = tool == _FarmTool.harvest;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: water ? 950 : 550),
      onEnd: onEnd,
      child: Image.asset(_farmIcon(tool.name),
          width: 39, height: 39, excludeFromSemantics: true),
      builder: (context, progress, sprite) {
        if (progress >= 1) return const SizedBox.shrink();
        final strike = math.sin(progress * math.pi);
        return SizedBox(
          width: 60,
          height: 66,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 9,
                top: 3 + strike * (harvest ? 17 : 9),
                child: Opacity(
                  opacity: math.min(1, (1 - progress) * 5),
                  child: Transform.rotate(
                    angle: strike *
                        (water
                            ? .62
                            : tool == _FarmTool.hoe
                                ? -.63
                                : .24),
                    child: sprite,
                  ),
                ),
              ),
              if (water || fertilizer || tool == _FarmTool.hoe)
                for (var i = 0; i < 4; i++)
                  Positioned(
                    left: 18 + i * 6 + strike * i,
                    top: 31 + ((progress * 2 + i * .15) % 1) * 21,
                    child: Icon(
                      water
                          ? Icons.water_drop
                          : fertilizer
                              ? Icons.auto_awesome
                              : Icons.circle,
                      size: water ? 8 : 6,
                      color: (water
                              ? const Color(0xff8cdaff)
                              : fertilizer
                                  ? const Color(0xffc8ed75)
                                  : const Color(0xffbb8b59))
                          .withValues(alpha: math.min(1, (1 - progress) * 4)),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
