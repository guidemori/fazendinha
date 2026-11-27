part of 'main.dart';

class _ToolArt extends CustomPainter {
  const _ToolArt(this.tool);

  final _FarmTool tool;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40, size.height / 40);
    final paint = Paint()..isAntiAlias = true;

    void fill(Path path, Color color) {
      canvas.drawPath(path, paint..color = color);
      canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xff273d31)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..strokeJoin = StrokeJoin.round);
    }

    void oval(double x, double y, double w, double h, Color color) {
      canvas.drawOval(Rect.fromLTWH(x, y, w, h), paint..color = color);
    }

    switch (tool) {
      case _FarmTool.harvest:
        fill(
            Path()
              ..moveTo(17, 33)
              ..quadraticBezierTo(12, 25, 6, 23)
              ..quadraticBezierTo(5, 17, 12, 19)
              ..lineTo(16, 22)
              ..lineTo(12, 10)
              ..quadraticBezierTo(12, 6, 16, 7)
              ..lineTo(20, 17)
              ..lineTo(18, 5)
              ..quadraticBezierTo(21, 1, 24, 5)
              ..lineTo(26, 17)
              ..lineTo(27, 8)
              ..quadraticBezierTo(30, 5, 32, 9)
              ..lineTo(32, 19)
              ..lineTo(34, 14)
              ..quadraticBezierTo(39, 12, 38, 18)
              ..lineTo(35, 30)
              ..lineTo(30, 36)
              ..close(),
            const Color(0xfffff2d2));
      case _FarmTool.hoe:
        fill(
            Path()
              ..moveTo(8, 32)
              ..lineTo(28, 6)
              ..lineTo(32, 9)
              ..lineTo(12, 35)
              ..close(),
            const Color(0xffc58952));
        fill(
            Path()
              ..moveTo(18, 5)
              ..quadraticBezierTo(25, 2, 30, 6)
              ..lineTo(38, 15)
              ..lineTo(34, 20)
              ..lineTo(26, 10)
              ..lineTo(18, 10)
              ..close(),
            const Color(0xffb7d2d2));
      case _FarmTool.seed:
        fill(
            Path()
              ..moveTo(13, 7)
              ..lineTo(27, 7)
              ..lineTo(24, 14)
              ..quadraticBezierTo(35, 23, 33, 32)
              ..quadraticBezierTo(19, 39, 7, 32)
              ..quadraticBezierTo(6, 23, 16, 14)
              ..close(),
            const Color(0xffdba769));
        oval(15, 14, 11, 3, const Color(0xff795038));
        oval(16, 22, 9, 12, const Color(0xffffdd95));
      case _FarmTool.water:
        fill(
            Path()
              ..moveTo(23, 12)
              ..cubicTo(44, 2, 43, 27, 29, 27)
              ..lineTo(29, 23)
              ..cubicTo(38, 22, 38, 12, 26, 16)
              ..close(),
            const Color(0xff8cd2dc));
        fill(
            Path()
              ..moveTo(11, 17)
              ..lineTo(7, 11)
              ..lineTo(2, 13)
              ..lineTo(4, 18)
              ..lineTo(6, 17)
              ..lineTo(12, 27)
              ..quadraticBezierTo(21, 36, 31, 30)
              ..lineTo(33, 16)
              ..quadraticBezierTo(20, 12, 11, 17)
              ..close(),
            const Color(0xff70c6d7));
        oval(14, 14, 16, 4, const Color(0xff3e7782));
        oval(2, 23, 3, 5, const Color(0xffa2e8ed));
        oval(4, 30, 3, 5, const Color(0xffa2e8ed));
      case _FarmTool.fertilizer:
        fill(
            Path()
              ..moveTo(15, 6)
              ..lineTo(25, 6)
              ..lineTo(25, 13)
              ..quadraticBezierTo(32, 15, 32, 23)
              ..lineTo(32, 34)
              ..quadraticBezierTo(20, 38, 8, 34)
              ..lineTo(8, 23)
              ..quadraticBezierTo(8, 15, 15, 13)
              ..close(),
            const Color(0xff94c95c));
        oval(13, 4, 14, 6, const Color(0xffffce59));
        oval(12, 20, 16, 11, const Color(0xffffecc3));
        oval(17, 22, 6, 7, const Color(0xff3e7a37));
    }
  }

  @override
  bool shouldRepaint(_ToolArt oldDelegate) => tool != oldDelegate.tool;
}

void _paintCropArt(
    Canvas canvas, Offset center, double size, CropType type, int stage) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(size / 40);
  final paint = Paint()..isAntiAlias = true;

  void oval(double x, double y, double w, double h, Color color) {
    canvas.drawOval(Rect.fromLTWH(x, y, w, h), paint..color = color);
  }

  void leaf(double x, double y, double angle, double length, Color color) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    final blade = Path()
      ..moveTo(0, 0)
      ..cubicTo(-length * .55, -length * .48, -length * .44, -length * .86, 0,
          -length)
      ..cubicTo(length * .55, -length * .86, length * .50, -length * .38, 0, 0);
    canvas.drawPath(blade, paint..color = color);
    canvas.drawLine(
        Offset.zero,
        Offset(0, -length * .74),
        Paint()
          ..color = const Color(0x88dcf59b)
          ..strokeWidth = .75);
    canvas.restore();
  }

  const dark = Color(0xff2d6429);
  const green = Color(0xff5a9f38);
  const bright = Color(0xffa4d661);
  oval(-13, 3, 26, 7, const Color(0x55261d12));

  if (stage == 1) {
    leaf(0, 5, -.78, 13, green);
    leaf(0, 5, .70, 15, bright);
    canvas.restore();
    return;
  }

  if (type == CropType.alface) {
    final count = stage == 4
        ? 9
        : stage == 3
            ? 6
            : 4;
    for (var i = 0; i < count; i++) {
      leaf(0, 3, i * 2 * math.pi / count, stage == 4 ? 16 : 12,
          i.isEven ? dark : green);
    }
    if (stage >= 3) {
      leaf(0, 2, -.65, 11, const Color(0xff77bd49));
      leaf(0, 2, .55, 10, bright);
      leaf(0, 3, 2.7, 9, const Color(0xff8bca52));
    }
    canvas.restore();
    return;
  }

  final upright = type == CropType.milho || type == CropType.cana;
  leaf(-4, 6, -.90, upright ? 24 : 17, dark);
  leaf(2, 7, .90, upright ? 24 : 17, green);
  leaf(0, 6, -.16, upright ? 28 : 20, bright);
  if (stage >= 3) {
    final mature = stage == 4;
    switch (type) {
      case CropType.alface:
        break;
      case CropType.cenoura:
        final root = Path()
          ..moveTo(-7, 2)
          ..quadraticBezierTo(0, -2, 7, 2)
          ..quadraticBezierTo(5, 9, -3, 15)
          ..quadraticBezierTo(-7, 10, -7, 2);
        canvas.drawPath(
            root,
            paint
              ..color =
                  mature ? const Color(0xfff89530) : const Color(0xffdbac53));
        leaf(0, 3, .35, 13, green);
      case CropType.milho:
        oval(-5, -17, 12, 21, mature ? const Color(0xffffd455) : bright);
        leaf(-1, 8, .60, 18, green);
        if (mature) {
          for (var row = 0; row < 4; row++) {
            oval(2, -13 + row * 3.0, 2, 2, const Color(0xffedaa31));
          }
        }
      case CropType.cana:
        for (final x in [-7.0, 1.0]) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(x, mature ? -21 : -14, 5, mature ? 29 : 22),
                  const Radius.circular(2)),
              paint..color = const Color(0xffa9c665));
          for (final y in [-9.0, 0.0]) {
            canvas.drawLine(
                Offset(x, y),
                Offset(x + 5, y),
                Paint()
                  ..color = dark
                  ..strokeWidth = 1);
          }
        }
      case CropType.tomate:
      case CropType.morango:
      case CropType.cafe:
        final berry = switch (type) {
          CropType.morango => const Color(0xfff55264),
          CropType.cafe => const Color(0xffa92e37),
          _ => const Color(0xffe85130),
        };
        final radius = type == CropType.cafe ? 4.0 : 7.0;
        for (final (x, y) in [(-8.0, -4.0), (4.0, 1.0), (0.0, -11.0)]) {
          oval(
              x - radius / 2,
              y,
              radius,
              radius + (type == CropType.morango ? 2 : 0),
              mature ? berry : const Color(0xffb6cd64));
          leaf(x, y + 1, .8, 4, dark);
          if (mature) oval(x - 1, y + 2, 1.5, 1.5, const Color(0xffffcb9e));
        }
      case CropType.abobora:
        final skin = mature ? const Color(0xfff69a32) : const Color(0xffb5ad4e);
        oval(-13, -5, 26, 16, skin);
        oval(-8, -6, 16, 17, mature ? const Color(0xffed7b24) : green);
        oval(-4, -6, 8, 17, skin);
        leaf(0, -5, .40, 8, dark);
    }
  }
  canvas.restore();
}

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
          CustomPaint(painter: _MatureCropArt(type)),
          if (quantity case final count?)
            Positioned(
                right: 0,
                bottom: 0,
                child: Text('$count',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}

class _MatureCropArt extends CustomPainter {
  const _MatureCropArt(this.type);

  final CropType type;

  @override
  void paint(Canvas canvas, Size size) {
    _paintCropArt(canvas, Offset(size.width / 2, size.height * .62),
        size.shortestSide, type, GameConstants.cropStageCount);
  }

  @override
  bool shouldRepaint(_MatureCropArt oldDelegate) => type != oldDelegate.type;
}

enum _FarmShortcut { warehouse, store, friends, ranking, notices }

class _ShortcutArt extends CustomPainter {
  const _ShortcutArt(this.shortcut);

  final _FarmShortcut shortcut;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40, size.height / 40);
    final brush = Paint();
    const amber = Color(0xffffc257);
    const cream = Color(0xffffecd0);
    const umber = Color(0xff75482f);
    const red = Color(0xffd8674b);
    const teal = Color(0xff539f97);

    void box(double x, double y, double width, double height, Color color) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, width, height), const Radius.circular(3)),
        brush..color = color,
      );
    }

    void disk(double x, double y, double radius, Color color) {
      canvas.drawCircle(Offset(x, y), radius, brush..color = color);
    }

    canvas.drawOval(const Rect.fromLTWH(4, 32, 32, 6),
        brush..color = const Color(0x63302019));
    switch (shortcut) {
      case _FarmShortcut.warehouse:
        box(8, 15, 24, 20, cream);
        canvas.drawPath(
            Path()
              ..moveTo(3, 17)
              ..lineTo(20, 5)
              ..lineTo(37, 17)
              ..close(),
            brush..color = teal);
        box(15, 19, 10, 16, umber);
        box(17, 23, 6, 2, amber);
      case _FarmShortcut.store:
        box(8, 14, 24, 20, cream);
        box(12, 20, 8, 8, teal);
        box(23, 20, 6, 13, umber);
        box(6, 8, 28, 9, red);
        for (final x in [9.0, 18.0, 27.0]) {
          box(x, 9, 4, 9, amber);
        }
      case _FarmShortcut.friends:
        box(4, 21, 19, 13, teal);
        box(20, 20, 16, 14, red);
        disk(27, 14, 6, amber);
        disk(13, 13, 7, cream);
      case _FarmShortcut.ranking:
        box(7, 10, 26, 11, umber);
        box(9, 12, 22, 6, amber);
        box(13, 6, 14, 19, amber);
        box(17, 22, 6, 10, amber);
        box(12, 31, 16, 4, umber);
        disk(20, 14, 3, cream);
      case _FarmShortcut.notices:
        box(8, 8, 24, 28, umber);
        box(11, 11, 18, 22, cream);
        box(15, 5, 10, 8, amber);
        for (final y in [17.0, 22.0, 27.0]) {
          box(14, y, 12, 2, teal);
        }
    }
  }

  @override
  bool shouldRepaint(_ShortcutArt oldDelegate) =>
      shortcut != oldDelegate.shortcut;
}
