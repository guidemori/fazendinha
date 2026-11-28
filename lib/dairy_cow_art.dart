import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shows individual image assets so every pose uses Flutter's normal Image
/// widget on both web and Android.
class DairyCowArt extends StatelessWidget {
  const DairyCowArt({
    super.key,
    required this.asset,
    required this.width,
    required this.stride,
    required this.headDip,
    required this.tailSwing,
  });

  final String asset;
  final double width;
  final double? stride;
  final double headDip;
  final double tailSwing;

  int get _poseIndex {
    final phase = stride;
    if (phase != null) return (phase * 6 / math.pi).round() % 12;
    if (headDip > 0) return 12 + (headDip.clamp(0, 1) * 7).round();
    return 20 + ((tailSwing.clamp(-1, 1) + 1) * 2.5).round();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: width * 2 / 3,
        child: Image.asset(
          'assets/images/farm_sprites/icons/cow_pose_$_poseIndex.webp',
          excludeFromSemantics: true,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, synchronouslyLoaded) {
            if (frame != null) return child;
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(asset, excludeFromSemantics: true),
                child,
              ],
            );
          },
          errorBuilder: (context, error, stackTrace) =>
              Image.asset(asset, excludeFromSemantics: true),
        ),
      );
}
