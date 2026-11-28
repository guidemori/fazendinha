import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fazendinhaidle/dairy_cow_art.dart';

void main() {
  testWidgets('a cabeça muda de pose mantendo a vaca visível', (tester) async {
    const asset = 'assets/images/farm_sprites/icons/cow.webp';
    final boundaryKey = GlobalKey();
    Future<void> showPose(double headDip) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: DairyCowArt(
              asset: asset,
              width: 300,
              stride: null,
              headDip: headDip,
              tailSwing: 0,
            ),
          ),
        ),
      ));
    }

    await tester.runAsync(() async {
      await showPose(0);
      await precacheImage(
        const AssetImage('assets/images/farm_sprites/icons/cow_pose_23.webp'),
        boundaryKey.currentContext!,
      );
      await precacheImage(
        const AssetImage('assets/images/farm_sprites/icons/cow_pose_19.webp'),
        boundaryKey.currentContext!,
      );
    });
    await tester.pumpAndSettle();

    Future<List<int>> pixels() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final frame = await boundary.toImage();
        try {
          return await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
        } finally {
          frame.dispose();
        }
      });
      return bytes!.buffer.asUint8List();
    }

    final standing = await pixels();
    await showPose(1);
    await tester.pump();
    final headDown = await pixels();
    expect(standing, isNot(equals(headDown)));
    expect(
        headDown
            .skip(3)
            .indexed
            .where(
              (entry) => entry.$1 % 4 == 0 && entry.$2 > 200,
            )
            .length,
        greaterThan(8000));
  });
}
