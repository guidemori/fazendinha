import 'package:flutter/material.dart';

import '../../models/plot.dart';

class PlotWidget extends StatelessWidget {
  const PlotWidget({
    super.key,
    required this.plot,
    required this.number,
    required this.selected,
    required this.onTap,
  });

  final Plot plot;
  final int number;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: ClipPath(
        clipper: const _PlotClipper(),
        child: Tooltip(
          message:
              'Canteiro $number · ${plot.plantedCrop?.label ?? 'Terra vazia'}',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Ink(
                child: CustomPaint(
                  painter: _SoilPainter(
                    selected: selected,
                    planted: plot.isPlanted,
                  ),
                  child: Center(
                    child: Text(
                      plot.plantedCrop?.emoji ?? '',
                      style: const TextStyle(fontSize: 18),
                    ),
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

Path _diamond(Size size) => Path()
  ..moveTo(size.width / 2, 0)
  ..lineTo(size.width, size.height / 2)
  ..lineTo(size.width / 2, size.height)
  ..lineTo(0, size.height / 2)
  ..close();

class _PlotClipper extends CustomClipper<Path> {
  const _PlotClipper();

  @override
  Path getClip(Size size) => _diamond(size);

  @override
  bool shouldReclip(_PlotClipper oldClipper) => false;
}

class _SoilPainter extends CustomPainter {
  const _SoilPainter({required this.selected, required this.planted});

  final bool selected;
  final bool planted;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _diamond(size);
    final rectangle = Offset.zero & size;
    final soil = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: planted
            ? const [Color(0xffa17447), Color(0xff65462e)]
            : const [Color(0xffb78451), Color(0xff794a30)],
      ).createShader(rectangle);

    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(rectangle, soil);

    final furrow = Paint()
      ..color = const Color(0xff66452e)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final highlight = Paint()
      ..color = const Color(0xffc09460)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (var row = 1; row < 5; row++) {
      final x = size.width * (.10 + row * .10);
      final y = size.height * (.64 - row * .10);
      final start = Offset(x, y);
      final end = Offset(x + size.width * .34, y + size.height * .34);
      canvas.drawLine(start, end, furrow);
      const offset = Offset(0, -2);
      canvas.drawLine(start + offset, end + offset, highlight);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 5 : 3
        ..color = selected ? const Color(0xffffe98c) : const Color(0xff59402b),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SoilPainter oldDelegate) =>
      selected != oldDelegate.selected || planted != oldDelegate.planted;
}
